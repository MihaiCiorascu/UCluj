class MatchTeamStats {
  final double? ballPossession;
  final int? shotsOnTarget;
  final int? shotsOffTarget;
  final int? shotsTotal;
  final int? cornerKicks;
  final int? yellowCards;
  final int? redCards;
  final int? offsides;
  final int? fouls;
  final int? goalkeeperSaves;

  MatchTeamStats({
    this.ballPossession,
    this.shotsOnTarget,
    this.shotsOffTarget,
    this.shotsTotal,
    this.cornerKicks,
    this.yellowCards,
    this.redCards,
    this.offsides,
    this.fouls,
    this.goalkeeperSaves,
  });

  bool get hasData =>
      ballPossession != null ||
      shotsOnTarget != null ||
      cornerKicks != null;

  int get totalShots => shotsTotal ?? ((shotsOnTarget ?? 0) + (shotsOffTarget ?? 0));

  factory MatchTeamStats.fromJson(Map<String, dynamic> j) => MatchTeamStats(
        ballPossession: (j['ball_possession'] as num?)?.toDouble(),
        shotsOnTarget: (j['shots_on_target'] as num?)?.toInt(),
        shotsOffTarget: (j['shots_off_target'] as num?)?.toInt(),
        shotsTotal: (j['shots_total'] as num?)?.toInt(),
        cornerKicks: (j['corner_kicks'] as num?)?.toInt(),
        yellowCards: (j['yellow_cards'] as num?)?.toInt(),
        redCards: (j['red_cards'] as num?)?.toInt(),
        offsides: (j['offsides'] as num?)?.toInt(),
        fouls: (j['fouls'] as num?)?.toInt(),
        goalkeeperSaves: (j['goalkeeper_saves'] as num?)?.toInt(),
      );
}

class MatchPlayer {
  final String name;
  final int? jerseyNumber;
  final String type; // "starter" | "substitute"
  final String position; // G, D, M, F
  // Official slot label (RB, RCB, DM, RW, ST, ...) and pitch slot index for
  // starters, assigned server-side from the Sportradar shape. Empty / -1 for
  // substitutes and older payloads.
  final String officialPosition;
  final int slotIndex;
  final int goalsScored;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int shotsOnTarget;
  final int? minutesPlayed;
  // Ground-truth substitution flags from the Wyscout total block. cameOff: a
  // starter who was substituted OFF. cameOn: a substitute who came ON. In both
  // cases minutesPlayed is the elapsed duration on the pitch (minutesOnField,
  // including stoppage, so it can exceed 90); it is shown as a duration, not a
  // match-clock minute. The data has no in/out pairing or exact event minute.
  // Both false for older payloads.
  final bool cameOff;
  final bool cameOn;
  // Self-hosted headshot URL resolved server-side by name; '' when unmatched
  // (the avatar then renders initials).
  final String photoUrl;
  // Per-match performance grade on a 0-10 scale (one decimal), derived
  // server-side from this match's Wyscout per-player stats via the thesis
  // performance-score composite. Null when the player could not be matched to
  // Wyscout stats (or for cached payloads built before grades shipped).
  final double? grade;

  /// Per-player match stats (curated Wyscout totals + computed percentages),
  /// keyed by stat name (e.g. 'passAccuracy', 'duelWinRate', 'interceptions').
  /// Empty for payloads without per-player detail. Rendered on the player-detail
  /// sheet when a concluded-match player is tapped.
  final Map<String, double> stats;

  MatchPlayer({
    required this.name,
    this.jerseyNumber,
    required this.type,
    required this.position,
    this.officialPosition = '',
    this.slotIndex = -1,
    required this.goalsScored,
    required this.assists,
    required this.yellowCards,
    required this.redCards,
    required this.shotsOnTarget,
    this.minutesPlayed,
    this.cameOff = false,
    this.cameOn = false,
    this.photoUrl = '',
    this.grade,
    this.stats = const {},
  });

  bool get isStarter => type == 'starter';

  factory MatchPlayer.fromJson(Map<String, dynamic> j) => MatchPlayer(
        name: j['name'] as String? ?? '',
        jerseyNumber: (j['jersey_number'] as num?)?.toInt(),
        type: j['type'] as String? ?? 'starter',
        position: j['position'] as String? ?? '',
        officialPosition: j['official_position'] as String? ?? '',
        slotIndex: (j['slot_index'] as num?)?.toInt() ?? -1,
        goalsScored: (j['goals_scored'] as num?)?.toInt() ?? 0,
        assists: (j['assists'] as num?)?.toInt() ?? 0,
        yellowCards: (j['yellow_cards'] as num?)?.toInt() ?? 0,
        redCards: (j['red_cards'] as num?)?.toInt() ?? 0,
        shotsOnTarget: (j['shots_on_target'] as num?)?.toInt() ?? 0,
        minutesPlayed: (j['minutes_played'] as num?)?.toInt(),
        cameOff: j['came_off'] as bool? ?? false,
        cameOn: j['came_on'] as bool? ?? false,
        photoUrl: j['photo_url'] as String? ?? '',
        grade: (j['grade'] as num?)?.toDouble(),
        stats: {
          for (final e in (j['stats'] as Map<String, dynamic>? ?? {}).entries)
            e.key: (e.value as num?)?.toDouble() ?? 0,
        },
      );
}

class MatchDetails {
  final String matchId;
  final MatchTeamStats homeStats;
  final MatchTeamStats awayStats;
  final List<MatchPlayer> homeLineup;
  final List<MatchPlayer> awayLineup;
  // Formation key the backend used to assign each lineup's official slots, so
  // the pitch lays players out with the matching slot order. Empty when no
  // full eleven was assigned.
  final String homeFormation;
  final String awayFormation;
  // True when the team stats are the per-player Wyscout approximation (the sheet
  // then shows an "estimated" caveat); false when they are official Sportradar
  // totals. Defaults false for the live Sportradar path and older payloads.
  final bool statsEstimated;

  MatchDetails({
    required this.matchId,
    required this.homeStats,
    required this.awayStats,
    required this.homeLineup,
    required this.awayLineup,
    this.homeFormation = '',
    this.awayFormation = '',
    this.statsEstimated = false,
  });

  bool get hasStats => homeStats.hasData || awayStats.hasData;
  bool get hasLineups => homeLineup.isNotEmpty || awayLineup.isNotEmpty;

  factory MatchDetails.fromJson(Map<String, dynamic> j) => MatchDetails(
        matchId: j['match_id'] as String? ?? '',
        homeStats: MatchTeamStats.fromJson(
            (j['home_stats'] as Map<String, dynamic>?) ?? {}),
        awayStats: MatchTeamStats.fromJson(
            (j['away_stats'] as Map<String, dynamic>?) ?? {}),
        homeLineup: (j['home_lineup'] as List<dynamic>?)
                ?.map((e) => MatchPlayer.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        awayLineup: (j['away_lineup'] as List<dynamic>?)
                ?.map((e) => MatchPlayer.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        homeFormation: j['home_formation'] as String? ?? '',
        awayFormation: j['away_formation'] as String? ?? '',
        statsEstimated: j['stats_estimated'] as bool? ?? false,
      );
}
