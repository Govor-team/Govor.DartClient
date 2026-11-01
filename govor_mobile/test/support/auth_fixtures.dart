import 'dart:convert';
import 'package:govor_mobile/core/crypto/primitives.dart';
import 'package:govor_mobile/core/models.dart';

const testUser = '11111111-1111-4111-8111-111111111111';
const testSession = '22222222-2222-4222-8222-222222222222';
String testToken(String version, {String user = testUser, int? expiry}) =>
    'header.${b64u(utf(jsonEncode({'userId': user, 'sid': testSession, 'exp': expiry ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'version': version})))}.signature';
Json tokenJson(String version) => {
  'accessToken': testToken(version),
  'refreshToken': 'refresh-$version',
};
