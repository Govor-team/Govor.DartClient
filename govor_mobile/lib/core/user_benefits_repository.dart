import 'api_client.dart';
import 'crypto/primitives.dart';
import 'models.dart';
import 'user_benefits.dart';

class UserBenefitsRepository {
  UserBenefitsRepository(this.api);
  final ApiClient api;
  void _id(String id) {
    if (!validId(id)) throw const ApiFailure(400, 'Неверный ID пользователя.');
  }

  Future<UserBenefits> load(String id) async {
    _id(id);
    return UserBenefits.fromJson(
      object(await api.request('GET', '/api/profile/$id/benefits')),
    );
  }

  Future<UserBenefits> saveTag(ProfileTag? tag) async => UserBenefits.fromJson(
    object(
      await api.request(
        tag == null ? 'DELETE' : 'PUT',
        '/api/profile/tag',
        body: tag?.json,
      ),
    ),
  );
  Future<UserBenefits> setPrivileges(String id, int privileges) async {
    _id(id);
    if (privileges < 0 || privileges > 3) {
      throw const ApiFailure(400, 'Неверные привилегии.');
    }
    return UserBenefits.fromJson(
      object(
        await api.request(
          'PUT',
          '/api/admin/users/$id/privileges',
          body: {'privileges': privileges},
        ),
      ),
    );
  }
}
