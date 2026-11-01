import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'crypto/primitives.dart';
import 'models.dart';
import 'storage.dart';
import 'media/image_validation.dart';
import 'attachment_files.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class ServerAddress {
  ServerAddress(String value, {bool allowLoopbackHttp = false}) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        !['', '/'].contains(parsed.path) ||
        !(parsed.scheme == 'https' ||
            (allowLoopbackHttp &&
                parsed.scheme == 'http' &&
                [
                  'localhost',
                  '127.0.0.1',
                  '::1',
                  '10.0.2.2',
                ].contains(parsed.host)))) {
      throw const ApiFailure(
        0,
        'Укажите HTTPS-адрес сервера без /api, логина и параметров.',
      );
    }
    uri = Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
    );
  }
  late final Uri uri;
  String get scope => 'govor-${hex(sha256(utf(uri.origin)))}';
  Uri endpoint(String path, [Map<String, String>? query]) {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('..') ||
        path.contains('\\') ||
        path.contains('?') ||
        path.contains('#')) {
      throw ArgumentError(
        'Use a relative API path and separate query parameters.',
      );
    }
    return uri.replace(path: path, queryParameters: query);
  }
}

class TokenPair {
  const TokenPair(this.access, this.refresh);
  factory TokenPair.fromJson(Json j) =>
      TokenPair(j['accessToken'] as String, j['refreshToken'] as String);
  final String access, refresh;
  Json toJson() => {'accessToken': access, 'refreshToken': refresh};
  Json get claims {
    final parts = access.split('.');
    requireCrypto(parts.length == 3, 'Неверный access token.');
    // This is local metadata, never a replacement for server-side JWT validation.
    return object(jsonDecode(utf8.decode(unb64u(parts[1]))));
  }

  String get user => claims['userId'] as String;
  String get session => claims['sid'] as String;
  bool get expiresSoon =>
      (claims['exp'] as num).toInt() <=
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
  void validate() {
    requireCrypto(
      access.length < 20000 &&
          refresh.isNotEmpty &&
          refresh.length < 20000 &&
          validId(user) &&
          validId(session) &&
          claims['exp'] is num,
      'Некорректный ответ авторизации.',
    );
  }
}

class ApiClient {
  ApiClient(this.server, this.store, {http.Client? client})
    : _client = client ?? http.Client();
  final ServerAddress server;
  final SecretStore store;
  final http.Client _client;
  TokenPair? tokens;
  Future<void>? _refreshing;
  bool _closed = false;
  int _epoch = 0;
  String get _tokenKey => '${server.scope}-tokens';
  Future<void> restore() async {
    final value = await store.read(_tokenKey);
    if (value != null) {
      final pair = TokenPair.fromJson(object(jsonDecode(value)));
      pair.validate();
      tokens = pair;
    }
  }

  Future<void> accept(TokenPair pair) async {
    pair.validate();
    await store.write(_tokenKey, jsonEncode(pair.toJson()));
    tokens = pair;
  }

  Future<void> clearSession() async {
    _epoch++;
    tokens = null;
    await store.remove(_tokenKey);
  }

  Future<String> accessToken() async {
    if (tokens == null) throw const ApiFailure(401, 'Войдите в аккаунт.');
    if (tokens!.expiresSoon) await refresh();
    return tokens!.access;
  }

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    final task = _refresh();
    _refreshing = task;
    return task.whenComplete(() {
      if (identical(_refreshing, task)) _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    final previous = tokens;
    final epoch = _epoch;
    if (previous == null) throw const ApiFailure(401, 'Войдите в аккаунт.');
    try {
      final value = await request(
        'POST',
        '/api/auth/token/refresh',
        body: {'refreshToken': previous.refresh},
        authenticated: false,
      );
      if (_closed || epoch != _epoch) {
        throw const ApiFailure(401, 'Сессия завершена.');
      }
      final next = TokenPair.fromJson(object(value));
      next.validate();
      requireCrypto(
        next.user == previous.user && next.session == previous.session,
        'Контекст refresh изменился.',
      );
      await accept(next);
    } on ApiFailure catch (e) {
      if ((e.status == 400 || e.status == 401) && epoch == _epoch) {
        await clearSession();
      }
      rethrow;
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (_closed) throw const ApiFailure(0, 'Соединение закрыто.');
    final epoch = _epoch;
    final token = authenticated ? await accessToken() : null;
    try {
      return await _send(method, path, body, query, token);
    } on ApiFailure catch (e) {
      if (!authenticated || e.status != 401 || epoch != _epoch) rethrow;
      if (tokens?.access == token) await refresh();
      if (_closed || epoch != _epoch || tokens == null) {
        throw const ApiFailure(401, 'Войдите в аккаунт.');
      }
      return _send(method, path, body, query, tokens!.access);
    }
  }

  Future<dynamic> _send(
    String method,
    String path,
    Object? body,
    Map<String, String>? query,
    String? token,
  ) async {
    final request = http.Request(method, server.endpoint(path, query))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 25));
      final buffer = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 25),
      )) {
        if (buffer.length + chunk.length > 6000000) {
          throw const ApiFailure(0, 'Ответ сервера слишком большой.');
        }
        buffer.addAll(chunk);
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const ApiFailure(
          0,
          'Сервер перенаправил запрос. Проверьте адрес.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Do not surface server bodies: they may echo tokens, proofs or internals.
        throw ApiFailure(response.statusCode, switch (response.statusCode) {
          400 || 401 => 'Вход не подтверждён или сессия истекла.',
          403 => 'Нет доступа. Обновите права или войдите снова.',
          404 => 'Данные не найдены.',
          409 => 'Данные изменились на другом устройстве. Повторите действие.',
          429 => 'Слишком много запросов. Попробуйте позже.',
          _ => 'Сервер недоступен. Повторите попытку.',
        });
      }
      return buffer.isEmpty ? null : jsonDecode(utf8.decode(buffer));
    } on TimeoutException {
      throw const ApiFailure(0, 'Сервер не ответил вовремя.');
    } on http.ClientException {
      throw const ApiFailure(0, 'Не удалось подключиться к серверу.');
    } on FormatException {
      throw const ApiFailure(0, 'Некорректный ответ сервера.');
    }
  }

  Future<Uint8List> _binary(
    http.BaseRequest Function(String token) create,
    int limit,
  ) async {
    final epoch = _epoch;
    var token = await accessToken();
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_closed || epoch != _epoch) {
        throw const ApiFailure(401, 'Сессия завершена.');
      }
      final request = create(token)..followRedirects = false;
      request.headers['Authorization'] = 'Bearer $token';
      try {
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 60));
        final data = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          if (data.length + chunk.length > limit) {
            throw const ApiFailure(
              0,
              'Файл или ответ сервера слишком большой.',
            );
          }
          data.add(chunk);
        }
        if (response.statusCode == 401 && attempt == 0 && epoch == _epoch) {
          if (tokens?.access == token) await refresh();
          token = await accessToken();
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiFailure(
            response.statusCode,
            response.statusCode == 413
                ? 'Файл слишком большой для сервера.'
                : 'Передача файла не удалась. Проверьте соединение и доступ.',
          );
        }
        if (_closed || epoch != _epoch) {
          throw const ApiFailure(401, 'Сессия завершена.');
        }
        return data.takeBytes();
      } on TimeoutException {
        throw const ApiFailure(0, 'Передача файла прервана по времени.');
      } on http.ClientException {
        throw const ApiFailure(0, 'Не удалось передать файл.');
      }
    }
    throw const ApiFailure(401, 'Войдите в аккаунт.');
  }

  Future<String> uploadAttachment(Uint8List ciphertext) async {
    requireCrypto(
      ciphertext.length >= 28 && ciphertext.length <= 19000028,
      'Неверный размер вложения.',
    );
    final response = await _binary(
      (_) => http.MultipartRequest('POST', server.endpoint('/api/media/upload'))
        ..fields.addAll({
          'Type': '3',
          'MimeType': 'application/vnd.govor.encrypted',
          'OwnerType': '0',
        })
        ..files.add(
          http.MultipartFile.fromBytes(
            'FromFile',
            ciphertext,
            filename: 'encrypted.bin',
          ),
        ),
      65536,
    );
    final result = object(jsonDecode(utf8.decode(response)));
    requireCrypto(
      validId(result['mediaId']),
      'Неверный ID загруженного файла.',
    );
    return result['mediaId'] as String;
  }

  Future<Uint8List> downloadAttachment(
    String id, {
    int maxBytes = 19000028,
  }) async {
    requireCrypto(validId(id), 'Неверный ID вложения.');
    return _binary(
      (_) => http.Request('GET', server.endpoint('/api/media/download/$id')),
      maxBytes,
    );
  }

  Future<String> uploadProfileAvatar(Uint8List data, String mime) async {
    requireCrypto(
      data.isNotEmpty &&
          data.length <= 2000000 &&
          ['image/png', 'image/jpeg', 'image/webp'].contains(mime),
      'Нужна статичная картинка PNG, JPEG или WebP до 2 МБ.',
    );
    final result = await _binary(
      (_) =>
          http.MultipartRequest('POST', server.endpoint('/api/profile/avatar'))
            ..fields.addAll({'Type': '0', 'MimeType': mime})
            ..files.add(
              http.MultipartFile.fromBytes(
                'FromFile',
                data,
                filename: 'avatar.${mime.split('/').last}',
              ),
            ),
      65536,
    );
    final id = object(jsonDecode(utf8.decode(result)))['mediaId'];
    requireCrypto(validId(id), 'Неверный ID аватара.');
    return id as String;
  }

  Future<String> uploadGroupAvatar(String groupId, Uint8List data) async {
    requireCrypto(validId(groupId), 'Неверный ID сообщества.');
    final mime = fileMime(data);
    requireCrypto(
      data.isNotEmpty &&
          data.length <= 2 * 1024 * 1024 &&
          const ['image/png', 'image/jpeg', 'image/webp'].contains(mime),
      'Нужна статичная картинка PNG, JPEG или WebP до 2 МиБ.',
    );
    try {
      await validateImageBytes(data, maxDimension: 2048);
    } catch (_) {
      throw const ApiFailure(0, 'Нужна картинка со сторонами до 2048 px.');
    }
    final result = await _binary(
      (_) =>
          http.MultipartRequest(
              'POST',
              server.endpoint('/api/groups/$groupId/avatar'),
            )
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                data,
                filename:
                    'avatar.${mime == 'image/jpeg' ? 'jpg' : mime.split('/').last}',
              ),
            ),
      65536,
    );
    final id = object(jsonDecode(utf8.decode(result)))['imageId'];
    requireCrypto(validId(id), 'Неверный ID аватара сообщества.');
    return id as String;
  }

  void close() {
    _closed = true;
    _epoch++;
    _client.close();
  }
}
