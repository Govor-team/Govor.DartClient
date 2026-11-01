import 'package:flutter/material.dart';
import '../features/settings/settings_cubit.dart';
import '../l10n/l10n.dart';
import 'design.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key, required this.settings});
  final SettingsCubit settings;
  @override
  Widget build(BuildContext context) {
    final choices = {
      'ru': context.l10n.russianLanguage,
      'en': 'English',
      'system': context.l10n.systemLanguage,
    };
    final selected = settings.state.language ?? 'system';
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide.none),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      menuChildren: [
        Glass(
          radius: 18,
          tint: Theme.of(context).colorScheme.surface.withValues(alpha: .75),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in choices.entries)
                MenuItemButton(
                  leadingIcon: Icon(
                    entry.key == selected
                        ? Icons.check_rounded
                        : entry.key == 'system'
                        ? Icons.devices_rounded
                        : Icons.translate_rounded,
                    size: 18,
                  ),
                  onPressed: settings.state.saving
                      ? null
                      : () => settings.setLanguage(
                          entry.key == 'system' ? null : entry.key,
                        ),
                  child: SizedBox(width: 156, child: Text(entry.value)),
                ),
            ],
          ),
        ),
      ],
      builder: (context, menu, _) => ListTile(
        key: const Key('language-selector'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        minLeadingWidth: 20,
        horizontalTitleGap: 10,
        dense: true,
        leading: const Icon(Icons.language_rounded, size: 20),
        title: Text(
          context.l10n.interfaceLanguage,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          choices[selected]!,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.unfold_more_rounded),
        onTap: settings.state.saving
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
