import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'crypto/password_protocol.dart';
import 'crypto/primitives.dart';
import 'models.dart';

Future<Json> _derivePassword(Json args) async {
  final salt = args['salt'] as String, identity = args['identity'] as String;
  final material = await PasswordProtocol.derive(
    args['password'] as String,
    salt,
    identity,
  );
  final ephemeral = args['ephemeral'] as SrpEphemeral?;
  if (ephemeral != null) {
    final proof = PasswordProtocol.prove(
      ephemeral,
      args['public'] as String,
      salt,
      identity,
      material.secret,
    );
    return {'proof': proof, 'archiveKey': material.archiveKey};
  }
  return {
    'verifier': PasswordProtocol.verifier(salt, identity, material.secret),
    'archiveKey': material.archiveKey,
  };
}

/// The server confirms that this account has no SRP credentials yet.
/// Do not fall back to sending the password to a legacy login endpoint.
class LegacyAccountMigrationRequired implements Exception {
  const LegacyAccountMigrationRequired();

  @override
  String toString() => 'Для входа необходимо обновить защиту аккаунта.';
}

class AuthService {
  AuthService(this.api);
  final ApiClient api;
  static String passwordKey(ApiClient api, String user) =>
      '${api.server.scope}-$user-password';
  String get deviceInfo =>
      'Govor Flutter / ${kIsWeb ? 'web' : defaultTargetPlatform.name}';
  Future<void> login(String name, String password) async {
    final ephemeral = PasswordProtocol.ephemeral();
    final challenge = object(
      await api.request(
        'POST',
        '/api/auth/password/challenge',
        authenticated: false,
        body: {
          'name': name.trim(),
          'publicEphemeral': ephemeral.public.toLowerCase(),
          'deviceInfo': deviceInfo,
        },
      ),
    );
    if (challenge['legacy'] == true) {
      throw const LegacyAccountMigrationRequired();
    }
    requireCrypto(
      validId(challenge['challengeId']) &&
          (challenge['credentialVersion'] as int) > 0,
      'Неверный challenge.',
    );
    final derived = await compute(_derivePassword, {
      'password': password,
      'salt': challenge['salt'],
      'identity': challenge['identity'],
      'ephemeral': ephemeral,
      'public': challenge['publicEphemeral'],
    });
    final proof = derived['proof'] as SrpProof;
    final result = object(
      await api.request(
        'POST',
        '/api/auth/password/login',
        authenticated: false,
        body: {
          'challengeId': challenge['challengeId'],
          'proof': proof.proof.toLowerCase(),
        },
      ),
    );
    proof.verifyServer(result['serverProof'] as String);
    requireCrypto(
      result['credentialVersion'] == challenge['credentialVersion'],
      'Пароль изменился во время входа.',
    );
    final tokens = TokenPair.fromJson(result);
    tokens.validate();
    await api.store.write(
      passwordKey(api, tokens.user),
      jsonEncode({
        'key': derived['archiveKey'],
        'salt': challenge['salt'],
        'identity': challenge['identity'],
        'version': challenge['credentialVersion'],
      }),
    );
    await api.accept(tokens);
  }

  /// One-time upgrade of a legacy bcrypt account. The old password is sent
  /// ONLY to the legacy HTTPS login and the authenticated enrollment route.
  /// The new password is never sent: only its SRP verifier is uploaded.
  Future<void> migrateLegacyAccount(
    String name,
    String oldPassword,
    String newPassword,
  ) async {
    requireCrypto(
      newPassword.length >= 8 &&
          newPassword.length <= 256 &&
          newPassword != oldPassword,
      'Новый пароль должен отличаться от старого и содержать 8–256 символов.',
    );
    // Compute everything before acquiring the legacy session to minimize
    // its lifetime. If the server rejects enrollment, do not retain it.
    final generated = await newCredentials(newPassword);
    final result = object(await api.request(
      'POST',
      '/api/auth/login',
      authenticated: false,
      body: {
        'name': name.trim(),
        'password': oldPassword,
        'deviceInfo': deviceInfo,
      },
    ));
    final tokens = TokenPair.fromJson(result);
    tokens.validate();
    await api.accept(tokens);
    try {
      await api.request(
        'PUT',
        '/api/auth/password/enrollment',
        body: {
          'credentials': generated['credentials'],
          'legacyPassword': oldPassword,
        },
      );
    } finally {
      // No bcrypt-session should survive this one-time operation locally.
      await api.clearSession();
    }
    // A fresh SRP login establishes the archive key in secure storage.
    // On a network failure here, enrollment may have succeeded: next sign-in
    // should use the NEW password, never re-run legacy enrollment blindly.
    try {
      await login(name, newPassword);
    } catch (_) {
      throw StateError(
        'SRP-данные аккаунта обновлены, но повторный вход не удался. '
        'Попробуйте войти с НОВЫМ паролем.',
      );
    }
  }

  Future<void> register(String name, String password, String invitation) async {
    final salt = hex(randomBytes(32)), identity = hex(randomBytes(32));
    final derived = await compute(_derivePassword, {
      'password': password,
      'salt': salt,
      'identity': identity,
    });
    final result = object(
      await api.request(
        'POST',
        '/api/auth/register',
        authenticated: false,
        body: {
          'name': name.trim(),
          'inviteLink': invitation.trim(),
          'deviceInfo': deviceInfo,
          'srpSalt': salt,
          'srpIdentity': identity,
          'srpVerifier': (derived['verifier'] as String).toLowerCase(),
        },
      ),
    );
    final tokens = TokenPair.fromJson(result);
    tokens.validate();
    await api.store.write(
      passwordKey(api, tokens.user),
      jsonEncode({
        'key': derived['archiveKey'],
        'salt': salt,
        'identity': identity,
        'version': 1,
      }),
    );
    await api.accept(tokens);
  }

  Future<Json> authorize(String purpose, String password) async {
    requireCrypto(['change', 'reset'].contains(purpose), 'Неверное действие.');
    final ephemeral = PasswordProtocol.ephemeral();
    final challenge = object(
      await api.request(
        'POST',
        '/api/auth/password/$purpose/challenge',
        body: {
          'name': '',
          'publicEphemeral': ephemeral.public.toLowerCase(),
          'deviceInfo': deviceInfo,
        },
      ),
    );
    requireCrypto(
      challenge['legacy'] != true && validId(challenge['challengeId']),
      'Требуется SRP-вход.',
    );
    final derived = await compute(_derivePassword, {
      'password': password,
      'salt': challenge['salt'],
      'identity': challenge['identity'],
      'ephemeral': ephemeral,
      'public': challenge['publicEphemeral'],
    });
    final proof = derived['proof'] as SrpProof;
    final grant = object(
      await api.request(
        'POST',
        '/api/auth/password/$purpose/authorize',
        body: {
          'challengeId': challenge['challengeId'],
          'proof': proof.proof.toLowerCase(),
        },
      ),
    );
    proof.verifyServer(grant['serverProof'] as String);
    requireCrypto(
      grant['credentialVersion'] == challenge['credentialVersion'] &&
          validId(grant['authorizationId']),
      'Пароль изменился во время подтверждения.',
    );
    return {
      'grant': grant,
      'key': derived['archiveKey'],
      'salt': challenge['salt'],
      'identity': challenge['identity'],
    };
  }

  Future<Json> newCredentials(String password) async {
    final salt = hex(randomBytes(32)), identity = hex(randomBytes(32));
    final derived = await compute(_derivePassword, {
      'password': password,
      'salt': salt,
      'identity': identity,
    });
    return {
      'credentials': {
        'Version': 1,
        'Salt': salt,
        'Identity': identity,
        'Verifier': (derived['verifier'] as String).toLowerCase(),
      },
      'key': derived['archiveKey'],
    };
  }
}
