import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../crypto/primitives.dart';
import 'media_cache_store.dart';

MediaCacheStore createMediaCacheStore() => _FileCache();

class _FileCache implements MediaCacheStore {
  Future<Directory> _root() async {
    final root = await getTemporaryDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}govor-media-v1',
    ).create(recursive: true);
  }

  Future<File> _file(String key) async {
    if (!RegExp(r'^[A-F0-9]{64}$').hasMatch(key)) {
      throw ArgumentError('Cache key');
    }
    return File('${(await _root()).path}${Platform.pathSeparator}$key');
  }

  @override
  Future<List<CacheEntry>> entries() async {
    final result = <CacheEntry>[];
    await for (final entry in (await _root()).list(followLinks: false)) {
      if (entry is! File) continue;
      final key = entry.uri.pathSegments.last;
      if (RegExp(r'^[A-F0-9]{64}$').hasMatch(key)) {
        final info = await entry.stat();
        if (info.type == FileSystemEntityType.file) {
          result.add((key: key, bytes: info.size, touched: info.modified));
        }
      } else if (RegExp(
            r'^[A-F0-9]{64}(\.[A-F0-9]{16})?\.tmp$',
          ).hasMatch(key) &&
          DateTime.now().difference(await entry.lastModified()).inDays >= 1) {
        await entry.delete();
      }
    }
    return result;
  }

  @override
  Future<Uint8List?> read(String key) async {
    final file = await _file(key);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    if (await file.length() > 20000000) return null;
    final data = await file.readAsBytes();
    await file.setLastModified(DateTime.now());
    return data;
  }

  @override
  Future<void> write(String key, Uint8List data) async {
    final file = await _file(key);
    final temp = File('${file.path}.${hex(randomBytes(8))}.tmp');
    try {
      await temp.writeAsBytes(data, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }
}
