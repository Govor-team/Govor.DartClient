import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/crypto/e2ee_protocol.dart';
import 'package:govor_mobile/core/media/attachment_repository.dart';
import 'package:govor_mobile/core/media/media_cache.dart';
import 'package:govor_mobile/core/media/media_cache_store.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/auth_fixtures.dart';

class MemoryMediaStore implements MediaCacheStore {
  final data = <String, Uint8List>{};
  final synthetic = <String, int>{};
  final removed = <String>[];
  @override
  Future<List<CacheEntry>> entries() async => [
    for (final e in synthetic.entries)
      (key: e.key, bytes: e.value, touched: DateTime.utc(2020)),
    for (final e in data.entries)
      (key: e.key, bytes: e.value.length, touched: DateTime.utc(2021)),
  ];
  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Uint8List value) async =>
      data[key] = Uint8List.fromList(value);
  @override
  Future<void> remove(String key) async {
    removed.add(key);
    synthetic.remove(key);
    data.remove(key);
  }
}

void main() {
  test(
    'media cache reuses authenticated ciphertext across sessions and isolates accounts',
    () async {
      final original = Uint8List.fromList([1, 3, 5, 7]);
      final sealed = E2eeProtocol.encryptAttachment(original);
      final store = MemoryMediaStore();
      var requests = 0;
      Future<ApiClient> client(String user) async {
        final api = ApiClient(
          ServerAddress('https://cache.test'),
          MemorySecretStore(),
          client: MockClient((_) async {
            requests++;
            return user == testUser
                ? http.Response.bytes(sealed.data, 200)
                : http.Response('', 403);
          }),
        );
        addTearDown(api.close);
        await api.accept(TokenPair(testToken('media', user: user), 'refresh'));
        return api;
      }

      final api = await client(testUser);
      final file = Attachment(
        id: testSession,
        key: sealed.key,
        name: 'private.png',
        mime: 'image/png',
      );
      final cache = MediaCache(store: store);
      final first = EncryptedAttachmentRepository(api, disk: cache);
      expect(await Future.wait([first.load(file), first.load(file)]), [
        original,
        original,
      ]);
      expect(requests, 1);
      expect(store.data.values.single, sealed.data);
      expect(store.data.keys.single, matches(r'^[A-F0-9]{64}$'));
      first.clear();

      final reopened = EncryptedAttachmentRepository(
        api,
        disk: MediaCache(store: store),
      );
      expect(await reopened.load(file), original);
      expect(requests, 1);

      final other = await client('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      await expectLater(
        EncryptedAttachmentRepository(other, disk: cache).load(file),
        throwsA(isA<ApiFailure>()),
      );
      expect(requests, 2);

      store.data.values.single[0] ^= 1;
      final afterCorruption = EncryptedAttachmentRepository(api, disk: cache);
      expect(await afterCorruption.load(file), original);
      expect(requests, 3);
      expect(store.data.values.single, sealed.data);
    },
  );

  test(
    'limit evicts older files, persists the choice, and clearing rejects in-flight writes',
    () async {
      var persisted = 1;
      final store = MemoryMediaStore()..synthetic['old'] = bytesPerGiB - 3;
      final cache = MediaCache(
        store: store,
        loadLimit: () async => persisted,
        saveLimit: (limit) async => persisted = limit,
      );
      final data = Uint8List.fromList([1, 2, 3, 4]);
      await cache.write('new', data, revision: cache.revision);
      expect(store.removed, ['old']);
      expect(await cache.stats(), (limit: 1, bytes: 4));
      final revision = cache.revision;
      await cache.clear();
      await cache.write('in-flight', data, revision: revision);
      expect(store.data, isEmpty);
      await cache.setLimit(0);
      await cache.write('disabled', data, revision: cache.revision);
      expect(store.data, isEmpty);
      expect(
        await MediaCache(
          store: store,
          loadLimit: () async => persisted,
        ).stats(),
        (limit: 0, bytes: 0),
      );
    },
  );
}
