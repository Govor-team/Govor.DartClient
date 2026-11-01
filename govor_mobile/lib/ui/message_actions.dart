import '../l10n/l10n.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/models.dart';
import '../features/messenger_controller.dart';
import '../features/reactions/reaction_picker_cubit.dart';
import 'reaction_graphic.dart';
import 'design.dart';

Future<String?> showMessageActions(
  BuildContext context,
  MessengerController controller,
  ChatMessage message, {
  Offset? position,
}) => showDialog<String>(
  context: context,
  barrierColor: Colors.black26,
  builder: (_) => _MessageActions(
    controller: controller,
    message: message,
    position: position,
  ),
);

class _MessageActions extends StatefulWidget {
  const _MessageActions({
    required this.controller,
    required this.message,
    this.position,
  });
  final MessengerController controller;
  final ChatMessage message;
  final Offset? position;
  @override
  State<_MessageActions> createState() => _MessageActionsState();
}

class _MessageActionsState extends State<_MessageActions> {
  late final chat = widget.controller.selected;
  int policyVersion = -1;
  late final picker = ReactionPickerCubit(
    loadPacks: () => widget.controller.reactionChoices(conversation: chat),
    applyReaction: (id) => widget.controller.react(widget.message, id),
  );
  @override
  void initState() {
    super.initState();
    policyVersion = widget.controller.channelPolicyVersions[chat?.id] ?? -1;
    widget.controller.addListener(_policyChanged);
    unawaited(picker.load());
  }

  void _policyChanged() {
    final version = widget.controller.channelPolicyVersions[chat?.id] ?? -1;
    if (version != policyVersion) {
      policyVersion = version;
      unawaited(picker.load());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_policyChanged);
    unawaited(picker.close());
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ReactionPickerCubit, ReactionPickerState>(
    bloc: picker,
    builder: (context, state) {
      final message = widget.message, c = widget.controller;
      final actions = <(String, String, IconData)>[
        if (c.selected?.canPost == true && message.failure == null)
          ('reply', context.l10n.reply, Icons.reply_rounded),
        if (message.text != null)
          ('copy', context.l10n.copyText, Icons.copy_rounded),
        if (message.text != null && message.failure == null)
          ('forward', context.l10n.forward, Icons.forward_rounded),
        if (message.senderId == c.userId &&
            message.failure == null &&
            message.attachments.isEmpty)
          ('edit', context.l10n.edit, Icons.edit_outlined),
        if (c.reactionStates[message.id]?['mine'] != null)
          (
            'removeReaction',
            context.l10n.removeReaction,
            Icons.remove_circle_outline_rounded,
          ),
        ('select', context.l10n.select, Icons.check_circle_outline_rounded),
        if (message.senderId == c.userId || (c.selected?.role ?? 0) >= 1)
          ('delete', context.l10n.delete, Icons.delete_outline_rounded),
      ];
      return LayoutBuilder(
        builder: (context, bounds) {
          final width = 320.0.clamp(0.0, bounds.maxWidth - 24);
          final errorsHeight = state.failed || state.applyFailed ? 48.0 : 0.0;
          final fixedHeight = 53.0 + errorsHeight + (state.expanded ? 58 : 0);
          final desiredGrid =
              ((((state.reactions.length + 7) ~/ 8) * (width - 14) / 8) + 14)
                  .clamp(64.0, 280.0);
          final height =
              (fixedHeight +
                      actions.length * 44 +
                      (state.expanded ? desiredGrid : 0))
                  .clamp(0.0, bounds.maxHeight - 32);
          final gridHeight = desiredGrid.clamp(
            0.0,
            (height - fixedHeight - (actions.length * 44).clamp(0, 88)).clamp(
              0.0,
              desiredGrid,
            ),
          );
          final position =
              widget.position ??
              Offset(
                (bounds.maxWidth - width) / 2,
                (bounds.maxHeight - height) / 2,
              );
          return Stack(
            children: [
              Positioned(
                left: position.dx.clamp(12.0, bounds.maxWidth - width - 12),
                top: position.dy.clamp(16.0, bounds.maxHeight - height - 16),
                width: width,
                height: height,
                child: Glass(
                  radius: 18,
                  tint: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: .9),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              Expanded(
                                child: state.loading
                                    ? const Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : state.expanded
                                    ? ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        itemCount: state.packs.length,
                                        itemBuilder: (context, i) {
                                          final pack = state.packs[i];
                                          final reactions = objects(
                                            pack['reactions'],
                                          );
                                          final label =
                                              pack['id'] == 'channel-reactions'
                                              ? context.l10n.allowedReactions
                                              : pack['name'] as String? ?? '';
                                          return Tooltip(
                                            message: label,
                                            child: Semantics(
                                              label: label,
                                              selected: state.pack == i,
                                              child: InkWell(
                                                onTap: () =>
                                                    picker.selectPack(i),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: Container(
                                                  width: 42,
                                                  margin: const EdgeInsets.all(
                                                    5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: state.pack == i
                                                        ? accent.withValues(
                                                            alpha: .23,
                                                          )
                                                        : null,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: Center(
                                                    child: reactions.isEmpty
                                                        ? const Icon(
                                                            Icons
                                                                .emoji_emotions_outlined,
                                                            size: 23,
                                                          )
                                                        : ReactionGraphic(
                                                            reaction:
                                                                reactions.first,
                                                            controller: c,
                                                            size: 24,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    : Row(
                                        children: [
                                          for (final reaction
                                              in state.reactions.take(6))
                                            Expanded(
                                              child: _reaction(
                                                context,
                                                reaction,
                                                state,
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                              IconButton(
                                key: const Key('expand-reactions'),
                                tooltip: context.l10n.allReactions,
                                onPressed: picker.expand,
                                icon: Icon(
                                  state.expanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (state.failed || state.applyFailed)
                          SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    state.applyFailed
                                        ? context.l10n.couldNotApplyReaction
                                        : context.l10n.couldNotLoadReactions,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.l10n.retry,
                                  onPressed: picker.load,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                              ],
                            ),
                          ),
                        if (state.expanded) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: TextField(
                              key: const Key('reaction-search'),
                              onChanged: picker.search,
                              decoration: InputDecoration(
                                hintText: context.l10n.findEmoji,
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  size: 19,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: gridHeight,
                            child: state.reactions.isEmpty
                                ? Center(child: Text(context.l10n.nothingFound))
                                : GridView.builder(
                                    key: const Key('reaction-grid'),
                                    padding: const EdgeInsets.all(7),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 8,
                                        ),
                                    itemCount: state.reactions.length,
                                    itemBuilder: (context, index) => _reaction(
                                      context,
                                      state.reactions[index],
                                      state,
                                    ),
                                  ),
                          ),
                        ],
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              for (final (action, label, icon) in actions)
                                ListTile(
                                  key: ValueKey('message-action-$action'),
                                  dense: true,
                                  minTileHeight: 44,
                                  visualDensity: VisualDensity.compact,
                                  leading: Icon(
                                    icon,
                                    size: 19,
                                    color: action == 'delete'
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                  ),
                                  title: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: action == 'delete'
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                                  ),
                                  onTap: state.sending
                                      ? null
                                      : () => Navigator.pop(context, action),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  Widget _reaction(
    BuildContext context,
    Json reaction,
    ReactionPickerState state,
  ) => Tooltip(
    message: reaction['name'] as String? ?? '',
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: state.sending
          ? null
          : () async {
              final applied = await picker.react(reaction['id'] as String);
              if (applied && context.mounted) Navigator.pop(context);
            },
      child: SizedBox(
        height: 42,
        child: Center(
          child: ReactionGraphic(
            reaction: reaction,
            controller: widget.controller,
            size: 24,
          ),
        ),
      ),
    ),
  );
}
