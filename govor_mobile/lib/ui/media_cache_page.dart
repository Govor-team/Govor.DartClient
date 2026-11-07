import 'package:flutter/material.dart';
import '../core/media/media_cache.dart';
import '../features/messenger_controller.dart';
import '../l10n/l10n.dart';
import 'design.dart';
import 'feature_shared.dart';

class MediaCachePage extends StatefulWidget {
  const MediaCachePage({super.key, required this.controller});
  final MessengerController controller;

  @override
  State<MediaCachePage> createState() => _MediaCachePageState();
}

class _MediaCachePageState extends State<MediaCachePage> {
  ({int limit, int bytes})? _stats;
  bool _busy = false, _failed = false;
  MediaCache get _cache => widget.controller.dependencies.mediaCache;

  @override
  void initState() {
    super.initState();
    _update();
  }

  Future<void> _update([Future<void> Function()? action]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action?.call();
      final stats = await _cache.stats();
      if (mounted) {
        setState(() {
          _stats = stats;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => GlassPage(
    title: context.l10n.mediaCacheTitle,
    child: ListView(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(context.l10n.mediaCacheHint),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_failed) ErrorNotice(context.l10n.mediaCacheError),
              if (_stats case final stats?) ...[
                Text(
                  context.l10n.mediaCacheUsed(
                    (stats.bytes / (1024 * 1024)).toStringAsFixed(1),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final limit in mediaCacheLimits)
                      ChoiceChip(
                        label: Text(
                          limit == 0
                              ? context.l10n.mediaCacheOff
                              : context.l10n.mediaCacheLimit('$limit'),
                        ),
                        selected: limit == stats.limit,
                        onSelected: _busy
                            ? null
                            : (_) => _update(() => _cache.setLimit(limit)),
                      ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: _busy || stats.bytes == 0
                      ? null
                      : () => _update(_cache.clear),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(context.l10n.mediaCacheClear),
                ),
              ] else if (_failed)
                TextButton(onPressed: _update, child: Text(context.l10n.retry)),
            ],
          ),
        ),
      ],
    ),
  );
}
