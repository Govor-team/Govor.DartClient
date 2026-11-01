import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Only public appearance data lives here; authentication and E2EE secrets never
// enter the browser cache. No network request is made for this synthetic URL.
const _cacheName = 'govor-appearance-v1';
String get _key => '${web.window.location.origin}/__govor_local__/appearance';

Future<String?> readWallpaperSettings() async {
  final cache = await web.window.caches.open(_cacheName).toDart;
  final response = await cache.match(_key.toJS).toDart;
  if (response == null) return null;
  final value = (await response.text().toDart).toDart;
  return value.length > 42000000 ? null : value;
}

Future<void> writeWallpaperSettings(String value) async {
  final cache = await web.window.caches.open(_cacheName).toDart;
  await cache.put(_key.toJS, web.Response(value.toJS)).toDart;
}
