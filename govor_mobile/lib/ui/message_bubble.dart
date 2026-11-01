import 'person_name.dart';
import 'reply_preview.dart';
import 'user_badge.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../core/models.dart';
import '../features/messenger_controller.dart';
import '../l10n/l10n.dart';
import 'design.dart';
import 'feature_pages.dart';
import 'attachment_gallery.dart';
import 'govor_markdown.dart';
import '../features/reactions/reaction_selection.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.controller,
    required this.selectedIds,
    required this.onToggle,
    required this.onActions,
    required this.onSave,
    required this.onReact,
  });
  final ChatMessage message;
  final MessengerController controller;
  MessengerController get c => controller;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final Future<void> Function(ChatMessage, {Offset? position}) onActions;
  final Future<void> Function(Json) onSave;
  final Future<void> Function(ChatMessage, String?) onReact;
  @override
  Widget build(BuildContext context) {
    final m = message;
    Offset? menuPosition;
    Offset? pointerPosition;
    PointerDeviceKind? pointerKind;
    final mine = m.senderId == c.userId;
    final failed = m.failure != null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width < 820
                ? MediaQuery.sizeOf(context).width * .77
                : 530,
          ),
          child: Listener(
            onPointerDown: (event) {
              pointerKind = event.kind;
              pointerPosition = event.position;
              if (event.buttons & kSecondaryMouseButton != 0) {
                menuPosition = event.position;
              }
            },
            onPointerCancel: (_) => menuPosition = null,
            onPointerUp: (_) {
              final position = menuPosition;
              menuPosition = null;
              if (position != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  ContextMenuController.removeAny();
                  unawaited(onActions(m, position: position));
                });
              }
            },
            child: GestureDetector(
              onTap: selectedIds.isEmpty ? null : () => onToggle(m.id),
              onLongPressStart: (details) =>
                  onActions(m, position: details.globalPosition),

              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                decoration: BoxDecoration(
                  gradient: mine
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0x8C8060C0), Color(0x70494780)],
                        )
                      : null,
                  color: mine
                      ? null
                      : (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF333B53).withValues(alpha: .52)
                            : Colors.white.withValues(alpha: .72)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: const Radius.circular(24),
                    bottomRight: Radius.circular(mine ? 0 : 24),
                  ),
                  border: Border.all(
                    color: selectedIds.contains(m.id)
                        ? accent
                        : Colors.white.withValues(alpha: mine ? .20 : .16),
                    width: selectedIds.contains(m.id) ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedIds.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Icon(
                          selectedIds.contains(m.id)
                              ? Icons.check_circle_outline_rounded
                              : Icons.circle_outlined,
                          color: accent,
                          size: 20,
                        ),
                      ),
                    if (m.type == 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            PersonName(
                              controller: c,
                              userId: m.senderId,
                              style: const TextStyle(
                                color: accent,
                                fontSize: 12,
                              ),
                            ),
                            UserBadge(controller: c, userId: m.senderId),
                          ],
                        ),
                      ),
                    if (m.forwardedFromMessageId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              context.l10n.forwarded,
                              style: const TextStyle(
                                color: accent,
                                fontSize: 11,
                              ),
                            ),
                            if (m.forwardedFromUserId != null)
                              PersonName(
                                controller: c,
                                userId: m.forwardedFromUserId!,
                                style: const TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (m.replyTo != null)
                      ReplyPreview(controller: c, message: m),
                    if (failed)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 5),
                        child: Icon(
                          Icons.gpp_bad_outlined,
                          size: 20,
                          color: Color(0xFFFFB0B0),
                        ),
                      ),
                    if (m.attachments.isNotEmpty && c.media != null)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: (m.text?.isNotEmpty ?? false) ? 6 : 0,
                        ),
                        child: AttachmentGallery(
                          attachments: m.attachments,
                          repository: c.media!,
                          onSave: onSave,
                        ),
                      ),
                    if (failed || m.text == null || m.text!.isNotEmpty)
                      GovorMarkdown(
                        failed
                            ? context.l10n.couldNotVerifyOrDecryptThisMessage
                            : m.text ?? context.l10n.encryptedMessage,
                        contextMenuBuilder: (context, state) {
                          if (pointerKind == PointerDeviceKind.touch ||
                              pointerKind == PointerDeviceKind.stylus) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              state.hideToolbar();
                              unawaited(
                                onActions(m, position: pointerPosition),
                              );
                            });
                            return const SizedBox.shrink();
                          }
                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: state.contextMenuAnchors,
                            buttonItems: [
                              ContextMenuButtonItem(
                                label: context.l10n.copy,
                                onPressed: () {
                                  state.copySelection(
                                    SelectionChangedCause.toolbar,
                                  );
                                  state.hideToolbar();
                                },
                              ),
                              ContextMenuButtonItem(
                                label: context.l10n.messageActions,
                                onPressed: () {
                                  state.hideToolbar();
                                  unawaited(onActions(m));
                                },
                              ),
                            ],
                          );
                        },
                        style: TextStyle(
                          color: mine ? Colors.white : null,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                    if (failed)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          m.failure!,
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                    if ((c.reactionStates[m.id]?['counts'] as List? ?? [])
                        .isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final reaction in objects(
                            c.reactionStates[m.id]!['counts'],
                          ))
                            ActionChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HistoricalReaction(
                                    reaction: reaction,
                                    controller: c,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${reaction['count']}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                              backgroundColor:
                                  isOwnReaction(
                                    c.reactionStates[m.id]?['mine'] as Json?,
                                    reaction,
                                  )
                                  ? accent.withValues(alpha: .3)
                                  : null,
                              onPressed: () {
                                final id = reaction['reactionId'] as String?;
                                if (id != null ||
                                    isOwnReaction(
                                      c.reactionStates[m.id]?['mine'] as Json?,
                                      reaction,
                                    )) {
                                  unawaited(onReact(m, id));
                                } else {
                                  unawaited(onActions(m));
                                }
                              },
                            ),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.edited
                              ? context.l10n.editedTime(clockText(m.sentAt))
                              : clockText(m.sentAt),
                          style: TextStyle(
                            fontSize: 9,
                            color: mine ? Colors.white60 : muted,
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 4),
                          Icon(
                            c.demo
                                ? Icons.check_rounded
                                : Icons.cloud_done_outlined,
                            size: 12,
                            color: Colors.white60,
                          ),
                        ],
                        const SizedBox(width: 2),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            tooltip: context.l10n.messageActions,
                            padding: EdgeInsets.zero,
                            onPressed: () => onActions(m),
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              size: 15,
                              color: mine ? Colors.white60 : muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
