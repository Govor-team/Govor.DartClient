import 'api_client.dart';
import 'models.dart';

/// Read each page until exhaustion; preserve order and deduplicate stable IDs.
Future<List<Json>> loadApiPages(
  ApiClient api,
  String path, {
  Map<String, String> query = const {},
}) async {
  final result = <Json>[];
  final seen = <Object>{};
  for (var skip = 0; ; skip += 100) {
    final page = objects(
      await api.request(
        'GET',
        path,
        query: {...query, 'skip': '$skip', 'take': '100'},
      ),
    );
    for (final item in page) {
      final id = item['id'] ?? item['userId'];
      if (id == null || seen.add(id)) result.add(item);
    }
    if (page.length < 100) return result;
    if (skip >= 100000) {
      throw const ApiFailure(0, 'Список слишком большой. Уточните поиск.');
    }
  }
}
