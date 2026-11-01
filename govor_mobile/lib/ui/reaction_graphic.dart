import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../features/messenger_controller.dart';
import 'design.dart';

class ReactionGraphic extends StatelessWidget {
  const ReactionGraphic({
    super.key,
    required this.reaction,
    required this.controller,
    this.size = 30,
  });
  final Json reaction;
  final MessengerController controller;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (reaction['kind'] == 0 || reaction['mediaFileId'] == null) {
      return Text(
        reaction['emoji'] as String? ??
            reaction['reactionCode'] as String? ??
            reaction['code'] as String? ??
            '☺',
        style: TextStyle(fontSize: size),
      );
    }
    return FutureBuilder<Uint8List>(
      future: controller.reactionImage(reaction['mediaFileId'] as String),
      builder: (context, state) => state.hasData
          ? Image.memory(
              state.data!,
              width: size,
              height: size,
              cacheWidth: 128,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            )
          : SizedBox(
              width: size,
              height: size,
              child: const Icon(Icons.emoji_emotions_outlined, color: muted),
            ),
    );
  }
}

/// Historical reactions may belong to packs that are no longer installed.
class HistoricalReaction extends StatelessWidget {
  const HistoricalReaction({
    super.key,
    required this.reaction,
    required this.controller,
  });
  final Json reaction;
  final MessengerController controller;
  @override
  Widget build(BuildContext context) {
    final id = reaction['reactionId'] as String?;
    if (id == null || controller.demo) {
      return ReactionGraphic(
        reaction: reaction,
        controller: controller,
        size: 18,
      );
    }
    return FutureBuilder<Json>(
      future: controller.reactionDefinition(id),
      builder: (context, value) => ReactionGraphic(
        reaction: value.data ?? reaction,
        controller: controller,
        size: 18,
      ),
    );
  }
}
