import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

class CryptoFailure implements Exception {
  const CryptoFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

void requireCrypto(bool condition, String message) {
  if (!condition) throw CryptoFailure(message);
}

Uint8List bytes(List<int> value) => Uint8List.fromList(value);
Uint8List utf(String value) => bytes(utf8.encode(value));
String b64u(List<int> value) => base64Url.encode(value).replaceAll('=', '');
Uint8List unb64u(String value) => base64Url.decode(base64Url.normalize(value));
String hex(List<int> value) =>
    value.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
Uint8List unhex(String value) {
  requireCrypto(
    value.length.isEven && RegExp(r'^[a-fA-F0-9]+$').hasMatch(value),
    'Неверный hex.',
  );
  return bytes([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List randomBytes(int length) {
  final rng = Random.secure();
  return bytes(List.generate(length, (_) => rng.nextInt(256)));
}

SecureRandom secureRandom() =>
    FortunaRandom()..seed(KeyParameter(randomBytes(32)));
Uint8List sha256(List<int> value) => SHA256Digest().process(bytes(value));
Uint8List sha512(List<int> value) => SHA512Digest().process(bytes(value));
bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

BigInt integer(List<int> value) => BigInt.parse(hex(value), radix: 16);
Uint8List integerBytes(BigInt value, [int? length]) {
  var encoded = value.toRadixString(16);
  encoded = encoded.padLeft(
    length == null ? (encoded.length + 1) ~/ 2 * 2 : length * 2,
    '0',
  );
  return unhex(encoded);
}

String newId() {
  final v = randomBytes(16);
  v[6] = (v[6] & 15) | 64;
  v[8] = (v[8] & 63) | 128;
  final s = hex(v).toLowerCase();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

bool validId(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value) &&
    value != '00000000-0000-0000-0000-000000000000';

/// The binding records in .NET use System.Text.Json's default encoder.
String dotnetJson(Object? value) => jsonEncode(value).replaceAllMapped(
  RegExp("[+<>&'`\\u007f-\\uffff]"),
  (m) =>
      '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0').toUpperCase()}',
);

final _curve = ECDomainParameters('prime256v1');
ASN1Sequence _seq(List<ASN1Object> values) {
  final s = ASN1Sequence();
  for (final v in values) {
    s.add(v);
  }
  return s;
}

ASN1Object _oid(String v) => ASN1ObjectIdentifier.fromComponentString(v);
ASN1Sequence _parse(List<int> encoded) {
  final parser = ASN1Parser(bytes(encoded));
  final value = parser.nextObject();
  requireCrypto(
    value is ASN1Sequence && !parser.hasNext(),
    'Неверный DER ключ.',
  );
  return value as ASN1Sequence;
}

final _ecAlgorithm = _seq([
  _oid('1.2.840.10045.2.1'),
  _oid('1.2.840.10045.3.1.7'),
]);
final _rsaAlgorithm = _seq([_oid('1.2.840.113549.1.1.1'), ASN1Null()]);
void _algorithm(ASN1Object value, ASN1Sequence expected) => requireCrypto(
  sameBytes(value.encodedBytes, expected.encodedBytes),
  'Неподдерживаемый алгоритм ключа.',
);

String generateIdentity() {
  final gen = ECKeyGenerator()
    ..init(
      ParametersWithRandom(ECKeyGeneratorParameters(_curve), secureRandom()),
    );
  final private = gen.generateKeyPair().privateKey;
  final inner = _seq([
    ASN1Integer(BigInt.one),
    ASN1OctetString(integerBytes(private.d!, 32)),
  ]);
  return base64.encode(
    _seq([
      ASN1Integer(BigInt.zero),
      _ecAlgorithm,
      ASN1OctetString(inner.encodedBytes),
    ]).encodedBytes,
  );
}

ECPrivateKey signingPrivate(String encoded) {
  final outer = _parse(base64.decode(encoded));
  requireCrypto(outer.elements.length == 3, 'Неверный закрытый ключ.');
  _algorithm(outer.elements[1], _ecAlgorithm);
  final inner = _parse((outer.elements[2] as ASN1OctetString).octets);
  final d = integer((inner.elements[1] as ASN1OctetString).octets);
  requireCrypto(d > BigInt.zero && d < _curve.n, 'Неверный EC скаляр.');
  return ECPrivateKey(d, _curve);
}

String publicIdentity(String private) {
  final q = _curve.G * signingPrivate(private).d!;
  return base64.encode(
    _seq([_ecAlgorithm, ASN1BitString(q!.getEncoded(false))]).encodedBytes,
  );
}

ECPublicKey signingPublic(String encoded) {
  requireCrypto(encoded.length <= 200, 'Слишком большой ключ.');
  final outer = _parse(base64.decode(encoded));
  requireCrypto(outer.elements.length == 2, 'Неверный открытый ключ.');
  _algorithm(outer.elements[0], _ecAlgorithm);
  final bits = outer.elements[1] as ASN1BitString;
  requireCrypto(
    bits.unusedbits == 0 &&
        bits.stringValue.length == 65 &&
        bits.stringValue[0] == 4,
    'Неверная EC точка.',
  );
  final q = _curve.curve.decodePoint(bytes(bits.stringValue));
  requireCrypto(q != null && !q.isInfinity, 'Неверная EC точка.');
  return ECPublicKey(q, _curve);
}

Uint8List sign(String private, List<int> value) {
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter(signingPrivate(private)));
  final signature = signer.generateSignature(bytes(value)) as ECSignature;
  return bytes([
    ...integerBytes(signature.r, 32),
    ...integerBytes(signature.s, 32),
  ]);
}

void verify(String public, List<int> value, List<int> signature) {
  requireCrypto(signature.length == 64, 'Неверная длина подписи.');
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter(signingPublic(public)));
  requireCrypto(
    verifier.verifySignature(
      bytes(value),
      ECSignature(
        integer(signature.sublist(0, 32)),
        integer(signature.sublist(32)),
      ),
    ),
    'Подпись не прошла проверку.',
  );
}

String generateEncryptionKey() {
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 3072, 64),
        secureRandom(),
      ),
    );
  final key = generator.generateKeyPair().privateKey;
  final p = key.p!, q = key.q!, d = key.privateExponent!;
  final inner = _seq([
    for (final n in [
      BigInt.zero,
      key.modulus!,
      BigInt.from(65537),
      d,
      p,
      q,
      d % (p - BigInt.one),
      d % (q - BigInt.one),
      q.modInverse(p),
    ])
      ASN1Integer(n),
  ]);
  return base64.encode(
    _seq([
      ASN1Integer(BigInt.zero),
      _rsaAlgorithm,
      ASN1OctetString(inner.encodedBytes),
    ]).encodedBytes,
  );
}

RSAPrivateKey encryptionPrivate(String encoded) {
  final outer = _parse(base64.decode(encoded));
  _algorithm(outer.elements[1], _rsaAlgorithm);
  final inner = _parse((outer.elements[2] as ASN1OctetString).octets);
  BigInt n(int i) => (inner.elements[i] as ASN1Integer).valueAsBigInteger;
  requireCrypto(
    n(1).bitLength == 3072 && n(2) == BigInt.from(65537),
    'Нужен RSA-3072.',
  );
  return RSAPrivateKey(n(1), n(3), n(4), n(5));
}

String publicEncryption(String private) {
  final key = encryptionPrivate(private);
  return base64.encode(
    _seq([
      _rsaAlgorithm,
      ASN1BitString(
        _seq([
          ASN1Integer(key.modulus!),
          ASN1Integer(BigInt.from(65537)),
        ]).encodedBytes,
      ),
    ]).encodedBytes,
  );
}

RSAPublicKey encryptionPublic(String encoded) {
  requireCrypto(encoded.length <= 1000, 'Слишком большой ключ.');
  final outer = _parse(base64.decode(encoded));
  _algorithm(outer.elements[0], _rsaAlgorithm);
  final bits = outer.elements[1] as ASN1BitString;
  requireCrypto(bits.unusedbits == 0, 'Неверный RSA ключ.');
  final inner = _parse(bits.stringValue);
  final n = (inner.elements[0] as ASN1Integer).valueAsBigInteger;
  final e = (inner.elements[1] as ASN1Integer).valueAsBigInteger;
  requireCrypto(
    n.bitLength == 3072 && e == BigInt.from(65537),
    'Нужен RSA-3072.',
  );
  return RSAPublicKey(n, e);
}

Uint8List wrapKey(String public, List<int> value) {
  final cipher = OAEPEncoding.withSHA256(RSAEngine())
    ..init(
      true,
      ParametersWithRandom<PublicKeyParameter<RSAPublicKey>>(
        PublicKeyParameter<RSAPublicKey>(encryptionPublic(public)),
        secureRandom(),
      ),
    );
  return cipher.process(bytes(value));
}

Uint8List unwrapKey(String private, List<int> value) {
  requireCrypto(value.length == 384, 'Неверный RSA ciphertext.');
  final cipher = OAEPEncoding.withSHA256(RSAEngine())
    ..init(
      false,
      ParametersWithRandom<PrivateKeyParameter<RSAPrivateKey>>(
        PrivateKeyParameter<RSAPrivateKey>(encryptionPrivate(private)),
        secureRandom(),
      ),
    );
  return cipher.process(bytes(value));
}

Uint8List aesSeal(
  List<int> key,
  List<int> nonce,
  List<int> plaintext,
  List<int> aad,
) {
  requireCrypto(
    key.length == 32 && nonce.length == 12,
    'Неверные параметры AES.',
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(bytes(key)), 128, bytes(nonce), bytes(aad)),
    );
  return cipher.process(bytes(plaintext));
}

Uint8List aesOpen(
  List<int> key,
  List<int> nonce,
  List<int> ciphertextAndTag,
  List<int> aad,
) {
  requireCrypto(
    key.length == 32 && nonce.length == 12 && ciphertextAndTag.length >= 16,
    'Неверные параметры AES.',
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(bytes(key)), 128, bytes(nonce), bytes(aad)),
    );
  try {
    return cipher.process(bytes(ciphertextAndTag));
  } on InvalidCipherTextException {
    throw const CryptoFailure('Зашифрованные данные повреждены.');
  }
}
