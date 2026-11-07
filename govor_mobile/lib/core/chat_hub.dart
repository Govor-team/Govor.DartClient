import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'models.dart';
import 'socket_native.dart' if (dart.library.js_interop) 'socket_web.dart';

enum ConnectionStatus { offline, connecting, connected, reconnecting }

/// A business response from the server, distinct from a lost SignalR reply.
class HubCommandFailure extends ApiFailure {
  const HubCommandFailure._(super.status, super.message, this.sendRejected);

  /// True only for documented checks that reject Send before saving a message.
  final bool sendRejected;

  factory HubCommandFailure.fromResult(
    String method,
    int status,
    Object? error,
  ) {
    final reason = switch ((status, error)) {
      (400, 'E2EE_DEVICES_CHANGED') =>
        'Изменились устройства участников. Отправьте сообщение ещё раз с актуальными ключами.',
      (400, 'E2EE_TIMESTAMP_OUT_OF_RANGE') =>
        'Время устройства отличается от времени сервера больше чем на 5 минут. Включите автоматическую установку времени и отправьте сообщение снова.',
      (400, 'E2EE routing, attachment or time context does not match.') =>
        'Сервер отклонил параметры шифрования. Проверьте дату и время устройства, затем повторите отправку.',
      (400, 'E2EE routing or attachment context does not match.') =>
        'Сервер отклонил параметры шифрования чата, цитаты или вложений. Обновите чат и повторите отправку.',
      (403, 'E2EE_SIGNING_DEVICE_REJECTED') =>
        'Сервер не принимает ключ подписи этого устройства. Переподключитесь и проверьте состояние защиты переписки.',
      (403, 'You do not have permission to perform this action.') =>
        'Сервер запретил отправку (403). Проверьте доступ к чату и состояние устройства.',
      (401, 'Session revoked or expired.') =>
        'Сессия истекла или была отозвана (401). Переподключитесь к аккаунту.',
      (400, 'Invalid E2EE envelope.') =>
        'Сервер не смог проверить шифрование сообщения. Проверьте, что у вас актуальная версия клиента.',
      (400, 'Reply must belong to the same chat.') =>
        'Сообщение для ответа недоступно в этом чате. Обновите чат или уберите цитату.',
      _ => null,
    };
    final message =
        reason ??
        switch (status) {
          401 =>
            'Сессия не подтверждена сервером (401). Проверьте подключение к аккаунту.',
          403 =>
            'Сервер запретил команду (403). Проверьте доступ к чату и состояние устройства.',
          500 => 'Ошибка на сервере (500). Проверьте историю перед повтором.',
          _ when status >= 400 && status <= 599 =>
            'Сервер отклонил команду ($status). Обновите чат и повторите действие.',
          _ =>
            'Сервер вернул неожиданный ответ. Проверьте историю перед повтором.',
        };
    return HubCommandFailure._(
      status,
      message,
      method == 'Send' && reason != null,
    );
  }
}

/// SignalR JSON v1 over negotiated WebSocket. Bounded frames, invocation deadlines,
/// keepalive, reconnect and an explicit resync callback; no plaintext fallback.
class ChatHub {
  ChatHub(this.api, {this.path = '/hubs/chats'});
  final ApiClient api;
  final String path;
  void Function(String event, List<dynamic> args)? onEvent;
  void Function(ConnectionStatus status)? onStatus;
  Future<void> Function()? onReconnected;
  ConnectionStatus status = ConnectionStatus.offline;
  final Map<String, Completer<dynamic>> _pending = {};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat, _retry;
  Completer<void>? _handshake;
  Future<void>? _starting;
  String _buffer = '';
  DateTime _lastReceived = DateTime.now();
  int _sequence = 0, _attempt = 0, _generation = 0;
  bool _stopped = true, _everConnected = false;
  void _status(ConnectionStatus value) {
    status = value;
    onStatus?.call(value);
  }

  Future<void> start() {
    _stopped = false;
    if (status == ConnectionStatus.connected) return Future.value();
    if (_starting != null) return _starting!;
    final task = _connect();
    _starting = task;
    return task.whenComplete(() {
      if (identical(task, _starting)) _starting = null;
    });
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _retry?.cancel();
    _status(
      _everConnected
          ? ConnectionStatus.reconnecting
          : ConnectionStatus.connecting,
    );
    try {
      final negotiated = object(
        await api.request(
          'POST',
          '$path/negotiate',
          query: {'negotiateVersion': '1'},
        ),
      );
      if (_stopped || generation != _generation) return;
      if (negotiated['url'] != null ||
          negotiated['error'] != null ||
          negotiated['connectionToken'] is! String ||
          !objects(negotiated['availableTransports']).any(
            (t) =>
                t['transport'] == 'WebSockets' &&
                (t['transferFormats'] as List).contains('Text'),
          )) {
        throw const ApiFailure(0, 'Сервер не поддерживает SignalR WebSocket.');
      }
      final token = await api.accessToken();
      if (_stopped || generation != _generation) return;
      final uri = api.server.endpoint(path, {
        'id': negotiated['connectionToken'] as String,
      });
      final channel = connectSocket(
        uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws'),
        token,
      );
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 20));
      if (_stopped || generation != _generation) {
        await channel.sink.close();
        return;
      }
      _buffer = '';
      _handshake = Completer<void>();
      _subscription = channel.stream.listen(
        (data) => _receive(data, generation),
        onError: (Object _) => _disconnected(generation),
        onDone: () => _disconnected(generation),
      );
      channel.sink.add('${jsonEncode({'protocol': 'json', 'version': 1})}\x1e');
      await _handshake!.future.timeout(const Duration(seconds: 15));
      if (_stopped || generation != _generation) return;
      _lastReceived = DateTime.now();
      _attempt = 0;
      _status(ConnectionStatus.connected);
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (DateTime.now().difference(_lastReceived) >
            const Duration(seconds: 45)) {
          _disconnected(generation);
          return;
        }
        channel.sink.add('{"type":6}\x1e');
      });
      final reconnect = _everConnected;
      _everConnected = true;
      if (reconnect) await onReconnected?.call();
    } catch (_) {
      _disconnected(generation);
      if (!_stopped) {
        throw const ApiFailure(
          0,
          'Связь с сервером прервана. Выполняется переподключение.',
        );
      }
    }
  }

  void _receive(dynamic raw, int generation) {
    if (_stopped || generation != _generation) return;
    try {
      if (raw is! String || raw.length + _buffer.length > 2200000) {
        throw const FormatException();
      }
      _lastReceived = DateTime.now();
      _buffer += raw;
      while (_buffer.contains('\x1e')) {
        final end = _buffer.indexOf('\x1e');
        final frame = _buffer.substring(0, end);
        _buffer = _buffer.substring(end + 1);
        if (frame.isEmpty) continue;
        final value = object(jsonDecode(frame));
        if (_handshake?.isCompleted == false) {
          if (value.containsKey('error') || value.containsKey('type')) {
            throw const FormatException();
          }
          _handshake!.complete();
          continue;
        }
        switch (value['type']) {
          case 1:
            onEvent?.call(
              value['target'] as String,
              value['arguments'] as List<dynamic>,
            );
          case 3:
            final pending = _pending.remove(value['invocationId']);
            if (pending != null && !pending.isCompleted) {
              if (value['error'] != null) {
                pending.completeError(
                  const ApiFailure(0, 'Команда отклонена сервером.'),
                );
              } else {
                pending.complete(value['result']);
              }
            }
          case 6:
            break;
          case 7:
            _disconnected(generation);
            return;
          default:
            break;
        }
      }
    } catch (_) {
      _disconnected(generation);
    }
  }

  Future<dynamic> invoke(String method, List<Object?> args) async {
    if (status != ConnectionStatus.connected) {
      throw const ApiFailure(0, 'Нет соединения. Дождитесь подключения.');
    }
    final id = '${++_sequence}';
    final pending = Completer<dynamic>();
    _pending[id] = pending;
    try {
      _channel!.sink.add(
        '${jsonEncode({'type': 1, 'invocationId': id, 'target': method, 'arguments': args})}\x1e',
      );
      final result = object(
        await pending.future.timeout(const Duration(seconds: 25)),
      );
      if (![200, 201, 204].contains(result['status'])) {
        throw HubCommandFailure.fromResult(
          method,
          result['status'] is int ? result['status'] as int : 0,
          result['errorMessage'],
        );
      }
      return result['result'];
    } on TimeoutException {
      throw const ApiFailure(
        0,
        'Подтверждение не получено. Сообщение могло быть доставлено.',
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _disconnected(int generation) {
    if (generation != _generation) return;
    _generation++;
    _heartbeat?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
    if (_handshake?.isCompleted == false) {
      _handshake!.completeError(
        const ApiFailure(0, 'SignalR handshake прерван.'),
      );
    }
    for (final item in _pending.values) {
      if (!item.isCompleted) {
        item.completeError(
          const ApiFailure(
            0,
            'Связь прервана. Проверьте историю перед повтором.',
          ),
        );
      }
    }
    _pending.clear();
    _status(
      _stopped ? ConnectionStatus.offline : ConnectionStatus.reconnecting,
    );
    if (!_stopped) {
      final delay = min(30, 1 << min(_attempt++, 5));
      _retry = Timer(
        Duration(milliseconds: delay * 1000 + Random().nextInt(500)),
        () {
          if (!_stopped) unawaited(start().catchError((Object _) {}));
        },
      );
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    _disconnected(_generation);
    _everConnected = false;
  }
}
