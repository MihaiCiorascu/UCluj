class XiPlayer {
  final int playerId;
  final String shortName;
  final String role;
  final String roleGroup;
  // Official-position fields (see MatchPreviewPlayer for the convention).
  final String officialPosition;
  final int slotIndex;
  final String positionGroupFine;
  // See MatchPreviewPlayer for the convention. rating is the honest
  // within-position league percentile rating; statPct holds per-KPI
  // within-position percentiles; photoUrl is the self-hosted headshot.
  final int rating;
  final String positionNorm;
  final Map<String, double> statPct;
  final String photoUrl;
  final double predictedScore;
  final double performanceScore;
  final double recentFormScore;
  final int totalMinutes;
  final int matchesPlayed;

  XiPlayer({
    required this.playerId,
    required this.shortName,
    required this.role,
    required this.roleGroup,
    this.officialPosition = '',
    this.slotIndex = -1,
    this.positionGroupFine = '',
    this.rating = 0,
    this.positionNorm = 'COARSE',
    this.statPct = const {},
    this.photoUrl = '',
    required this.predictedScore,
    required this.performanceScore,
    required this.recentFormScore,
    required this.totalMinutes,
    required this.matchesPlayed,
  });

  factory XiPlayer.fromJson(Map<String, dynamic> json) {
    return XiPlayer(
      playerId: json['playerId'] as int? ?? 0,
      shortName: json['shortName'] as String? ?? 'Unknown',
      role: json['role'] as String? ?? '',
      roleGroup: json['role_group'] as String? ?? '',
      officialPosition: json['official_position'] as String? ?? '',
      slotIndex: (json['slot_index'] as num?)?.toInt() ?? -1,
      positionGroupFine: json['position_group_fine'] as String? ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      positionNorm: json['position_norm'] as String? ?? 'COARSE',
      statPct: {
        for (final e in json.entries)
          if (e.key.endsWith('_pct'))
            e.key.substring(0, e.key.length - 4): (e.value as num?)?.toDouble() ?? 0,
      },
      photoUrl: json['photo_url'] as String? ?? '',
      predictedScore: (json['predicted_score'] as num?)?.toDouble() ?? 0.0,
      performanceScore: (json['performance_score'] as num?)?.toDouble() ?? 0.0,
      recentFormScore: (json['recent_form_score'] as num?)?.toDouble() ?? 0.0,
      totalMinutes: json['total_minutes'] as int? ?? 0,
      matchesPlayed: json['matches_played'] as int? ?? 0,
    );
  }
}

class XiPredictionResponse {
  final int myTeamId;
  final int? opponentTeamId;
  final String formation;
  final List<XiPlayer> startingXI;
  final List<XiPlayer> bench;
  // The 'ideal' eleven by pure within-position rating, alongside the predicted
  // lineup, for the best-XI toggle. Empty on older backends.
  final List<XiPlayer> bestXI;
  final List<XiPlayer> bestBench;

  XiPredictionResponse({
    required this.myTeamId,
    this.opponentTeamId,
    required this.formation,
    required this.startingXI,
    required this.bench,
    this.bestXI = const [],
    this.bestBench = const [],
  });

  factory XiPredictionResponse.fromJson(Map<String, dynamic> json) {
    List<XiPlayer> parse(String key) =>
        (json[key] as List<dynamic>?)
            ?.map((e) => XiPlayer.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return XiPredictionResponse(
      myTeamId: json['myTeamId'] as int? ?? 0,
      opponentTeamId: json['opponentTeamId'] as int?,
      formation: json['formation'] as String? ?? '4-3-3',
      startingXI: parse('startingXI'),
      bench: parse('bench'),
      bestXI: parse('bestXI'),
      bestBench: parse('bestBench'),
    );
  }
}
