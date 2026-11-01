import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/user_profile_repository.dart';

@immutable
class UserProfileState {
  const UserProfileState({
    this.profile,
    this.loading = false,
    this.working = false,
    this.failed = false,
  });
  final UserProfileSnapshot? profile;
  final bool loading, working, failed;
}

class UserProfileCubit extends Cubit<UserProfileState> {
  UserProfileCubit(this.repository, this.userId)
    : super(const UserProfileState());
  final UserProfileRepository repository;
  final String userId;
  int _generation = 0;
  Future<void> load() async {
    if (state.working || isClosed) return;
    final generation = ++_generation;
    emit(UserProfileState(profile: state.profile, loading: true));
    try {
      final profile = await repository.load(userId);
      if (!isClosed && generation == _generation) {
        emit(UserProfileState(profile: profile));
      }
    } catch (_) {
      if (!isClosed && generation == _generation) {
        emit(UserProfileState(profile: state.profile, failed: true));
      }
    }
  }

  Future<void> send() async {
    if (isClosed ||
        state.working ||
        state.loading ||
        ![
          Relationship.stranger,
          Relationship.rejected,
        ].contains(state.profile?.relationship)) {
      return;
    }
    await _mutate(
      () => repository.send(userId),
      acknowledged: Relationship.outgoing,
    );
  }

  Future<void> respond(bool accept) async {
    if (isClosed ||
        state.working ||
        state.loading ||
        state.profile?.relationship != Relationship.incoming ||
        state.profile?.requestId == null) {
      return;
    }
    await _mutate(
      () => repository.respond(state.profile!.requestId!, accept: accept),
      acknowledged: accept ? Relationship.friend : Relationship.rejected,
    );
  }

  Future<void> removeFriend() async {
    if (isClosed ||
        state.working ||
        state.loading ||
        state.profile?.relationship != Relationship.friend) {
      return;
    }
    await _mutate(
      () => repository.removeFriend(userId),
      acknowledged: Relationship.rejected,
    );
  }

  Future<void> block(bool blocked) async {
    final p = state.profile;
    if (isClosed ||
        state.working ||
        state.loading ||
        p == null ||
        p.relationship == Relationship.self ||
        blocked && p.relationship == Relationship.blocked ||
        !blocked &&
            (p.relationship != Relationship.blocked || !p.blockedByMe)) {
      return;
    }
    await _mutate(
      () => repository.block(userId, blocked: blocked),
      acknowledged: blocked ? Relationship.blocked : Relationship.rejected,
      blockedByMe: blocked,
    );
  }

  Future<void> _mutate(
    Future<void> Function() action, {
    required Relationship acknowledged,
    bool blockedByMe = false,
  }) async {
    final profile = state.profile!;
    final generation = ++_generation;
    emit(UserProfileState(profile: profile, working: true));
    try {
      await action();
      if (isClosed || generation != _generation) return;
      // Never offer a duplicate SendRequest after its acknowledgement, even when refresh fails.
      emit(
        UserProfileState(
          profile: UserProfileSnapshot(
            person: profile.person,
            relationship: acknowledged,
            blockedByMe: blockedByMe,
          ),
          working: true,
        ),
      );
      final fresh = await repository.load(userId);
      if (!isClosed && generation == _generation) {
        emit(UserProfileState(profile: fresh));
      }
    } catch (_) {
      if (!isClosed && generation == _generation) {
        emit(UserProfileState(profile: state.profile, failed: true));
      }
    }
  }
}
