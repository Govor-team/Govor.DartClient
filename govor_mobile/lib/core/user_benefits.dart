import 'package:flutter/foundation.dart';
import 'models.dart';

@immutable
class ProfileTag {
  ProfileTag(Json value)
    : json = Map.unmodifiable({
        for (final key in defaults.keys)
          key: value.containsKey(key) ? value[key] : defaults[key],
      }) {
    final text = json['text'];
    if (text is! String ||
        text.trim().isEmpty ||
        text.length > 32 ||
        RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(text)) {
      throw const FormatException('tag text');
    }
    for (final key in colors) {
      final color = json[key];
      if (color == null &&
          key != 'textColor' &&
          key != 'backgroundColor' &&
          key != 'borderColor' &&
          key != 'shadowColor') {
        continue;
      }
      if (color is! String ||
          !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(color)) {
        throw FormatException(key);
      }
    }
    for (final entry in ranges.entries) {
      final n = json[entry.key];
      if (n is! num ||
          !n.isFinite ||
          n < entry.value.$1 ||
          n > entry.value.$2) {
        throw FormatException(entry.key);
      }
    }
    if (!fonts.contains(json['fontFamily']) ||
        json['fontWeight'] is! int ||
        (json['fontWeight'] as int) % 100 != 0) {
      throw const FormatException('font');
    }
  }
  final Json json;
  static const fonts = [
    'Inter',
    'Roboto',
    'Arial',
    'Noto Sans',
    'serif',
    'sans-serif',
    'monospace',
  ];
  static const colors = [
    'textColor',
    'textGradientEndColor',
    'backgroundColor',
    'gradientEndColor',
    'borderColor',
    'borderGradientEndColor',
    'shadowColor',
  ];
  static const ranges = <String, (double, double)>{
    'gradientAngle': (0, 360),
    'borderWidth': (0, 4),
    'shadowBlur': (0, 20),
    'shadowOffsetX': (-10, 10),
    'shadowOffsetY': (-10, 10),
    'fontWeight': (100, 900),
    'fontSize': (10, 24),
  };
  static const defaults = <String, dynamic>{
    'text': 'Govor+',
    'textColor': '#FFFFFF',
    'textGradientEndColor': null,
    'backgroundColor': '#2455DD',
    'gradientEndColor': null,
    'gradientAngle': 90,
    'borderColor': '#6688FF',
    'borderGradientEndColor': null,
    'borderWidth': 1,
    'shadowColor': '#00000080',
    'shadowBlur': 4,
    'shadowOffsetX': 0,
    'shadowOffsetY': 1,
    'fontFamily': 'Inter',
    'fontWeight': 600,
    'fontSize': 12,
  };
  String get text => json['text'] as String;
  double number(String key) => (json[key] as num).toDouble();
}

@immutable
class UserBenefits {
  const UserBenefits({
    this.privileges = 0,
    this.isGovorPlus = false,
    this.canCustomizeProfileTag = false,
    this.tag,
    this.revision = 0,
  });
  factory UserBenefits.fromJson(Json j) {
    ProfileTag? tag;
    if (j['canCustomizeProfileTag'] == true && j['tag'] is Map) {
      try {
        tag = ProfileTag(object(j['tag']));
      } on FormatException {
        /* Invalid styles stay hidden. */
      }
    }
    return UserBenefits(
      privileges: j['privileges'] as int? ?? 0,
      isGovorPlus: j['isGovorPlus'] == true,
      canCustomizeProfileTag: j['canCustomizeProfileTag'] == true,
      tag: tag,
      revision: j['revision'] as int? ?? 0,
    );
  }
  final int privileges, revision;
  final bool isGovorPlus, canCustomizeProfileTag;
  final ProfileTag? tag;
}

/// HTTP snapshots and realtime events share one monotonically versioned cache.
class UserBenefitsCache extends ChangeNotifier {
  final _values = <String, UserBenefits>{};
  UserBenefits? operator [](String id) => _values[id];
  bool apply(String id, UserBenefits value) {
    if ((_values[id]?.revision ?? -1) >= value.revision) return false;
    _values[id] = value;
    notifyListeners();
    return true;
  }

  void clear() {
    _values.clear();
    notifyListeners();
  }
}
