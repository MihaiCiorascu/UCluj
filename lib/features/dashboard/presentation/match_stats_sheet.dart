import 'package:flutter/material.dart';

import '../../../core/constants/supported_formations.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../data/models/week_fixture.dart';
import '../../../data/models/match_details.dart';
import '../../../data/models/match_preview.dart' show MatchPreviewResponse;
import '../../../data/repositories/xi_repository.dart';
import '../../../data/repositories/match_details_repository.dart';
import '../../../core/services/api_client.dart';
import '../../team/presentation/recommended_xi_fifa_panel.dart';

// ── Prescription blueprint widget ──────────────────────────────────────────

class _PrescriptionBlueprint extends StatelessWidget {
  const _PrescriptionBlueprint({required this.prescription});
  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final uplift = prescription.improvement;
    final bestPct = '${(prescription.bestProb * 100).round()}%';
    final upliftPct = '+${(uplift * 100).round()}%';
    final recs = prescription.recommendations;

    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.surfaceLow,
        border: Border.all(color: ColorTokens.accent.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            color: ColorTokens.accent.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: ColorTokens.accent, size: 14),
                const SizedBox(width: SpacingTokens.xs),
                Text(L10n.t('sheet.optimalPlan'),
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: ColorTokens.accent, fontSize: 11)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: ColorTokens.positive.withValues(alpha: 0.15),
                    border: Border.all(
                        color: ColorTokens.positive.withValues(alpha: 0.5)),
                  ),
                  child: Text(upliftPct,
                      style: TypographyTokens.sectionLabel
                          .copyWith(color: ColorTokens.positive, fontSize: 10)),
                ),
              ],
            ),
          ),

          // ── Projected probability ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(bestPct,
                    style: TypographyTokens.displayHero
                        .copyWith(color: ColorTokens.positive, fontSize: 40)),
                const SizedBox(width: SpacingTokens.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L10n.t('sheet.projectedProb'),
                        style: TypographyTokens.sectionLabel.copyWith(
                            fontSize: 8, color: ColorTokens.textMuted)),
                    Text(L10n.t('sheet.projected'),
                        style: TypographyTokens.sectionLabel.copyWith(
                            fontSize: 8, color: ColorTokens.textMuted)),
                  ],
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: SpacingTokens.md),
            child: Divider(height: 1, color: ColorTokens.divider),
          ),

          // ── Recommendation chips ─────────────────────────────────────────
          if (recs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(SpacingTokens.md),
              child: Wrap(
                spacing: SpacingTokens.sm,
                runSpacing: SpacingTokens.sm,
                children: recs.map(_buildRecChip).toList(),
              ),
            ),

          // ── Footer ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.sm),
            child: Text(
              L10n.t('sheet.modelFooter'),
              style: TypographyTokens.sectionLabel
                  .copyWith(color: ColorTokens.textMuted, fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecChip(PrescriptionRec rec) {
    final isUp = rec.direction == 'up';
    final color = isUp ? ColorTokens.positive : ColorTokens.accent;
    final arrow = isUp ? '▲' : '▼';
    final unitStr = rec.unit;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rec.label.toUpperCase(),
              style: TypographyTokens.sectionLabel
                  .copyWith(color: ColorTokens.textMuted, fontSize: 8)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(arrow,
                  style: TypographyTokens.sectionLabel
                      .copyWith(color: color, fontSize: 10)),
              const SizedBox(width: 3),
              Text(
                '${rec.current}$unitStr → ${rec.target}$unitStr',
                style: TypographyTokens.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: ColorTokens.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Main sheet ──────────────────────────────────────────────────────────────

class MatchStatsSheet extends StatefulWidget {
  const MatchStatsSheet({
    required this.fixture,
    required this.myTeam,
    this.apiClient,
    super.key,
  });

  final WeekFixture fixture;
  final String myTeam;
  final ApiClient? apiClient;

  @override
  State<MatchStatsSheet> createState() => _MatchStatsSheetState();
}

class _MatchStatsSheetState extends State<MatchStatsSheet> {
  // XI (upcoming matches)
  final _xiRepo = XiRepository();
  bool _loadingXi = false;
  MatchPreviewResponse? _preview;
  String? _xiError;
  String _formation = '4-3-3';

  // Lineup team selector (completed matches): 0=home, 1=away
  int _lineupTeamIndex = 0;

  // Match details (completed matches)
  MatchDetailsRepository? _detailsRepo;
  bool _loadingDetails = false;
  MatchDetails? _matchDetails;

  static const _formations = kSupportedFormations;

  @override
  void initState() {
    super.initState();
    final f = widget.fixture;
    if (f.isCompleted && f.matchId.isNotEmpty) {
      _loadMatchDetails();
    } else if (f.involvesUCluj) {
      _loadXi();
    }
  }

  Future<void> _loadMatchDetails() async {
    setState(() => _loadingDetails = true);
    try {
      _detailsRepo ??= MatchDetailsRepository(
        apiClient: widget.apiClient ?? ApiClient(),
      );
      final details = await _detailsRepo!.fetchMatchDetails(widget.fixture.matchId);
      if (mounted) setState(() { _matchDetails = details; _loadingDetails = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _loadXi() async {
    setState(() { _loadingXi = true; _xiError = null; });
    try {
      final f = widget.fixture;
      final opponent = f.isUCLujHome ? f.awayTeam : f.homeTeam;
      final preview = await _xiRepo.fetchMatchPreview(
        opponentName: opponent,
        formation: _formation,
      );
      if (mounted) setState(() { _preview = preview; _loadingXi = false; });
    } catch (e) {
      if (mounted) setState(() { _xiError = e.toString(); _loadingXi = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    final screenH = MediaQuery.of(context).size.height;
    final uclProb = f.homeWinProbability;

    return Container(
      height: screenH * 0.92,
      decoration: const BoxDecoration(
        color: ColorTokens.surface,
        border: Border(top: BorderSide(color: ColorTokens.accent, width: 2)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: SpacingTokens.sm),
              width: 40,
              height: 3,
              color: ColorTokens.divider,
            ),
          ),
          _buildHeader(f),
          const Divider(height: 1, color: ColorTokens.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                _buildMatchStatus(f),
                const SizedBox(height: SpacingTokens.xl),

                if (f.isCompleted) ...[
                  // Official stats from Sportradar
                  if (_loadingDetails)
                    const Padding(
                      padding: EdgeInsets.all(SpacingTokens.xl),
                      child: Center(
                        child: CircularProgressIndicator(color: ColorTokens.accent),
                      ),
                    )
                  else if (_matchDetails != null) ...[
                    if (_matchDetails!.hasStats) ...[
                      _sectionLabel(L10n.t('sheet.officialStats')),
                      const SizedBox(height: SpacingTokens.sm),
                      _buildTeamStats(f, _matchDetails!),
                      const SizedBox(height: SpacingTokens.xl),
                    ],
                    if (_matchDetails!.hasLineups) ...[
                      _sectionLabel(L10n.t('sheet.startingLineups')),
                      const SizedBox(height: SpacingTokens.sm),
                      _buildLineupPitchSection(f, _matchDetails!),
                      const SizedBox(height: SpacingTokens.xl),
                    ],
                  ],
                ] else ...[
                  // ML prediction — only for upcoming
                  if (uclProb != null) ...[
                    _buildMLBlock(f, uclProb),
                    const SizedBox(height: SpacingTokens.xl),
                  ],

                  if (f.keyDrivers.isNotEmpty) ...[
                    _sectionLabel(L10n.t('sheet.keyDrivers')),
                    const SizedBox(height: SpacingTokens.sm),
                    ...f.keyDrivers.map(_buildDriverRow),
                    const SizedBox(height: SpacingTokens.md),
                  ],

                  if (f.topRisks.isNotEmpty) ...[
                    _sectionLabel(L10n.t('sheet.risks')),
                    const SizedBox(height: SpacingTokens.sm),
                    ...f.topRisks.map((r) => _buildDriverRow(r, isRisk: true)),
                    const SizedBox(height: SpacingTokens.md),
                  ],

                  if (f.prescription != null) ...[
                    _sectionLabel(L10n.t('sheet.diagnosticPlan')),
                    const SizedBox(height: SpacingTokens.sm),
                    _PrescriptionBlueprint(prescription: f.prescription!),
                    const SizedBox(height: SpacingTokens.xl),
                  ] else if (f.narrative.isNotEmpty) ...[
                    _sectionLabel(L10n.t('sheet.diagnostic')),
                    const SizedBox(height: SpacingTokens.sm),
                    Container(
                      color: ColorTokens.surfaceLow,
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      child: Text(f.narrative,
                          style: TypographyTokens.body
                              .copyWith(color: ColorTokens.textMuted, fontSize: 13)),
                    ),
                    const SizedBox(height: SpacingTokens.xl),
                  ],

                  // XI only for upcoming U Cluj matches
                  if (f.involvesUCluj) _buildXiSection(),
                ],

                const SizedBox(height: SpacingTokens.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(WeekFixture f) {
    final homeDisplay = f.homeTeam.replaceAll('Universitatea Cluj', 'U CLUJ').toUpperCase();
    final awayDisplay = f.awayTeam.replaceAll('Universitatea Cluj', 'U CLUJ').toUpperCase();

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Row(
        children: [
          Expanded(
            child: Text(homeDisplay,
                style: TypographyTokens.body.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: ColorTokens.textPrimary),
                textAlign: TextAlign.center),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
            color: ColorTokens.surfaceHigh,
            child: Text('VS',
                style: TypographyTokens.sectionLabel
                    .copyWith(color: ColorTokens.accent)),
          ),
          Expanded(
            child: Text(awayDisplay,
                style: TypographyTokens.body.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: ColorTokens.textPrimary),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchStatus(WeekFixture f) {
    if (f.isCompleted) {
      final isHome = f.isUCLujHome;
      final myScore = isHome ? f.homeScore! : f.awayScore!;
      final theirScore = isHome ? f.awayScore! : f.homeScore!;
      String result;
      Color col;
      if (myScore > theirScore) { result = L10n.t('sheet.win'); col = ColorTokens.positive; }
      else if (myScore < theirScore) { result = L10n.t('sheet.loss'); col = ColorTokens.negative; }
      else { result = L10n.t('sheet.draw'); col = ColorTokens.accent; }

      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${f.homeScore}',
                  style: TypographyTokens.displayHero.copyWith(
                      fontSize: 64, color: ColorTokens.textPrimary)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
                child: Text('—',
                    style: TypographyTokens.displayHero.copyWith(
                        fontSize: 32, color: ColorTokens.textMuted)),
              ),
              Text('${f.awayScore}',
                  style: TypographyTokens.displayHero.copyWith(
                      fontSize: 64, color: ColorTokens.textPrimary)),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          if (f.involvesUCluj)
            Container(
              color: col.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md, vertical: SpacingTokens.xs),
              child: Text(result,
                  style: TypographyTokens.sectionLabel.copyWith(color: col)),
            ),
        ],
      );
    }

    return Container(
      color: ColorTokens.surfaceLow,
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: ColorTokens.accent, size: 14),
          const SizedBox(width: SpacingTokens.xs),
          Text(f.displayDate,
              style: TypographyTokens.sectionLabel.copyWith(color: ColorTokens.accent)),
          if (f.venue != null) ...[
            Text('  ·  ${f.venue}',
                style: TypographyTokens.sectionLabel
                    .copyWith(color: ColorTokens.textMuted)),
          ],
        ],
      ),
    );
  }

  // ── Team stats comparison ────────────────────────────────────────────────

  Widget _buildTeamStats(WeekFixture f, MatchDetails d) {
    final h = d.homeStats;
    final a = d.awayStats;

    return Container(
      color: ColorTokens.surfaceLow,
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  f.homeTeam.replaceAll('Universitatea Cluj', 'U CLUJ').toUpperCase(),
                  style: TypographyTokens.sectionLabel.copyWith(
                    color: f.isUCLujHome ? ColorTokens.accent : ColorTokens.textMuted,
                    fontSize: 9,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '',
                  textAlign: TextAlign.center,
                  style: TypographyTokens.sectionLabel.copyWith(fontSize: 9),
                ),
              ),
              Expanded(
                child: Text(
                  f.awayTeam.replaceAll('Universitatea Cluj', 'U CLUJ').toUpperCase(),
                  style: TypographyTokens.sectionLabel.copyWith(
                    color: !f.isUCLujHome ? ColorTokens.accent : ColorTokens.textMuted,
                    fontSize: 9,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          const Divider(height: 1, color: ColorTokens.divider),
          const SizedBox(height: SpacingTokens.sm),

          if (h.ballPossession != null || a.ballPossession != null)
            _buildStatRow(
              L10n.t('sheet.statPossession'),
              '${h.ballPossession?.toStringAsFixed(0) ?? '—'}%',
              '${a.ballPossession?.toStringAsFixed(0) ?? '—'}%',
              homeVal: h.ballPossession ?? 50,
              awayVal: a.ballPossession ?? 50,
              higherIsBetter: true,
              isUCLujHome: f.isUCLujHome,
            ),
          _buildStatRowRaw(L10n.t('sheet.statShotsOnTarget'),
              '${h.shotsOnTarget ?? '—'}', '${a.shotsOnTarget ?? '—'}',
              homeVal: (h.shotsOnTarget ?? 0).toDouble(),
              awayVal: (a.shotsOnTarget ?? 0).toDouble(),
              higherIsBetter: true, isUCLujHome: f.isUCLujHome),
          _buildStatRowRaw(L10n.t('sheet.statShotsTotal'),
              '${h.totalShots}', '${a.totalShots}',
              homeVal: h.totalShots.toDouble(),
              awayVal: a.totalShots.toDouble(),
              higherIsBetter: true, isUCLujHome: f.isUCLujHome),
          _buildStatRowRaw(L10n.t('sheet.statCorners'),
              '${h.cornerKicks ?? '—'}', '${a.cornerKicks ?? '—'}',
              homeVal: (h.cornerKicks ?? 0).toDouble(),
              awayVal: (a.cornerKicks ?? 0).toDouble(),
              higherIsBetter: true, isUCLujHome: f.isUCLujHome),
          _buildStatRowRaw(L10n.t('sheet.statOffsides'),
              '${h.offsides ?? '—'}', '${a.offsides ?? '—'}',
              homeVal: (h.offsides ?? 0).toDouble(),
              awayVal: (a.offsides ?? 0).toDouble(),
              higherIsBetter: false, isUCLujHome: f.isUCLujHome),
          _buildStatRowRaw(L10n.t('sheet.statFouls'),
              '${h.fouls ?? '—'}', '${a.fouls ?? '—'}',
              homeVal: (h.fouls ?? 0).toDouble(),
              awayVal: (a.fouls ?? 0).toDouble(),
              higherIsBetter: false, isUCLujHome: f.isUCLujHome),
          if (h.yellowCards != null || a.yellowCards != null)
            _buildStatRowRaw(L10n.t('sheet.statYellow'),
                '${h.yellowCards ?? '—'}', '${a.yellowCards ?? '—'}',
                homeVal: (h.yellowCards ?? 0).toDouble(),
                awayVal: (a.yellowCards ?? 0).toDouble(),
                higherIsBetter: false, isUCLujHome: f.isUCLujHome),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    String homeStr,
    String awayStr, {
    required double homeVal,
    required double awayVal,
    required bool higherIsBetter,
    required bool isUCLujHome,
  }) {
    final total = homeVal + awayVal;
    final homeRatio = total > 0 ? homeVal / total : 0.5;

    final uclVal = isUCLujHome ? homeVal : awayVal;
    final oppVal = isUCLujHome ? awayVal : homeVal;
    final uclColor = higherIsBetter
        ? (uclVal >= oppVal ? ColorTokens.positive : ColorTokens.negative)
        : (uclVal <= oppVal ? ColorTokens.positive : ColorTokens.negative);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(homeStr,
                    style: TypographyTokens.body.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isUCLujHome ? uclColor : ColorTokens.textPrimary,
                    )),
              ),
              Expanded(
                child: Center(
                  child: Text(label,
                      style: TypographyTokens.sectionLabel
                          .copyWith(fontSize: 8, color: ColorTokens.textMuted)),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(awayStr,
                    style: TypographyTokens.body.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: !isUCLujHome ? uclColor : ColorTokens.textPrimary,
                    ),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            child: Row(
              children: [
                Expanded(
                  flex: (homeRatio * 100).round(),
                  child: Container(
                    height: 4,
                    color: isUCLujHome
                        ? uclColor
                        : ColorTokens.textMuted.withValues(alpha: 0.5),
                  ),
                ),
                Expanded(
                  flex: ((1 - homeRatio) * 100).round(),
                  child: Container(
                    height: 4,
                    color: !isUCLujHome
                        ? uclColor
                        : ColorTokens.textMuted.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRowRaw(
    String label,
    String homeStr,
    String awayStr, {
    required double homeVal,
    required double awayVal,
    required bool higherIsBetter,
    required bool isUCLujHome,
  }) =>
      _buildStatRow(label, homeStr, awayStr,
          homeVal: homeVal,
          awayVal: awayVal,
          higherIsBetter: higherIsBetter,
          isUCLujHome: isUCLujHome);

  // ── Lineup pitch section (completed matches) ─────────────────────────────

  Widget _buildLineupPitchSection(WeekFixture f, MatchDetails d) {
    final homeDisplay = f.homeTeam.replaceAll('Universitatea Cluj', 'U CLUJ').toUpperCase();
    final awayDisplay = f.awayTeam.replaceAll('Universitatea Cluj', 'U CLUJ').toUpperCase();

    final isShowingHome = _lineupTeamIndex == 0;
    final players = isShowingHome ? d.homeLineup : d.awayLineup;
    final isUCluj = isShowingHome ? f.isUCLujHome : !f.isUCLujHome;

    final starters = players.where((p) => p.isStarter).toList();
    final subs = players.where((p) => !p.isStarter).toList();
    final formation = _inferFormation(starters);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Team selector tabs ───────────────────────────────────────────
        Row(
          children: [
            _teamTab(homeDisplay, f.isUCLujHome, _lineupTeamIndex == 0,
                () => setState(() => _lineupTeamIndex = 0)),
            Container(width: 1, color: ColorTokens.divider),
            _teamTab(awayDisplay, !f.isUCLujHome, _lineupTeamIndex == 1,
                () => setState(() => _lineupTeamIndex = 1)),
          ],
        ),

        // ── Formation label ──────────────────────────────────────────────
        if (formation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md, SpacingTokens.xs, SpacingTokens.md, 0),
            child: Text(
              formation,
              style: TypographyTokens.sectionLabel.copyWith(
                color: isUCluj ? ColorTokens.accent : ColorTokens.textMuted,
                fontSize: 10,
              ),
            ),
          ),

        // ── Pitch (swipeable) ────────────────────────────────────────────
        GestureDetector(
          onHorizontalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200 && _lineupTeamIndex == 0) {
              setState(() => _lineupTeamIndex = 1);
            } else if ((d.primaryVelocity ?? 0) > 200 && _lineupTeamIndex == 1) {
              setState(() => _lineupTeamIndex = 0);
            }
          },
          child: starters.isNotEmpty
              ? _ActualLineupPitchPanel(starters: starters)
              : const SizedBox.shrink(),
        ),

        // ── Substitutes ──────────────────────────────────────────────────
        if (subs.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.xs),
          Container(
            color: ColorTokens.surfaceLow,
            padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md, vertical: 4),
            child: Text(L10n.t('sheet.subs'),
                style: TypographyTokens.sectionLabel
                    .copyWith(fontSize: 8, color: ColorTokens.textMuted)),
          ),
          ...subs.map((p) => _buildPlayerRow(p, isUCluj: isUCluj, isSub: true)),
        ],
      ],
    );
  }

  Widget _teamTab(
      String name, bool isUCluj, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: SpacingTokens.sm, horizontal: SpacingTokens.xs),
          color: selected ? ColorTokens.surfaceLow : ColorTokens.surfaceHigh,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isUCluj) ...[
                const Icon(Icons.shield, color: ColorTokens.accent, size: 10),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  name,
                  style: TypographyTokens.sectionLabel.copyWith(
                    fontSize: 9,
                    color: selected
                        ? (isUCluj ? ColorTokens.accent : ColorTokens.textPrimary)
                        : ColorTokens.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _inferFormation(List<MatchPlayer> starters) {
    final d = starters.where((p) => p.position == 'D').length;
    final m = starters.where((p) => p.position == 'M').length;
    final fw = starters.where((p) => p.position == 'F').length;
    if (d + m + fw == 0) return '';
    return '$d-$m-$fw';
  }

  Widget _buildPlayerRow(MatchPlayer p, {required bool isUCluj, bool isSub = false}) {
    final posColor = _positionColor(p.position);

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      color: isSub
          ? ColorTokens.surface
          : ColorTokens.surfaceLow.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: 6),
      child: Row(
        children: [
          // Jersey number
          SizedBox(
            width: 24,
            child: Text(
              p.jerseyNumber != null ? '${p.jerseyNumber}' : '—',
              style: TypographyTokens.sectionLabel.copyWith(
                fontSize: 10,
                color: ColorTokens.textMuted,
              ),
            ),
          ),
          // Position badge
          Container(
            width: 20,
            height: 16,
            color: posColor.withValues(alpha: 0.15),
            child: Center(
              child: Text(
                p.position.isNotEmpty ? p.position[0] : '?',
                style: TypographyTokens.sectionLabel.copyWith(
                    fontSize: 8, color: posColor),
              ),
            ),
          ),
          const SizedBox(width: SpacingTokens.xs),
          // Name
          Expanded(
            child: Text(
              p.name,
              style: TypographyTokens.body.copyWith(
                fontSize: 12,
                fontWeight: isSub ? FontWeight.w400 : FontWeight.w600,
                color: isSub ? ColorTokens.textMuted : ColorTokens.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Stats badges
          _buildPlayerBadges(p),
        ],
      ),
    );
  }

  Widget _buildPlayerBadges(MatchPlayer p) {
    final badges = <Widget>[];

    if (p.goalsScored > 0) {
      badges.add(_badge('⚽ ${p.goalsScored}', ColorTokens.positive));
    }
    if (p.assists > 0) {
      badges.add(_badge('A${p.assists}', ColorTokens.accent));
    }
    if (p.yellowCards > 0) {
      badges.add(_badge('▪', const Color(0xFFFFD700)));
    }
    if (p.redCards > 0) {
      badges.add(_badge('▪', ColorTokens.negative));
    }
    if (p.minutesPlayed != null && p.minutesPlayed! < 90 && !p.isStarter) {
      badges.add(_badge("${p.minutesPlayed}'", ColorTokens.textMuted));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: badges
          .expand((b) => [b, const SizedBox(width: 3)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: color.withValues(alpha: 0.15),
        child: Text(text,
            style:
                TypographyTokens.sectionLabel.copyWith(color: color, fontSize: 9)),
      );

  Color _positionColor(String pos) {
    switch (pos.toUpperCase()) {
      case 'G':
        return const Color(0xFFFFAA00);
      case 'D':
        return ColorTokens.positive;
      case 'M':
        return ColorTokens.accent;
      case 'F':
        return ColorTokens.negative;
      default:
        return ColorTokens.textMuted;
    }
  }

  // ── ML block (upcoming) ──────────────────────────────────────────────────

  Widget _buildMLBlock(WeekFixture f, double uclProb) {
    final winPct  = (uclProb * 100).round();
    final restPct = 100 - winPct;
    final col = uclProb >= 0.55
        ? ColorTokens.positive
        : uclProb >= 0.40
            ? ColorTokens.accent
            : ColorTokens.negative;

    return Container(
      color: ColorTokens.surfaceLow,
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L10n.t('sheet.winChanceUcluj'),
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: ColorTokens.textMuted)),
                const SizedBox(height: SpacingTokens.xs),
                Text('$winPct%',
                    style: TypographyTokens.displayHero
                        .copyWith(color: col, fontSize: 44)),
                const SizedBox(height: SpacingTokens.xs),
                Row(
                  children: [
                    _OutcomePill(label: L10n.t('sheet.outcomeWin'), pct: winPct, color: col),
                    const SizedBox(width: SpacingTokens.xs),
                    _OutcomePill(
                        label: L10n.t('sheet.outcomeRest'),
                        pct: restPct,
                        color: ColorTokens.textMuted),
                  ],
                ),
                const SizedBox(height: SpacingTokens.xs),
                Text(L10n.t('sheet.modelCaption'),
                    style: TypographyTokens.sectionLabel.copyWith(
                        fontSize: 8, color: ColorTokens.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          _ProbBar(probability: uclProb, color: col),
        ],
      ),
    );
  }

  Widget _buildDriverRow(WeekFixtureDriver d, {bool isRisk = false}) {
    final col = isRisk ? ColorTokens.negative : ColorTokens.positive;
    final sign = isRisk ? '▼' : '▲';
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      color: ColorTokens.surfaceLow,
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
      child: Row(
        children: [
          Text(sign,
              style: TypographyTokens.sectionLabel
                  .copyWith(color: col, fontSize: 9)),
          const SizedBox(width: SpacingTokens.xs),
          Expanded(
              child: Text(d.label.toUpperCase(),
                  style: TypographyTokens.body.copyWith(
                      fontSize: 12, color: ColorTokens.textPrimary))),
          Text(
            '${(d.importance * 100).toStringAsFixed(0)}%',
            style: TypographyTokens.body
                .copyWith(color: col, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── XI section (upcoming U Cluj) ─────────────────────────────────────────

  Widget _buildXiSection() {
    if (_loadingXi) {
      return const Padding(
        padding: EdgeInsets.all(SpacingTokens.xl),
        child: Center(child: CircularProgressIndicator(color: ColorTokens.accent)),
      );
    }
    if (_xiError != null) {
      return Container(
        color: ColorTokens.surfaceLow,
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Text('${L10n.t('sheet.xiUnavailable')}: $_xiError',
            style: TypographyTokens.body
                .copyWith(color: ColorTokens.textMuted, fontSize: 12)),
      );
    }
    if (_preview == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel(L10n.t('sheet.recommendedXi')),
            const Spacer(),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _formation,
                dropdownColor: ColorTokens.surfaceLow,
                style: TypographyTokens.body
                    .copyWith(color: ColorTokens.textPrimary, fontSize: 12),
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: ColorTokens.accent, size: 16),
                onChanged: (v) {
                  if (v != null && v != _formation) {
                    setState(() => _formation = v);
                    _loadXi();
                  }
                },
                items: _formations
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.sm),
        RecommendedXiFifaPanel(
          preview: _preview!,
          formation: _formation,
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Row(
        children: [
          Container(width: 2, height: 12, color: ColorTokens.accent),
          const SizedBox(width: SpacingTokens.xs),
          Text(text,
              style: TypographyTokens.sectionLabel
                  .copyWith(color: ColorTokens.textMuted)),
        ],
      );
}

// ── Actual lineup pitch widgets ──────────────────────────────────────────────

class _ActualLineupPitchPanel extends StatelessWidget {
  const _ActualLineupPitchPanel({required this.starters});
  final List<MatchPlayer> starters;

  List<double> _distributedXs(int count) {
    if (count <= 1) return const [0.50];
    const left = 0.18;
    const right = 0.82;
    final step = (right - left) / (count - 1);
    return List<double>.generate(count, (i) => left + step * i);
  }

  List<({MatchPlayer player, Offset offset})> _placements() {
    final gk = starters.where((p) => p.position == 'G').toList();
    final defs = starters.where((p) => p.position == 'D').toList();
    final mids = starters.where((p) => p.position == 'M').toList();
    final fwds = starters.where((p) => p.position == 'F').toList();

    final result = <({MatchPlayer player, Offset offset})>[];

    if (gk.isNotEmpty) {
      result.add((player: gk.first, offset: const Offset(0.50, 0.90)));
    }

    void addRow(List<MatchPlayer> players, double y) {
      if (players.isEmpty) return;
      final xs = _distributedXs(players.length);
      for (var i = 0; i < players.length; i++) {
        result.add((player: players[i], offset: Offset(xs[i], y)));
      }
    }

    addRow(defs, 0.73);
    addRow(mids, 0.43);
    addRow(fwds, 0.18);

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final placements = _placements();

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, c) {
          final maxLineCount = [
            starters.where((p) => p.position == 'D').length,
            starters.where((p) => p.position == 'M').length,
            starters.where((p) => p.position == 'F').length,
          ].fold(1, (a, b) => a > b ? a : b);

          final base = c.maxWidth < 430 ? 44.0 : 50.0;
          final chipSize = maxLineCount >= 5
              ? base - 6
              : maxLineCount >= 4
                  ? base - 3
                  : base;

          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: FifaPitchPainter()),
              for (final p in placements)
                Positioned(
                  left: p.offset.dx * c.maxWidth - chipSize / 2,
                  top: p.offset.dy * c.maxHeight - chipSize / 2,
                  width: chipSize,
                  height: chipSize,
                  child: _ActualPlayerChip(player: p.player, chipSize: chipSize),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActualPlayerChip extends StatelessWidget {
  const _ActualPlayerChip({required this.player, required this.chipSize});
  final MatchPlayer player;
  final double chipSize;

  Color get _posColor {
    switch (player.position.toUpperCase()) {
      case 'G':
        return const Color(0xFFFFAA00);
      case 'D':
        return ColorTokens.positive;
      case 'M':
        return ColorTokens.accent;
      case 'F':
        return ColorTokens.negative;
      default:
        return ColorTokens.textMuted;
    }
  }

  String get _lastName {
    final name = player.name.trim();
    // Data arrives as "Surname, Firstname" — take the part before the comma
    if (name.contains(',')) return name.split(',').first.trim();
    // Fallback: "Firstname Surname" — take the last word
    final parts = name.split(' ');
    return parts.length > 1 ? parts.last : name;
  }

  @override
  Widget build(BuildContext context) {
    final hasGoal = player.goalsScored > 0;
    final hasYellow = player.yellowCards > 0;
    final hasRed = player.redCards > 0;

    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        border: Border.all(color: _posColor.withValues(alpha: 0.7), width: 1.5),
      ),
      padding: EdgeInsets.all(chipSize * 0.06),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Position badge
          Text(
            player.position.isNotEmpty ? player.position : '?',
            style: TypographyTokens.body.copyWith(
              fontSize: chipSize * 0.13,
              color: _posColor,
            ),
          ),
          // Jersey number (prominent)
          Text(
            player.jerseyNumber != null ? '${player.jerseyNumber}' : '—',
            style: TypographyTokens.headline.copyWith(
              fontSize: chipSize * 0.22,
              color: _posColor,
            ),
          ),
          // Last name
          Text(
            _lastName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TypographyTokens.body.copyWith(
              fontSize: chipSize * 0.14,
              fontWeight: FontWeight.w700,
              color: ColorTokens.textPrimary,
            ),
          ),
          // Event indicators
          if (hasGoal || hasYellow || hasRed)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasGoal)
                  Text('⚽',
                      style: TextStyle(fontSize: chipSize * 0.13)),
                if (hasYellow)
                  Container(
                    width: chipSize * 0.1,
                    height: chipSize * 0.14,
                    color: const Color(0xFFFFD700),
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                  ),
                if (hasRed)
                  Container(
                    width: chipSize * 0.1,
                    height: chipSize * 0.14,
                    color: ColorTokens.negative,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _OutcomePill extends StatelessWidget {
  const _OutcomePill({
    required this.label,
    required this.pct,
    required this.color,
  });
  final String label;
  final int pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$pct%',
              style: TypographyTokens.sectionLabel
                  .copyWith(color: color, fontSize: 10)),
          const SizedBox(width: 3),
          Text(label,
              style: TypographyTokens.sectionLabel
                  .copyWith(color: color.withValues(alpha: 0.7), fontSize: 8)),
        ],
      ),
    );
  }
}

class _ProbBar extends StatelessWidget {
  const _ProbBar({required this.probability, required this.color});
  final double probability;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 80,
          width: 20,
          child: RotatedBox(
            quarterTurns: 3,
            child: LinearProgressIndicator(
              value: probability,
              backgroundColor: ColorTokens.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 20,
            ),
          ),
        ),
      ],
    );
  }
}
