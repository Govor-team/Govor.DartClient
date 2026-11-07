import '../l10n/l10n.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/material.dart';

const accent = Color(0xFF9A8CFF);
const primary = Color(0xFF6E73F1);
const muted = Color(0xFFA6A6BE);

TextTheme _textTheme(Brightness brightness, double fontSize) {
  final color = brightness == Brightness.dark
      ? const Color(0xFFF0EFF9)
      : const Color(0xFF222238);
  final base = Typography.material2021(
    platform: TargetPlatform.windows,
  ).black.apply(fontFamily: 'GovorSans', bodyColor: color, displayColor: color);
  return base.copyWith(
    bodyMedium: base.bodyMedium?.copyWith(fontSize: fontSize),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: fontSize + 2),
    bodySmall: base.bodySmall?.copyWith(fontSize: fontSize - 2),
  );
}

ThemeData govorTheme(Brightness brightness, {double fontSize = 14}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    surface: dark ? const Color(0xFF202130) : const Color(0xFFF3F2FA),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'GovorSans',
    fontFamilyFallback: const [
      'Segoe UI Emoji',
      'Noto Color Emoji',
      'sans-serif',
    ],
    visualDensity: VisualDensity.standard,
    textTheme: _textTheme(brightness, fontSize),
    dividerColor: dark
        ? Colors.white.withValues(alpha: .08)
        : Colors.black.withValues(alpha: .06),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? Colors.white.withValues(alpha: .045)
          : Colors.white.withValues(alpha: .6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: accent.withValues(alpha: .15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: accent.withValues(alpha: .15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: accent),
      ),
      hintStyle: TextStyle(
        color: dark ? muted : const Color(0xFF71718C),
        fontSize: 14,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: dark
            ? const Color(0xFFD4D1ED)
            : const Color(0xFF686482),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}

class GlassStyle extends InheritedWidget {
  const GlassStyle({super.key, required this.intensity, required super.child});
  final double intensity;
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassStyle>()?.intensity ?? .5;
  @override
  bool updateShouldNotify(GlassStyle oldWidget) =>
      intensity != oldWidget.intensity;
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.blur = true,
    this.tint,
    this.border = true,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool blur, border;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accessible = MediaQuery.highContrastOf(context) || !blur;
    final intensity = GlassStyle.of(context);
    final opacity = dark ? .08 + intensity * .54 : .28 + intensity * .72;
    final color = tint ?? (dark ? const Color(0xFF191C29) : Colors.white);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: accessible
              ? 1
              : (tint == null
                    ? opacity
                    : (color.a * opacity / (dark ? .35 : .64)).clamp(0, 1)),
        ),
        borderRadius: BorderRadius.circular(radius),
        border: border
            ? Border.all(
                color: (dark ? Colors.white : const Color(0xFF9A8CFF))
                    .withValues(alpha: accessible ? .25 : .12),
              )
            : null,
        gradient: accessible
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: dark ? .045 : .35),
                  Colors.white.withValues(alpha: .015),
                ],
              ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: accessible
          ? panel
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: intensity * 44,
                sigmaY: intensity * 44,
              ),
              child: panel,
            ),
    );
  }
}

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({
    super.key,
    required this.child,
    this.wallpaper = 'assets/backgrounds/background_girls.jpg',
    this.customWallpaper,
  });
  final Widget child;
  final String? wallpaper;
  final Uint8List? customWallpaper;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (wallpaper != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF13151F)),
          Image(
            image: customWallpaper != null
                ? MemoryImage(customWallpaper!)
                : AssetImage(wallpaper!) as ImageProvider,
            fit: BoxFit.cover,
            alignment: const Alignment(.5, 0),
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF13151F)),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: dark ? .40 : .15)),
          child,
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  const Color(0xFF202036),
                  const Color(0xFF13151F),
                  const Color(0xFF1B2032),
                ]
              : [
                  const Color(0xFFE5E1F7),
                  const Color(0xFFF3F1FC),
                  const Color(0xFFDDE6F3),
                ],
        ),
      ),
      child: CustomPaint(painter: _LiquidPainter(dark), child: child),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = Offset(size.width * .7, size.height * .25);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: .85,
          center: const Alignment(.65, -.5),
          colors: [
            primary.withValues(alpha: dark ? .17 : .12),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    for (var i = 0; i < 5; i++) {
      final path = Path()
        ..moveTo(size.width * .20 - i * 25, size.height)
        ..cubicTo(
          size.width * .7,
          size.height * .7,
          -size.width * .1,
          size.height * .25,
          size.width * 1.2,
          -size.height * .2 - i * 30,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 50 + i * 7
          ..color = accent.withValues(alpha: dark ? .012 : .025),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: dark ? .025 : .2),
      );
    }
    canvas.drawCircle(
      center,
      math.min(size.width, size.height) * .4,
      Paint()
        ..color = primary.withValues(alpha: .04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
  }

  @override
  bool shouldRepaint(_LiquidPainter oldDelegate) => oldDelegate.dark != dark;
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .33),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFABA2FF), primary, Color(0xFF5862C7)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .3)),
      boxShadow: [
        BoxShadow(
          color: primary.withValues(alpha: .25),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .33),
      child: Image.asset('assets/govor.png', fit: BoxFit.contain),
    ),
  );
}

class GlassSegments extends StatelessWidget {
  const GlassSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Glass(
    radius: 28,
    padding: const EdgeInsets.all(3),
    child: Row(
      children: [
        for (final (index, label) in labels.indexed)
          Expanded(
            child: Semantics(
              selected: selected == index,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    gradient: selected != index
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF7864E4), Color(0xFF4E417E)],
                          ),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected == index
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: selected == index ? Colors.white : muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class GlassPage extends StatelessWidget {
  const GlassPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.maxWidth = 820,
    this.compact = false,
    this.embedded = false,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final double maxWidth;
  final bool compact;
  final bool embedded;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Glass(
                radius: 28,
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 2 : 10,
                  horizontal: 8,
                ),
                child: Row(
                  children: [
                    if (!embedded)
                      IconButton(
                        tooltip: context.l10n.back,
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: compact ? 20 : 24,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: compact ? 17 : 20,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar(
    this.name, {
    super.key,
    this.size = 48,
    this.online = false,
    this.group = false,
    this.image,
  });
  final String name;
  final double size;
  final bool online, group;
  final Uint8List? image;
  @override
  Widget build(BuildContext context) {
    final palette = [
      const Color(0xFF8270BD),
      const Color(0xFF608DA0),
      const Color(0xFFA17B93),
      const Color(0xFF748CC2),
      const Color(0xFF789B8D),
    ];
    final color = palette[name.runes.fold(0, (s, c) => s + c) % palette.length];
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2);
    final initials = words.map((w) => w.characters.first).join().toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: .85),
                  color.withValues(alpha: .4),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .15)),
            ),
            child: image != null
                ? ClipOval(
                    child: Image.memory(
                      image!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      cacheWidth: 256,
                      errorBuilder: (_, _, _) => Text(
                        initials,
                        style: TextStyle(
                          fontSize: size * .32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                : group
                ? Icon(
                    Icons.people_outline_rounded,
                    color: Colors.white,
                    size: size * .45,
                  )
                : Text(
                    initials,
                    style: TextStyle(
                      fontSize: size * .32,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF89CEB2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, {super.key, this.onDismiss});
  final String message;
  final VoidCallback? onDismiss;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFF8D9C).withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFF8D9C).withValues(alpha: .2)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 19,
          color: Color(0xFFFF9FAE),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        if (onDismiss != null)
          IconButton(
            tooltip: context.l10n.closeNotice,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
    ),
  );
}

String clockText(DateTime date) {
  final local = date.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
