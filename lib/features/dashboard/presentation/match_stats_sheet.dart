import 'package:flutter/material.dart';

import '../../../core/constants/formation_slots.dart';
import '../../../core/constants/supported_formations.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/widgets/team_crest.dart';
import '../../../core/theme/app_colors.dart';
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

  // PR 12 hierarchy shift: the diagnostic pod is the third tier of the
  // Match Intelligence surface (after the dominant probability headline
  // and the tone-tagged drivers strip). The pod earns its weight via a
  // 4 px cobalt top accent rule, an explicit baseline → optimised
  // before-and-after layout that tells the predictive-to-prescriptive
  // story in one glance, and a tactical-levers section that surfaces the
  // optimiser's actual recommendations under a clear section label.

  @override
  Widget build(BuildContext context) {
    final baselinePct = '${(prescription.baselineProb * 100).round()}%';
    final bestPct = '${(prescription.bestProb * 100).round()}%';
    final upliftPct = '+${(prescription.improvement * 100).round()}%';
    final recs = prescription.recommendations;

    return Container(
      decoration: const BoxDecoration(
        color: ColorTokens.surfaceLow,
        border: Border(
          top: BorderSide(color: ColorTokens.accent, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header label ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: ColorTokens.accent, size: 14),
                const SizedBox(width: SpacingTokens.xs),
                Text(L10n.t('sheet.optimalPlan'),
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: ColorTokens.accent, fontSize: 11)),
              ],
            ),
          ),

          // ── Baseline → Optimised before/after ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _ProbColumn(
                    label: L10n.t('sheet.baselineLabel'),
                    value: baselinePct,
                    valueColor: ColorTokens.textMuted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_forward,
                          color: ColorTokens.accent, size: 16),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: SpacingTokens.sm, vertical: 3),
                        color: ColorTokens.accent.withValues(alpha: 0.14),
                        child: Text(upliftPct,
                            style: TypographyTokens.sectionLabel.copyWith(
                                color: ColorTokens.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 4),
                      Text(L10n.t('sheet.upliftLabel'),
                          style: TypographyTokens.sectionLabel.copyWith(
                              color: ColorTokens.textMuted, fontSize: 8)),
                    ],
                  ),
                ),
                Expanded(
                  child: _ProbColumn(
                    label: L10n.t('sheet.optimisedLabel'),
                    value: bestPct,
                    valueColor: ColorTokens.positive,
                  ),
                ),
              ],
            ),
          ),

          // ── Tactical-levers section ──────────────────────────────────────
          if (recs.isNotEmpty) ...[
            const Divider(height: 1, color: ColorTokens.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.xs),
              child: Row(
                children: [
                  Container(width: 2, height: 12, color: ColorTokens.accent),
                  const SizedBox(width: SpacingTokens.xs),
                  Text(L10n.t('sheet.tacticalLevers'),
                      style: TypographyTokens.sectionLabel
                          .copyWith(color: ColorTokens.textMuted)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.md,
                  SpacingTokens.xs, SpacingTokens.md, SpacingTokens.md),
              child: Wrap(
                spacing: SpacingTokens.sm,
                runSpacing: SpacingTokens.sm,
                children: recs.map(_buildRecChip).toList(),
              ),
            ),
          ],

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

                  // PR 12 hierarchy shift: drivers + risks live in one
                  // horizontal strip below the headline probability. The
                  // earlier full-width bullet rows for each looked so similar
                  // a coach skimming the screen could not tell them apart at
                  // thumb distance; collapsing both into a tone-tagged chip
                  // row (▲ green for drivers, ▼ red for risks) reads in a
                  // single glance and frees vertical space for the
                  // tactical-plan pod underneath.
                  if (f.keyDrivers.isNotEmpty || f.topRisks.isNotEmpty) ...[
                    _sectionLabel(L10n.t('sheet.keyDrivers')),
                    const SizedBox(height: SpacingTokens.sm),
                    _buildDriverStrip(f),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TeamCrest(teamName: f.homeTeam, size: 22),
                const SizedBox(width: SpacingTokens.xs),
                Flexible(
                  child: Text(homeDisplay,
                      style: TypographyTokens.body.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: ColorTokens.textPrimary),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(awayDisplay,
                      style: TypographyTokens.body.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: ColorTokens.textPrimary),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: SpacingTokens.xs),
                TeamCrest(teamName: f.awayTeam, size: 22),
              ],
            ),
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
                // Iteration N polish: when neither team is U Cluj, the home
                // value keeps the strong primary tone and the away value
                // drops to 65% alpha. Same hue, different weight, so the eye
                // anchors on the home side first instead of seeing twins.
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
                      color: !isUCLujHome
                          ? uclColor
                          : ColorTokens.textPrimary.withValues(alpha: 0.65),
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
    // Prefer the backend-assigned formation key (so the pitch slot order
    // matches the official-position assignment); fall back to the coarse shape.
    final backendFormation = isShowingHome ? d.homeFormation : d.awayFormation;
    final formation =
        backendFormation.isNotEmpty ? backendFormation : _inferFormation(starters);

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
              ? _ActualLineupPitchPanel(starters: starters, formation: formation)
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
        // Amber goalkeeper marker; the named warning token replaces the old
        // hardcoded literal so it tracks the palette.
        return ColorTokens.warning;
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
  //
  // PR 12 hierarchy shift: the headline probability is the screen's anchor,
  // so the percentage is promoted to a 72 px hero glyph and the surrounding
  // chrome is trimmed. The dual Win + Rest pills collapsed into a single
  // verdict tag (dominant / favoured / contested / risky), because telling a
  // coach "win = 65% and rest = 35%" twice is just visual noise. A vertical
  // tone-coded rail on the left replaces the appended chart and a thin top
  // accent line keeps the block in the same editorial rhythm as the
  // drivers strip and the diagnostic pod below.

  Widget _buildMLBlock(WeekFixture f, double uclProb) {
    final winPct = (uclProb * 100).round();
    final col = uclProb >= 0.55
        ? ColorTokens.positive
        : uclProb >= 0.40
            ? ColorTokens.accent
            : ColorTokens.negative;
    final verdictKey = uclProb >= 0.65
        ? 'sheet.verdictDominant'
        : uclProb >= 0.50
            ? 'sheet.verdictFavoured'
            : uclProb >= 0.35
                ? 'sheet.verdictContested'
                : 'sheet.verdictRisky';

    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.surfaceLow,
        border: Border(
          top: BorderSide(color: col.withValues(alpha: 0.8), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
          SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.md),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tone-coded vertical rail. Replaces the old _ProbBar; reads as
            // a colour accent first and a magnitude cue second (the rail
            // height tracks the probability via the inner fill below).
            SizedBox(
              width: 4,
              child: Column(
                children: [
                  Expanded(
                    flex: (uclProb * 100).round().clamp(1, 99),
                    child: Container(color: col),
                  ),
                  Expanded(
                    flex: (100 - (uclProb * 100).round()).clamp(1, 99),
                    child: Container(color: ColorTokens.surfaceHigh),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SpacingTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.t('sheet.winChanceUcluj'),
                      style: TypographyTokens.sectionLabel
                          .copyWith(color: ColorTokens.textMuted, fontSize: 10)),
                  const SizedBox(height: SpacingTokens.xs),
                  Text('$winPct%',
                      style: TypographyTokens.displayHero
                          .copyWith(color: col, fontSize: 72, height: 1.0)),
                  const SizedBox(height: SpacingTokens.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.sm, vertical: 3),
                    color: col.withValues(alpha: 0.14),
                    child: Text(L10n.t(verdictKey),
                        style: TypographyTokens.sectionLabel
                            .copyWith(color: col, fontSize: 10)),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(L10n.t('sheet.modelCaption'),
                      style: TypographyTokens.sectionLabel.copyWith(
                          fontSize: 8, color: ColorTokens.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Drivers + risks chip strip ───────────────────────────────────────────
  //
  // One horizontal strip combines positive drivers (▲ green) and risks
  // (▼ red), in that order, so the eye scans tone-tagged chips left to
  // right and weighs them against the headline probability above. Each
  // chip is a compact tone-rule + sign + label + importance percent. The
  // strip scrolls horizontally so it never wraps into the layout below.

  Widget _buildDriverStrip(WeekFixture f) {
    final chips = <Widget>[];
    for (final d in f.keyDrivers) {
      chips.add(_buildDriverChip(d, isRisk: false));
    }
    for (final r in f.topRisks) {
      chips.add(_buildDriverChip(r, isRisk: true));
    }
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: SpacingTokens.xs),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Widget _buildDriverChip(WeekFixtureDriver d, {required bool isRisk}) {
    final col = isRisk ? ColorTokens.negative : ColorTokens.positive;
    final sign = isRisk ? '▼' : '▲';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
      decoration: BoxDecoration(
        color: ColorTokens.surfaceLow,
        border: Border(
          top: BorderSide(color: col, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sign,
                  style: TypographyTokens.sectionLabel
                      .copyWith(color: col, fontSize: 10)),
              const SizedBox(width: 4),
              Text(
                '${(d.importance * 100).toStringAsFixed(0)}%',
                style: TypographyTokens.body.copyWith(
                    color: col, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            d.label.toUpperCase(),
            style: TypographyTokens.sectionLabel
                .copyWith(color: ColorTokens.textPrimary, fontSize: 9),
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
  const _ActualLineupPitchPanel({required this.starters, this.formation = ''});
  final List<MatchPlayer> starters;
  final String formation;

  List<double> _distributedXs(int count) {
    if (count <= 1) return const [0.50];
    const left = 0.18;
    const right = 0.82;
    final step = (right - left) / (count - 1);
    return List<double>.generate(count, (i) => left + step * i);
  }

  List<({MatchPlayer player, Offset offset, String? label})> _placements() {
    // Preferred path: place by the official slot index the backend assigned,
    // using the shared formation_slots geometry (same order the backend used).
    final slots = kFormationSlots[formation];
    if (slots != null &&
        starters.isNotEmpty &&
        starters.every((p) => p.slotIndex >= 0 && p.slotIndex < slots.length)) {
      return [
        for (final p in starters)
          (
            player: p,
            offset: Offset(slots[p.slotIndex].x, slots[p.slotIndex].y),
            label: slots[p.slotIndex].label,
          ),
      ];
    }

    // ── Legacy coarse-row fallback ───────────────────────────────────────
    final gk = starters.where((p) => p.position == 'G').toList();
    final defs = starters.where((p) => p.position == 'D').toList();
    final mids = starters.where((p) => p.position == 'M').toList();
    final fwds = starters.where((p) => p.position == 'F').toList();

    final result = <({MatchPlayer player, Offset offset, String? label})>[];

    if (gk.isNotEmpty) {
      result.add((player: gk.first, offset: const Offset(0.50, 0.90), label: null));
    }

    void addRow(List<MatchPlayer> players, double y) {
      if (players.isEmpty) return;
      final xs = _distributedXs(players.length);
      for (var i = 0; i < players.length; i++) {
        result.add((player: players[i], offset: Offset(xs[i], y), label: null));
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
    final tokens = context.colors;

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
              CustomPaint(
                painter: FifaPitchPainter(
                  surface: tokens.pitchSurface,
                  line: tokens.pitchLine,
                  halo: tokens.pitchHalo,
                  accent: tokens.accent,
                  border: tokens.chromeDeep,
                ),
              ),
              for (final p in placements)
                Positioned(
                  left: p.offset.dx * c.maxWidth - chipSize / 2,
                  top: p.offset.dy * c.maxHeight - chipSize / 2,
                  width: chipSize,
                  height: chipSize,
                  child: _ActualPlayerChip(
                      player: p.player, chipSize: chipSize, positionLabel: p.label),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActualPlayerChip extends StatelessWidget {
  const _ActualPlayerChip({
    required this.player,
    required this.chipSize,
    this.positionLabel,
  });
  final MatchPlayer player;
  final double chipSize;

  /// Official slot label (RB, RCB, DM, ...) when placed by slot index; falls
  /// back to the player's official position then the coarse code.
  final String? positionLabel;

  /// Map a one-letter position code to the matching role colour. Reads from
  /// ``AppColorTokens`` so the Match Stats pitch agrees with the Match
  /// Preview pitch and so GK does not silently disagree across the app.
  Color _roleColor(AppColorTokens c) {
    switch (player.position.toUpperCase()) {
      case 'G':
        return c.roleGoalkeeper;
      case 'D':
        return c.roleDefender;
      case 'M':
        return c.roleMidfielder;
      case 'F':
        return c.roleForward;
      default:
        return c.textMuted;
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
    final c = context.colors;
    final posColor = _roleColor(c);
    final hasGoal = player.goalsScored > 0;
    final hasYellow = player.yellowCards > 0;
    final hasRed = player.redCards > 0;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: posColor.withValues(alpha: 0.7), width: 1.5),
      ),
      padding: EdgeInsets.all(chipSize * 0.06),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Official position badge (RB, RCB, DM, ...), falling back to the
          // player's official position, then the coarse one-letter code.
          Text(
            (positionLabel != null && positionLabel!.isNotEmpty)
                ? positionLabel!
                : (player.officialPosition.isNotEmpty
                    ? player.officialPosition
                    : (player.position.isNotEmpty ? player.position : '?')),
            style: TypographyTokens.body.copyWith(
              fontSize: chipSize * 0.12,
              color: posColor,
            ),
          ),
          // Jersey number (prominent)
          Text(
            player.jerseyNumber != null ? '${player.jerseyNumber}' : '—',
            style: TypographyTokens.headline.copyWith(
              fontSize: chipSize * 0.22,
              color: posColor,
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
              color: c.textPrimary,
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

/// One column of the diagnostic before/after pod. Renders an uppercase
/// label above a hero-scaled probability glyph in the supplied tone, so
/// the baseline and the optimised value sit on the same baseline and
/// can be compared at a glance.
class _ProbColumn extends StatelessWidget {
  const _ProbColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TypographyTokens.sectionLabel
                .copyWith(color: ColorTokens.textMuted, fontSize: 9)),
        const SizedBox(height: 4),
        Text(value,
            style: TypographyTokens.displayHero
                .copyWith(color: valueColor, fontSize: 36, height: 1.0)),
      ],
    );
  }
}

// _OutcomePill and _ProbBar were removed in the PR 12 hierarchy shift.
// The dual Win + Rest pills collapsed into a single verdict tag and the
// vertical bar moved into _buildMLBlock as an inline tone-coded rail.
