import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/auth_service.dart';
import 'package:govor_mobile/core/crypto/e2ee_protocol.dart';
import 'package:govor_mobile/core/crypto/primitives.dart';
import 'package:govor_mobile/core/crypto/recovery_protocol.dart';
import 'package:govor_mobile/core/encryption_service.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/auth_fixtures.dart' show tokenJson, testSession;

class EncryptionHarness {
  EncryptionHarness(this.fixture) {
    keys = DeviceKeys.fromJson(object(fixture['Keys']));
    device = DeviceKey.fromJson(object(fixture['Device']));
    archive = {
      'IdentityPrivateKey': fixture['RootKey'],
      'Keys': [keys.toJson()..['IdentityKey'] = device.identity],
      'TrustedAccounts': <String, dynamic>{},
      'IdentityEpochs': <String, dynamic>{},
    };
    vault = RecoveryProtocol.sealVault(
      fixture['User'] as String,
      1,
      fixture['RootKey'] as String,
      fixture['Code'] as String,
      jsonEncode(archive),
    );
    api = ApiClient(
      ServerAddress('https://fixture.example'),
      store,
      client: MockClient(_handle),
    );
    service = EncryptionService(api);
  }
  final Json fixture;
  final store = MemorySecretStore();
  late DeviceKeys keys;
  late DeviceKey device;
  late Json archive, vault;
  late ApiClient api;
  late EncryptionService service;
  List<Json> changes = [];
  DeviceKey? peer;
  bool failVaultWrite = false, conflictOnce = false;
  int registrations = 0, vaultWrites = 0;
  String get stateKey => '${api.server.scope}-${fixture['User']}-encryption';
  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path;
    if (path == '/api/auth/password') {
      return http.Response(
        jsonEncode({
          'credentials': fixture['Credentials'],
          'credentialVersion': 1,
          'envelope': fixture['PasswordEnvelope'],
        }),
        200,
      );
    }
    if (path == '/api/e2ee/recovery' && r.method == 'GET') {
      return http.Response(jsonEncode({'vault': vault}), 200);
    }
    if (path == '/api/e2ee/recovery' && r.method == 'PUT') {
      vaultWrites++;
      if (failVaultWrite) return http.Response('', 503);
      if (conflictOnce) {
        conflictOnce = false;
        final extra = {
          'IdentityKey': publicIdentity(generateIdentity()),
          'EncryptionKey': keys.encryption,
        };
        archive['Keys'] = [...objects(archive['Keys']), extra];
        vault = RecoveryProtocol.sealVault(
          fixture['User'] as String,
          (vault['Revision'] as int) + 1,
          fixture['RootKey'] as String,
          fixture['Code'] as String,
          jsonEncode(archive),
        );
        return http.Response('', 409);
      }
      final j = object(jsonDecode(r.body));
      expect(j['expectedRevision'], vault['Revision']);
      vault = {
        'UserId': fixture['User'],
        'Revision': (j['expectedRevision'] as int) + 1,
        'IdentityKey': j['identityKey'],
        'Ciphertext': j['ciphertext'],
        'Signature': j['signature'],
      };
      archive = object(
        jsonDecode(
          RecoveryProtocol.openVault(
            vault,
            fixture['User'] as String,
            fixture['Code'] as String,
          ),
        ),
      );
      return http.Response(jsonEncode(vault), 200);
    }
    if (path == '/api/e2ee/device') {
      final registered = DeviceKey.fromJson(object(jsonDecode(r.body)));
      registered.validate();
      final history = objects(archive['Keys']);
      expect(
        history.any(
          (k) =>
              field(k, 'identityKey') == registered.identity &&
              publicEncryption(field(k, 'encryptionKey') as String) ==
                  registered.encryption,
        ),
        isTrue,
        reason:
            'Never activate a device before its private decryption key is backed up.',
      );
      registrations++;
      return http.Response('{"registered":true}', 200);
    }
    if (path.endsWith('/keys')) {
      return http.Response(
        jsonEncode({
          'conversationId': fixture['Conversation'],
          'recipientType': 0,
          'members': [fixture['User'], if (peer != null) peer!.user],
          'devices': [device.toJson(), if (peer != null) peer!.toJson()],
        }),
        200,
      );
    }
    if (path.endsWith('/changes')) {
      return http.Response(jsonEncode(changes), 200);
    }
    fail('Unexpected API request: ${r.method} $path');
  }

  Future<void> prepare({bool local = true, int localRevision = 1}) async {
    await api.accept(TokenPair.fromJson(tokenJson('fixture')));
    await store.write(
      AuthService.passwordKey(api, fixture['User'] as String),
      jsonEncode({
        'key': fixture['ArchiveKey'],
        'salt': fixture['Salt'],
        'identity': fixture['Identity'],
        'version': 1,
      }),
    );
    if (local) {
      await store.write(
        stateKey,
        jsonEncode({
          'code': fixture['Code'],
          'revision': localRevision,
          'archive': archive,
          'devices': {
            testSession: {
              'keys': keys.toJson(),
              'generation': 0,
              'previous': null,
              'rotatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'pending': false,
            },
          },
        }),
      );
    }
  }
}

void main() {
  final fixture = object(
    jsonDecode(File('test/fixtures/dotnet.json').readAsStringSync()),
  );
  test(
    'initialization registers only archived certified keys and keeps pending state on network failure',
    () async {
      final h = EncryptionHarness(fixture);
      addTearDown(h.api.close);
      await h.prepare();
      await h.service.initialize();
      expect(h.registrations, 1);
      h.failVaultWrite = true;
      final state = object(jsonDecode((await h.store.read(h.stateKey))!));
      final archive = object(state['archive']);
      archive['TrustedAccounts'] = {
        newId(): publicIdentity(generateIdentity()),
      };
      state['archive'] = archive;
      await h.store.write(h.stateKey, jsonEncode(state));
      final retry = EncryptionService(h.api);
      await expectLater(retry.initialize(), throwsA(isA<ApiFailure>()));
      expect(h.registrations, 1);
      final preserved = object(jsonDecode((await h.store.read(h.stateKey))!));
      expect(object(preserved['devices']).containsKey(testSession), isTrue);
      expect(
        field(object(preserved['archive']), 'identityPrivateKey'),
        fixture['RootKey'],
      );
    },
  );
  test(
    'CAS conflict re-reads and merges remote and local history keys',
    () async {
      final h = EncryptionHarness(fixture);
      addTearDown(h.api.close);
      await h.prepare();
      final state = object(jsonDecode((await h.store.read(h.stateKey))!));
      final archive = object(state['archive']);
      archive['Keys'] = [
        ...objects(archive['Keys']),
        {
          'IdentityKey': publicIdentity(fixture['RootKey'] as String),
          'EncryptionKey': h.keys.encryption,
        },
      ];
      state['archive'] = archive;
      await h.store.write(h.stateKey, jsonEncode(state));
      h.conflictOnce = true;
      await h.service.initialize();
      expect(h.vaultWrites, 2);
      expect(objects(h.archive['Keys']), hasLength(3));
      expect(h.registrations, 1);
    },
  );
  test(
    'archive rollback is rejected without replacing local secrets',
    () async {
      final h = EncryptionHarness(fixture);
      addTearDown(h.api.close);
      await h.prepare(localRevision: 4);
      final before = await h.store.read(h.stateKey);
      await expectLater(h.service.initialize(), throwsA(isA<CryptoFailure>()));
      expect(await h.store.read(h.stateKey), before);
      expect(h.registrations, 0);
    },
  );
  test(
    'missing recovery code does not create a replacement account identity',
    () async {
      final h = EncryptionHarness(fixture);
      addTearDown(h.api.close);
      await h.prepare(local: false);
      await h.store.remove(
        AuthService.passwordKey(h.api, fixture['User'] as String),
      );
      await expectLater(
        h.service.initialize(),
        throwsA(isA<RecoveryCodeRequired>()),
      );
      expect(await h.store.read(h.stateKey), isNull);
      expect(h.vaultWrites, 0);
      expect(h.registrations, 0);
    },
  );
  test(
    'substituted conversation context fails before new trust is accepted',
    () async {
      final h = EncryptionHarness(fixture);
      addTearDown(h.api.close);
      await h.prepare();
      await h.service.initialize();
      final message = ChatMessage(
        id: newId(),
        senderId: fixture['User'] as String,
        conversationId: fixture['Conversation'] as String,
        type: 0,
        sentAt: DateTime.now(),
        content: fixture['Message'] as String,
      );
      await expectLater(
        h.service.decrypt(message),
        throwsA(isA<CryptoFailure>()),
      );
      final state = object(jsonDecode((await h.store.read(h.stateKey))!));
      expect(
        object(field(object(state['archive']), 'trustedAccounts')),
        isEmpty,
      );
    },
  );
  test(
    'authorized peer reset advances trust; pre-reset signatures remain valid; old key cannot send afterwards',
    () async {
      final h = EncryptionHarness(fixture);
      addTearDown(h.api.close);
      final peerId = newId(),
          oldRoot = generateIdentity(),
          newRoot = generateIdentity();
      final oldKeys = DeviceKeys(oldRoot, h.keys.encryption),
          newKeys = DeviceKeys(newRoot, h.keys.encryption);
      final oldDevice = devicePublic(oldKeys, peerId, newId()).certify(oldRoot);
      final newDevice = devicePublic(newKeys, peerId, newId()).certify(newRoot);
      h.archive['TrustedAccounts'] = {peerId: publicIdentity(oldRoot)};
      h.archive['IdentityEpochs'] = {peerId: 0};
      h.vault = RecoveryProtocol.sealVault(
        fixture['User'] as String,
        1,
        fixture['RootKey'] as String,
        fixture['Code'] as String,
        jsonEncode(h.archive),
      );
      await h.prepare();
      await h.service.initialize();
      h.peer = newDevice;
      h.changes = [
        {
          'UserId': peerId,
          'Epoch': 1,
          'PreviousIdentityKey': publicIdentity(oldRoot),
          'IdentityKey': publicIdentity(newRoot),
          'ChangedAt': 2000,
        },
      ];
      await h.service.encrypt(
        Conversation(id: fixture['Conversation'] as String, title: 'peer'),
        'New message',
        newId(),
      );
      expect(
        object(field(h.archive, 'trustedAccounts'))[peerId],
        publicIdentity(newRoot),
      );
      Future<ChatMessage> oldMessage(int created) {
        final id = newId();
        final content = E2eeProtocol.encrypt(
          text: 'history',
          keys: oldKeys,
          sender: oldDevice,
          conversation: fixture['Conversation'] as String,
          type: 0,
          devices: [h.device],
          messageId: id,
          createdAt: created,
        );
        return h.service.decrypt(
          ChatMessage(
            id: id,
            senderId: peerId,
            conversationId: fixture['Conversation'] as String,
            type: 0,
            sentAt: DateTime.now(),
            content: content,
          ),
        );
      }

      expect((await oldMessage(1000)).text, 'history');
      await expectLater(oldMessage(3000), throwsA(isA<CryptoFailure>()));
      h.peer = devicePublic(
        DeviceKeys(generateIdentity(), h.keys.encryption),
        peerId,
        newId(),
      ).certify(generateIdentity());
      await expectLater(
        h.service.encrypt(
          Conversation(id: fixture['Conversation'] as String, title: 'peer'),
          'Blocked',
          newId(),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    },
  );
}
