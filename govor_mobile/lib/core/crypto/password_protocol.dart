import 'package:cryptography/cryptography.dart' as crypto;

import '../models.dart';
import 'primitives.dart';

class PasswordMaterial {
  const PasswordMaterial(this.secret, this.archiveKey);
  final String secret, archiveKey;
}

class SrpEphemeral {
  const SrpEphemeral(this.secret, this.public);
  final String secret, public;
}

class SrpProof {
  const SrpProof(this.key, this.proof, this.serverProof);
  final String key, proof, serverProof;
  void verifyServer(String actual) {
    requireCrypto(
      actual.length == 128 && sameBytes(unhex(actual), unhex(serverProof)),
      'Сервер не подтвердил пароль.',
    );
  }
}

/// Wire-compatible with srp.net 1.0.7 `Create4096<SHA512>`.
/// All group elements are 512-byte big endian; hash/salt lengths are preserved.
class PasswordProtocol {
  static final prime = BigInt.parse(
    'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A92108011A723C12A787E6D788719A10BDBA5B2699C327186AF4E23C1A946834B6150BDA2583E9CA2AD44CE8DBBBC2DB04DE8EF92E8EFC141FBECAA6287C59474E6BC05D99B2964FA090C3A2233BA186515BE7ED1F612970CEE2D7AFB81BDD762170481CD0069127D5B05AA993B4EA988D8FDDC186FFB7DC90A6C08F4DF435C934063199FFFFFFFFFFFFFFFF',
    radix: 16,
  );
  static final generator = BigInt.from(5);
  static bool hexLength(String s, int length) =>
      s.length == length && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
  static Future<PasswordMaterial> derive(
    String password,
    String salt,
    String identity,
  ) async {
    requireCrypto(
      password.length >= 8 &&
          password.length <= 256 &&
          hexLength(salt, 64) &&
          hexLength(identity, 64),
      'Неверные параметры пароля.',
    );
    final master = await crypto.Pbkdf2.hmacSha256(
      iterations: 600000,
      bits: 256,
    ).deriveKey(secretKey: crypto.SecretKey(utf(password)), nonce: unhex(salt));
    final extracted = bytes(await master.extractBytes());
    try {
      final hkdf = crypto.Hkdf(hmac: crypto.Hmac.sha256(), outputLength: 32);
      Future<String> deriveDomain(String domain) async => b64u(
        await (await hkdf.deriveKey(
          secretKey: crypto.SecretKey(extracted),
          nonce: const [],
          info: utf('$domain\n$identity'),
        )).extractBytes(),
      );
      return PasswordMaterial(
        await deriveDomain('govor-auth-v1'),
        await deriveDomain('govor-password-archive-v1'),
      );
    } finally {
      extracted.fillRange(0, extracted.length, 0);
    }
  }

  static SrpEphemeral ephemeral() {
    final secret = randomBytes(64);
    return SrpEphemeral(
      hex(secret),
      hex(integerBytes(generator.modPow(integer(secret), prime), 512)),
    );
  }

  static BigInt privateKey(String salt, String identity, String secret) =>
      integer(sha512([...unhex(salt), ...sha512(utf('$identity:$secret'))]));
  static String verifier(String salt, String identity, String secret) => hex(
    integerBytes(
      generator.modPow(privateKey(salt, identity, secret), prime),
      512,
    ),
  );
  static SrpProof prove(
    SrpEphemeral ephemeral,
    String serverPublic,
    String salt,
    String identity,
    String secret,
  ) {
    requireCrypto(
      hexLength(serverPublic, 1024) &&
          hexLength(salt, 64) &&
          hexLength(identity, 64),
      'Неверные SRP-параметры.',
    );
    final nBytes = integerBytes(prime, 512), gBytes = integerBytes(generator);
    final a = integer(unhex(ephemeral.secret)),
        bigA = unhex(ephemeral.public),
        bigB = unhex(serverPublic);
    final b = integer(bigB);
    requireCrypto(
      b > BigInt.zero && b < prime,
      'Неверное доказательство сервера.',
    );
    final x = privateKey(salt, identity, secret);
    final k = integer(sha512([...nBytes, ...integerBytes(generator, 512)]));
    final u = integer(sha512([...bigA, ...bigB]));
    requireCrypto(u != BigInt.zero, 'Неверный SRP scramble.');
    final base = (b - k * generator.modPow(x, prime)) % prime;
    final s = base.modPow(a + u * x, prime);
    final key = sha512(integerBytes(s, 512));
    final hn = sha512(nBytes), hg = sha512(gBytes);
    final proof = sha512([
      for (var i = 0; i < 64; i++) hn[i] ^ hg[i],
      ...sha512(utf(identity)),
      ...unhex(salt),
      ...bigA,
      ...bigB,
      ...key,
    ]);
    return SrpProof(
      hex(key),
      hex(proof),
      hex(sha512([...bigA, ...proof, ...key])),
    );
  }

  static void validateCredentials(Json credentials) {
    final v = field(credentials, 'verifier') as String;
    requireCrypto(
      field(credentials, 'version') == 1 &&
          hexLength(field(credentials, 'salt') as String, 64) &&
          hexLength(field(credentials, 'identity') as String, 64) &&
          hexLength(v, 1024),
      'Неверные SRP credentials.',
    );
    final n = integer(unhex(v));
    requireCrypto(
      n > BigInt.one && n < prime - BigInt.one,
      'Неверный SRP verifier.',
    );
  }

  static Json canonicalCredentials(Json j) => {
    'Version': field(j, 'version'),
    'Salt': field(j, 'salt'),
    'Identity': field(j, 'identity'),
    'Verifier': field(j, 'verifier'),
  };
}
