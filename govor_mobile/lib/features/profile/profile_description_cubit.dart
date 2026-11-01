import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@immutable
class ProfileDescriptionState {
  const ProfileDescriptionState({
    required this.draft,
    required this.saved,
    this.saving = false,
    this.error,
  });
  final String draft, saved;
  final bool saving;
  final String? error;
}

/// Owns debounce, retry and serialization independently of the widget lifecycle.
class ProfileDescriptionCubit extends Cubit<ProfileDescriptionState> {
  ProfileDescriptionCubit({
    required String saved,
    String? draft,
    required this.save,
    required this.onDraft,
    required this.errorText,
    this.debounce = const Duration(milliseconds: 800),
  }) : super(ProfileDescriptionState(draft: draft ?? saved, saved: saved)) {
    if (state.draft != state.saved) _schedule();
  }
  final Future<void> Function(String) save;
  final void Function(String?) onDraft;
  final String Function(Object) errorText;
  final Duration debounce;
  Timer? _timer;
  Future<void>? _saving;
  void changed(String value) {
    if (isClosed) return;
    onDraft(value);
    emit(
      ProfileDescriptionState(
        draft: value,
        saved: state.saved,
        saving: state.saving,
        error: state.error,
      ),
    );
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    return _saving ??= _flush().whenComplete(() => _saving = null);
  }

  Future<void> _flush() async {
    if (isClosed || state.draft == state.saved) return;
    emit(
      ProfileDescriptionState(
        draft: state.draft,
        saved: state.saved,
        saving: true,
      ),
    );
    try {
      while (!isClosed && state.draft != state.saved) {
        final value = state.draft;
        await save(value);
        if (isClosed) return;
        emit(
          ProfileDescriptionState(
            draft: state.draft,
            saved: value,
            saving: true,
          ),
        );
      }
      onDraft(null);
      if (!isClosed) {
        emit(ProfileDescriptionState(draft: state.draft, saved: state.saved));
      }
    } catch (e) {
      if (!isClosed) {
        emit(
          ProfileDescriptionState(
            draft: state.draft,
            saved: state.saved,
            error: errorText(e),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await flush();
    return super.close();
  }
}
