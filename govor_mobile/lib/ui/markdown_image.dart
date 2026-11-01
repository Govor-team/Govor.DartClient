import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/media/remote_image_repository.dart';
import '../l10n/l10n.dart';

class MarkdownImage extends StatefulWidget {
  const MarkdownImage({super.key, required this.uri, this.alt});
  final Uri uri;
  final String? alt;
  @override
  State<MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<MarkdownImage> {
  late final repository = RemoteImageRepository();
  late Future<Uint8List> data;
  Future<Uint8List> _load() {
    final future = repository.load(widget.uri);
    // A quick failure can arrive before the next FutureBuilder frame subscribes.
    // Keep it handled while preserving the error for the builder's own listener.
    future.ignore();
    return future;
  }

  @override
  void initState() {
    super.initState();
    data = _load();
  }

  Uint8List? loaded;
  void _evict() {
    final bytes = loaded;
    loaded = null;
    if (bytes == null) return;
    unawaited(
      ResizeImage(
        MemoryImage(bytes),
        width: 960,
        height: 640,
        policy: ResizeImagePolicy.fit,
      ).evict(),
    );
    unawaited(MemoryImage(bytes).evict());
  }

  @override
  void didUpdateWidget(MarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      _evict();
      data = _load();
    }
  }

  @override
  void dispose() {
    repository.close();
    _evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 480),
        child: FutureBuilder<Uint8List>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              loaded = snapshot.data;
              return Image(
                image: ResizeImage(
                  MemoryImage(snapshot.data!),
                  width: 960,
                  height: 640,
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.contain,
                semanticLabel: widget.alt,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              );
            }
            if (snapshot.hasError) {
              return TextButton.icon(
                onPressed: () => setState(() {
                  data = _load();
                }),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.retryDownload),
              );
            }
            return const SizedBox(
              height: 120,
              width: 180,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
      ),
    ),
  );
}
