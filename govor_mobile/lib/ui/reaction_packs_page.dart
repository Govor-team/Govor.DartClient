import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../features/messenger_controller.dart';
import 'design.dart';

import 'feature_shared.dart';
import 'reaction_graphic.dart';

class ReactionPacksPage extends StatefulWidget {
  const ReactionPacksPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final bool embedded;
  final MessengerController controller;
  @override
  State<ReactionPacksPage> createState() => _ReactionPacksPageState();
}

class _ReactionPacksPageState extends State<ReactionPacksPage>
    with PageActions<ReactionPacksPage> {
  @override
  MessengerController get controller => widget.controller;
  final _query = TextEditingController(), _code = TextEditingController();
  int _tab = 0;
  List<Json> _packs = [];
  Set<String> _installed = {};
  Future<void> _load() => run(() async {
    final mine = await controller.reactionPacks();
    _installed = mine.map((p) => p['id'] as String).toSet();
    _packs = _tab == 0 ? mine : await controller.reactionPacks(mine: false);
  });
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassPage(
    embedded: widget.embedded,
    title: context.l10n.reactionPacks,
    subtitle: context.l10n.yourEmojiForMessages,
    trailing: IconButton(
      tooltip: context.l10n.refresh,
      onPressed: working ? null : _load,
      icon: const Icon(Icons.refresh_rounded),
    ),
    child: ListView(
      children: [
        GlassSegments(
          labels: [context.l10n.myPacks, context.l10n.catalog],
          selected: _tab,
          onChanged: (v) {
            setState(() => _tab = v);
            _load();
          },
        ),
        const SizedBox(height: 14),
        Glass(
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.l10n.findAPack,
              prefixIcon: Icon(Icons.search_rounded),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        feedback,
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.addByCode,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      decoration: InputDecoration(
                        hintText: context.l10n.sharedPackCode,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: working || controller.demo
                        ? null
                        : () => run(() async {
                            final pack = await controller.sharedPack(
                              _code.text,
                            );
                            _packs = [
                              pack,
                              ..._packs.where((p) => p['id'] != pack['id']),
                            ];
                          }),
                    child: Text(context.l10n.open),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final pack in _packs.where(
          (p) => p['name'].toString().toLowerCase().contains(
            _query.text.toLowerCase(),
          ),
        ))
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pack['name'] as String,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      pack['isDefault'] == true
                          ? context.l10n.alwaysAvailable
                          : _installed.contains(pack['id'])
                          ? context.l10n.installed
                          : '',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  pack['description'] as String? ?? '',
                  style: const TextStyle(color: muted, height: 1.6),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    for (final r in objects(pack['reactions']))
                      ReactionGraphic(reaction: r, controller: controller),
                  ],
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: pack['shareCode'] as String),
                  ),
                  child: Text(context.l10n.copyPackCode),
                ),
                if (pack['isDefault'] != true) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: working
                        ? null
                        : () => run(() async {
                            await controller.subscribePack(
                              pack['id'] as String,
                              !_installed.contains(pack['id']),
                            );
                            final mine = await controller.reactionPacks();
                            _installed = mine
                                .map((p) => p['id'] as String)
                                .toSet();
                          }),
                    child: Text(
                      _installed.contains(pack['id'])
                          ? context.l10n.removeFromMyPacks
                          : context.l10n.install,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    ),
  );
}
