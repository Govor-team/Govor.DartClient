import 'dart:typed_data';

typedef CacheEntry = ({String key, int bytes, DateTime touched});

abstract interface class MediaCacheStore {
  Future<List<CacheEntry>> entries();
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List data);
  Future<void> remove(String key);
}
