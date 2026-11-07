import 'package:web/web.dart' as web;

Future<String?> readPreferences([String name = 'preferences']) async =>
    web.window.localStorage.getItem('govor-$name-v1');
Future<void> writePreferences(
  String text, [
  String name = 'preferences',
]) async => web.window.localStorage.setItem('govor-$name-v1', text);
