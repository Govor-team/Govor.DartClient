import 'api_client.dart';
import 'api_pagination.dart';
import 'models.dart';

abstract interface class ReactionRepository {
  Future<List<Json>> packs({bool mine = true});
  Future<Json> shared(String code);
  Future<void> subscribe(String id, bool subscribe);
  Future<Json> policy(String groupId);
  Future<Json> definition(String id);
  Future<Json> updatePolicy(String groupId, Json policy);
}

class ApiReactionRepository implements ReactionRepository {
  ApiReactionRepository(this.api);
  final ApiClient api;
  @override
  Future<List<Json>> packs({bool mine = true}) => loadApiPages(
    api,
    mine ? '/api/reaction-packs/mine' : '/api/reaction-packs',
  );
  @override
  Future<Json> shared(String code) async {
    final cleaned = code.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(cleaned)) {
      throw const ApiFailure(0, 'Неверный код пака.');
    }
    return object(
      await api.request('GET', '/api/reaction-packs/shared/$cleaned'),
    );
  }

  @override
  Future<void> subscribe(String id, bool subscribe) async {
    await api.request(
      subscribe ? 'PUT' : 'DELETE',
      '/api/reaction-packs/$id/subscription',
    );
  }

  @override
  Future<Json> policy(String groupId) async =>
      object(await api.request('GET', '/api/groups/$groupId/reactions'));
  @override
  Future<Json> definition(String id) async =>
      object(await api.request('GET', '/api/reactions/$id'));
  @override
  Future<Json> updatePolicy(String groupId, Json policy) async => object(
    await api.request('PUT', '/api/groups/$groupId/reactions', body: policy),
  );
}
