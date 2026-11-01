import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'crypto/primitives.dart';

String safeFileName(String input) {
  final name = input
      .split(RegExp(r'[/\\]'))
      .last
      .replaceAll(
        RegExp(r'[\x00-\x1f\x7f<>:"|?*\u202a-\u202e\u2066-\u2069]'),
        '_',
      )
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  if (name.isEmpty || name == '.' || name == '..') return 'attachment.bin';
  final reserved = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  );
  final safe = reserved.hasMatch(name) ? '_$name' : name;
  return safe.length > 160 ? safe.substring(safe.length - 160) : safe;
}

String fileMime(List<int> data) {
  bool prefix(List<int> values) =>
      data.length >= values.length &&
      Iterable<int>.generate(values.length).every((i) => data[i] == values[i]);
  if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (prefix([255, 216, 255])) return 'image/jpeg';
  if (prefix([71, 73, 70, 56])) return 'image/gif';
  if (prefix([82, 73, 70, 70]) &&
      data.length > 12 &&
      String.fromCharCodes(data.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  if (data.length >= 12 && String.fromCharCodes(data.sublist(4, 8)) == 'ftyp') {
    final brand = String.fromCharCodes(data.sublist(8, 12));
    if (brand == 'qt  ') return 'video/quicktime';
    if (const [
          'isom',
          'iso2',
          'iso3',
          'iso4',
          'iso5',
          'iso6',
          'mp41',
          'mp42',
          'avc1',
          'M4V ',
          'MSNV',
          'dash',
        ].contains(brand) ||
        brand.startsWith('3gp')) {
      return 'video/mp4';
    }
  }
  if (prefix([0x1a, 0x45, 0xdf, 0xa3])) {
    final header = String.fromCharCodes(data.take(256));
    if (header.contains('webm')) return 'video/webm';
    if (header.contains('matroska')) return 'video/x-matroska';
  }
  return 'application/octet-stream';
}

Future<({Uint8List data, String name})?> pickAttachment({
  int maxBytes = 19000000,
  String title = 'Прикрепить зашифрованный файл',
}) async {
  final file = await FilePicker.pickFile(dialogTitle: title);
  if (file == null) return null;
  final size = file.lengthSync() ?? await file.length();
  requireCrypto(
    size != null && size > 0 && size <= maxBytes,
    'Размер файла должен быть от 1 байта до ${maxBytes ~/ 1000000} МБ.',
  );
  final data = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    requireCrypto(
      data.length + chunk.length <= maxBytes,
      'Файл слишком большой.',
    );
    data.add(chunk);
  }
  requireCrypto(
    data.length > 0 && data.length <= maxBytes,
    'Неверный размер файла.',
  );
  return (data: data.takeBytes(), name: safeFileName(file.name));
}

Future<void> saveAttachment(
  String name,
  Uint8List plaintext, {
  String dialogTitle = 'Сохранить расшифрованный файл',
}) async {
  await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: safeFileName(name),
    bytes: plaintext,
  );
}
