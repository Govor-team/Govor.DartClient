import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _file(String name) async {
  final root = await getApplicationSupportDirectory();
  await root.create(recursive: true);
  return File('${root.path}${Platform.pathSeparator}$name.json');
}

Future<String?> readPreferences([String name = 'preferences']) async {
  final file = await _file(name);
  if (!await file.exists() || await file.length() > 4096) return null;
  return file.readAsString();
}

Future<void> writePreferences(
  String text, [
  String name = 'preferences',
]) async {
  final file = await _file(name);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(text, flush: true);
  await temporary.rename(file.path);
}
