import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/attachment_files.dart';
import '../core/media/image_validation.dart';
import '../features/messenger_controller.dart';
import '../l10n/l10n.dart';
import 'design.dart';

/// Shared avatar interaction for lists, profiles, headers and settings.
class PreviewAvatar extends StatelessWidget {
  const PreviewAvatar(
    this.name, {
    super.key,
    required this.controller,
    this.imageId,
    this.userId,
    this.size = 48,
    this.online = false,
    this.group = false,
  });
  final MessengerController controller;
  final String name;
  final String? imageId, userId;
  final double size;
  final bool online, group;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${context.l10n.avatar}: $name',
    child: Tooltip(
      message: context.l10n.viewAvatar,
      child: InkResponse(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AvatarPreviewDialog(
            controller: controller,
            name: name,
            imageId: imageId,
            userId: userId,
            group: group,
          ),
        ),
        child: PersonAvatar(
          name,
          size: size,
          online: online,
          group: group,
          image: controller.avatarBytes[imageId],
        ),
      ),
    ),
  );
}

class AvatarPreviewDialog extends StatefulWidget {
  const AvatarPreviewDialog({
    super.key,
    required this.controller,
    required this.name,
    this.imageId,
    this.userId,
    this.group = false,
    this.save,
  });
  final MessengerController controller;
  final String name;
  final String? imageId, userId;
  final bool group;
  final Future<void> Function(String, Uint8List)? save;
  @override
  State<AvatarPreviewDialog> createState() => _AvatarPreviewDialogState();
}

class _AvatarPreviewDialogState extends State<AvatarPreviewDialog> {
  late final int revision;
  String? id, extension;
  Uint8List? data;
  bool loading = true, saving = false, failed = false, saveFailed = false;
  ImageProvider? provider;
  bool get active => revision == widget.controller.sessionRevision;

  @override
  void initState() {
    super.initState();
    // Capture the session before any asynchronous work starts.
    revision = widget.controller.sessionRevision;
    id = widget.imageId;
    widget.controller.addListener(_changed);
    _load();
  }

  void _changed() {
    if (!mounted) return;
    if (!active) {
      provider?.evict();
      setState(() {
        data = null;
        provider = null;
        loading = false;
      });
    } else if (!loading &&
        data == null &&
        widget.controller.avatarBytes[id] != null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      if (id == null && widget.userId != null) {
        id = (await widget.controller.person(widget.userId!)).iconId;
      }
      if (!mounted || !active) return;
      if (id != null) await widget.controller.loadAvatar(id!);
      final bytes = widget.controller.avatarBytes[id];
      if (bytes != null) {
        if (bytes.isEmpty || bytes.length > 4000000) {
          throw const FormatException();
        }
        final type = fileMime(bytes);
        extension = const {
          'image/png': 'png',
          'image/jpeg': 'jpg',
          'image/gif': 'gif',
          'image/webp': 'webp',
        }[type];
        if (extension == null) throw const FormatException();
        // Decode a bounded preview before permitting a download. Files never
        // obtain their extension from an untrusted user name or URL.
        await validateImageBytes(bytes);
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 768,
          targetHeight: 768,
          allowUpscaling: false,
        );
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
        if (!mounted || !active) return;
        data = bytes;
        provider = ResizeImage(
          MemoryImage(bytes),
          width: 768,
          height: 768,
          policy: ResizeImagePolicy.fit,
        );
      }
      if (mounted && active) {
        setState(() {
          failed = id != null && data == null;
        });
      }
    } catch (_) {
      if (mounted && active) {
        setState(() {
          failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (saving || data == null || !active) return;
    setState(() {
      saving = true;
      saveFailed = false;
    });
    try {
      if (widget.save != null) {
        await widget.save!('avatar.$extension', data!);
      } else {
        await saveAttachment(
          'avatar.$extension',
          data!,
          dialogTitle: context.l10n.downloadAvatar,
        );
      }
    } catch (_) {
      if (mounted && active) {
        setState(() {
          saveFailed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    provider?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      key: const Key('avatar-preview'),
      constraints: const BoxConstraints(maxWidth: 360),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : provider != null && active
                    ? Image(image: provider!, fit: BoxFit.contain)
                    : Center(
                        child: PersonAvatar(
                          widget.name,
                          size: 112,
                          group: widget.group,
                        ),
                      ),
              ),
            ),
            if (failed || !active) ...[
              const SizedBox(height: 8),
              Text(context.l10n.avatarUnavailable),
              if (active)
                TextButton(
                  onPressed: loading ? null : _load,
                  child: Text(context.l10n.retryDownload),
                ),
            ],
            if (saveFailed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.l10n.couldNotSaveFile,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('download-avatar'),
              onPressed: loading || saving || data == null || !active
                  ? null
                  : _save,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(context.l10n.downloadAvatar),
            ),
          ],
        ),
      ),
    ),
  );
}
