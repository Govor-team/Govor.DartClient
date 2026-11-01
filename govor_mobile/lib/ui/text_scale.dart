import 'package:flutter/painting.dart';

/// Applies the user's preference to every text style, preserving the platform's
/// accessibility scaler (including nonlinear scaling).
class GovorTextScaler extends TextScaler {
  const GovorTextScaler(this.platform, this.factor);
  final TextScaler platform;
  final double factor;

  @override
  double scale(double fontSize) => platform.scale(fontSize * factor);

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is GovorTextScaler &&
      other.platform == platform &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(platform, factor);
}
