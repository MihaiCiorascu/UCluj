import '../../core/services/api_client.dart';
import '../models/xi_prediction.dart';
import '../models/match_preview.dart';

class XiOpponentOption {
  XiOpponentOption({required this.id, required this.name});

  factory XiOpponentOption.fromJson(Map<String, dynamic> json) {
    return XiOpponentOption(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
    );
  }

  final int id;
  final String name;
}

/// The curated formation shapes the optimiser can resolve to, plus the "auto"
/// sentinel that asks the backend to score the pool once and pick the
/// highest-objective shape. These mirror ``CURATED_FORMATIONS`` on the backend;
/// any other value is silently treated as "auto" server-side.
const String kFormationAuto = 'auto';
const List<String> kCuratedFormations = [
  '4-3-3',
  '4-2-3-1',
  '4-4-2',
  '3-5-2',
  '3-4-3',
  '5-3-2',
  '4-1-4-1',
  '4-3-1-2',
  '3-4-2-1',
  '4-1-2-1-2',
  '4-4-1-1',
  '5-4-1',
  '3-1-4-2',
  '4-3-2-1',
  '3-4-1-2',
];

class XiRepository {
  final ApiClient _apiClient;

  XiRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<XiPredictionResponse> predictXi({
    required String formation,
    int? opponentTeamId,
  }) async {
    final response = await _apiClient.post(
      '/xi/predict',
      body: {
        'formation': formation,
        if (opponentTeamId != null) 'opponent_team_id': opponentTeamId,
      },
    );
    return XiPredictionResponse.fromJson(response);
  }

  Future<List<XiOpponentOption>> fetchOpponentOptions() async {
    final response = await _apiClient.getList('/xi/opponents');
    return response
        .map((item) => XiOpponentOption.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MatchPreviewResponse> fetchMatchPreview({
    required String opponentName,
    String formation = '4-3-3',
  }) async {
    final encoded = Uri.encodeComponent(opponentName);
    final response = await _apiClient
        .get('/xi/match-preview?opponent_name=$encoded&formation=$formation');
    return MatchPreviewResponse.fromJson(response);
  }

  /// Flexible-XI match preview via the POST contract: lets the caller pin
  /// players to slots ([locked]) and/or ask the optimiser to auto-pick the
  /// shape ([formation] == [kFormationAuto]). [locked] maps a 0-based slot
  /// index to a playerId; it is serialised as a JSON object whose keys are the
  /// stringified slot indices, exactly as the backend expects. Invalid locks
  /// (unknown player, out-of-range slot, duplicate) are ignored server-side.
  /// Returns the same response shape as [fetchMatchPreview]; render the pitch
  /// from the RESOLVED [MatchPreviewResponse.formation], never from [formation].
  Future<MatchPreviewResponse> postMatchPreview({
    required String opponentName,
    String formation = kFormationAuto,
    Map<int, int> locked = const {},
  }) async {
    final response = await _apiClient.post(
      '/xi/match-preview',
      body: {
        'opponent_name': opponentName,
        'formation': formation,
        'locked': {
          for (final e in locked.entries) e.key.toString(): e.value,
        },
      },
    );
    return MatchPreviewResponse.fromJson(response);
  }
}
