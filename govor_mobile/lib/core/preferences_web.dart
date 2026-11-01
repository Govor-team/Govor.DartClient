import 'package:web/web.dart' as web;

Future<String?> readPreferences() async =>
    web.window.localStorage.getItem('govor-preferences-v1');
Future<void> writePreferences(String text) async =>
    web.window.localStorage.setItem('govor-preferences-v1', text);
