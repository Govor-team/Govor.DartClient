import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/crypto/e2ee_protocol.dart';
import 'package:govor_mobile/core/crypto/password_protocol.dart';
import 'package:govor_mobile/core/crypto/primitives.dart';
import 'package:govor_mobile/core/crypto/recovery_protocol.dart';
import 'package:govor_mobile/core/models.dart';

void main() {
  final fixture = object(
    jsonDecode(File('test/fixtures/dotnet.json').readAsStringSync()),
  );
  final keys = DeviceKeys.fromJson(object(fixture['Keys']));
  final device = DeviceKey.fromJson(object(fixture['Device']));
  test('C# device binding, certificate and PKCS8 keys verify in Dart', () {
    device.validate();
    expect(publicIdentity(keys.identity), device.identity);
    expect(publicEncryption(keys.encryption), device.encryption);
  });
  test('C# multi-recipient JOSE message decrypts in Dart', () {
    final plain = E2eeProtocol.decrypt(
      value: fixture['Message'] as String,
      historyIdentity: device.identity,
      historyEncryption: keys.encryption,
      messageId: fixture['MessageId'] as String,
      conversation: fixture['Conversation'] as String,
      type: 0,
      author: fixture['User'] as String,
    );
    expect(plain['text'], 'Привет из .NET 🔐');
  });
  test(
    'C# recovery and password archives open with exact .NET JSON bindings',
    () {
      expect(
        RecoveryProtocol.openVault(
          object(fixture['Vault']),
          fixture['User'] as String,
          fixture['Code'] as String,
        ),
        'dotnet archive',
      );
      expect(
        RecoveryProtocol.openPassword(
          fixture['User'] as String,
          object(fixture['Credentials']),
          object(fixture['PasswordEnvelope']),
          fixture['ArchiveKey'] as String,
        ),
        fixture['Code'],
      );
    },
  );
  test(
    'PBKDF2/HKDF/SRP match C# including Unicode password and padding',
    () async {
      final material = await PasswordProtocol.derive(
        fixture['Password'] as String,
        fixture['Salt'] as String,
        fixture['Identity'] as String,
      );
      expect(material.secret, fixture['Secret']);
      expect(material.archiveKey, fixture['ArchiveKey']);
      expect(
        PasswordProtocol.verifier(
          fixture['Salt'] as String,
          fixture['Identity'] as String,
          material.secret,
        ),
        (fixture['Verifier'] as String).toUpperCase(),
      );
      final proof = PasswordProtocol.prove(
        SrpEphemeral(
          fixture['ClientSecret'] as String,
          fixture['ClientPublic'] as String,
        ),
        fixture['ServerPublic'] as String,
        fixture['Salt'] as String,
        fixture['Identity'] as String,
        material.secret,
      );
      expect(proof.key, (fixture['SessionKey'] as String).toUpperCase());
      expect(proof.proof, (fixture['ClientProof'] as String).toUpperCase());
      proof.verifyServer(fixture['ServerProof'] as String);
      expect(
        () => proof.verifyServer('00' * 64),
        throwsA(isA<CryptoFailure>()),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('attachments match .NET and reject corruption/wrong keys', () {
    final ciphertext = base64.decode(fixture['Attachment'] as String);
    expect(
      utf8.decode(
        E2eeProtocol.decryptAttachment(
          ciphertext,
          fixture['AttachmentKey'] as String,
        ),
      ),
      'attachment 🔐',
    );
    ciphertext[ciphertext.length - 1] ^= 1;
    expect(
      () => E2eeProtocol.decryptAttachment(
        ciphertext,
        fixture['AttachmentKey'] as String,
      ),
      throwsA(isA<CryptoFailure>()),
    );
  });
  test('Dart emits a certified message and vault that .NET can verify', () {
    final freshKeys = DeviceKeys(generateIdentity(), keys.encryption);
    final freshRoot = generateIdentity();
    final freshDevice = devicePublic(
      freshKeys,
      fixture['User'] as String,
      fixture['Session'] as String,
    ).certify(freshRoot);
    final message = E2eeProtocol.encrypt(
      text: 'Привет из Flutter 🔐',
      keys: freshKeys,
      sender: freshDevice,
      conversation: fixture['Conversation'] as String,
      type: 0,
      devices: [freshDevice],
      messageId: fixture['MessageId'] as String,
    );
    final vault = RecoveryProtocol.sealVault(
      fixture['User'] as String,
      2,
      freshRoot,
      fixture['Code'] as String,
      'flutter archive',
    );
    final directory = Directory('build/interop')..createSync(recursive: true);
    File('${directory.path}/dart.json').writeAsStringSync(
      jsonEncode({
        'Keys': freshKeys.toJson(),
        'Message': message,
        'Vault': vault,
        'Code': fixture['Code'],
      }),
    );
    expect(
      E2eeProtocol.decrypt(
        value: message,
        historyIdentity: freshDevice.identity,
        historyEncryption: freshKeys.encryption,
        messageId: fixture['MessageId'] as String,
        conversation: fixture['Conversation'] as String,
        type: 0,
        author: fixture['User'] as String,
      )['text'],
      'Привет из Flutter 🔐',
    );
  });
  test(
    'context substitution, tampering, plaintext and wrong SRP elements fail closed',
    () {
      final message = fixture['Message'] as String;
      expect(
        () => E2eeProtocol.decrypt(
          value: message,
          historyIdentity: device.identity,
          historyEncryption: keys.encryption,
          messageId: newId(),
          conversation: fixture['Conversation'] as String,
          type: 0,
          author: fixture['User'] as String,
        ),
        throwsA(isA<CryptoFailure>()),
      );
      final parts = message.substring(E2eeProtocol.prefix.length).split('.');
      final signature = unb64u(parts.last);
      signature[0] ^= 1;
      expect(
        () => E2eeProtocol.verifyEnvelope(
          '${E2eeProtocol.prefix}${parts[0]}.${parts[1]}.${b64u(signature)}',
        ),
        throwsA(isA<CryptoFailure>()),
      );
      expect(
        () => E2eeProtocol.verifyEnvelope('hello'),
        throwsA(isA<CryptoFailure>()),
      );
      expect(
        () => PasswordProtocol.prove(
          SrpEphemeral(
            fixture['ClientSecret'] as String,
            fixture['ClientPublic'] as String,
          ),
          '00' * 512,
          fixture['Salt'] as String,
          fixture['Identity'] as String,
          fixture['Secret'] as String,
        ),
        throwsA(isA<CryptoFailure>()),
      );
    },
  );
}
