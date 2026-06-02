class MatchPreviewPlayer {
  final int playerId;
  final String shortName;
  final String role;
  final String roleGroup;
  // Official-position fields (thesis fine taxonomy + Hungarian slot assignment).
  // officialPosition is the slot label (RB, RCB, DM, RW, ST, ...), slotIndex is
  // the position on the pitch (0 = GK), and positionGroupFine is the player's
  // primary fine group (GK, CB, FB, WB, DM, CM, AM, W, WF, ST). All optional so
  // bench players and older payloads still parse.
  final String officialPosition;
  final int slotIndex;
  final String positionGroupFine;
  // Honest display rating (0-99) = within-position league percentile of the
  // player's performance score. positionNorm is FINE or COARSE depending on
  // which group the percentiles were taken against (small groups fall back to
  // coarse). statPct holds every within-position league percentile keyed by the
  // raw KPI name (e.g. 'per90_goals', 'pass_accuracy'). photoUrl is the
  // self-hosted headshot (empty until the photo pipeline runs).
  final int rating;
  final String positionNorm;
  final Map<String, double> statPct;
  final String photoUrl;
  final double predictedScore;
  final double compositeScore;
  final double performanceScore;
  final double recentFormScore;
  final int totalMinutes;
  final int matchesPlayed;
  final double passAccuracy;
  final double duelWinRate;
  final double per90Goals;
  final double per90Assists;
  final double per90KeyPasses;
  final double per90Interceptions;
  final double per90GkSaves;
  final double per90GkCleanSheets;

  MatchPreviewPlayer({
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
    required this.compositeScore,
    required this.performanceScore,
    required this.recentFormScore,
    required this.totalMinutes,
    required this.matchesPlayed,
    required this.passAccuracy,
    required this.duelWinRate,
    required this.per90Goals,
    required this.per90Assists,
    required this.per90KeyPasses,
    required this.per90Interceptions,
    required this.per90GkSaves,
    required this.per90GkCleanSheets,
  });

  factory MatchPreviewPlayer.fromJson(Map<String, dynamic> j) =>
      MatchPreviewPlayer(
        playerId: (j['playerId'] as num?)?.toInt() ?? 0,
        shortName: j['shortName'] as String? ?? '',
        role: j['role'] as String? ?? '',
        roleGroup: j['role_group'] as String? ?? '',
        officialPosition: j['official_position'] as String? ?? '',
        slotIndex: (j['slot_index'] as num?)?.toInt() ?? -1,
        positionGroupFine: j['position_group_fine'] as String? ?? '',
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        positionNorm: j['position_norm'] as String? ?? 'COARSE',
        statPct: {
          for (final e in j.entries)
            if (e.key.endsWith('_pct'))
              e.key.substring(0, e.key.length - 4): (e.value as num?)?.toDouble() ?? 0,
        },
        photoUrl: j['photo_url'] as String? ?? '',
        predictedScore: (j['predicted_score'] as num?)?.toDouble() ?? 0,
        compositeScore: (j['composite_score'] as num?)?.toDouble() ?? 0,
        performanceScore: (j['performance_score'] as num?)?.toDouble() ?? 0,
        recentFormScore: (j['recent_form_score'] as num?)?.toDouble() ?? 0,
        totalMinutes: (j['total_minutes'] as num?)?.toInt() ?? 0,
        matchesPlayed: (j['matches_played'] as num?)?.toInt() ?? 0,
        passAccuracy: (j['pass_accuracy'] as num?)?.toDouble() ?? 0,
        duelWinRate: (j['duel_win_rate'] as num?)?.toDouble() ?? 0,
        per90Goals: (j['per90_goals'] as num?)?.toDouble() ?? 0,
        per90Assists: (j['per90_assists'] as num?)?.toDouble() ?? 0,
        per90KeyPasses: (j['per90_keyPasses'] as num?)?.toDouble() ?? 0,
        per90Interceptions: (j['per90_interceptions'] as num?)?.toDouble() ?? 0,
        per90GkSaves: (j['per90_gkSaves'] as num?)?.toDouble() ?? 0,
        per90GkCleanSheets: (j['per90_gkCleanSheets'] as num?)?.toDouble() ?? 0,
      );

  // Returns the most relevant per-90 stat label + value for this player's position
  String get keyStatLabel {
    switch (roleGroup) {
      case 'GK':
        return 'SVS/90';
      case 'DEF':
        return 'INT/90';
      case 'FWD':
        return 'G/90';
      default:
        return 'KP/90';
    }
  }

  double get keyStatValue {
    switch (roleGroup) {
      case 'GK':
        return per90GkSaves;
      case 'DEF':
        return per90Interceptions;
      case 'FWD':
        return per90Goals;
      default:
        return per90KeyPasses;
    }
  }
}

class MatchTeamStats {
  final double avgPerformanceScore;
  final double avgRecentForm;
  final double avgPassAccuracy;
  final double avgDuelWinRate;
  final String topScorer;
  final double topScorerStat;
  final String topCreator;
  final double topCreatorStat;

  MatchTeamStats({
    required this.avgPerformanceScore,
    required this.avgRecentForm,
    required this.avgPassAccuracy,
    required this.avgDuelWinRate,
    required this.topScorer,
    required this.topScorerStat,
    required this.topCreator,
    required this.topCreatorStat,
  });

  factory MatchTeamStats.fromJson(Map<String, dynamic> j) => MatchTeamStats(
        avgPerformanceScore:
            (j['avg_performance_score'] as num?)?.toDouble() ?? 0,
        avgRecentForm: (j['avg_recent_form'] as num?)?.toDouble() ?? 0,
        avgPassAccuracy: (j['avg_pass_accuracy'] as num?)?.toDouble() ?? 0,
        avgDuelWinRate: (j['avg_duel_win_rate'] as num?)?.toDouble() ?? 0,
        topScorer: j['top_scorer'] as String? ?? '',
        topScorerStat: (j['top_scorer_stat'] as num?)?.toDouble() ?? 0,
        topCreator: j['top_creator'] as String? ?? '',
        topCreatorStat: (j['top_creator_stat'] as num?)?.toDouble() ?? 0,
      );
}

class H2HStats {
  final int total;
  final int ourWins;
  final int draws;
  final int theirWins;
  final double ourAvgGoals;
  final double theirAvgGoals;

  H2HStats({
    required this.total,
    required this.ourWins,
    required this.draws,
    required this.theirWins,
    required this.ourAvgGoals,
    required this.theirAvgGoals,
  });

  factory H2HStats.fromJson(Map<String, dynamic> j) => H2HStats(
        total: (j['total'] as num?)?.toInt() ?? 0,
        ourWins: (j['our_wins'] as num?)?.toInt() ?? 0,
        draws: (j['draws'] as num?)?.toInt() ?? 0,
        theirWins: (j['their_wins'] as num?)?.toInt() ?? 0,
        ourAvgGoals: (j['our_avg_goals'] as num?)?.toDouble() ?? 0,
        theirAvgGoals: (j['their_avg_goals'] as num?)?.toDouble() ?? 0,
      );
}

class MatchPreviewResponse {
  final String formation;
  final String opponentName;
  final int? opponentTeamId;
  final List<MatchPreviewPlayer> startingXi;
  final List<MatchPreviewPlayer> bench;
  final MatchTeamStats teamStats;
  final MatchTeamStats opponentStats;
  final H2HStats headToHead;

  MatchPreviewResponse({
    required this.formation,
    required this.opponentName,
    this.opponentTeamId,
    required this.startingXi,
    required this.bench,
    required this.teamStats,
    required this.opponentStats,
    required this.headToHead,
  });

  factory MatchPreviewResponse.fromJson(Map<String, dynamic> j) =>
      MatchPreviewResponse(
        formation: j['formation'] as String? ?? '4-3-3',
        opponentName: j['opponent_name'] as String? ?? '',
        opponentTeamId: (j['opponent_team_id'] as num?)?.toInt(),
        startingXi: (j['starting_xi'] as List<dynamic>?)
                ?.map((e) =>
                    MatchPreviewPlayer.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        bench: (j['bench'] as List<dynamic>?)
                ?.map((e) =>
                    MatchPreviewPlayer.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        teamStats: MatchTeamStats.fromJson(
            j['team_stats'] as Map<String, dynamic>? ?? {}),
        opponentStats: MatchTeamStats.fromJson(
            j['opponent_stats'] as Map<String, dynamic>? ?? {}),
        headToHead: H2HStats.fromJson(
            j['head_to_head'] as Map<String, dynamic>? ?? {}),
      );
}
