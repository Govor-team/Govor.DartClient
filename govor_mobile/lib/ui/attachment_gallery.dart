import '../l10n/l10n.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/media/attachment_repository.dart';
import '../core/media/playback_source_native.dart'
    if (dart.library.js_interop) '../core/media/playback_source_web.dart';
import '../core/models.dart';
import '../features/media/attachment_cubit.dart';
import 'design.dart';

class AttachmentGallery extends StatelessWidget {
  const AttachmentGallery({
    super.key,
    required this.attachments,
    required this.repository,
    required this.onSave,
  });
  final List<Json> attachments;
  final AttachmentRepository repository;
  final Future<void> Function(Json) onSave;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = attachments.where((json) {
        final item = Attachment.fromJson(json);
        return item.isImage || item.isVideo;
      }).toList();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (media.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  for (final row in albumRows(media.length))
                    SizedBox(
                      height:
                          (constraints.maxWidth /
                                  row.length *
                                  (media.length == 1 ? .75 : .85))
                              .clamp(80.0, 320.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 2,
                        children: [
                          for (final index in row)
                            Expanded(
                              child: _AttachmentTile(
                                key: ValueKey(
                                  Attachment.fromJson(media[index]).id,
                                ),
                                attachment: Attachment.fromJson(media[index]),
                                repository: repository,
                                onOpen: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _MediaViewer(
                                    attachments: media,
                                    initial: index,
                                    repository: repository,
                                    onSave: onSave,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          for (final json in attachments.where((json) {
            final a = Attachment.fromJson(json);
            return !a.isImage && !a.isVideo;
          }))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(
                Attachment.fromJson(json).name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.download_rounded),
              onTap: () => onSave(json),
            ),
        ],
      );
    },
  );
}

/// Balanced rows without empty cells, preserving the attachment order.
List<List<int>> albumRows(int count) {
  if (count <= 0) return [];
  final rows = <List<int>>[];
  var next = 0;
  while (next < count) {
    final remaining = count - next;
    final size = remaining == 3 && count == 3
        ? 1
        : remaining >= 5 || remaining == 3
        ? 3
        : remaining >= 2
        ? 2
        : 1;
    rows.add(List.generate(size, (i) => next + i));
    next += size;
  }
  return rows;
}

class AttachmentPreview extends StatelessWidget {
  const AttachmentPreview({
    super.key,
    required this.attachments,
    required this.repository,
    required this.onRemove,
    required this.onSave,
  });
  final List<Json> attachments;
  final AttachmentRepository repository;
  final ValueChanged<int>? onRemove;
  final Future<void> Function(Json) onSave;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: attachments.length,
      separatorBuilder: (_, _) => const SizedBox(width: 3),
      itemBuilder: (context, index) {
        final a = Attachment.fromJson(attachments[index]);
        return SizedBox(
          width: 96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (a.isImage || a.isVideo)
                  _AttachmentTile(
                    key: ValueKey(a.id),
                    attachment: a,
                    repository: repository,
                    onOpen: () => showDialog<void>(
                      context: context,
                      builder: (_) => _MediaViewer(
                        attachments: [attachments[index]],
                        initial: 0,
                        repository: repository,
                        onSave: onSave,
                      ),
                    ),
                  )
                else
                  Center(
                    child: Text(
                      a.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton.filled(
                    tooltip: context.l10n.delete,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                    onPressed: onRemove == null ? null : () => onRemove!(index),
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({
    super.key,
    required this.attachment,
    required this.repository,
    required this.onOpen,
    this.full = false,
  });
  final Attachment attachment;
  final AttachmentRepository repository;
  final VoidCallback onOpen;
  final bool full;
  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  late final cubit = AttachmentCubit(widget.repository, widget.attachment);
  @override
  void initState() {
    super.initState();
    unawaited(cubit.load());
  }

  @override
  void dispose() {
    final bytes = cubit.state.bytes;
    if (bytes != null) {
      unawaited(
        ResizeImage.resizeIfNeeded(640, null, MemoryImage(bytes)).evict(),
      );
      unawaited(MemoryImage(bytes).evict());
    }
    unawaited(cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AttachmentCubit, AttachmentState>(
        bloc: cubit,
        builder: (context, state) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.full ? null : widget.onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.full ? 12 : 0),
            child: Material(
              color: Colors.black26,
              child: switch (state.status) {
                AttachmentStatus.initial ||
                AttachmentStatus.loading => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                AttachmentStatus.failed => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: cubit.load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(context.l10n.retryDownload),
                      ),
                      if (!widget.full)
                        TextButton(
                          onPressed: widget.onOpen,
                          child: Text(context.l10n.open),
                        ),
                    ],
                  ),
                ),
                AttachmentStatus.ready =>
                  widget.attachment.isVideo
                      ? _AttachmentVideo(
                          bytes: state.bytes!,
                          mime: widget.attachment.mime,
                          full: widget.full,
                          onOpen: widget.onOpen,
                        )
                      : InkWell(
                          onTap: widget.onOpen,
                          child: widget.full
                              ? InteractiveViewer(
                                  minScale: .5,
                                  maxScale: 5,
                                  child: Image.memory(
                                    state.bytes!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                )
                              : Image.memory(
                                  state.bytes!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 640,
                                  semanticLabel: widget.attachment.name,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                        ),
              },
            ),
          ),
        ),
      );
}

class _MediaViewer extends StatefulWidget {
  const _MediaViewer({
    required this.attachments,
    required this.initial,
    required this.repository,
    required this.onSave,
  });
  final List<Json> attachments;
  final int initial;
  final AttachmentRepository repository;
  final Future<void> Function(Json) onSave;
  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late int index = widget.initial;
  late final pages = PageController(initialPage: index);
  String? problem;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: const Color(0xFF101018),
    child: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: context.l10n.close,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Text(
                  Attachment.fromJson(widget.attachments[index]).name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${index + 1} / ${widget.attachments.length}'),
              IconButton(
                tooltip: context.l10n.save,
                onPressed: () async {
                  try {
                    await widget.onSave(widget.attachments[index]);
                  } catch (_) {
                    if (mounted) {
                      setState(() => problem = context.l10n.couldNotSaveFile);
                    }
                  }
                },
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
          if (problem != null) ErrorNotice(problem!),
          Expanded(
            child: PageView.builder(
              controller: pages,
              itemCount: widget.attachments.length,
              onPageChanged: (value) => setState(() {
                index = value;
                problem = null;
              }),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.all(12),
                child: i == index
                    ? _AttachmentTile(
                        key: ValueKey(
                          Attachment.fromJson(widget.attachments[i]).id,
                        ),
                        attachment: Attachment.fromJson(widget.attachments[i]),
                        repository: widget.repository,
                        onOpen: () {},
                        full: true,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          if (widget.attachments.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: context.l10n.previousFile,
                  onPressed: index == 0
                      ? null
                      : () => pages.previousPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        ),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: context.l10n.nextFile,
                  onPressed: index == widget.attachments.length - 1
                      ? null
                      : () => pages.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        ),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _AttachmentVideo extends StatefulWidget {
  const _AttachmentVideo({
    required this.bytes,
    required this.mime,
    required this.full,
    required this.onOpen,
  });
  final Uint8List bytes;
  final String mime;
  final bool full;
  final VoidCallback onOpen;
  @override
  State<_AttachmentVideo> createState() => _AttachmentVideoState();
}

class _AttachmentVideoState extends State<_AttachmentVideo> {
  Player? player;
  VideoController? video;
  PlaybackSource? source;
  bool failed = false;
  StreamSubscription<String>? errors;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final lease = await PlaybackSource.create(widget.bytes, widget.mime);
      if (!mounted) {
        await lease.dispose();
        return;
      }
      source = lease;
      final next = Player(
        configuration: PlayerConfiguration(
          muted: !widget.full,
          bufferSize: 4 * 1024 * 1024,
          protocolWhitelist: const ['file', 'data', 'crypto'],
        ),
      );
      player = next;
      video = VideoController(next);
      errors = next.stream.error.listen((_) {
        if (mounted) setState(() => failed = true);
      });
      await next.open(Media(lease.uri), play: false);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    final old = player, lease = source;
    unawaited(errors?.cancel());
    unawaited(() async {
      try {
        await old?.dispose();
      } finally {
        await lease?.dispose();
      }
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => failed
      ? Center(
          child: widget.full
              ? Text(context.l10n.couldNotOpenVideo)
              : TextButton(
                  onPressed: widget.onOpen,
                  child: Text(context.l10n.couldNotOpenVideo),
                ),
        )
      : video == null
      ? const Center(child: CircularProgressIndicator())
      : Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: video!,
              fit: widget.full ? BoxFit.contain : BoxFit.cover,
              controls: widget.full ? AdaptiveVideoControls : NoVideoControls,
            ),
            if (!widget.full)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onOpen,
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
          ],
        );
}
