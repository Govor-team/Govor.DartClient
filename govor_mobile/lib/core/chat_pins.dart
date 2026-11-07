import 'dart:convert';
import 'crypto/primitives.dart';
import 'preferences_native.dart'
    if (dart.library.js_interop) 'preferences_web.dart'
    as platform;

class ChatPinsRepository {
  ChatPinsRepository({
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
  }) : _read = read ?? ((key) => platform.readPreferences(key)),
       _write =
           write ?? ((key, value) => platform.writePreferences(value, key));
  static const maxPins = 90;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  String _key(String scope) => 'chat-pins-${hex(sha256(utf(scope)))}';
  bool _valid(Object? key) =>
      key is String &&
      (key.startsWith('0/') || key.startsWith('1/')) &&
      validId(key.substring(2));
  Future<Set<String>> load(String scope) async {
    final value = await _read(_key(scope));
    if (value == null || value.length > 4096) return {};
    try {
      final decoded = jsonDecode(value);
      return decoded is List
          ? decoded.where(_valid).cast<String>().take(maxPins).toSet()
          : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> save(String scope, Set<String> pins) => _write(
    _key(scope),
    jsonEncode(pins.where(_valid).take(maxPins).toList()),
  );
}
