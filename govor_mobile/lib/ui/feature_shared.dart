import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../features/messenger_controller.dart';
import 'design.dart';

Future<void> openFeaturePage(
  BuildContext context,
  MessengerController c,
  Widget page,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
        body: LiquidBackground(
          wallpaper: c.wallpaper,
          customWallpaper: c.customWallpaperBytes,
          child: page,
        ),
      ),
    ),
  ),
);

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Glass(radius: 26, padding: padding, child: child),
  );
}

mixin PageActions<T extends StatefulWidget> on State<T> {
  bool working = false;
  String? problem;
  MessengerController get controller;
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      problem = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => problem = controller.safeError(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Widget get feedback => Column(
    children: [
      if (working)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (problem != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ErrorNotice(problem!),
        ),
    ],
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String text,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    ) ??
    false;
