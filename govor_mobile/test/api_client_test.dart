import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/crypto/primitives.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/auth_fixtures.dart';

void main() {
  test(
    'server origin, scheme and path validation prevents credential redirects',
    () {
      for (final value in [
        'http://evil.example',
        'https://u:p@host',
        'https://host/api',
        'https://host?q=1',
        'https://host/#token',
        'javascript:alert(1)',
      ]) {
        expect(() => ServerAddress(value), throwsA(isA<ApiFailure>()));
      }
      final address = ServerAddress('https://EXAMPLE.com:443/');
      expect(address.uri.origin, 'https://example.com');
      expect(() => address.endpoint('//evil.example'), throwsArgumentError);
      expect(() => address.endpoint('/api/../secret'), throwsArgumentError);
      expect(
        ServerAddress(
          'http://localhost:7155',
          allowLoopbackHttp: true,
        ).uri.port,
        7155,
      );
      expect(
        () => ServerAddress('http://192.168.1.1', allowLoopbackHttp: true),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'parallel 401s rotate refresh once and atomically save both tokens',
    () async {
      var refreshes = 0;
      final oldTokens = tokenJson('old');
      final refreshStarted = Completer<void>();
      final gate = Completer<void>();
      final store = MemorySecretStore();
      final api = ApiClient(
        ServerAddress('https://test.example'),
        store,
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          if (request.url.path.endsWith('/refresh')) {
            refreshes++;
            if (!refreshStarted.isCompleted) refreshStarted.complete();
            expect(
              object(jsonDecode(request.body))['refreshToken'],
              'refresh-old',
            );
            await gate.future;
            return http.Response(jsonEncode(tokenJson('new')), 200);
          }
          if (request.headers['Authorization'] ==
              'Bearer ${oldTokens['accessToken']}') {
            return http.Response('', 401);
          }
          return http.Response('{"ok":true}', 200);
        }),
      );
      addTearDown(api.close);
      await api.accept(TokenPair.fromJson(oldTokens));
      final requests = Future.wait([
        api.request('GET', '/one'),
        api.request('GET', '/two'),
      ]);
      await refreshStarted.future.timeout(const Duration(seconds: 5));
      gate.complete();
      expect((await requests).length, 2);
      expect(refreshes, 1);
      expect(api.tokens!.refresh, 'refresh-new');
      final stored = object(
        jsonDecode((await store.read('${api.server.scope}-tokens'))!),
      );
      expect(stored['refreshToken'], 'refresh-new');
      expect(stored['accessToken'], api.tokens!.access);
    },
  );
  test(
    'temporary refresh failure preserves session; invalid refresh removes tokens only',
    () async {
      var code = 503;
      final store = MemorySecretStore();
      final api = ApiClient(
        ServerAddress('https://test.example'),
        store,
        client: MockClient((_) async => http.Response('', code)),
      );
      addTearDown(api.close);
      await api.accept(TokenPair.fromJson(tokenJson('old')));
      await store.write('history-keys', 'keep');
      await expectLater(api.refresh(), throwsA(isA<ApiFailure>()));
      expect(api.tokens, isNotNull);
      code = 400;
      await expectLater(api.refresh(), throwsA(isA<ApiFailure>()));
      expect(api.tokens, isNull);
      expect(await store.read('history-keys'), 'keep');
    },
  );
  test('logout during refresh cannot resurrect tokens', () async {
    final gate = Completer<void>();
    final api = ApiClient(
      ServerAddress('https://test.example'),
      MemorySecretStore(),
      client: MockClient((_) async {
        await gate.future;
        return http.Response(jsonEncode(tokenJson('new')), 200);
      }),
    );
    addTearDown(api.close);
    await api.accept(TokenPair.fromJson(tokenJson('old')));
    final refresh = api.refresh();
    final assertion = expectLater(refresh, throwsA(isA<ApiFailure>()));
    await api.clearSession();
    gate.complete();
    await assertion;
    expect(api.tokens, isNull);
  });
  test('redirects are not followed and error bodies never reach UI', () async {
    var code = 302;
    final api = ApiClient(
      ServerAddress('https://test.example'),
      MemorySecretStore(),
      client: MockClient(
        (_) async => http.Response(
          'secret-refresh-token',
          code,
          headers: {'location': 'https://evil.example'},
        ),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.request('GET', '/server/ping', authenticated: false),
      throwsA(isA<ApiFailure>()),
    );
    code = 500;
    try {
      await api.request('GET', '/server/ping', authenticated: false);
      fail('Expected error');
    } on ApiFailure catch (e) {
      expect(e.message, isNot(contains('secret-refresh-token')));
    }
  });
  test('refresh rejects account substitution', () async {
    final api = ApiClient(
      ServerAddress('https://test.example'),
      MemorySecretStore(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'accessToken': testToken(
              'new',
              user: '33333333-3333-4333-8333-333333333333',
            ),
            'refreshToken': 'new',
          }),
          200,
        ),
      ),
    );
    addTearDown(api.close);
    await api.accept(TokenPair.fromJson(tokenJson('old')));
    await expectLater(api.refresh(), throwsA(isA<CryptoFailure>()));
    expect(api.tokens!.user, testUser);
  });
}
