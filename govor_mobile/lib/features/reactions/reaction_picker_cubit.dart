import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/models.dart';

@immutable
class ReactionPickerState {
  ReactionPickerState({
    List<Json> packs = const [],
    this.pack = 0,
    this.query = '',
    this.expanded = false,
    this.loading = false,
    this.failed = false,
    this.sending = false,
    this.applyFailed = false,
  }) : packs = List.unmodifiable(packs);
  final List<Json> packs;
  final int pack;
  final String query;
  final bool expanded, loading, failed, sending, applyFailed;
  List<Json> get reactions => packs.isEmpty
      ? []
      : (query.trim().isEmpty
                ? objects(packs[pack]['reactions'])
                : packs.expand((p) => objects(p['reactions'])))
            .where(
              (r) =>
                  r['isEnabled'] != false &&
                  '${r['name']} ${r['emoji']} ${r['code']}'
                      .toLowerCase()
                      .contains(query.toLowerCase().trim()),
            )
            .toList();
  ReactionPickerState copy({
    List<Json>? packs,
    int? pack,
    String? query,
    bool? expanded,
    bool? loading,
    bool? failed,
    bool? sending,
    bool? applyFailed,
  }) => ReactionPickerState(
    packs: packs ?? this.packs,
    pack: pack ?? this.pack,
    query: query ?? this.query,
    expanded: expanded ?? this.expanded,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    sending: sending ?? this.sending,
    applyFailed: applyFailed ?? this.applyFailed,
  );
}

class ReactionPickerCubit extends Cubit<ReactionPickerState> {
  ReactionPickerCubit({required this.loadPacks, required this.applyReaction})
    : super(ReactionPickerState());
  final Future<List<Json>> Function() loadPacks;
  final Future<void> Function(String) applyReaction;
  Future<void> load() async {
    if (state.loading) return;
    emit(state.copy(loading: true, failed: false, applyFailed: false));
    try {
      final packs = await loadPacks();
      if (!isClosed) emit(state.copy(packs: packs, pack: 0, loading: false));
    } catch (_) {
      if (!isClosed) emit(state.copy(loading: false, failed: true));
    }
  }

  void expand() => emit(state.copy(expanded: !state.expanded));
  void search(String query) => emit(state.copy(query: query));
  void selectPack(int index) {
    if (index >= 0 && index < state.packs.length) emit(state.copy(pack: index));
  }

  Future<bool> react(String id) async {
    if (state.sending) return false;
    emit(state.copy(sending: true, applyFailed: false));
    try {
      await applyReaction(id);
      if (isClosed) return false;
      emit(state.copy(sending: false));
      return true;
    } catch (_) {
      if (!isClosed) emit(state.copy(sending: false, applyFailed: true));
      return false;
    }
  }
}
