import 'dart:convert';
import 'media/media_cache.dart';
import 'preferences_native.dart'
    if (dart.library.js_interop) 'preferences_web.dart'
    as platform;

abstract interface class PreferencesRepository {
  Future<String?> loadLanguage();
  Future<void> saveLanguage(String? language);
  Future<double> loadFontSize();
  Future<void> saveFontSize(double fontSize);
}

abstract interface class VisualPreferencesRepository {
  Future<double> loadGlassIntensity();
  Future<void> saveGlassIntensity(double value);
  Future<double> loadSidebarWidth();
  Future<void> saveSidebarWidth(double value);
}

abstract interface class MediaPreferencesRepository {
  Future<int> loadMediaCacheLimit();
  Future<void> saveMediaCacheLimit(int limit);
}

class LocalPreferencesRepository
    implements
        PreferencesRepository,
        VisualPreferencesRepository,
        MediaPreferencesRepository {
  LocalPreferencesRepository({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? platform.readPreferences,
       _write = write ?? platform.writePreferences;
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Future<void> _writes = Future.value();
  Future<Map<String, dynamic>> _data() async {
    final text = await _read();
    if (text == null || text.length > 4096) return {};
    try {
      final data = jsonDecode(text);
      return data is Map<String, dynamic> ? data : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _update(String key, Object? value) {
    final task = _writes.then((_) async {
      final data = await _data();
      await _write(jsonEncode({...data, key: value}));
    });
    // Serialize read-modify-write operations without poisoning later retries.
    _writes = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  @override
  Future<int> loadMediaCacheLimit() async {
    final limit = (await _data())['mediaCacheGiB'];
    return limit is int && mediaCacheLimits.contains(limit)
        ? limit
        : defaultMediaCacheGiB;
  }

  @override
  Future<void> saveMediaCacheLimit(int limit) =>
      _update('mediaCacheGiB', limit);

  @override
  Future<String?> loadLanguage() async {
    final code = (await _data())['language'];
    return code == 'ru' || code == 'en' ? code as String : null;
  }

  @override
  Future<void> saveLanguage(String? language) => _update('language', language);
  @override
  Future<double> loadFontSize() async {
    final size = (await _data())['fontSize'];
    return size is num && size.isFinite && size >= 12 && size <= 24
        ? size.toDouble()
        : 14;
  }

  @override
  Future<void> saveFontSize(double fontSize) {
    if (!fontSize.isFinite || fontSize < 12 || fontSize > 24) {
      return Future.error(ArgumentError.value(fontSize, 'fontSize'));
    }
    return _update('fontSize', fontSize);
  }

  Future<double> _number(
    String key,
    double fallback,
    double min,
    double max,
  ) async {
    final value = (await _data())[key];
    return value is num && value.isFinite && value >= min && value <= max
        ? value.toDouble()
        : fallback;
  }

  @override
  Future<double> loadGlassIntensity() => _number('glassIntensity', .5, 0, 1);
  @override
  Future<void> saveGlassIntensity(double value) =>
      _update('glassIntensity', value.clamp(0, 1));
  @override
  Future<double> loadSidebarWidth() => _number('sidebarWidth', 330, 92, 600);
  @override
  Future<void> saveSidebarWidth(double value) =>
      _update('sidebarWidth', value.clamp(92, 600));
}
