import '../../core/services/api_client.dart';
import '../models/week_fixture.dart';

class WeekRepository {
  WeekRepository({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// Fetch every fixture of one Superliga round.
  ///
  /// For the live 2025-26 season the backend reinterprets the `week_offset`
  /// query parameter as a ROUND offset relative to the current round (0 = the
  /// current round, -1 = previous, +1 = next, clamped to [1, 33]), and returns
  /// all fixtures of that resolved round (mid-week and weekend alike). The
  /// query name stays `week_offset` for backward compatibility even though the
  /// semantics are now round-based. [roundOffset] is forwarded verbatim.
  Future<List<WeekFixture>> fetchWeekFixtures({int roundOffset = 0}) async {
    final list = await _api.getList('/week-fixtures?week_offset=$roundOffset');
    return list
        .cast<Map<String, dynamic>>()
        .map(WeekFixture.fromJson)
        .toList();
  }
}
