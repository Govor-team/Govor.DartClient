import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/api_pagination.dart';
import 'package:govor_mobile/core/crypto/e2ee_protocol.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/core/media/attachment_repository.dart';
import 'package:govor_mobile/core/reaction_repository.dart';
import 'package:govor_mobile/core/attachment_files.dart';
import 'package:govor_mobile/core/media/playback_source_native.dart';
import 'dart:io';
import 'package:govor_mobile/features/media/attachment_cubit.dart';
import 'support/auth_fixtures.dart' show testToken;
import 'support/fake_attachments.dart';

ApiClient makeApi(Future<http.Response> Function(http.Request) handler) {
  final api = ApiClient(
    ServerAddress('https://test.example'),
    MemorySecretStore(),
    client: MockClient(handler),
  );
  api.tokens = TokenPair.fromJson({
    'accessToken': testToken('media'),
    'refreshToken': 'refresh',
  });
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cached plaintext cannot be changed or reused under another key',
    () async {
      var downloads = 0;
      final sealed = E2eeProtocol.encryptAttachment(
        Uint8List.fromList([1, 2, 3]),
      );
      final other = E2eeProtocol.encryptAttachment(Uint8List.fromList([4]));
      final api = makeApi((_) async {
        downloads++;
        return http.Response.bytes(sealed.data, 200);
      });
      addTearDown(api.close);
      final repo = EncryptedAttachmentRepository(api);
      final a = Attachment(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        key: sealed.key,
        name: 'a',
        mime: 'application/octet-stream',
      );
      final bytes = await repo.load(a);
      expect(() => bytes[0] = 9, throwsUnsupportedError);
      await expectLater(
        repo.load(
          Attachment(id: a.id, key: other.key, name: 'a', mime: a.mime),
        ),
        throwsA(anything),
      );
      expect(downloads, 2);
      expect(await repo.load(a), [1, 2, 3]);
    },
  );
  test('legacy video attachment metadata is only a hint until verified', () {
    final a = Attachment.fromJson({
      'mediaId': 'a',
      'key': 'key',
      'fileName': 'clip.MP4',
      'mimeType': 'application/octet-stream',
    });
    expect(a.isVideo, isTrue);
    expect(
      fileMime([0, 0, 0, 24, 102, 116, 121, 112, ...ascii.encode('avif')]),
      'application/octet-stream',
    );
  });
  test(
    'upload encrypts before transport, hides metadata and reuses verified local bytes',
    () async {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      var uploads = 0;
      final api = makeApi((request) async {
        uploads++;
        expect(request.url.path, '/api/media/upload');
        expect(
          latin1.decode(request.bodyBytes),
          contains('application/vnd.govor.encrypted'),
        );
        expect(
          latin1.decode(request.bodyBytes),
          isNot(contains('secret-name')),
        );
        expect(
          latin1.decode(request.bodyBytes),
          isNot(contains('EncryptedKey')),
        );
        return http.Response(
          '{"mediaId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}',
          200,
        );
      });
      addTearDown(api.close);
      final repo = EncryptedAttachmentRepository(api);
      final attachment = await repo.upload(payload, 'secret-name.bin');
      expect(attachment.name, 'secret-name.bin');
      expect(await repo.load(attachment), payload);
      expect(uploads, 1);
      expect(attachment.toString(), isNot(contains(attachment.key)));
    },
  );
  test('playback source deletes temporary plaintext after disposal', () async {
    final source = await PlaybackSource.create(
      Uint8List.fromList([1, 2, 3]),
      'video/mp4',
    );
    expect(await File(source.uri).readAsBytes(), [1, 2, 3]);
    await source.dispose();
    expect(await File(source.uri).exists(), isFalse);
  });
  test(
    'encrypted repository coalesces downloads, caches, evicts and clears',
    () async {
      var downloads = 0;
      final payload = Uint8List.fromList([1, 2, 3]);
      final sealed = E2eeProtocol.encryptAttachment(payload);
      final api = makeApi((request) async {
        downloads++;
        expect(request.headers['Authorization'], startsWith('Bearer '));
        return http.Response.bytes(sealed.data, 200);
      });
      addTearDown(api.close);
      final repo = EncryptedAttachmentRepository(api, maxCacheBytes: 3);
      final a = Attachment(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        key: sealed.key,
        name: 'a.bin',
        mime: 'application/octet-stream',
      );
      final b = Attachment(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        key: sealed.key,
        name: 'b.bin',
        mime: 'application/octet-stream',
      );
      final results = await Future.wait([repo.load(a), repo.load(a)]);
      expect(results.first, payload);
      expect(downloads, 1);
      await repo.load(a);
      expect(downloads, 1);
      await repo.load(b);
      await repo.load(a);
      expect(downloads, 3);
      repo.clear();
      await repo.load(a);
      expect(downloads, 4);
    },
  );
  test(
    'corrupt ciphertext never reaches a preview or successful cache',
    () async {
      var downloads = 0;
      final sealed = E2eeProtocol.encryptAttachment(
        Uint8List.fromList([1, 2, 3]),
      );
      sealed.data[sealed.data.length - 1] ^= 1;
      final api = makeApi((_) async {
        downloads++;
        return http.Response.bytes(sealed.data, 200);
      });
      addTearDown(api.close);
      final repo = EncryptedAttachmentRepository(api);
      final a = Attachment(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        key: sealed.key,
        name: 'a.png',
        mime: 'image/png',
      );
      await expectLater(repo.load(a), throwsA(anything));
      await expectLater(repo.load(a), throwsA(anything));
      expect(downloads, 2);
    },
  );
  test('session clear invalidates downloads already in flight', () async {
    final gate = Completer<http.Response>();
    final api = makeApi((_) => gate.future);
    addTearDown(api.close);
    final sealed = E2eeProtocol.encryptAttachment(Uint8List.fromList([1]));
    final repo = EncryptedAttachmentRepository(api);
    final task = repo.load(
      Attachment(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        key: sealed.key,
        name: 'a',
        mime: 'video/mp4',
      ),
    );
    final assertion = expectLater(task, throwsStateError);
    repo.clear();
    gate.complete(http.Response.bytes(sealed.data, 200));
    await assertion;
  });
  test('pagination loads subsequent pages and deduplicates IDs', () async {
    final skips = <String?>[];
    final api = makeApi((request) async {
      final skip = request.url.queryParameters['skip'];
      skips.add(skip);
      return http.Response(
        jsonEncode(
          skip == '0'
              ? List.generate(100, (i) => {'id': '$i'})
              : [
                  {'id': '99'},
                  {'id': '100'},
                ],
        ),
        200,
      );
    });
    addTearDown(api.close);
    final result = await loadApiPages(api, '/api/groups/mine');
    expect(result, hasLength(101));
    expect(skips, ['0', '100']);
  });
  test(
    'reaction repository handles no-content subscription and policy contract',
    () async {
      final api = makeApi((request) async {
        if (request.url.path.endsWith('/subscription')) {
          expect(request.method, 'PUT');
          return http.Response('', 204);
        }
        return http.Response('{"mode":2,"reactionIds":["a"]}', 200);
      });
      addTearDown(api.close);
      final repo = ApiReactionRepository(api);
      await repo.subscribe('pack', true);
      expect((await repo.policy('channel'))['mode'], 2);
      await expectLater(repo.shared('../escape'), throwsA(isA<ApiFailure>()));
    },
  );
  test('video MIME comes from its header and generic files stay generic', () {
    expect(
      fileMime([0, 0, 0, 24, 102, 116, 121, 112, 105, 115, 111, 109]),
      'video/mp4',
    );
    expect(
      fileMime([0x1a, 0x45, 0xdf, 0xa3, ...utf8.encode('webm')]),
      'video/webm',
    );
    expect(fileMime([1, 2, 3]), 'application/octet-stream');
  });
  test(
    'preview rejects a fake image even when its metadata says PNG',
    () async {
      final cubit = AttachmentCubit(
        FakeAttachments(Uint8List.fromList([1, 2, 3])),
        const Attachment(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          key: 'key',
          name: 'a.png',
          mime: 'image/png',
        ),
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.status, AttachmentStatus.failed);
      expect(cubit.state.bytes, isNull);
    },
  );
}
