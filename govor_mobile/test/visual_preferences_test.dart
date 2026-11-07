import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/app_dependencies.dart';
import 'package:govor_mobile/core/preferences_repository.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/features/settings/settings_cubit.dart';
import 'package:govor_mobile/ui/design.dart';

void main() {
  test('visual preferences persist together with font and language', () async {
    String? data;
    final repo = LocalPreferencesRepository(
      read: () async => data,
      write: (v) async => data = v,
    );
    await Future.wait([
      repo.saveGlassIntensity(.8),
      repo.saveSidebarWidth(92),
      repo.saveLanguage('en'),
      repo.saveFontSize(18),
    ]);
    final c = SettingsCubit(repo);
    addTearDown(c.close);
    await c.load();
    expect(c.state.glassIntensity, .8);
    expect(c.state.sidebarWidth, 92);
    expect(c.state.fontSize, 18);
    expect(c.state.language, 'en');
    await c.setSidebarWidth(-100, save: true);
    expect(await repo.loadSidebarWidth(), 92);
  });
  testWidgets('all glass panels react to shared intensity', (tester) async {
    Future<void> show(double value) => tester.pumpWidget(
      MaterialApp(
        home: GlassStyle(
          intensity: value,
          child: const Row(
            children: [
              Glass(child: Text('one')),
              Glass(child: Text('two')),
            ],
          ),
        ),
      ),
    );
    await show(0);
    expect(
      tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).length,
      2,
    );
    final before = tester
        .widget<BackdropFilter>(find.byType(BackdropFilter).first)
        .filter
        .toString();
    await show(1);
    expect(
      tester
          .widget<BackdropFilter>(find.byType(BackdropFilter).first)
          .filter
          .toString(),
      isNot(before),
    );
  });
  testWidgets('divider reaches avatar minimum and preserves gap', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.view.resetPhysicalSize());
    String? data;
    final c = MessengerController(
      store: MemorySecretStore(),
      dependencies: AppDependencies(
        preferences: LocalPreferencesRepository(
          read: () async => data,
          write: (v) async => data = v,
        ),
      ),
    );
    c.startDemo();
    addTearDown(c.dispose);
    await tester.pumpWidget(GovorApp(controller: c));
    await tester.pumpAndSettle();
    final divider = find.byKey(const Key('sidebar-divider'));
    expect(tester.getSize(divider).width, 12);
    await tester.drag(divider, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(c.settings.state.sidebarWidth, 92);
    expect(tester.takeException(), isNull);
    await tester.drag(divider, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(c.settings.state.sidebarWidth, greaterThan(92));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'contacts remain usable when resizing to portrait and changing tabs',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final c = MessengerController(store: MemorySecretStore())..startDemo();
      addTearDown(c.dispose);

      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Друзья и заявки'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Вставить ID из буфера'), findsOneWidget);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byTooltip('Вставить ID из буфера').hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sidebar-divider')), findsNothing);

      await tester.tap(find.text('Чаты'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 680);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Контакты'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Входящие'));
      await tester.pumpAndSettle();
      expect(find.text('Заявок пока нет'), findsOneWidget);
      expect(find.text('Чаты').hitTestable(), findsOneWidget);
    },
  );
}
