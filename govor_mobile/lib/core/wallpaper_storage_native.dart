import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _settingsFile() async {
  final root = await getApplicationSupportDirectory();
  await root.create(recursive: true);
  return File('${root.path}${Platform.pathSeparator}appearance.json');
}

Future<String?> readWallpaperSettings() async {
  final file = await _settingsFile();
  if (!await file.exists()) return null;
  if (await file.length() > 42000000) return null;
  return file.readAsString();
}

Future<void> writeWallpaperSettings(String value) async {
  final file = await _settingsFile();
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(value, flush: true);
  await temporary.rename(file.path);
}
