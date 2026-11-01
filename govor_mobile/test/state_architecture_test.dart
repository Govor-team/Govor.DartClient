import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/preferences_repository.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/wallpapers.dart';
import 'package:govor_mobile/features/settings/appearance_cubit.dart';
import 'package:govor_mobile/features/settings/settings_cubit.dart';
import 'package:govor_mobile/features/profile/profile_description_cubit.dart';
import 'package:govor_mobile/features/reactions/reaction_picker_cubit.dart';

void main() {
  test('reaction apply failure is separate from loading the catalog', () async {
    final cubit = ReactionPickerCubit(
      loadPacks: () async => [],
      applyReaction: (_) async => throw StateError('forbidden'),
    );
    addTearDown(cubit.close);
    await cubit.load();
    expect(await cubit.react('a'), isFalse);
    expect(cubit.state.applyFailed, isTrue);
    expect(cubit.state.failed, isFalse);
    await cubit.load();
    expect(cubit.state.applyFailed, isFalse);
  });
  test(
    'appearance serializes overlapping writes and recovers after storage failure',
    () async {
      final writes = <WallpaperSettings>[];
      final gates = <Completer<void>>[];
      final cubit = AppearanceCubit(
        WallpaperRepository(
          read: () async => null,
          write: (json) {
            final data = jsonDecode(json) as Map<String, dynamic>;
            writes.add(
              WallpaperSettings(
                selected: data['selected'] as String?,
                dark: data['dark'] as bool,
              ),
            );
            final gate = Completer<void>();
            gates.add(gate);
            return gate.future;
          },
        ),
      );
      final first = cubit.update(background: AppearanceCubit.wallpapers.first);
      final second = cubit.update(dark: false);
      await Future<void>.delayed(Duration.zero);
      expect(writes, hasLength(1));
      gates.first.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(writes.last.selected, AppearanceCubit.wallpapers.first);
      expect(writes.last.dark, isFalse);
      gates.last.complete();
      await second;
      final failing = cubit.update(useGradient: true);
      await Future<void>.delayed(Duration.zero);
      final assertion = expectLater(failing, throwsStateError);
      gates.last.completeError(StateError('disk'));
      await assertion;
      expect(cubit.state.selected, AppearanceCubit.wallpapers.first);
      expect(cubit.state.dark, isFalse);
      await cubit.close();
    },
  );
  test(
    'preferences persist supported languages and system choice; reject unknown locale',
    () async {
      String? text;
      final repo = LocalPreferencesRepository(
        read: () async => text,
        write: (value) async => text = value,
      );
      expect(await repo.loadLanguage(), isNull);
      await repo.saveLanguage('en');
      expect(await repo.loadLanguage(), 'en');
      await repo.saveLanguage(null);
      expect(await repo.loadLanguage(), isNull);
      text = '{"language":"unknown"}';
      expect(await repo.loadLanguage(), isNull);
    },
  );
  test(
    'settings keep the previous language on storage failure and retry',
    () async {
      var fails = true;
      final cubit = SettingsCubit(
        LocalPreferencesRepository(
          read: () async => null,
          write: (_) async {
            if (fails) throw StateError('disk');
          },
        ),
      );
      addTearDown(cubit.close);
      await cubit.setLanguage('en');
      expect(cubit.state.language, 'ru');
      expect(cubit.state.failed, isTrue);
      fails = false;
      await cubit.setLanguage('en');
      expect(cubit.state.language, 'en');
      expect(cubit.state.failed, isFalse);
      cubit.select(SettingsSection.security);
      expect(cubit.state.language, 'en');
      await cubit.setLanguage('bad');
      expect(cubit.state.language, 'en');
    },
  );
  test(
    'late preference load cannot undo an explicit user language selection',
    () async {
      final gate = Completer<String?>();
      final cubit = SettingsCubit(
        LocalPreferencesRepository(
          read: () => gate.future,
          write: (_) async {},
        ),
      );
      addTearDown(cubit.close);
      final loading = cubit.load();
      final selecting = cubit.setLanguage('en');
      gate.complete('{"language":"ru"}');
      await selecting;
      await loading;
      expect(cubit.state.language, 'en');
    },
  );
  test(
    'profile serializes saves and preserves the latest draft after failure',
    () async {
      final gates = <Completer<void>>[], values = <String>[];
      String? draft;
      final cubit = ProfileDescriptionCubit(
        saved: '',
        save: (value) {
          values.add(value);
          final gate = Completer<void>();
          gates.add(gate);
          return gate.future;
        },
        onDraft: (value) => draft = value,
        errorText: (_) => 'failed',
        debounce: const Duration(days: 1),
      );
      cubit.changed('first');
      final saving = cubit.flush();
      cubit.changed('second');
      expect(values, ['first']);
      gates.first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(values, ['first', 'second']);
      gates.last.completeError(StateError('offline'));
      await saving;
      expect(cubit.state.saved, 'first');
      expect(cubit.state.error, 'failed');
      expect(draft, 'second');
      final retry = cubit.flush();
      gates.last.complete();
      await retry;
      expect(cubit.state.saved, 'second');
      expect(draft, isNull);
      await cubit.close();
    },
  );
  test(
    'reaction picker loads, filters packs, retries and serializes sends',
    () async {
      var fails = true;
      final send = Completer<void>();
      final cubit = ReactionPickerCubit(
        loadPacks: () async {
          if (fails) throw StateError('offline');
          return <Json>[
            {
              'id': 'pack',
              'name': 'Pack',
              'reactions': [
                {'id': 'a', 'name': 'happy', 'emoji': '😁', 'isEnabled': true},
                {'id': 'b', 'name': 'hidden', 'isEnabled': false},
              ],
            },
          ];
        },
        applyReaction: (_) => send.future,
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.failed, isTrue);
      fails = false;
      await cubit.load();
      expect(cubit.state.reactions, hasLength(1));
      cubit.expand();
      cubit.search('missing');
      expect(cubit.state.reactions, isEmpty);
      cubit.search('HAPPY');
      expect(cubit.state.reactions.single['id'], 'a');
      final first = cubit.react('a');
      expect(await cubit.react('a'), isFalse);
      send.complete();
      expect(await first, isTrue);
    },
  );
  test(
    'closing picker during a load prevents post-dispose emissions',
    () async {
      final gate = Completer<List<Json>>();
      final cubit = ReactionPickerCubit(
        loadPacks: () => gate.future,
        applyReaction: (_) async {},
      );
      final task = cubit.load();
      await cubit.close();
      gate.complete([]);
      await task;
    },
  );
  test('ARB catalogs have identical keys and placeholder sets', () {
    final ru =
        jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final keys = ru.keys.where((key) => !key.startsWith('@')).toSet();
    expect(keys, en.keys.where((key) => !key.startsWith('@')).toSet());
    for (final key in keys) {
      final placeholders = RegExp(r'{(\w+)}');
      expect(
        placeholders.allMatches(ru[key] as String).map((m) => m[1]).toSet(),
        placeholders.allMatches(en[key] as String).map((m) => m[1]).toSet(),
        reason: key,
      );
    }
  });
}
