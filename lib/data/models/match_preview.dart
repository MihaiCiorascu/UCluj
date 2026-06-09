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
  // Preferred pitch side derived from the player's match positions: 'L', 'R' or
  // 'C' (central / two-footed / no side penalty). Used to reveal the L/R flank
  // on bench cards whose fine group (FB, WB, W) does not itself encode a side.
  final String positionSide;
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
  // Load / fatigue / rotation advisor fields (additive; safe defaults so older
  // payloads still parse). freshness/fatigueRisk are 0-100; loadStatus is one of
  // fresh / ok / at_risk; restedAndReady flags a rested regular.
  final double freshness;
  final double fatigueRisk;
  final String loadStatus;
  final bool restedAndReady;
  final String loadNote;
  final double restDays;
  final double ageAtFixture;
  final double acwr;

  MatchPreviewPlayer({
    required this.playerId,
    required this.shortName,
    required this.role,
    required this.roleGroup,
    this.officialPosition = '',
    this.slotIndex = -1,
    this.positionGroupFine = '',
    this.positionSide = '',
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
    this.freshness = 100,
    this.fatigueRisk = 0,
    this.loadStatus = 'fresh',
    this.restedAndReady = false,
    this.loadNote = '',
    this.restDays = 0,
    this.ageAtFixture = 0,
    this.acwr = 0,
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
        positionSide: j['position_side'] as String? ?? '',
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
        freshness: (j['freshness'] as num?)?.toDouble() ?? 100,
        fatigueRisk: (j['fatigue_risk'] as num?)?.toDouble() ?? 0,
        loadStatus: j['load_status'] as String? ?? 'fresh',
        restedAndReady: j['rested_and_ready'] as bool? ?? false,
        loadNote: j['load_note'] as String? ?? '',
        restDays: (j['rest_days'] as num?)?.toDouble() ?? 0,
        ageAtFixture: (j['age_at_fixture'] as num?)?.toDouble() ?? 0,
        acwr: (j['acwr'] as num?)?.toDouble() ?? 0,
      );

  /// The optimiser's selection signal as a 0-100 value: round(predicted_score
  /// * 100). This is the quantity the Monte Carlo / lineup model actually
  /// selects the XI on, so it explains why a high-`rating` player can still be
  /// benched (a low selection score). Distinct from `rating`, which is the
  /// within-position quality percentile.
  int get selectionScore => (predictedScore * 100).clamp(0, 100).round();

  /// Short left/right flank tag ('L' or 'R') when the player has a clear
  /// preferred side AND that side is meaningful for their group (full-backs,
  /// wing-backs, wingers). Empty for central / two-footed players and for
  /// groups where a flank is not a defining trait (CB, DM, CM, ST, GK), so the
  /// marker only appears where it adds information.
  String get sideTag {
    final s = positionSide.toUpperCase();
    if (s != 'L' && s != 'R') return '';
    switch (positionGroupFine.toUpperCase()) {
      case 'FB':
      case 'WB':
      case 'W':
      case 'WF':
        return s;
      default:
        return '';
    }
  }

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
  // The RESOLVED formation: the concrete curated key actually used by the
  // optimiser (never "auto"). The pitch must render from THIS value, not from
  // what the client requested, because formation="auto" lets the backend pick
  // the highest-objective shape.
  final String formation;
  // Total assignment objective per evaluated shape (formation key -> score).
  // For an "auto" request this holds all nine curated shapes; for an explicit
  // request it holds just the one. Used to show the optimiser's "why this
  // shape" ranking next to the resolved-formation badge. Empty on older
  // backends, in which case the ranking strip is hidden.
  final Map<String, double> formationScores;
  final String opponentName;
  final int? opponentTeamId;
  // The tracked (home) team's short label and Sportradar id, echoed back by the
  // backend. Optional so older payloads still parse.
  final String homeTeamShort;
  final String homeTeamSrId;
  final List<MatchPreviewPlayer> startingXi;
  final List<MatchPreviewPlayer> bench;
  // The 'ideal' eleven by pure within-position rating (opponent-agnostic),
  // returned alongside the predicted lineup so the UI can offer a "best XI"
  // toggle. Empty on older backends, in which case the toggle is hidden.
  final List<MatchPreviewPlayer> bestXi;
  final List<MatchPreviewPlayer> bestBench;
  // The opponent's own predicted XI (and bench), from the same model, for the
  // scouting view. Empty on older backends, in which case the toggle is hidden.
  final List<MatchPreviewPlayer> opponentXi;
  final List<MatchPreviewPlayer> opponentBench;
  final MatchTeamStats teamStats;
  final MatchTeamStats opponentStats;
  final H2HStats headToHead;

  MatchPreviewResponse({
    required this.formation,
    this.formationScores = const {},
    required this.opponentName,
    this.opponentTeamId,
    this.homeTeamShort = '',
    this.homeTeamSrId = '',
    required this.startingXi,
    required this.bench,
    this.bestXi = const [],
    this.bestBench = const [],
    this.opponentXi = const [],
    this.opponentBench = const [],
    required this.teamStats,
    required this.opponentStats,
    required this.headToHead,
  });

  factory MatchPreviewResponse.fromJson(Map<String, dynamic> j) {
    List<MatchPreviewPlayer> parsePlayers(String key) =>
        (j[key] as List<dynamic>?)
            ?.map((e) => MatchPreviewPlayer.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return MatchPreviewResponse(
      formation: j['formation'] as String? ?? '4-3-3',
      formationScores: {
        for (final e
            in (j['formation_scores'] as Map<String, dynamic>? ?? {}).entries)
          e.key: (e.value as num?)?.toDouble() ?? 0,
      },
      opponentName: j['opponent_name'] as String? ?? '',
      opponentTeamId: (j['opponent_team_id'] as num?)?.toInt(),
      homeTeamShort: j['home_team_short'] as String? ?? '',
      homeTeamSrId: j['home_team_sr_id'] as String? ?? '',
      startingXi: parsePlayers('starting_xi'),
      bench: parsePlayers('bench'),
      bestXi: parsePlayers('best_xi'),
      bestBench: parsePlayers('best_bench'),
      opponentXi: parsePlayers('opponent_xi'),
      opponentBench: parsePlayers('opponent_bench'),
      teamStats: MatchTeamStats.fromJson(
          j['team_stats'] as Map<String, dynamic>? ?? {}),
      opponentStats: MatchTeamStats.fromJson(
          j['opponent_stats'] as Map<String, dynamic>? ?? {}),
      headToHead: H2HStats.fromJson(
          j['head_to_head'] as Map<String, dynamic>? ?? {}),
    );
  }
}
