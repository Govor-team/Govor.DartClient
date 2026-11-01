import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/user_benefits.dart';
import '../features/messenger_controller.dart';

Color tagColor(String value) {
  final hex = value.substring(1);
  return hex.length == 8
      ? Color(int.parse('${hex.substring(6)}${hex.substring(0, 6)}', radix: 16))
      : Color(int.parse('FF$hex', radix: 16));
}

class ProfileTagBadge extends StatelessWidget {
  const ProfileTagBadge({super.key, required this.tag});
  final ProfileTag tag;
  @override
  Widget build(BuildContext context) {
    final angle = tag.number('gradientAngle') * math.pi / 180;
    final end = Alignment(math.sin(angle), -math.cos(angle));
    LinearGradient gradient(String a, String b) => LinearGradient(
      begin: Alignment(-end.x, -end.y),
      end: end,
      colors: [
        tagColor(tag.json[a] as String),
        tagColor(tag.json[b] as String? ?? tag.json[a] as String),
      ],
    );
    Widget text = Text(
      tag.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: tagColor(tag.json['textColor'] as String),
        fontFamily: tag.json['fontFamily'] as String,
        fontFamilyFallback: const ['GovorSans', 'sans-serif'],
        fontWeight:
            FontWeight.values[(tag.number('fontWeight').toInt() ~/ 100) - 1],
        fontSize: tag.number('fontSize'),
      ),
    );
    if (tag.json['textGradientEndColor'] != null) {
      text = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) =>
            gradient('textColor', 'textGradientEndColor').createShader(rect),
        child: text,
      );
    }
    return Semantics(
      label: tag.text,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: gradient('borderColor', 'borderGradientEndColor'),
          boxShadow: [
            BoxShadow(
              color: tagColor(tag.json['shadowColor'] as String),
              blurRadius: tag.number('shadowBlur'),
              offset: Offset(
                tag.number('shadowOffsetX'),
                tag.number('shadowOffsetY'),
              ),
            ),
          ],
        ),
        padding: EdgeInsets.all(tag.number('borderWidth')),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: gradient('backgroundColor', 'gradientEndColor'),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: text,
          ),
        ),
      ),
    );
  }
}

class UserBadge extends StatefulWidget {
  const UserBadge({
    super.key,
    required this.controller,
    required this.userId,
    this.fallback = const UserBenefits(),
  });
  final MessengerController controller;
  final String userId;
  final UserBenefits fallback;
  @override
  State<UserBadge> createState() => _UserBadgeState();
}

class _UserBadgeState extends State<UserBadge> {
  @override
  void initState() {
    super.initState();
    widget.controller.watchBenefits(widget.userId);
    _remember();
  }

  void _remember() {
    final revision = widget.controller.sessionRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == widget.controller.sessionRevision) {
        widget.controller.benefits.apply(widget.userId, widget.fallback);
      }
    });
  }

  @override
  void didUpdateWidget(UserBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fallback != widget.fallback) _remember();
    if (oldWidget.controller != widget.controller ||
        oldWidget.userId != widget.userId) {
      oldWidget.controller.unwatchBenefits(oldWidget.userId);
      widget.controller.watchBenefits(widget.userId);
    }
  }

  @override
  void dispose() {
    widget.controller.unwatchBenefits(widget.userId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller.benefits,
    builder: (context, _) {
      final cached = widget.controller.benefits[widget.userId];
      final benefits =
          cached == null || cached.revision < widget.fallback.revision
          ? widget.fallback
          : cached;
      return Wrap(
        spacing: 4,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (benefits.isGovorPlus)
            const Tooltip(
              message: 'Govor+',
              child: Icon(
                Icons.verified_rounded,
                color: Color(0xFF9A8CFF),
                size: 16,
              ),
            ),
          if (benefits.tag != null) ProfileTagBadge(tag: benefits.tag!),
        ],
      );
    },
  );
}
