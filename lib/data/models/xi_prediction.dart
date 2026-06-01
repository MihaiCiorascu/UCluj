class XiPlayer {
  final int playerId;
  final String shortName;
  final String role;
  final String roleGroup;
  // Official-position fields (see MatchPreviewPlayer for the convention).
  final String officialPosition;
  final int slotIndex;
  final String positionGroupFine;
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

  XiPredictionResponse({
    required this.myTeamId,
    this.opponentTeamId,
    required this.formation,
    required this.startingXI,
    required this.bench,
  });

  factory XiPredictionResponse.fromJson(Map<String, dynamic> json) {
    return XiPredictionResponse(
      myTeamId: json['myTeamId'] as int? ?? 0,
      opponentTeamId: json['opponentTeamId'] as int?,
      formation: json['formation'] as String? ?? '4-3-3',
      startingXI: (json['startingXI'] as List<dynamic>?)
              ?.map((e) => XiPlayer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      bench: (json['bench'] as List<dynamic>?)
              ?.map((e) => XiPlayer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
