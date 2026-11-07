import 'dart:typed_data';
import 'media_cache_store.dart';
import 'media_cache_native.dart'
    if (dart.library.js_interop) 'media_cache_web.dart'
    as platform;

const mediaCacheLimits = [0, 1, 2, 5, 10, 20];
const defaultMediaCacheGiB = 2;
const bytesPerGiB = 1024 * 1024 * 1024;

/// A bounded cache of encrypted server files. No filenames, content keys, or
/// decrypted bytes are persisted here. Work is serialized across all accounts.
class MediaCache {
  MediaCache({
    MediaCacheStore? store,
    Future<int> Function()? loadLimit,
    Future<void> Function(int)? saveLimit,
  }) : _store = store ?? platform.createMediaCacheStore(),
       _loadLimit = loadLimit,
       _saveLimit = saveLimit;

  final MediaCacheStore _store;
  final Future<int> Function()? _loadLimit;
  final Future<void> Function(int)? _saveLimit;
  final _entries = <String, int>{};
  Future<void> _tail = Future.value();
  int _limit = defaultMediaCacheGiB, _used = 0, _revision = 0;
  bool _ready = false;
  int get revision => _revision;

  Future<T> _run<T>(Future<T> Function() work) {
    final result = _tail.then((_) async {
      if (!_ready) {
        final limit = await _loadLimit?.call();
        if (mediaCacheLimits.contains(limit)) _limit = limit!;
        final entries = (await _store.entries())
          ..sort((a, b) => a.touched.compareTo(b.touched));
        _entries.clear();
        _used = 0;
        for (final entry in entries) {
          _entries[entry.key] = entry.bytes;
          _used += entry.bytes;
        }
        await _trim();
        _ready = true;
      }
      return work();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _remove(String key) async {
    await _store.remove(key);
    _used -= _entries.remove(key) ?? 0;
  }

  Future<void> _trim([int extra = 0]) async {
    while (_entries.isNotEmpty && _used + extra > _limit * bytesPerGiB) {
      await _remove(_entries.keys.first);
    }
  }

  Future<Uint8List?> read(String key) => _run(() async {
    final size = _entries[key];
    if (size == null) return null;
    final data = await _store.read(key);
    if (data == null || data.length != size) {
      await _remove(key);
      return null;
    }
    _entries.remove(key);
    _entries[key] = size;
    return data;
  });

  Future<void> write(String key, Uint8List data, {required int revision}) =>
      _run(() async {
        if (revision != _revision ||
            _limit == 0 ||
            data.isEmpty ||
            data.length > 20000000) {
          return;
        }
        if (_entries.containsKey(key)) await _remove(key);
        await _trim(data.length);
        await _store.write(key, data);
        _entries[key] = data.length;
        _used += data.length;
      });

  Future<void> remove(String key) => _run(() => _remove(key));

  Future<({int limit, int bytes})> stats() =>
      _run(() async => (limit: _limit, bytes: _used));

  Future<void> setLimit(int limit) => _run(() async {
    if (!mediaCacheLimits.contains(limit)) throw ArgumentError.value(limit);
    await _saveLimit?.call(limit);
    _limit = limit;
    if (limit == 0) _revision++;
    await _trim();
  });

  Future<void> clear() {
    _revision++;
    return _run(() async {
      for (final key in _entries.keys.toList()) {
        await _remove(key);
      }
    });
  }
}
