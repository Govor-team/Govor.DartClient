import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/api_client.dart';
import '../../core/wallpapers.dart';

class AppearanceCubit extends Cubit<WallpaperSettings> {
  AppearanceCubit(this.repository)
    : super(const WallpaperSettings(selected: defaultWallpaper));
  final WallpaperRepository repository;
  static const defaultWallpaper = 'assets/backgrounds/background_girls.jpg';
  static const wallpapers = [
    'assets/backgrounds/background_flag.png',
    defaultWallpaper,
    'assets/backgrounds/vedu_theme.png',
    'assets/backgrounds/rod_theme.png',
    'assets/backgrounds/aria_theme.png',
  ];
  Future<void> _queue = Future.value();
  Future<void> _serialize(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  bool _available(String? id, List<CustomWallpaper> custom) =>
      wallpapers.contains(id) || custom.any((e) => e.id == id);
  Future<void> load() => _serialize(() async {
    final value = await repository.load();
    if (value != null && !isClosed) {
      emit(
        WallpaperSettings(
          selected: _available(value.selected, value.custom)
              ? value.selected
              : null,
          dark: value.dark,
          custom: List.unmodifiable(value.custom),
        ),
      );
    }
  });
  Future<void> update({
    String? background,
    bool? dark,
    bool useGradient = false,
  }) => _serialize(() async {
    final next = WallpaperSettings(
      selected: useGradient
          ? null
          : background != null && _available(background, state.custom)
          ? background
          : state.selected,
      dark: dark ?? state.dark,
      custom: state.custom,
    );
    await repository.save(next);
    if (!isClosed) emit(next);
  });
  Future<void> migrate(Map<String, dynamic> legacy) => _serialize(() async {
    final next = WallpaperSettings(
      selected: wallpapers.contains(legacy['background'])
          ? legacy['background'] as String
          : null,
      dark: legacy['dark'] != false,
      custom: state.custom,
    );
    await repository.save(next);
    if (!isClosed) emit(next);
  });
  Future<void> add(Uint8List bytes, String name) => _serialize(() async {
    final item = await WallpaperRepository.validate(bytes, name);
    final custom = [...state.custom];
    if (!custom.any((e) => e.id == item.id)) {
      if (custom.length >= WallpaperRepository.maxCount) {
        throw const ApiFailure(
          0,
          'Можно сохранить до 6 своих фонов. Удалите ненужный фон.',
        );
      }
      custom.add(item);
    }
    final next = WallpaperSettings(
      selected: item.id,
      dark: state.dark,
      custom: List.unmodifiable(custom),
    );
    await repository.save(next);
    if (!isClosed) emit(next);
  });
  Future<void> remove(String id) => _serialize(() async {
    final next = WallpaperSettings(
      selected: state.selected == id ? defaultWallpaper : state.selected,
      dark: state.dark,
      custom: List.unmodifiable(state.custom.where((e) => e.id != id)),
    );
    await repository.save(next);
    if (!isClosed) emit(next);
  });
  @override
  Future<void> close() async {
    await _queue;
    return super.close();
  }
}
