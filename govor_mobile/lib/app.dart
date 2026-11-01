import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'l10n/l10n.dart';
import 'features/settings/settings_cubit.dart';
import 'core/app_dependencies.dart';

import 'package:flutter/material.dart';

import 'features/messenger_controller.dart';
import 'core/server_ip_provider.dart';
import 'ui/auth_screen.dart';
import 'ui/design.dart';
import 'ui/text_scale.dart';
import 'ui/messenger_screen.dart';

class GovorApp extends StatefulWidget {
  const GovorApp({
    super.key,
    this.controller,
    this.serverProvider,
    this.dependencies,
  });
  final MessengerController? controller;
  final ServerIpProvider? serverProvider;
  final AppDependencies? dependencies;
  @override
  State<GovorApp> createState() => _GovorAppState();
}

class _GovorAppState extends State<GovorApp> with WidgetsBindingObserver {
  late final controller =
      widget.controller ??
      MessengerController(
        dependencies: widget.dependencies,
        serverProvider: widget.serverProvider ?? const ServerIpProvider(),
      );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null) unawaited(controller.boot());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        controller.ready &&
        !controller.demo) {
      unawaited(controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepositoryProvider<AppDependencies>.value(
        value: controller.dependencies,
        child: BlocBuilder<SettingsCubit, SettingsState>(
          bloc: controller.settings,
          builder: (context, settings) => AnimatedBuilder(
            animation: controller,
            builder: (context, _) => MaterialApp(
              onGenerateTitle: (context) => context.l10n.govor,
              locale: controller.ready ? settings.locale : null,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              debugShowCheckedModeBanner: false,
              theme: govorTheme(Brightness.light),
              darkTheme: govorTheme(Brightness.dark),
              themeMode: controller.darkTheme
                  ? ThemeMode.dark
                  : ThemeMode.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: GovorTextScaler(
                    MediaQuery.textScalerOf(context),
                    settings.fontSize / SettingsCubit.defaultFontSize,
                  ),
                ),
                child: child!,
              ),
              home: LiquidBackground(
                wallpaper: controller.wallpaper,
                customWallpaper: controller.customWallpaperBytes,
                child: Scaffold(
                  body: controller.booting
                      ? const Center(child: CircularProgressIndicator())
                      : controller.ready
                      ? MessengerScreen(
                          controller: controller,
                          dark: controller.darkTheme,
                          onThemeChanged: (v) =>
                              controller.setAppearance(dark: v),
                        )
                      : AuthScreen(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
}
