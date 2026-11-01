import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _file() async {
  final root = await getApplicationSupportDirectory();
  await root.create(recursive: true);
  return File('${root.path}${Platform.pathSeparator}preferences.json');
}

Future<String?> readPreferences() async {
  final file = await _file();
  if (!await file.exists() || await file.length() > 4096) return null;
  return file.readAsString();
}

Future<void> writePreferences(String text) async {
  final file = await _file();
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(text, flush: true);
  await temporary.rename(file.path);
}
