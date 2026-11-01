import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'attachment_files.dart';
import 'crypto/primitives.dart';
import 'wallpaper_storage_native.dart'
    if (dart.library.js_interop) 'wallpaper_storage_web.dart'
    as platform;

class CustomWallpaper {
  const CustomWallpaper(this.id, this.name, this.bytes);
  final String id, name;
  final Uint8List bytes;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'data': base64Encode(bytes),
  };
}

class WallpaperSettings {
  const WallpaperSettings({
    this.selected,
    this.dark = true,
    this.custom = const [],
  });
  final String? selected;
  final bool dark;
  final List<CustomWallpaper> custom;
}

class WallpaperRepository {
  WallpaperRepository({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? platform.readWallpaperSettings,
       _write = write ?? platform.writeWallpaperSettings;
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  static const maxBytes = 5000000, maxCount = 6;

  static Future<CustomWallpaper> validate(Uint8List bytes, String name) async {
    requireCrypto(
      bytes.isNotEmpty && bytes.length <= maxBytes,
      'Для фона выберите изображение размером до 5 МБ.',
    );
    requireCrypto(
      ['image/png', 'image/jpeg', 'image/webp'].contains(fileMime(bytes)),
      'Поддерживаются фоны PNG, JPEG и WebP.',
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        requireCrypto(
          descriptor.width > 0 &&
              descriptor.height > 0 &&
              descriptor.width <= 8192 &&
              descriptor.height <= 8192 &&
              descriptor.width * descriptor.height <= 24000000,
          'Изображение слишком большое: максимум 24 мегапикселя и 8192 px по стороне.',
        );
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
    return CustomWallpaper(
      'custom:${hex(sha256(bytes))}',
      safeFileName(name),
      Uint8List.fromList(bytes),
    );
  }

  Future<WallpaperSettings?> load() async {
    final text = await _read();
    if (text == null || text.length > 42000000) return null;
    final json = jsonDecode(text) as Map<String, dynamic>;
    final custom = <CustomWallpaper>[];
    final entries = json['custom'];
    if (entries is List && entries.length <= maxCount) {
      for (final entry in entries) {
        try {
          final data = base64Decode(entry['data'] as String);
          final item = await validate(data, entry['name'] as String);
          if (item.id == entry['id'] && !custom.any((e) => e.id == item.id)) {
            custom.add(item);
          }
        } catch (_) {
          // A corrupt/deleted wallpaper must not prevent sign-in.
        }
      }
    }
    return WallpaperSettings(
      selected: json['selected'] as String?,
      dark: json['dark'] != false,
      custom: custom,
    );
  }

  Future<void> save(WallpaperSettings value) => _write(
    jsonEncode({
      'selected': value.selected,
      'dark': value.dark,
      'custom': value.custom.map((e) => e.toJson()).toList(),
    }),
  );
}
