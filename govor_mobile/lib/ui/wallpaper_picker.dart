import '../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../core/wallpapers.dart';
import '../features/messenger_controller.dart';
import 'design.dart';

class WallpaperPicker extends StatelessWidget {
  const WallpaperPicker({
    super.key,
    required this.controller,
    required this.onAction,
    this.disabled = false,
  });
  final MessengerController controller;
  final Future<void> Function(Future<void> Function()) onAction;
  final bool disabled;
  List<String> names(BuildContext context) => [
    context.l10n.tricolor,
    context.l10n.journey,
    context.l10n.vedas,
    context.l10n.rod,
    context.l10n.aria,
  ];

  Widget _addTile(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.addABackground,
    child: Material(
      color: const Color(0xFF202130).withValues(alpha: .7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: .4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('import-wallpaper-tile'),
        onTap: disabled ? null : () => onAction(controller.importWallpaper),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 42, color: accent),
            SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                context.l10n.customBackground,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'PNG · JPEG · WebP',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tile(
    BuildContext context,
    String? id,
    String name, {
    CustomWallpaper? custom,
  }) {
    final active = id == controller.wallpaper;
    return Semantics(
      selected: active,
      button: true,
      label: context.l10n.wallpaperName(name),
      child: Material(
        color: const Color(0xFF181A27),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('wallpaper-${id ?? 'gradient'}'),
          onTap: disabled
              ? null
              : () => onAction(
                  () => controller.setAppearance(
                    background: id,
                    useGradient: id == null,
                  ),
                ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (id == null)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF5E4F8D), Color(0xFF161C2F)],
                    ),
                  ),
                )
              else
                Image(
                  image: ResizeImage.resizeIfNeeded(
                    360,
                    null,
                    custom == null
                        ? AssetImage(id) as ImageProvider
                        : MemoryImage(custom.bytes),
                  ),
                  fit: BoxFit.cover,
                  // Decode an actual thumbnail, not a full wallpaper per tile.
                  filterQuality: FilterQuality.medium,
                  frameBuilder: (_, child, frame, loaded) =>
                      loaded || frame != null
                      ? child
                      : const Center(
                          child: Icon(Icons.landscape_outlined, color: muted),
                        ),
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ),
              if (active)
                const Positioned(
                  top: 9,
                  left: 9,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
              if (custom != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    tooltip: context.l10n.deleteWallpaperName(custom.name),
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: disabled
                        ? null
                        : () => onAction(
                            () => controller.removeWallpaper(custom.id),
                          ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: active ? accent : Colors.white24,
                      width: active ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = <Widget>[
      for (var i = 0; i < MessengerController.wallpapers.length; i++)
        _tile(context, MessengerController.wallpapers[i], names(context)[i]),
      _tile(context, null, context.l10n.gradient),
      for (final custom in controller.customWallpapers)
        _tile(context, custom.id, custom.name, custom: custom),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.chooseAppearance,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton.filledTonal(
              key: const Key('import-wallpaper'),
              tooltip: context.l10n.addABackground,
              onPressed: disabled
                  ? null
                  : () => onAction(controller.importWallpaper),
              icon: const Icon(Icons.add_rounded, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 480) {
              return GridView.count(
                key: const Key('wallpaper-grid'),
                crossAxisCount: constraints.maxWidth >= 720 ? 4 : 3,
                childAspectRatio: .68,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [...choices, _addTile(context)],
              );
            }
            return SizedBox(
              height: 194,
              child: Scrollbar(
                child: ListView.separated(
                  key: const Key('wallpaper-carousel'),
                  scrollDirection: Axis.horizontal,
                  itemCount: choices.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, index) =>
                      SizedBox(width: 124, child: choices[index]),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
