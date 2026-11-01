import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'crypto/e2ee_protocol.dart';
import 'crypto/primitives.dart';
import 'crypto/recovery_protocol.dart';
import 'models.dart';

class RecoveryCodeRequired implements Exception {
  const RecoveryCodeRequired();
  @override
  String toString() =>
      'Для архива нужен резервный код с доверенного устройства.';
}

/// Serializes local key and trust changes. The archive is saved before a device
/// becomes a recipient. Network failures never replace account secrets.
class EncryptionService {
  EncryptionService(this.api);
  final ApiClient api;
  Json? _state;
  DeviceKeys? _keys;
  DeviceKey? _device;
  Future<void> _tail = Future.value();
  bool _ready = false;
  final Set<String> identityChanges = {};
  String get _user => api.tokens!.user;
  String get _session => api.tokens!.session;
  String get _scope => '${api.server.scope}-$_user';
  String get _stateKey => '$_scope-encryption';
  String? get recoveryCode => _state?['code'] as String?;
  DeviceKey? get ownDevice => _device;
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _save() => api.store.write(_stateKey, jsonEncode(_state));
  Json get _archive => object(_state!['archive']);
  Future<Json?> _passwordConfiguration() async {
    final value = await api.store.read(AuthService.passwordKey(api, _user));
    if (value == null) return null;
    var key = object(jsonDecode(value));
    final configuration = object(
      await api.request('GET', '/api/auth/password'),
    );
    final credentials = object(field(configuration, 'credentials'));
    final pending = await api.store.read(
      '${AuthService.passwordKey(api, _user)}-pending',
    );
    if (pending != null) {
      final replacement = object(jsonDecode(pending));
      if (replacement['salt'] == field(credentials, 'salt') &&
          replacement['identity'] == field(credentials, 'identity') &&
          replacement['version'] == field(configuration, 'credentialVersion')) {
        key = replacement;
        await api.store.write(AuthService.passwordKey(api, _user), pending);
        await api.store.remove(
          '${AuthService.passwordKey(api, _user)}-pending',
        );
      }
    }
    requireCrypto(
      key['salt'] == field(credentials, 'salt') &&
          key['identity'] == field(credentials, 'identity') &&
          key['version'] == field(configuration, 'credentialVersion'),
      'Пароль изменён. Войдите снова для восстановления архива.',
    );
    return {'key': key['key'], 'configuration': configuration};
  }

  Future<void> initialize({String? recoveryCode}) => _exclusive(() async {
    if (_ready) return;
    await _completePendingReset();
    final encoded = await api.store.read(_stateKey);
    if (encoded != null) _state = object(jsonDecode(encoded));
    final password = await _passwordConfiguration();
    await _sync(password, suppliedCode: recoveryCode);
    final devices = object(_state!['devices']);
    final saved = devices[_session] == null ? null : object(devices[_session]);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    Json candidate;
    if (saved == null) {
      final generated = await compute(generateDeviceKeys, null);
      candidate = {
        'keys': generated.toJson(),
        'generation': 0,
        'previous': null,
        'rotatedAt': now,
        'pending': true,
      };
    } else if (saved['pending'] == true ||
        now - (saved['rotatedAt'] as int) < 7 * 24 * 3600) {
      candidate = saved;
    } else {
      final generated = await compute(generateDeviceKeys, null);
      final oldKeys = DeviceKeys.fromJson(object(saved['keys']));
      final previous = devicePublic(oldKeys, _user, _session).fingerprint;
      candidate = {
        'keys': DeviceKeys(oldKeys.identity, generated.encryption).toJson(),
        'generation': (saved['generation'] as int) + 1,
        'previous': previous,
        'rotatedAt': now,
        'pending': true,
      };
    }
    devices[_session] = candidate;
    _state!['devices'] = devices;
    _keys = DeviceKeys.fromJson(object(candidate['keys']));
    _device = devicePublic(
      _keys!,
      _user,
      _session,
      generation: candidate['generation'] as int,
      previous: candidate['previous'] as String?,
    );
    final archive = _archive;
    final history = objects(field(archive, 'keys'));
    final ownHistory = {
      'IdentityKey': _device!.identity,
      'EncryptionKey': _keys!.encryption,
    };
    if (!history.any((k) => _historyFingerprint(k) == _device!.fingerprint)) {
      history.add(ownHistory);
    }
    archive['Keys'] = history;
    _state!['archive'] = archive;
    await _save(); // Journal generated keys before any network mutation.
    await _sync(password);
    _device = _device!.certify(field(_archive, 'identityPrivateKey') as String);
    await api.request('PUT', '/api/e2ee/device', body: _device!.toJson());
    candidate['pending'] = false;
    devices[_session] = candidate;
    _state!['devices'] = devices;
    await _save();
    await _ensurePasswordEnvelope(password);
    _ready = true;
  });
  String _historyFingerprint(Json k) => hex(
    sha256(
      utf(
        'govor-device-v1\n${field(k, 'identityKey')}\n${publicEncryption(field(k, 'encryptionKey') as String)}',
      ),
    ),
  );

  Json _mergeArchives(Json first, Json? second) {
    final root = field(first, 'identityPrivateKey') as String;
    requireCrypto(
      second == null || field(second, 'identityPrivateKey') == root,
      'Корневой ключ аккаунта изменился. Отправка остановлена.',
    );
    final history = <String, Json>{};
    final pins = <String, dynamic>{};
    final epochs = <String, dynamic>{};
    for (final archive in [first, ?second]) {
      final keys = objects(field(archive, 'keys'));
      final trust = object(field(archive, 'trustedAccounts'));
      requireCrypto(
        keys.length <= 1500 && trust.length <= 10000,
        'Архив слишком большой.',
      );
      for (final key in keys) {
        history[_historyFingerprint(key)] = {
          'IdentityKey': field(key, 'identityKey'),
          'EncryptionKey': field(key, 'encryptionKey'),
        };
      }
      final remoteEpochs = field(archive, 'identityEpochs');
      for (final entry in trust.entries) {
        final previous = epochs[entry.key] as int? ?? 0;
        final next = remoteEpochs == null
            ? 0
            : object(remoteEpochs)[entry.key] as int? ?? 0;
        if (pins.containsKey(entry.key) && pins[entry.key] != entry.value) {
          requireCrypto(
            previous != next,
            'Ключ собеседника отличается между устройствами.',
          );
          if (previous > next) continue;
        }
        pins[entry.key] = entry.value;
        epochs[entry.key] = next;
      }
      if (remoteEpochs != null) {
        for (final entry in object(remoteEpochs).entries) {
          final old = epochs[entry.key] as int? ?? 0;
          if ((entry.value as int) >= old) epochs[entry.key] = entry.value;
        }
      }
    }
    requireCrypto(
      history.length <= 1500 && pins.length <= 10000,
      'Архив слишком большой.',
    );
    final fingerprints = history.keys.toList()..sort();
    return {
      'IdentityPrivateKey': root,
      'Keys': [for (final f in fingerprints) history[f]],
      'TrustedAccounts': pins,
      'IdentityEpochs': epochs,
    };
  }

  Future<void> _sync(Json? password, {String? suppliedCode}) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final response = object(await api.request('GET', '/api/e2ee/recovery'));
      final remoteValue = field(response, 'vault');
      Json? remote;
      String? remotePlain;
      if (remoteValue == null) {
        requireCrypto(
          (_state?['revision'] as int? ?? 0) == 0,
          'Сервер потерял архив. Новые ключи не созданы.',
        );
        _state ??= {
          'code': b64u(randomBytes(32)),
          'revision': 0,
          'devices': <String, dynamic>{},
          'archive': {
            'IdentityPrivateKey': generateIdentity(),
            'Keys': <Json>[],
            'TrustedAccounts': <String, dynamic>{},
            'IdentityEpochs': <String, dynamic>{},
          },
        };
      } else {
        remote = object(remoteValue);
        requireCrypto(
          (field(remote, 'revision') as int) >=
              (_state?['revision'] as int? ?? 0),
          'Обнаружен откат архива.',
        );
        final rootChanged =
            _state != null &&
            publicIdentity(field(_archive, 'identityPrivateKey') as String) !=
                field(remote, 'identityKey');
        final provisionalConflict =
            rootChanged && (_state!['revision'] as int) == 0;
        String? code = rootChanged
            ? suppliedCode?.trim()
            : _state?['code'] as String? ?? suppliedCode?.trim();
        if (code == null && password != null) {
          final config = object(password['configuration']);
          final wrapper = field(config, 'envelope');
          if (wrapper != null) {
            code = RecoveryProtocol.openPassword(
              _user,
              object(field(config, 'credentials')),
              object(wrapper),
              password['key'] as String,
            );
          }
        }
        if (code == null) throw const RecoveryCodeRequired();
        remotePlain = RecoveryProtocol.openVault(remote, _user, code);
        final archive = object(jsonDecode(remotePlain));
        requireCrypto(
          publicIdentity(field(archive, 'identityPrivateKey') as String) ==
              field(remote, 'identityKey'),
          'Ключ внутри архива не совпадает с подписью.',
        );
        final localArchive =
            _state == null || (rootChanged && !provisionalConflict)
            ? null
            : provisionalConflict
            ? {
                'IdentityPrivateKey': field(archive, 'identityPrivateKey'),
                'Keys': field(_archive, 'keys'),
                'TrustedAccounts': <String, dynamic>{},
              }
            : _archive;
        final merged = _mergeArchives(archive, localArchive);
        _state = {
          'code': code,
          'revision': field(remote, 'revision'),
          'archive': merged,
          'devices': rootChanged && !provisionalConflict
              ? <String, dynamic>{}
              : _state?['devices'] ?? <String, dynamic>{},
        };
      }
      await _save();
      final archive = _mergeArchives(_archive, null);
      _state!['archive'] = archive;
      final plaintext = jsonEncode(archive);
      if (remotePlain != null &&
          jsonEncode(_mergeArchives(object(jsonDecode(remotePlain)), null)) ==
              plaintext) {
        return;
      }
      final revision = _state!['revision'] as int;
      final vault = RecoveryProtocol.sealVault(
        _user,
        revision + 1,
        field(archive, 'identityPrivateKey') as String,
        _state!['code'] as String,
        plaintext,
      );
      try {
        await api.request(
          'PUT',
          '/api/e2ee/recovery',
          body: {
            'expectedRevision': revision,
            'identityKey': vault['IdentityKey'],
            'ciphertext': vault['Ciphertext'],
            'signature': vault['Signature'],
          },
        );
        _state!['revision'] = revision + 1;
        await _save();
        return;
      } on ApiFailure catch (e) {
        if (e.status != 409) rethrow;
      }
    }
    throw const ApiFailure(
      409,
      'Архив обновляется на другом устройстве. Повторите попытку.',
    );
  }

  Future<void> _ensurePasswordEnvelope(Json? password) async {
    if (password == null) return;
    final config = object(password['configuration']);
    final credentials = object(field(config, 'credentials'));
    final existing = field(config, 'envelope');
    if (existing != null) {
      requireCrypto(
        RecoveryProtocol.openPassword(
                  _user,
                  credentials,
                  object(existing),
                  password['key'] as String,
                ) ==
                recoveryCode &&
            field(object(existing), 'identityKey') ==
                publicIdentity(field(_archive, 'identityPrivateKey') as String),
        'Парольная копия архива не совпадает.',
      );
      return;
    }
    final envelope = RecoveryProtocol.sealPassword(
      _user,
      field(config, 'credentialVersion') as int,
      credentials,
      field(_archive, 'identityPrivateKey') as String,
      recoveryCode!,
      password['key'] as String,
    );
    await api.request(
      'PUT',
      '/api/auth/password/recovery',
      body: {'envelope': envelope},
    );
  }

  Future<void> synchronize() => _exclusive(() async {
    await _sync(await _passwordConfiguration());
  });
  Future<void> _trust(DeviceKey device, {int? messageCreatedAt}) async {
    device.validate();
    final archive = _archive;
    final pins = object(field(archive, 'trustedAccounts'));
    final ownRoot = publicIdentity(
      field(archive, 'identityPrivateKey') as String,
    );
    final known = device.user == _user ? ownRoot : pins[device.user] as String?;
    if (known == device.accountIdentity) return;
    final changes = objects(
      await api.request('GET', '/api/e2ee/identities/${device.user}/changes'),
    );
    requireCrypto(
      changes.every(
        (c) =>
            field(c, 'userId') == device.user &&
            field(c, 'epoch') is int &&
            field(c, 'changedAt') is int,
      ),
      'Неверный журнал смены ключей.',
    );
    changes.sort(
      (a, b) => (field(a, 'epoch') as int).compareTo(field(b, 'epoch') as int),
    );
    var epoch = 0;
    if (known != null) {
      var current = known;
      for (final change in changes) {
        if (field(change, 'previousIdentityKey') != current) continue;
        current = field(change, 'identityKey') as String;
        epoch = field(change, 'epoch') as int;
        if (current == device.accountIdentity) break;
      }
      if (current != device.accountIdentity) {
        current = device.accountIdentity!;
        for (final change in changes) {
          if (field(change, 'previousIdentityKey') != current) continue;
          requireCrypto(
            messageCreatedAt != null &&
                messageCreatedAt <= (field(change, 'changedAt') as int),
            'Старый ключ использован после сброса E2EE.',
          );
          current = field(change, 'identityKey') as String;
          if (current == known) return;
        }
        throw const CryptoFailure(
          'Ключ аккаунта собеседника изменился без подтверждённого сброса.',
        );
      }
      identityChanges.add(device.user);
    } else {
      for (final change in changes) {
        if (field(change, 'identityKey') == device.accountIdentity) {
          epoch = field(change, 'epoch') as int;
        }
      }
    }
    {
      pins[device.user] = device.accountIdentity;
      final epochs = object(field(archive, 'identityEpochs') ?? {});
      epochs[device.user] = epoch;
      archive['TrustedAccounts'] = pins;
      archive['IdentityEpochs'] = epochs;
      _state!['archive'] = archive;
      await _save();
    }
  }

  Future<String> encrypt(
    Conversation chat,
    String text,
    String messageId, {
    String? replyTo,
    bool edit = false,
    List<Json> attachments = const [],
  }) => _exclusive(() async {
    requireCrypto(_ready, 'Ключи E2EE ещё не готовы.');
    final directory = object(
      await api.request(
        'GET',
        '/api/e2ee/conversations/${chat.type}/${chat.id}/keys',
      ),
    );
    final members = (field(directory, 'members') as List).cast<String>();
    final devices = objects(
      field(directory, 'devices'),
    ).map(DeviceKey.fromJson).toList();
    requireCrypto(
      field(directory, 'conversationId') == chat.id &&
          field(directory, 'recipientType') == chat.type &&
          members.contains(_user) &&
          devices.isNotEmpty &&
          devices.length <= 500 &&
          members.every((m) => devices.any((d) => d.user == m)) &&
          devices.every((d) => members.contains(d.user)) &&
          devices.any(
            (d) =>
                d.user == _user &&
                d.session == _session &&
                d.fingerprint == _device!.fingerprint,
          ),
      'Неполный или подменённый каталог устройств.',
    );
    for (final d in devices) {
      await _trust(d);
    }
    await _sync(
      await _passwordConfiguration(),
    ); // Persist TOFU pins to encrypted archive before use.
    return compute(_encrypt, {
      'text': text,
      'keys': _keys,
      'sender': _device,
      'conversation': chat.id,
      'type': chat.type,
      'devices': devices,
      'messageId': messageId,
      'replyTo': replyTo,
      'edit': edit,
      'attachments': attachments,
    });
  });
  Future<ChatMessage> decrypt(ChatMessage message) => _exclusive(() async {
    if (!message.content.startsWith(E2eeProtocol.prefix)) {
      return message.decoded('[Без E2EE] ${message.content}');
    }
    final env = E2eeProtocol.verifyEnvelope(message.content);
    final recipients = (field(env, 'recipients') as List).cast<String>();
    Json? findKey() {
      for (final key in objects(field(_archive, 'keys'))) {
        if (recipients.contains(_historyFingerprint(key))) return key;
      }
      return null;
    }

    var key = findKey();
    if (key == null) {
      await _sync(await _passwordConfiguration());
      key = findKey();
    }
    requireCrypto(
      key != null,
      'В архиве нет ключа этого сообщения. Синхронизируйте доверенное устройство.',
    );
    final plain = await compute(_decrypt, {'message': message, 'key': key});
    var signer = DeviceKey.fromJson(object(field(env, 'sender')));
    if (signer.accountIdentity == null) {
      final historical = DeviceKey.fromJson(
        object(
          await api.request(
            'GET',
            '/api/e2ee/conversations/${message.type}/${message.conversationId}/signers/${signer.session}',
            query: {'identityKey': signer.identity},
          ),
        ),
      );
      requireCrypto(
        historical.user == signer.user &&
            historical.session == signer.session &&
            historical.identity == signer.identity &&
            historical.encryption == signer.encryption,
        'Подменён исторический подписант.',
      );
      signer = historical;
    }
    await _trust(signer, messageCreatedAt: field(env, 'createdAt') as int);
    final revisionKey = '$_scope-message-${message.id}';
    final accepted = await api.store.read(revisionKey);
    final created = field(env, 'createdAt') as int,
        digest = hex(sha256(utf(message.content)));
    if (accepted != null) {
      final previous = object(jsonDecode(accepted));
      requireCrypto(
        created > (previous['createdAt'] as int) ||
            (created == previous['createdAt'] && digest == previous['hash']),
        'Получена устаревшая версия сообщения.',
      );
    }
    await api.store.write(
      revisionKey,
      jsonEncode({'createdAt': created, 'hash': digest}),
    );
    return message.decoded(
      plain['text'] as String,
      objects(plain['attachments']),
    );
  });
  Future<void> changePassword(String oldPassword, String newPassword) =>
      _exclusive(() async {
        requireCrypto(
          oldPassword != newPassword,
          'Новый пароль должен отличаться.',
        );
        await _sync(await _passwordConfiguration());
        final auth = AuthService(api);
        final authorized = await auth.authorize('change', oldPassword);
        final prepared = await auth.newCredentials(newPassword);
        final grant = object(authorized['grant']),
            credentials = object(prepared['credentials']);
        final version = (grant['credentialVersion'] as int) + 1;
        final envelope = RecoveryProtocol.sealPassword(
          _user,
          version,
          credentials,
          field(_archive, 'identityPrivateKey') as String,
          recoveryCode!,
          prepared['key'] as String,
        );
        final savedKey = jsonEncode({
          'key': prepared['key'],
          'salt': field(credentials, 'salt'),
          'identity': field(credentials, 'identity'),
          'version': version,
        });
        final key = AuthService.passwordKey(api, _user);
        await api.store.write('$key-pending', savedKey);
        await api.request(
          'POST',
          '/api/auth/password/change',
          body: {
            'authorizationId': grant['authorizationId'],
            'credentials': credentials,
            'envelope': envelope,
          },
        );
        await api.store.write(key, savedKey);
        await api.store.remove('$key-pending');
      });
  Future<bool> _completePendingReset() async {
    final encoded = await api.store.read('$_stateKey-reset');
    if (encoded == null) return false;
    final pending = object(jsonDecode(encoded));
    final remote = field(
      object(await api.request('GET', '/api/e2ee/recovery')),
      'vault',
    );
    if (remote == null) {
      throw const CryptoFailure('Нельзя проверить завершение сброса E2EE.');
    }
    final candidate = object(pending['state']),
        candidateArchive = object(candidate['archive']);
    if (field(object(remote), 'identityKey') !=
        publicIdentity(
          field(candidateArchive, 'identityPrivateKey') as String,
        )) {
      return false;
    }
    RecoveryProtocol.openVault(
      object(remote),
      _user,
      candidate['code'] as String,
    );
    candidate['revision'] = field(object(remote), 'revision');
    _state = candidate;
    await _save();
    await api.store.remove('$_stateKey-reset');
    return true;
  }

  Future<void> resetEncryption(String password) => _exclusive(() async {
    _ready = false;
    if (await _completePendingReset()) return;
    final remote = object(
      field(object(await api.request('GET', '/api/e2ee/recovery')), 'vault'),
    );
    final authorized = await AuthService(api).authorize('reset', password);
    final config = object(await api.request('GET', '/api/auth/password'));
    requireCrypto(
      field(config, 'credentialVersion') ==
          object(authorized['grant'])['credentialVersion'],
      'Пароль изменился.',
    );
    var pendingEncoded = await api.store.read('$_stateKey-reset');
    Json pending;
    if (pendingEncoded == null) {
      final keys = await compute(generateDeviceKeys, null),
          root = generateIdentity();
      final code = b64u(randomBytes(32));
      final state = {
        'code': code,
        'revision': field(remote, 'revision'),
        'archive': {
          'IdentityPrivateKey': root,
          'Keys': [
            {
              'IdentityKey': publicIdentity(keys.identity),
              'EncryptionKey': keys.encryption,
            },
          ],
          'TrustedAccounts': <String, dynamic>{},
          'IdentityEpochs': <String, dynamic>{},
        },
        'devices': {
          _session: {
            'keys': keys.toJson(),
            'generation': 0,
            'previous': null,
            'rotatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'pending': true,
          },
        },
      };
      pending = {
        'expectedIdentity': field(remote, 'identityKey'),
        'expectedRevision': field(remote, 'revision'),
        'state': state,
      };
      pendingEncoded = jsonEncode(pending);
      await api.store.write('$_stateKey-reset', pendingEncoded);
    } else {
      pending = object(jsonDecode(pendingEncoded));
    }
    requireCrypto(
      pending['expectedIdentity'] == field(remote, 'identityKey') &&
          pending['expectedRevision'] == field(remote, 'revision'),
      'Архив изменился. Проверьте завершение сброса перед повтором.',
    );
    final replacement = object(pending['state']),
        archive = object(replacement['archive']);
    final root = field(archive, 'identityPrivateKey') as String;
    final vault = RecoveryProtocol.sealVault(
      _user,
      (pending['expectedRevision'] as int) + 1,
      root,
      replacement['code'] as String,
      jsonEncode(archive),
    );
    final envelope = RecoveryProtocol.sealPassword(
      _user,
      field(config, 'credentialVersion') as int,
      object(field(config, 'credentials')),
      root,
      replacement['code'] as String,
      authorized['key'] as String,
    );
    await api.request(
      'POST',
      '/api/auth/password/reset-encryption',
      body: {
        'authorizationId': object(authorized['grant'])['authorizationId'],
        'expectedIdentityKey': pending['expectedIdentity'],
        'expectedRevision': pending['expectedRevision'],
        'vault': vault,
        'envelope': envelope,
      },
    );
    await _completePendingReset();
    // Keep the password-derived key in sync, including sessions created before it was saved.
    await api.store.write(
      AuthService.passwordKey(api, _user),
      jsonEncode({
        'key': authorized['key'],
        'salt': authorized['salt'],
        'identity': authorized['identity'],
        'version': field(config, 'credentialVersion'),
      }),
    );
  });
}

String _encrypt(Json j) => E2eeProtocol.encrypt(
  text: j['text'] as String,
  keys: j['keys'] as DeviceKeys,
  sender: j['sender'] as DeviceKey,
  conversation: j['conversation'] as String,
  type: j['type'] as int,
  devices: (j['devices'] as List).cast<DeviceKey>(),
  messageId: j['messageId'] as String,
  replyTo: j['replyTo'] as String?,
  edit: j['edit'] as bool,
  attachments: objects(j['attachments']),
);
Json _decrypt(Json j) {
  final m = j['message'] as ChatMessage, key = object(j['key']);
  return E2eeProtocol.decrypt(
    value: m.content,
    historyIdentity: field(key, 'identityKey') as String,
    historyEncryption: field(key, 'encryptionKey') as String,
    messageId: m.id,
    conversation: m.conversationId,
    type: m.type,
    author: m.senderId,
    replyTo: m.replyTo,
    edit: m.edited,
  );
}
