import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/preferences_repository.dart';

enum SettingsSection { appearance, security, reactions }

@immutable
class SettingsState {
  const SettingsState({
    this.language = 'ru',
    this.section = SettingsSection.appearance,
    this.saving = false,
    this.failed = false,
    this.fontSize = 14,
    this.glassIntensity = .5,
    this.sidebarWidth = 330,
    this.visualFailed = false,
    this.fontSaving = false,
    this.fontFailed = false,
  });
  final String? language;
  Locale? get locale => language == null ? null : Locale(language!);
  final SettingsSection section;
  final bool saving, failed, fontSaving, fontFailed;
  final double fontSize, glassIntensity, sidebarWidth;
  final bool visualFailed;
  SettingsState copy({
    String? language,
    bool replaceLanguage = false,
    SettingsSection? section,
    bool? saving,
    bool? failed,
    double? fontSize,
    double? glassIntensity,
    double? sidebarWidth,
    bool? visualFailed,
    bool? fontSaving,
    bool? fontFailed,
  }) => SettingsState(
    language: replaceLanguage ? language : this.language,
    section: section ?? this.section,
    saving: saving ?? this.saving,
    failed: failed ?? this.failed,
    fontSize: fontSize ?? this.fontSize,
    glassIntensity: glassIntensity ?? this.glassIntensity,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    visualFailed: visualFailed ?? this.visualFailed,
    fontSaving: fontSaving ?? this.fontSaving,
    fontFailed: fontFailed ?? this.fontFailed,
  );
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this.repository) : super(const SettingsState());
  final PreferencesRepository repository;
  int _revision = 0, _fontRevision = 0;
  double _savedFontSize = 14;
  static const minFontSize = 12.0, maxFontSize = 24.0, defaultFontSize = 14.0;
  bool _validSize(double size) =>
      size.isFinite && size >= minFontSize && size <= maxFontSize;
  Future<void> load() async {
    final revision = _revision;
    try {
      final language = await repository.loadLanguage();
      final fontSize = await repository.loadFontSize();
      final visual = repository;
      final glass = visual is VisualPreferencesRepository
          ? await (visual as VisualPreferencesRepository).loadGlassIntensity()
          : .5;
      final width = visual is VisualPreferencesRepository
          ? await (visual as VisualPreferencesRepository).loadSidebarWidth()
          : 330.0;
      if (!isClosed && revision == _revision) {
        _savedFontSize = fontSize;
        emit(
          state.copy(
            language: language,
            replaceLanguage: true,
            fontSize: fontSize,
            glassIntensity: glass,
            sidebarWidth: width,
          ),
        );
      }
    } catch (_) {
      /* A local preference must not prevent sign-in. */
    }
  }

  void select(SettingsSection section) => emit(state.copy(section: section));
  Future<void> setLanguage(String? code) async {
    if (state.saving || (code != null && code != 'ru' && code != 'en')) return;
    _revision++;
    emit(state.copy(saving: true, failed: false));
    try {
      await repository.saveLanguage(code);
      if (!isClosed) {
        emit(state.copy(language: code, replaceLanguage: true, saving: false));
      }
    } catch (_) {
      if (!isClosed) emit(state.copy(saving: false, failed: true));
    }
  }

  void previewFontSize(double size) {
    if (isClosed || !_validSize(size)) return;
    _revision++;
    emit(state.copy(fontSize: size, fontFailed: false));
  }

  Future<void> setFontSize(double size) async {
    if (isClosed || !_validSize(size)) return;
    _revision++;
    final revision = ++_fontRevision;
    emit(state.copy(fontSize: size, fontSaving: true, fontFailed: false));
    try {
      await repository.saveFontSize(size);
      _savedFontSize = size;
      if (!isClosed && revision == _fontRevision) {
        emit(state.copy(fontSaving: false));
      }
    } catch (_) {
      if (!isClosed && revision == _fontRevision) {
        emit(
          state.copy(
            fontSaving: false,
            fontFailed: true,
            fontSize: state.fontSize == size ? _savedFontSize : state.fontSize,
          ),
        );
      }
    }
  }

  void previewGlass(double value) {
    if (!value.isFinite || isClosed) return;
    _revision++;
    emit(state.copy(glassIntensity: value.clamp(0, 1), visualFailed: false));
  }

  Future<void> saveGlass(double value) async {
    previewGlass(value);
    final visual = repository;
    try {
      if (visual is VisualPreferencesRepository) {
        await (visual as VisualPreferencesRepository).saveGlassIntensity(
          state.glassIntensity,
        );
      }
    } catch (_) {
      if (!isClosed) emit(state.copy(visualFailed: true));
    }
  }

  Future<void> setSidebarWidth(double value, {bool save = false}) async {
    if (!value.isFinite || isClosed) return;
    _revision++;
    emit(state.copy(sidebarWidth: value.clamp(92, 600)));
    final visual = repository;
    try {
      if (save && visual is VisualPreferencesRepository) {
        await (visual as VisualPreferencesRepository).saveSidebarWidth(
          state.sidebarWidth,
        );
      }
    } catch (_) {
      if (!isClosed) emit(state.copy(visualFailed: true));
    }
  }
}
