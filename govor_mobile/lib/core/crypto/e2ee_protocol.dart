import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';
import 'primitives.dart';

class DeviceKeys {
  const DeviceKeys(this.identity, this.encryption);
  factory DeviceKeys.fromJson(Json j) => DeviceKeys(
    field(j, 'identityKey') as String,
    field(j, 'encryptionKey') as String,
  );
  final String identity, encryption;
  Json toJson() => {'IdentityKey': identity, 'EncryptionKey': encryption};
}

DeviceKeys generateDeviceKeys(Object? _) =>
    DeviceKeys(generateIdentity(), generateEncryptionKey());

class DeviceKey {
  const DeviceKey({
    required this.user,
    required this.session,
    required this.identity,
    required this.encryption,
    required this.signature,
    this.accountIdentity,
    this.accountSignature,
    this.generation = 0,
    this.previous,
  });
  factory DeviceKey.fromJson(Json j) => DeviceKey(
    user: field(j, 'userId') as String,
    session: field(j, 'sessionId') as String,
    identity: field(j, 'identityKey') as String,
    encryption: field(j, 'encryptionKey') as String,
    signature: field(j, 'signature') as String,
    accountIdentity: field(j, 'accountIdentityKey') as String?,
    accountSignature: field(j, 'accountSignature') as String?,
    generation: field(j, 'generation') as int? ?? 0,
    previous: field(j, 'previousFingerprint') as String?,
  );
  final String user, session, identity, encryption, signature;
  final String? accountIdentity, accountSignature, previous;
  final int generation;
  String get fingerprint =>
      hex(sha256(utf('govor-device-v1\n$identity\n$encryption')));
  Json toJson() => {
    'UserId': user,
    'SessionId': session,
    'IdentityKey': identity,
    'EncryptionKey': encryption,
    'Signature': signature,
    'AccountIdentityKey': accountIdentity,
    'AccountSignature': accountSignature,
    'Generation': generation,
    'PreviousFingerprint': previous,
  };
  Json get certificateBinding => {
    'purpose': 'govor-account-device-v1',
    'UserId': user,
    'SessionId': session,
    'Fingerprint': fingerprint,
    'Generation': generation,
    'PreviousFingerprint': previous,
  };
  DeviceKey certify(String root) {
    final signature = base64.encode(
      sign(root, utf(dotnetJson(certificateBinding))),
    );
    return DeviceKey(
      user: user,
      session: session,
      identity: identity,
      encryption: encryption,
      signature: this.signature,
      accountIdentity: publicIdentity(root),
      accountSignature: signature,
      generation: generation,
      previous: previous,
    );
  }

  void validate({bool certificateRequired = true}) {
    requireCrypto(
      validId(user) && validId(session) && signature.length <= 100,
      'Неверный ключ устройства.',
    );
    encryptionPublic(encryption);
    verify(
      identity,
      utf('govor-key-binding-v1\n$encryption'),
      base64.decode(signature),
    );
    if (certificateRequired ||
        accountIdentity != null ||
        accountSignature != null) {
      requireCrypto(
        accountIdentity != null &&
            accountSignature != null &&
            generation >= 0 &&
            (generation == 0
                ? previous == null
                : RegExp(r'^[A-F0-9]{64}$').hasMatch(previous ?? '')),
        'Нет сертификата устройства.',
      );
      verify(
        accountIdentity!,
        utf(dotnetJson(certificateBinding)),
        base64.decode(accountSignature!),
      );
    }
  }
}

DeviceKey devicePublic(
  DeviceKeys keys,
  String user,
  String session, {
  int generation = 0,
  String? previous,
}) {
  final encryption = publicEncryption(keys.encryption);
  return DeviceKey(
    user: user,
    session: session,
    identity: publicIdentity(keys.identity),
    encryption: encryption,
    signature: base64.encode(
      sign(keys.identity, utf('govor-key-binding-v1\n$encryption')),
    ),
    generation: generation,
    previous: previous,
  );
}

class E2eeProtocol {
  static const prefix = 'govor.e2ee.v1:';
  static const maxEnvelope = 1000000;

  static String encrypt({
    required String text,
    required DeviceKeys keys,
    required DeviceKey sender,
    required String conversation,
    required int type,
    required List<DeviceKey> devices,
    required String messageId,
    String? replyTo,
    bool edit = false,
    int? createdAt,
    List<Json> attachments = const [],
  }) {
    requireCrypto(
      text.length <= 20000 &&
          (text.trim().isNotEmpty || attachments.isNotEmpty) &&
          attachments.length <= 100 &&
          validId(messageId) &&
          validId(conversation) &&
          (type == 0 || type == 1),
      'Неверный контекст сообщения.',
    );
    sender.validate();
    requireCrypto(
      publicIdentity(keys.identity) == sender.identity &&
          publicEncryption(keys.encryption) == sender.encryption,
      'Ключ отправителя не совпадает.',
    );
    final unique = {for (final d in devices) d.fingerprint: d}.values.toList();
    requireCrypto(
      unique.isNotEmpty && unique.length <= 500,
      'Неверный список устройств.',
    );
    final cek = randomBytes(32);
    try {
      final protected = b64u(utf(jsonEncode({'enc': 'A256GCM'})));
      final nonce = randomBytes(12);
      final sealed = aesSeal(
        cek,
        nonce,
        utf(jsonEncode({'Text': text, 'Attachments': attachments})),
        utf(protected),
      );
      final recipients = [for (final d in unique) _recipient(d, cek)];
      final jwe = jsonEncode({
        'protected': protected,
        'recipients': recipients,
        'iv': b64u(nonce),
        'ciphertext': b64u(sealed.sublist(0, sealed.length - 16)),
        'tag': b64u(sealed.sublist(sealed.length - 16)),
      });
      final ids = unique.map((d) => d.fingerprint).toList()..sort();
      final mediaIds =
          attachments.map((a) => field(a, 'mediaId') as String).toList()
            ..sort();
      final envelope = {
        'Version': 1,
        'MessageId': messageId,
        'ConversationId': conversation,
        'RecipientType': type,
        'Sender': sender.toJson(),
        'ReplyToMessageId': replyTo,
        'CreatedAt': createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
        'IsEdit': edit,
        'Recipients': ids,
        'MediaIds': mediaIds,
        'Ciphertext': jwe,
      };
      final header = b64u(utf('{"alg":"ES256"}'));
      final payload = b64u(utf(jsonEncode(envelope)));
      final input = '$header.$payload';
      final result = '$prefix$input.${b64u(sign(keys.identity, utf(input)))}';
      requireCrypto(result.length <= maxEnvelope, 'Сообщение слишком большое.');
      return result;
    } finally {
      cek.fillRange(0, cek.length, 0);
    }
  }

  static Json _recipient(DeviceKey device, List<int> cek) {
    device.validate();
    return {
      'header': {'alg': 'RSA-OAEP-256', 'kid': device.fingerprint},
      'encrypted_key': b64u(wrapKey(device.encryption, cek)),
    };
  }

  /// The result is signed, but caller must ALSO check context and account trust.
  static Json verifyEnvelope(String value) {
    requireCrypto(
      value.startsWith(prefix) && value.length <= maxEnvelope,
      'Требуется E2EE-конверт.',
    );
    final parts = value.substring(prefix.length).split('.');
    requireCrypto(parts.length == 3, 'Неверный JWS.');
    final header = object(jsonDecode(utf8.decode(unb64u(parts[0]))));
    requireCrypto(
      header['alg'] == 'ES256' &&
          header.keys.every((k) => k == 'alg' || k == 'typ') &&
          (!header.containsKey('typ') || header['typ'] == 'JWT'),
      'Неподдерживаемая подпись.',
    );
    final env = object(jsonDecode(utf8.decode(unb64u(parts[1]))));
    requireCrypto(
      field(env, 'version') == 1 &&
          validId(field(env, 'messageId')) &&
          validId(field(env, 'conversationId')) &&
          [0, 1].contains(field(env, 'recipientType')) &&
          field(env, 'createdAt') is int &&
          field(env, 'isEdit') is bool,
      'Неверный контекст конверта.',
    );
    final sender = DeviceKey.fromJson(object(field(env, 'sender')));
    sender.validate(certificateRequired: false);
    verify(sender.identity, utf('${parts[0]}.${parts[1]}'), unb64u(parts[2]));
    final manifest = (field(env, 'recipients') as List).cast<String>();
    requireCrypto(
      manifest.isNotEmpty &&
          manifest.length <= 500 &&
          manifest.toSet().length == manifest.length &&
          (field(env, 'mediaIds') as List).length <= 100,
      'Неверный манифест получателей.',
    );
    final jwe = object(jsonDecode(field(env, 'ciphertext') as String));
    requireCrypto(
      !jwe.containsKey('unprotected') && !jwe.containsKey('aad'),
      'Неподдерживаемые JWE-заголовки.',
    );
    final protected = object(
      jsonDecode(utf8.decode(unb64u(jwe['protected'] as String))),
    );
    requireCrypto(
      protected.length == 1 && protected['enc'] == 'A256GCM',
      'Неподдерживаемое шифрование.',
    );
    final recipients = jwe.containsKey('recipients')
        ? objects(jwe['recipients'])
        : [jwe];
    final kids = <String>[];
    for (final recipient in recipients) {
      final h = object(recipient['header']);
      requireCrypto(
        h.length == 2 && h['alg'] == 'RSA-OAEP-256' && h['kid'] is String,
        'Неверный алгоритм получателя.',
      );
      kids.add(h['kid'] as String);
    }
    requireCrypto(
      kids.length == manifest.length &&
          kids.toSet().length == kids.length &&
          kids.every(manifest.contains),
      'Манифест получателей подменён.',
    );
    return env;
  }

  static Json decrypt({
    required String value,
    required String historyIdentity,
    required String historyEncryption,
    required String messageId,
    required String conversation,
    required int type,
    required String author,
    String? replyTo,
    bool? edit,
  }) {
    final env = verifyEnvelope(value);
    final sender = DeviceKey.fromJson(object(field(env, 'sender')));
    requireCrypto(
      field(env, 'messageId') == messageId &&
          field(env, 'conversationId') == conversation &&
          field(env, 'recipientType') == type &&
          sender.user == author &&
          field(env, 'replyToMessageId') == replyTo &&
          (edit == null || field(env, 'isEdit') == edit),
      'Контекст E2EE не совпадает с сообщением.',
    );
    final fingerprint = hex(
      sha256(
        utf(
          'govor-device-v1\n$historyIdentity\n${publicEncryption(historyEncryption)}',
        ),
      ),
    );
    final jwe = object(jsonDecode(field(env, 'ciphertext') as String));
    final recipients = jwe.containsKey('recipients')
        ? objects(jwe['recipients'])
        : [jwe];
    final matches = recipients
        .where((r) => object(r['header'])['kid'] == fingerprint)
        .toList();
    requireCrypto(matches.length == 1, 'В архиве нет ключа этого сообщения.');
    final cek = unwrapKey(
      historyEncryption,
      unb64u(matches.single['encrypted_key'] as String),
    );
    try {
      final tag = unb64u(jwe['tag'] as String);
      requireCrypto(tag.length == 16, 'Неверный тег AES.');
      final plaintext = object(
        jsonDecode(
          utf8.decode(
            aesOpen(cek, unb64u(jwe['iv'] as String), [
              ...unb64u(jwe['ciphertext'] as String),
              ...tag,
            ], utf(jwe['protected'] as String)),
          ),
        ),
      );
      final text = field(plaintext, 'text');
      final files = objects(field(plaintext, 'attachments'));
      final expected = (field(env, 'mediaIds') as List).cast<String>();
      final actual = files.map((a) => field(a, 'mediaId')).toList();
      requireCrypto(
        text is String &&
            text.length <= 20000 &&
            actual.length == expected.length &&
            actual.toSet().length == actual.length &&
            actual.every(expected.contains),
        'Неверное содержимое сообщения.',
      );
      for (final file in files) {
        requireCrypto(
          base64.decode(field(file, 'key') as String).length == 32,
          'Неверный ключ вложения.',
        );
      }
      return {'text': text, 'attachments': files};
    } finally {
      cek.fillRange(0, cek.length, 0);
    }
  }

  static ({Uint8List data, String key}) encryptAttachment(List<int> plaintext) {
    requireCrypto(plaintext.length <= 19000000, 'Файл слишком большой.');
    final key = randomBytes(32), nonce = randomBytes(12);
    try {
      return (
        data: bytes([
          ...nonce,
          ...aesSeal(key, nonce, plaintext, utf('govor-attachment-v1')),
        ]),
        key: base64.encode(key),
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  static Uint8List decryptAttachment(List<int> ciphertext, String encodedKey) {
    requireCrypto(
      ciphertext.length >= 28 && ciphertext.length <= 19000028,
      'Неверный размер файла.',
    );
    final key = base64.decode(encodedKey);
    try {
      return aesOpen(
        key,
        ciphertext.sublist(0, 12),
        ciphertext.sublist(12),
        utf('govor-attachment-v1'),
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}
