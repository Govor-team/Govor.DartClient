import 'dart:convert';

import '../models.dart';
import 'password_protocol.dart';
import 'primitives.dart';

class RecoveryProtocol {
  static String sealDirect(String key, Json payload) {
    final secret = unb64u(key), nonce = randomBytes(12);
    try {
      final header = b64u(utf('{"alg":"dir","enc":"A256GCM"}'));
      final sealed = aesSeal(
        secret,
        nonce,
        utf(jsonEncode(payload)),
        utf(header),
      );
      return '$header..${b64u(nonce)}.${b64u(sealed.sublist(0, sealed.length - 16))}.${b64u(sealed.sublist(sealed.length - 16))}';
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
  }

  static List<String> validateDirect(String value, {int maxLength = 4000000}) {
    requireCrypto(
      value.length >= 50 && value.length <= maxLength,
      'Неверный размер архива.',
    );
    final parts = value.split('.');
    requireCrypto(
      parts.length == 5 && parts[1].isEmpty,
      'Неверный JWE архива.',
    );
    final header = object(jsonDecode(utf8.decode(unb64u(parts[0]))));
    requireCrypto(
      header.length == 2 &&
          header['alg'] == 'dir' &&
          header['enc'] == 'A256GCM' &&
          unb64u(parts[2]).length == 12 &&
          unb64u(parts[4]).length == 16,
      'Неверный алгоритм архива.',
    );
    return parts;
  }

  static Json openDirect(String key, String ciphertext) {
    final parts = validateDirect(ciphertext), secret = unb64u(key);
    try {
      return object(
        jsonDecode(
          utf8.decode(
            aesOpen(secret, unb64u(parts[2]), [
              ...unb64u(parts[3]),
              ...unb64u(parts[4]),
            ], utf(parts[0])),
          ),
        ),
      );
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
  }

  static Json vaultBinding(Json vault) => {
    'purpose': 'govor-recovery-v1',
    'UserId': field(vault, 'userId'),
    'Revision': field(vault, 'revision'),
    'IdentityKey': field(vault, 'identityKey'),
    'Ciphertext': field(vault, 'ciphertext'),
  };
  static Json sealVault(
    String user,
    int revision,
    String root,
    String code,
    String plaintext,
  ) {
    requireCrypto(validId(user) && revision > 0, 'Неверный контекст архива.');
    final vault = {
      'UserId': user,
      'Revision': revision,
      'IdentityKey': publicIdentity(root),
      'Ciphertext': sealDirect(code, {
        'Version': 1,
        'UserId': user,
        'Revision': revision,
        'Plaintext': plaintext,
      }),
    };
    return {
      ...vault,
      'Signature': base64.encode(
        sign(root, utf(dotnetJson(vaultBinding(vault)))),
      ),
    };
  }

  static String openVault(Json vault, String user, String code) {
    requireCrypto(
      field(vault, 'userId') == user && (field(vault, 'revision') as int) > 0,
      'Архив другого аккаунта.',
    );
    validateDirect(field(vault, 'ciphertext') as String);
    verify(
      field(vault, 'identityKey') as String,
      utf(dotnetJson(vaultBinding(vault))),
      base64.decode(field(vault, 'signature') as String),
    );
    final payload = openDirect(
      code.trim(),
      field(vault, 'ciphertext') as String,
    );
    requireCrypto(
      field(payload, 'version') == 1 &&
          field(payload, 'userId') == user &&
          field(payload, 'revision') == field(vault, 'revision'),
      'Контекст архива подменён.',
    );
    return field(payload, 'plaintext') as String;
  }

  static Json passwordBinding(String user, Json credentials, Json envelope) => {
    'purpose': 'govor-password-recovery-v1',
    'user': user,
    'credentials': PasswordProtocol.canonicalCredentials(credentials),
    'IdentityKey': field(envelope, 'identityKey'),
    'CredentialVersion': field(envelope, 'credentialVersion'),
    'Ciphertext': field(envelope, 'ciphertext'),
  };
  static Json sealPassword(
    String user,
    int version,
    Json credentials,
    String root,
    String code,
    String archiveKey,
  ) {
    PasswordProtocol.validateCredentials(credentials);
    final identity = publicIdentity(root);
    final envelope = {
      'IdentityKey': identity,
      'CredentialVersion': version,
      'Ciphertext': sealDirect(archiveKey, {
        'Version': 1,
        'UserId': user,
        'IdentityKey': identity,
        'CredentialVersion': version,
        'Code': code,
      }),
    };
    return {
      ...envelope,
      'Signature': base64.encode(
        sign(
          root,
          utf(dotnetJson(passwordBinding(user, credentials, envelope))),
        ),
      ),
    };
  }

  static String openPassword(
    String user,
    Json credentials,
    Json envelope,
    String archiveKey,
  ) {
    PasswordProtocol.validateCredentials(credentials);
    requireCrypto(
      (field(envelope, 'credentialVersion') as int) > 0,
      'Неверная версия пароля.',
    );
    validateDirect(field(envelope, 'ciphertext') as String, maxLength: 4096);
    verify(
      field(envelope, 'identityKey') as String,
      utf(dotnetJson(passwordBinding(user, credentials, envelope))),
      base64.decode(field(envelope, 'signature') as String),
    );
    final payload = openDirect(
      archiveKey,
      field(envelope, 'ciphertext') as String,
    );
    requireCrypto(
      field(payload, 'version') == 1 &&
          field(payload, 'userId') == user &&
          field(payload, 'identityKey') == field(envelope, 'identityKey') &&
          field(payload, 'credentialVersion') ==
              field(envelope, 'credentialVersion') &&
          unb64u(field(payload, 'code') as String).length == 32,
      'Контекст парольного архива подменён.',
    );
    return field(payload, 'code') as String;
  }
}
