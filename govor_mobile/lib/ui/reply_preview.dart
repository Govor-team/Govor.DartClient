import 'package:flutter/material.dart';
import '../core/models.dart';
import '../features/messenger_controller.dart';
import '../l10n/l10n.dart';
import 'design.dart';

class ReplyPreview extends StatefulWidget {
  const ReplyPreview({
    super.key,
    required this.controller,
    required this.message,
  });
  final MessengerController controller;
  final ChatMessage message;
  @override
  State<ReplyPreview> createState() => _ReplyPreviewState();
}

class _ReplyPreviewState extends State<ReplyPreview> {
  late Future<ChatMessage?> preview;
  late int revision;
  Future<ChatMessage?> _load() {
    final future = widget.controller.replyPreview(widget.message);
    future.ignore();
    return future;
  }

  @override
  void initState() {
    super.initState();
    revision = widget.controller.replyRevision;
    preview = _load();
  }

  @override
  void didUpdateWidget(ReplyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.replyTo != widget.message.replyTo ||
        revision != widget.controller.replyRevision) {
      revision = widget.controller.replyRevision;
      preview = _load();
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .08),
      border: const Border(left: BorderSide(color: accent, width: 2)),
    ),
    child: FutureBuilder<ChatMessage?>(
      future: preview,
      builder: (context, snapshot) {
        final original = snapshot.data;
        return InkWell(
          onTap: snapshot.hasError
              ? () => setState(() {
                  preview = _load();
                })
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.replyToAMessage,
                style: const TextStyle(color: accent, fontSize: 11),
              ),
              Text(
                snapshot.connectionState != ConnectionState.done
                    ? '…'
                    : snapshot.hasError
                    ? context.l10n.retry
                    : original == null
                    ? context.l10n.messageDeleted
                    : original.text?.isNotEmpty == true
                    ? original.text!
                    : context.l10n.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    ),
  );
}
