class WeekFixtureDriver {
  final String feature;
  final String label;
  final double importance;
  final String direction;

  WeekFixtureDriver({
    required this.feature,
    required this.label,
    required this.importance,
    required this.direction,
  });

  factory WeekFixtureDriver.fromJson(Map<String, dynamic> j) =>
      WeekFixtureDriver(
        feature: j['feature'] as String? ?? '',
        label: j['label'] as String? ?? '',
        importance: (j['importance'] as num?)?.toDouble() ?? 0,
        direction: j['direction'] as String? ?? 'positive',
      );
}

class PrescriptionRec {
  final String label;
  final String unit;
  final double current;
  final double target;
  final String direction; // "up" | "down"

  PrescriptionRec({
    required this.label,
    required this.unit,
    required this.current,
    required this.target,
    required this.direction,
  });

  factory PrescriptionRec.fromJson(Map<String, dynamic> j) => PrescriptionRec(
        label:     j['label'] as String? ?? '',
        unit:      j['unit'] as String? ?? '',
        current:   (j['current'] as num?)?.toDouble() ?? 0,
        target:    (j['target'] as num?)?.toDouble() ?? 0,
        direction: j['direction'] as String? ?? 'up',
      );
}

class Prescription {
  final double baselineProb;
  final double bestProb;
  final double improvement;
  final List<PrescriptionRec> recommendations;

  Prescription({
    required this.baselineProb,
    required this.bestProb,
    required this.improvement,
    required this.recommendations,
  });

  factory Prescription.fromJson(Map<String, dynamic> j) => Prescription(
        baselineProb: (j['baseline_prob'] as num?)?.toDouble() ?? 0,
        bestProb:     (j['best_prob'] as num?)?.toDouble() ?? 0,
        improvement:  (j['improvement'] as num?)?.toDouble() ?? 0,
        recommendations: (j['recommendations'] as List<dynamic>?)
                ?.map((e) => PrescriptionRec.fromJson(e as Map<String, dynamic>))
                .toList() ?? [],
      );
}

class WeekFixture {
  final String matchId;
  final String season;
  final String matchDate;
  final String homeTeam;
  final String awayTeam;
  final int? homeScore;
  final int? awayScore;
  final String? venue;
  final int? round;
  final String? phase;
  final double? homeWinProbability;
  // Three-way odds present ONLY on non-U-Cluj fixtures (the backend runs the
  // binary model once per team as the home subject and reports a documented
  // residual draw). On U-Cluj fixtures these are null and homeWinProbability
  // carries a correct P(U Cluj win) instead.
  final double? homeTeamWinProb;
  final double? awayTeamWinProb;
  final double? drawProb;
  final List<WeekFixtureDriver> keyDrivers;
  final List<WeekFixtureDriver> topRisks;
  final String narrative;
  final Prescription? prescription;

  WeekFixture({
    required this.matchId,
    required this.season,
    required this.matchDate,
    required this.homeTeam,
    required this.awayTeam,
    this.homeScore,
    this.awayScore,
    this.venue,
    this.round,
    this.phase,
    this.homeWinProbability,
    this.homeTeamWinProb,
    this.awayTeamWinProb,
    this.drawProb,
    required this.keyDrivers,
    required this.topRisks,
    required this.narrative,
    this.prescription,
  });

  bool get isCompleted => homeScore != null && awayScore != null;

  bool get involvesUCluj =>
      homeTeam.toLowerCase().contains('universitatea cluj') ||
      awayTeam.toLowerCase().contains('universitatea cluj') ||
      homeTeam.toLowerCase().contains('u cluj') ||
      awayTeam.toLowerCase().contains('u cluj');

  bool get isUCLujHome =>
      homeTeam.toLowerCase().contains('universitatea cluj') ||
      homeTeam.toLowerCase().contains('u cluj');

  String get displayDate {
    if (matchDate.length >= 10) {
      return matchDate.substring(0, 10);
    }
    return matchDate;
  }

  factory WeekFixture.fromJson(Map<String, dynamic> j) => WeekFixture(
        matchId: j['match_id'] as String? ?? '',
        season: j['season']?.toString() ?? '',
        matchDate: j['match_date'] as String? ?? '',
        homeTeam: j['home_team'] as String? ?? '',
        awayTeam: j['away_team'] as String? ?? '',
        homeScore: (j['home_score'] as num?)?.toInt(),
        awayScore: (j['away_score'] as num?)?.toInt(),
        venue: j['venue'] as String?,
        round: (j['round'] as num?)?.toInt(),
        phase: j['phase'] as String?,
        homeWinProbability:
            (j['home_win_probability'] as num?)?.toDouble(),
        homeTeamWinProb: (j['home_team_win_prob'] as num?)?.toDouble(),
        awayTeamWinProb: (j['away_team_win_prob'] as num?)?.toDouble(),
        drawProb: (j['draw_prob'] as num?)?.toDouble(),
        keyDrivers: (j['key_drivers'] as List<dynamic>?)
                ?.map((e) =>
                    WeekFixtureDriver.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        topRisks: (j['top_risks'] as List<dynamic>?)
                ?.map((e) =>
                    WeekFixtureDriver.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        narrative: j['narrative'] as String? ?? '',
        prescription: j['prescription'] != null
            ? Prescription.fromJson(j['prescription'] as Map<String, dynamic>)
            : null,
      );
}
