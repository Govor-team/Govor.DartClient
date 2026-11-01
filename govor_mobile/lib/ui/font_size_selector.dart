import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/settings/settings_cubit.dart';
import '../l10n/l10n.dart';
import 'design.dart';
import 'feature_shared.dart';

class FontSizeSelector extends StatelessWidget {
  const FontSizeSelector({super.key, required this.settings});
  final SettingsCubit settings;
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SettingsCubit, SettingsState>(
        bloc: settings,
        builder: (context, state) => GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.text_fields_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.fontSize,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${state.fontSize.round()}',
                    style: const TextStyle(color: accent, fontSize: 16),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    key: const Key('reset-font-size'),
                    tooltip: context.l10n.resetFontSize,
                    onPressed: state.fontSaving
                        ? null
                        : () => settings.setFontSize(
                            SettingsCubit.defaultFontSize,
                          ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 19),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                      ),
                      child: Slider(
                        key: const Key('font-size-slider'),
                        min: SettingsCubit.minFontSize,
                        max: SettingsCubit.maxFontSize,
                        divisions: 12,
                        value: state.fontSize,
                        label: '${state.fontSize.round()}',
                        semanticFormatterCallback: (value) =>
                            '${context.l10n.fontSize}: ${value.round()}',
                        onChanged: settings.previewFontSize,
                        onChangeEnd: settings.setFontSize,
                      ),
                    ),
                  ),
                ],
              ),
              if (state.fontFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.l10n.fontSizeSaveFailed,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
