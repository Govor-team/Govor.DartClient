import 'api_client.dart';
import 'chat_hub.dart';
import 'models.dart';
import 'crypto/primitives.dart';

enum Relationship {
  self,
  stranger,
  incoming,
  outgoing,
  friend,
  rejected,
  blocked,
}

class UserProfileSnapshot {
  const UserProfileSnapshot({
    required this.person,
    required this.relationship,
    this.requestId,
    this.blockedByMe = false,
  });
  final Person person;
  final Relationship relationship;
  final String? requestId;
  final bool blockedByMe;
}

Relationship relationshipFor(
  String me,
  String user,
  List<Person> friends,
  List<Json> incoming,
  List<Json> outgoing,
) {
  if (user == me) return Relationship.self;
  final received = incoming
      .where((r) => r['requesterId'] == user && r['addresseeId'] == me)
      .firstOrNull;
  final sent = outgoing
      .where((r) => r['requesterId'] == me && r['addresseeId'] == user)
      .firstOrNull;
  final row = received ?? sent;
  if (received?['status'] == 3 || sent?['status'] == 3) {
    return Relationship.blocked;
  }
  if (friends.any((p) => p.id == user)) return Relationship.friend;
  if (row == null) return Relationship.stranger;
  return switch (row['status']) {
    0 => received != null ? Relationship.incoming : Relationship.outgoing,
    1 => Relationship.friend,
    2 => Relationship.rejected,
    3 => Relationship.blocked,
    _ => Relationship.blocked,
  };
}

abstract interface class UserProfileRepository {
  Future<UserProfileSnapshot> load(String id);
  Future<void> send(String id);
  Future<void> removeFriend(String id);
  Future<void> block(String id, {required bool blocked});
  Future<void> respond(String requestId, {required bool accept});
}

class ApiUserProfileRepository implements UserProfileRepository {
  ApiUserProfileRepository(this.api, this.friendsHub, this.currentUser);
  final ApiClient api;
  final ChatHub friendsHub;
  final String currentUser;
  @override
  Future<UserProfileSnapshot> load(String id) async {
    final data = await Future.wait([
      api.request('GET', '/api/profile/download/$id'),
      api.request('GET', '/api/friends'),
      api.request('GET', '/api/friends/requests'),
      api.request('GET', '/api/friends/responses'),
    ]);
    final person = Person.fromJson(object(data[0]));
    final incoming = objects(data[2]), outgoing = objects(data[3]);
    final relation = relationshipFor(
      currentUser,
      id,
      objects(data[1]).map(Person.fromJson).toList(),
      incoming,
      outgoing,
    );
    final request = [...incoming, ...outgoing]
        .where(
          (r) =>
              (r['requesterId'] == id && r['addresseeId'] == currentUser) ||
              (r['addresseeId'] == id && r['requesterId'] == currentUser),
        )
        .firstOrNull;
    return UserProfileSnapshot(
      person: person,
      relationship: relation,
      requestId: request?['id'] as String?,
      blockedByMe:
          relation == Relationship.blocked &&
          request?['requesterId'] == currentUser,
    );
  }

  void _target(String id) {
    if (!validId(id) || id == currentUser) {
      throw const ApiFailure(400, 'Неверный пользователь.');
    }
  }

  @override
  Future<void> removeFriend(String id) async {
    _target(id);
    await api.request('DELETE', '/api/friends/$id');
  }

  @override
  Future<void> block(String id, {required bool blocked}) async {
    _target(id);
    await api.request(blocked ? 'PUT' : 'DELETE', '/api/friends/$id/block');
  }

  @override
  Future<void> send(String id) async {
    await friendsHub.invoke('SendRequest', [id]);
  }

  @override
  Future<void> respond(String requestId, {required bool accept}) async {
    await friendsHub.invoke(accept ? 'AcceptRequest' : 'RejectRequest', [
      requestId,
    ]);
  }
}

/// Same legal transitions, backed by the existing in-memory demo session.
class DemoUserProfileRepository implements UserProfileRepository {
  DemoUserProfileRepository({
    required this.snapshot,
    required this.sendRequest,
    required this.respondRequest,
    this.remove,
    this.setBlocked,
  });
  final Future<UserProfileSnapshot> Function(String) snapshot;
  final Future<void> Function(String) sendRequest;
  final Future<void> Function(String, bool) respondRequest;
  final Future<void> Function(String)? remove;
  final Future<void> Function(String, bool)? setBlocked;
  @override
  Future<void> removeFriend(String id) async => remove?.call(id);
  @override
  Future<void> block(String id, {required bool blocked}) async =>
      setBlocked?.call(id, blocked);
  @override
  Future<UserProfileSnapshot> load(String id) => snapshot(id);
  @override
  Future<void> send(String id) => sendRequest(id);
  @override
  Future<void> respond(String id, {required bool accept}) =>
      respondRequest(id, accept);
}
