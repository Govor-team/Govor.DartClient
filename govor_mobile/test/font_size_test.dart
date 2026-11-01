import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/app_dependencies.dart';
import 'package:govor_mobile/core/preferences_repository.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/features/settings/settings_cubit.dart';
import 'package:govor_mobile/ui/font_size_selector.dart';
import 'package:govor_mobile/ui/text_scale.dart';

void main() {
  test(
    'font size and language persist together across concurrent updates',
    () async {
      String? data;
      final repo = LocalPreferencesRepository(
        read: () async => data,
        write: (v) async => data = v,
      );
      await Future.wait([repo.saveFontSize(20), repo.saveLanguage('en')]);
      final restored = SettingsCubit(repo);
      addTearDown(restored.close);
      await restored.load();
      expect(restored.state.fontSize, 20);
      expect(restored.state.language, 'en');
      await restored.setLanguage(null);
      expect(await repo.loadFontSize(), 20);
      expect(jsonDecode(data!)['language'], isNull);
    },
  );
  test(
    'invalid stored sizes fall back to default and malformed preferences can be repaired',
    () async {
      String? data;
      final repo = LocalPreferencesRepository(
        read: () async => data,
        write: (v) async => data = v,
      );
      for (final value in ['huge', -1, 0, 25, 10000, null]) {
        data = jsonEncode({'fontSize': value});
        expect(await repo.loadFontSize(), 14);
      }
      data = '{broken';
      await repo.saveFontSize(18);
      expect(await repo.loadFontSize(), 18);
      await expectLater(repo.saveFontSize(double.nan), throwsArgumentError);
      await expectLater(repo.saveFontSize(100), throwsArgumentError);
    },
  );
  test(
    'preview does not write; failed commit restores the last saved size and can retry',
    () async {
      var writes = 0, fails = false;
      String? data;
      final cubit = SettingsCubit(
        LocalPreferencesRepository(
          read: () async => data,
          write: (v) async {
            writes++;
            if (fails) throw StateError('disk');
            data = v;
          },
        ),
      );
      addTearDown(cubit.close);
      cubit.previewFontSize(24);
      expect(cubit.state.fontSize, 24);
      expect(writes, 0);
      await cubit.setFontSize(20);
      fails = true;
      await cubit.setFontSize(22);
      expect(cubit.state.fontSize, 20);
      expect(cubit.state.fontFailed, isTrue);
      fails = false;
      await cubit.setFontSize(22);
      expect(cubit.state.fontSize, 22);
      expect(cubit.state.fontFailed, isFalse);
      cubit.previewFontSize(double.infinity);
      expect(cubit.state.fontSize, 22);
    },
  );
  test(
    'overlapping commits preserve the newest choice and the selected language',
    () async {
      String? data;
      final gates = <Completer<void>>[];
      final repo = LocalPreferencesRepository(
        read: () async => data,
        write: (v) async {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
          data = v;
        },
      );
      final c = SettingsCubit(repo);
      addTearDown(c.close);
      final first = c.setFontSize(18),
          second = c.setFontSize(24),
          language = c.setLanguage('en');
      await Future<void>.delayed(Duration.zero);
      expect(gates, hasLength(1));
      for (var i = 0; i < 3; i++) {
        gates[i].complete();
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait([first, second, language]);
      expect(c.state.fontSize, 24);
      expect(c.state.language, 'en');
      expect(await repo.loadFontSize(), 24);
    },
  );
  testWidgets(
    'slider previews immediately, commits and resets to the default',
    (tester) async {
      String? data;
      final c = SettingsCubit(
        LocalPreferencesRepository(
          read: () async => data,
          write: (v) async => data = v,
        ),
      );
      addTearDown(c.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FontSizeSelector(settings: c)),
        ),
      );
      final slider = tester.widget<Slider>(
        find.byKey(const Key('font-size-slider')),
      );
      slider.onChanged!(22);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byKey(const Key('font-size-slider'))).value,
        22,
      );
      expect(data, isNull);
      tester
          .widget<Slider>(find.byKey(const Key('font-size-slider')))
          .onChangeEnd!(22);
      await tester.pumpAndSettle();
      expect(jsonDecode(data!)['fontSize'], 22);
      await tester.tap(find.byKey(const Key('reset-font-size')));
      await tester.pumpAndSettle();
      expect(c.state.fontSize, 14);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'maximum font size changes chat text and composer without losing the draft',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MessengerController(
        store: MemorySecretStore(),
        dependencies: AppDependencies(
          preferences: LocalPreferencesRepository(
            read: () async => null,
            write: (_) async {},
          ),
        ),
      )..startDemo();
      addTearDown(c.dispose);
      await c.open(c.conversations.first);
      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('message-composer')),
        'Draft survives',
      );
      await c.settings.setFontSize(24);
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('message-composer'));
      final style = tester.widget<TextField>(composer).style!;
      expect(
        MediaQuery.textScalerOf(
          tester.element(composer),
        ).scale(style.fontSize!),
        24,
      );
      for (final element in find.byType(SelectableText).evaluate()) {
        final text = element.widget as SelectableText;
        expect(
          MediaQuery.textScalerOf(element).scale(text.style!.fontSize!),
          24,
        );
      }
      expect(find.text('Draft survives'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('user scaling composes with nonlinear accessibility scaling', () {
    const scaler = GovorTextScaler(_NonlinearScaler(), 24 / 14);
    expect(scaler.scale(14), const _NonlinearScaler().scale(24));
    expect(scaler.scale(22), const _NonlinearScaler().scale(22 * 24 / 14));
  });

  testWidgets(
    'settings stay compact and all explicit labels and menus obey the font preference',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 940);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MessengerController(
        store: MemorySecretStore(),
        dependencies: AppDependencies(
          preferences: LocalPreferencesRepository(
            read: () async => null,
            write: (_) async {},
          ),
        ),
      )..startDemo();
      addTearDown(c.dispose);
      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(FontSizeSelector)).height,
        lessThan(115),
      );
      final language = find.byKey(const Key('language-selector'));
      await tester.ensureVisible(language);
      expect(tester.getSize(language).height, lessThan(75));
      final title = find.text('Язык интерфейса');
      final before = tester.getSize(title).height;
      c.settings.previewFontSize(24);
      await tester.pumpAndSettle();
      await tester.ensureVisible(title);
      expect(tester.getSize(title).height, greaterThan(before * 1.5));
      for (final text in ['Язык интерфейса', 'Размер текста', 'Оформление']) {
        expect(
          MediaQuery.textScalerOf(tester.element(find.text(text))).scale(14),
          24,
        );
      }
      await tester.tap(language);
      await tester.pumpAndSettle();
      final english = find.text('English');
      expect(MediaQuery.textScalerOf(tester.element(english)).scale(14), 24);
      expect(tester.takeException(), isNull);
      await tester.tap(english);
      await tester.pumpAndSettle();
      for (final size in [const Size(320, 740), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final scrollable = find
            .descendant(
              of: find.byKey(const Key('profile-mobile')),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('font-size-slider')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          language,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(language);
        await tester.pumpAndSettle();
        await tester.tap(language);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Selecting the current language also closes the menu.
        await tester.tap(find.text('English').last);
        await tester.pumpAndSettle();
      }
    },
  );
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.8 : fontSize * 1.3;
  @override
  double get textScaleFactor => 1.8;
}
