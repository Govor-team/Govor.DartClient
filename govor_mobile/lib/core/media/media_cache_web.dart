import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'media_cache_store.dart';

MediaCacheStore createMediaCacheStore() => _BrowserCache();

class _BrowserCache implements MediaCacheStore {
  static const _path = '/__govor_cached_media/';
  Future<web.Cache> _cache() => web.window.caches.open('govor-media-v1').toDart;
  JSString _url(String key) => '${web.window.location.origin}$_path$key'.toJS;

  @override
  Future<List<CacheEntry>> entries() async {
    final cache = await _cache();
    final result = <CacheEntry>[];
    for (final request in (await cache.keys().toDart).toDart) {
      final path = Uri.parse(request.url).path;
      if (!path.startsWith(_path)) continue;
      final response = await cache.match(request).toDart;
      if (response.isUndefinedOrNull) continue;
      final headers = (response as web.Response).headers;
      final bytes = int.tryParse(headers.get('x-govor-size') ?? '');
      final date = DateTime.tryParse(headers.get('x-govor-touched') ?? '');
      if (bytes != null && bytes >= 0 && date != null) {
        result.add((
          key: path.substring(_path.length),
          bytes: bytes,
          touched: date,
        ));
      }
    }
    return result;
  }

  @override
  Future<Uint8List?> read(String key) async {
    final cache = await _cache();
    final value = await cache.match(_url(key)).toDart;
    if (value.isUndefinedOrNull) return null;
    final response = value as web.Response;
    final size = int.tryParse(response.headers.get('x-govor-size') ?? '');
    if (size == null || size < 1 || size > 20000000) return null;
    return (await response.arrayBuffer().toDart).toDart.asUint8List();
  }

  @override
  Future<void> write(String key, Uint8List data) async {
    final headers = web.Headers()
      ..set('x-govor-size', '${data.length}')
      ..set('x-govor-touched', DateTime.now().toUtc().toIso8601String());
    await (await _cache())
        .put(
          _url(key),
          web.Response(data.toJS, web.ResponseInit(headers: headers)),
        )
        .toDart;
  }

  @override
  Future<void> remove(String key) async {
    await (await _cache()).delete(_url(key)).toDart;
  }
}
