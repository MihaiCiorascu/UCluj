import 'package:flutter/material.dart';

import '../../../core/constants/formation_slots.dart';
import '../../../core/constants/supported_formations.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/widgets/team_crest.dart';
import '../../../core/widgets/player_photo_avatar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/theme/shape_tokens.dart';
import '../../../core/primitives/haptics.dart';
import '../../../core/primitives/signed_bar.dart';
import '../../../core/primitives/win_probability_arc.dart';
import '../../../core/primitives/skeleton_box.dart';
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
    final c = context.colors;
    final baselinePct = '${(prescription.baselineProb * 100).round()}%';
    final bestPct = '${(prescription.bestProb * 100).round()}%';
    final upliftPct = '+${(prescription.improvement * 100).round()}%';
    final recs = prescription.recommendations;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.card,
        border: Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header label ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.md,
                SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: c.highlight, size: 15),
                const SizedBox(width: SpacingTokens.xs),
                Text(L10n.t('sheet.optimalPlan'),
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: c.highlight)),
              ],
            ),
          ),

          // ── Baseline -> optimised, with the uplift as the single reserved
          //    amber number on the screen ─────────────────────────────────
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
                    valueColor: c.textMuted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_forward, color: c.textMuted, size: 16),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: SpacingTokens.sm, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.highlightSubtle,
                          borderRadius: ShapeTokens.chip,
                        ),
                        child: Text(upliftPct,
                            style: TypographyTokens.statValue
                                .copyWith(color: c.highlight, fontSize: 18)),
                      ),
                      const SizedBox(height: 4),
                      Text(L10n.t('sheet.upliftLabel'),
                          style: TypographyTokens.sectionLabel
                              .copyWith(color: c.textMuted, fontSize: 8)),
                    ],
                  ),
                ),
                Expanded(
                  child: _ProbColumn(
                    label: L10n.t('sheet.optimisedLabel'),
                    value: bestPct,
                    valueColor: c.positive,
                  ),
                ),
              ],
            ),
          ),

          // ── Tactical-levers section ──────────────────────────────────────
          if (recs.isNotEmpty) ...[
            Divider(height: 1, color: c.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.md,
                  SpacingTokens.md, SpacingTokens.md, SpacingTokens.xs),
              child: Row(
                children: [
                  Container(width: 2, height: 12, color: c.primary),
                  const SizedBox(width: SpacingTokens.xs),
                  Text(L10n.t('sheet.tacticalLevers'),
                      style: TypographyTokens.sectionLabel
                          .copyWith(color: c.textMuted)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SpacingTokens.md,
                  SpacingTokens.xs, SpacingTokens.md, SpacingTokens.md),
              child: Wrap(
                spacing: SpacingTokens.sm,
                runSpacing: SpacingTokens.sm,
                children: recs.map((r) => _buildRecChip(context, r)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecChip(BuildContext context, PrescriptionRec rec) {
    final c = context.colors;
    final isUp = rec.direction == 'up';
    final color = isUp ? c.positive : c.primary;
    final unit = rec.unit;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: ShapeTokens.control,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rec.label,
              style: TypographyTokens.meta.copyWith(color: c.textMuted)),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isUp ? Icons.trending_up : Icons.trending_down,
                  size: 14, color: color),
              const SizedBox(width: 6),
              Text('${rec.current}$unit',
                  style: TypographyTokens.mono.copyWith(color: c.textMuted)),
              Icon(Icons.arrow_right_alt, size: 16, color: c.textMuted),
              Text('${rec.target}$unit',
                  style: TypographyTokens.mono.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w700)),
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
    final c = context.colors;
    final screenH = MediaQuery.of(context).size.height;
    final uclProb = f.homeWinProbability;

    return Container(
      height: screenH * 0.92,
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: ShapeTokens.sheetTop,
        boxShadow: ShapeTokens.e3(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm, bottom: 2),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textMuted.withValues(alpha: 0.5),
                  borderRadius: ShapeTokens.chip,
                ),
              ),
            ),
          ),
          _buildHeader(f),
          Divider(height: 1, color: c.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SpacingTokens.md),
              children: [
                _buildMatchStatus(f),
                const SizedBox(height: SpacingTokens.xl),

                if (f.isCompleted) ...[
                  // Official stats from Sportradar
                  if (_loadingDetails)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: SpacingTokens.md),
                      child: Column(
                        children: const [
                          SkeletonBox(width: double.infinity, height: 18),
                          SizedBox(height: SpacingTokens.sm),
                          SkeletonBox(
                              width: double.infinity, height: 120, radius: 10),
                          SizedBox(height: SpacingTokens.sm),
                          SkeletonBox(
                              width: double.infinity, height: 200, radius: 10),
                        ],
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
                  // ML prediction — only for upcoming. For U Cluj fixtures the
                  // single U-Cluj-framed arc gauge is correct; for every other
                  // fixture the home/away framing is what matters, so we show a
                  // neutral two-sided per-team split instead.
                  if (uclProb != null) ...[
                    if (f.involvesUCluj)
                      _buildMLBlock(f, uclProb)
                    else
                      _buildTwoSidedWinProbability(f, uclProb),
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
                      color: context.colors.surfaceLow,
                      padding: const EdgeInsets.all(SpacingTokens.md),
                      child: Text(f.narrative,
                          style: TypographyTokens.body
                              .copyWith(color: context.colors.textMuted, fontSize: 13)),
                    ),
                    const SizedBox(height: SpacingTokens.xl),
                  ],

                  // XI only for upcoming U Cluj matches
                  if (f.involvesUCluj) _buildXiSection(),

                  const SizedBox(height: SpacingTokens.md),
                  Text(L10n.t('sheet.modelFooter'),
                      style: TypographyTokens.meta.copyWith(color: c.textMuted)),
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
    final c = context.colors;
    final homeDisplay = f.homeTeam.replaceAll('Universitatea Cluj', 'U Cluj');
    final awayDisplay = f.awayTeam.replaceAll('Universitatea Cluj', 'U Cluj');

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.xs,
          SpacingTokens.md, SpacingTokens.md),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TeamCrest(teamName: f.homeTeam, size: 26),
                const SizedBox(width: SpacingTokens.xs),
                Flexible(
                  child: Text(homeDisplay,
                      style: TypographyTokens.cardTitle
                          .copyWith(color: c.textPrimary),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
            child: Text('vs',
                style: TypographyTokens.meta.copyWith(color: c.textMuted)),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(awayDisplay,
                      style: TypographyTokens.cardTitle
                          .copyWith(color: c.textPrimary),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: SpacingTokens.xs),
                TeamCrest(teamName: f.awayTeam, size: 26),
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
      if (myScore > theirScore) { result = L10n.t('sheet.win'); col = context.colors.positive; }
      else if (myScore < theirScore) { result = L10n.t('sheet.loss'); col = context.colors.negative; }
      else { result = L10n.t('sheet.draw'); col = context.colors.accent; }

      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('${f.homeScore}',
                  style: TypographyTokens.statLarge.copyWith(
                      fontSize: 60, color: context.colors.textPrimary)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
                child: Text('-',
                    style: TypographyTokens.statLarge.copyWith(
                        fontSize: 30, color: context.colors.textMuted)),
              ),
              Text('${f.awayScore}',
                  style: TypographyTokens.statLarge.copyWith(
                      fontSize: 60, color: context.colors.textPrimary)),
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
      color: context.colors.surfaceLow,
      padding: const EdgeInsets.all(SpacingTokens.md),
      child: Row(
        children: [
          Icon(Icons.schedule, color: context.colors.accent, size: 14),
          const SizedBox(width: SpacingTokens.xs),
          Text(f.displayDate,
              style: TypographyTokens.sectionLabel.copyWith(color: context.colors.accent)),
          if (f.venue != null) ...[
            Text('  ·  ${f.venue}',
                style: TypographyTokens.sectionLabel
                    .copyWith(color: context.colors.textMuted)),
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
      color: context.colors.surfaceLow,
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
                    color: f.isUCLujHome ? context.colors.accent : context.colors.textMuted,
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
                    color: !f.isUCLujHome ? context.colors.accent : context.colors.textMuted,
                    fontSize: 9,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Divider(height: 1, color: context.colors.divider),
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
        ? (uclVal >= oppVal ? context.colors.positive : context.colors.negative)
        : (uclVal <= oppVal ? context.colors.positive : context.colors.negative);

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
                      color: isUCLujHome ? uclColor : context.colors.textPrimary,
                    )),
              ),
              Expanded(
                child: Center(
                  child: Text(label,
                      style: TypographyTokens.sectionLabel
                          .copyWith(fontSize: 8, color: context.colors.textMuted)),
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
                          : context.colors.textPrimary.withValues(alpha: 0.65),
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
                        : context.colors.textMuted.withValues(alpha: 0.5),
                  ),
                ),
                Expanded(
                  flex: ((1 - homeRatio) * 100).round(),
                  child: Container(
                    height: 4,
                    color: !isUCLujHome
                        ? uclColor
                        : context.colors.textMuted.withValues(alpha: 0.5),
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
            Container(width: 1, color: context.colors.divider),
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
                color: isUCluj ? context.colors.accent : context.colors.textMuted,
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
            color: context.colors.surfaceLow,
            padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md, vertical: 4),
            child: Text(L10n.t('sheet.subs'),
                style: TypographyTokens.sectionLabel
                    .copyWith(fontSize: 8, color: context.colors.textMuted)),
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
          color: selected ? context.colors.surfaceLow : context.colors.surfaceHigh,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isUCluj) ...[
                Icon(Icons.shield, color: context.colors.accent, size: 10),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  name,
                  style: TypographyTokens.sectionLabel.copyWith(
                    fontSize: 9,
                    color: selected
                        ? (isUCluj ? context.colors.accent : context.colors.textPrimary)
                        : context.colors.textMuted,
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
          ? context.colors.surface
          : context.colors.surfaceLow.withValues(alpha: 0.6),
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
                color: context.colors.textMuted,
              ),
            ),
          ),
          // Headshot (initials when unmatched), ringed in the role colour.
          PlayerPhotoAvatar(
            photoUrl: p.photoUrl,
            name: p.name,
            ringColor: posColor,
            size: 28,
          ),
          const SizedBox(width: SpacingTokens.xs),
          // Name
          Expanded(
            child: Text(
              p.name,
              style: TypographyTokens.body.copyWith(
                fontSize: 12,
                fontWeight: isSub ? FontWeight.w400 : FontWeight.w600,
                color: isSub ? context.colors.textMuted : context.colors.textPrimary,
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
      badges.add(_badge('⚽ ${p.goalsScored}', context.colors.positive));
    }
    if (p.assists > 0) {
      badges.add(_badge('A${p.assists}', context.colors.accent));
    }
    if (p.yellowCards > 0) {
      badges.add(_badge('▪', const Color(0xFFFFD700)));
    }
    if (p.redCards > 0) {
      badges.add(_badge('▪', context.colors.negative));
    }
    if (p.minutesPlayed != null && p.minutesPlayed! < 90 && !p.isStarter) {
      badges.add(_badge("${p.minutesPlayed}'", context.colors.textMuted));
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
        return context.colors.roleGoalkeeper;
      case 'D':
        return context.colors.positive;
      case 'M':
        return context.colors.accent;
      case 'F':
        return context.colors.negative;
      default:
        return context.colors.textMuted;
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
    final c = context.colors;
    final col = uclProb >= 0.55
        ? c.positive
        : uclProb >= 0.40
            ? c.primary
            : c.negative;
    final verdictKey = uclProb >= 0.65
        ? 'sheet.verdictDominant'
        : uclProb >= 0.50
            ? 'sheet.verdictFavoured'
            : uclProb >= 0.35
                ? 'sheet.verdictContested'
                : 'sheet.verdictRisky';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.card,
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: SpacingTokens.lg),
      child: Column(
        children: [
          WinProbabilityArc(
            probability: uclProb,
            color: col,
            label: L10n.t('sheet.winChance'),
            size: 184,
          ),
          const SizedBox(height: SpacingTokens.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md, vertical: 6),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.14),
              borderRadius: ShapeTokens.chip,
            ),
            child: Text(L10n.t(verdictKey),
                style: TypographyTokens.buttonLabel.copyWith(color: col)),
          ),
        ],
      ),
    );
  }

  // ── Two-sided win probability (upcoming, non-U-Cluj) ─────────────────────
  //
  // For neutral fixtures the U-Cluj arc framing is wrong: neither side is the
  // tracked team, so the model's home-win probability is shown as an explicit
  // home-vs-away split. `homeWinProbability` is a 0..1 value (same scale the
  // arc consumes); the away share is its complement. The two percentages sit
  // on a single flat split bar whose proportions track the split, with the
  // favoured (higher) side carried in the positive green token and the other
  // in the muted track tone. No "U CLUJ" text appears anywhere here.

  Widget _buildTwoSidedWinProbability(WeekFixture f, double homeProb) {
    final c = context.colors;
    final home = homeProb.clamp(0.0, 1.0);
    final away = 1.0 - home;
    final homePct = (home * 100).round();
    final awayPct = (away * 100).round();
    final homeFavoured = home >= away;

    final homeName = f.homeTeam.replaceAll('Universitatea Cluj', 'U Cluj');
    final awayName = f.awayTeam.replaceAll('Universitatea Cluj', 'U Cluj');

    final homeColor = homeFavoured ? c.positive : c.textMuted;
    final awayColor = homeFavoured ? c.textMuted : c.positive;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.card,
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(L10n.t('sheet.matchWinProbability'),
                style: TypographyTokens.sectionLabel
                    .copyWith(color: c.textMuted)),
          ),
          const SizedBox(height: SpacingTokens.md),

          // ── Team names + percentages, favoured side emphasised ───────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TwoSidedSide(
                  name: homeName,
                  pct: homePct,
                  color: homeColor,
                  favoured: homeFavoured,
                  alignEnd: false,
                ),
              ),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: _TwoSidedSide(
                  name: awayName,
                  pct: awayPct,
                  color: awayColor,
                  favoured: !homeFavoured,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),

          // ── Flat split bar, proportional to the two probabilities ────────
          SizedBox(
            height: 6,
            child: Row(
              children: [
                Expanded(
                  flex: (home * 1000).round().clamp(1, 1000),
                  child: Container(color: homeColor),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: (away * 1000).round().clamp(1, 1000),
                  child: Container(color: awayColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Drivers + risks (signed bars) ────────────────────────────────────────
  //
  // Top positive drivers (green, growing right) and top risks (red, growing
  // left) share a center-origin baseline so direction and magnitude read in
  // one glance, with the importance percentage right-aligned. Capped at the
  // three strongest drivers and two strongest risks to keep the block calm.

  Widget _buildDriverStrip(WeekFixture f) {
    final c = context.colors;
    final drivers = f.keyDrivers.take(3).toList();
    final risks = f.topRisks.take(2).toList();
    final maxImp = [...drivers, ...risks].fold<double>(
        0, (m, d) => d.importance.abs() > m ? d.importance.abs() : m);
    String pct(WeekFixtureDriver d) => '${(d.importance * 100).round()}%';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.card,
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
      child: Column(
        children: [
          for (final d in drivers)
            SignedBar(
              label: d.label,
              magnitude: d.importance.abs(),
              maxMagnitude: maxImp,
              positive: true,
              valueLabel: pct(d),
            ),
          for (final r in risks)
            SignedBar(
              label: r.label,
              magnitude: r.importance.abs(),
              maxMagnitude: maxImp,
              positive: false,
              valueLabel: pct(r),
            ),
        ],
      ),
    );
  }

  // ── XI section (upcoming U Cluj) ─────────────────────────────────────────

  Widget _buildXiSection() {
    if (_loadingXi) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(L10n.t('sheet.recommendedXi')),
          const SizedBox(height: SpacingTokens.sm),
          const AspectRatio(
            aspectRatio: 4 / 5,
            child: SkeletonBox(
                width: double.infinity,
                height: 320,
                radius: ShapeTokens.radiusCard),
          ),
        ],
      );
    }
    if (_xiError != null) {
      return Container(
        color: context.colors.surfaceLow,
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Text('${L10n.t('sheet.xiUnavailable')}: $_xiError',
            style: TypographyTokens.body
                .copyWith(color: context.colors.textMuted, fontSize: 12)),
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
                dropdownColor: context.colors.surfaceLow,
                style: TypographyTokens.body
                    .copyWith(color: context.colors.textPrimary, fontSize: 12),
                icon: Icon(Icons.keyboard_arrow_down,
                    color: context.colors.accent, size: 16),
                onChanged: (v) {
                  if (v != null && v != _formation) {
                    AppHaptics.selection();
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
          Container(width: 2, height: 12, color: context.colors.accent),
          const SizedBox(width: SpacingTokens.xs),
          Text(text,
              style: TypographyTokens.sectionLabel
                  .copyWith(color: context.colors.textMuted)),
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
      padding: EdgeInsets.all(chipSize * 0.05),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Headshot ringed in the role colour, with the shirt number badged
          // on its corner. Falls back to initials when no photo matched.
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomRight,
            children: [
              PlayerPhotoAvatar(
                photoUrl: player.photoUrl,
                name: _lastName,
                ringColor: posColor,
                size: chipSize * 0.48,
              ),
              if (player.jerseyNumber != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  color: posColor,
                  child: Text(
                    '${player.jerseyNumber}',
                    style: TypographyTokens.sectionLabel.copyWith(
                      fontSize: chipSize * 0.12,
                      color: c.onPrimary,
                      height: 1.0,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: chipSize * 0.04),
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
          if (hasGoal || hasYellow || hasRed)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasGoal)
                  Text('⚽', style: TextStyle(fontSize: chipSize * 0.13)),
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
                    color: c.negative,
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
                .copyWith(color: context.colors.textMuted, fontSize: 9)),
        const SizedBox(height: 6),
        Text(value,
            style: TypographyTokens.statLarge
                .copyWith(color: valueColor, fontSize: 34)),
      ],
    );
  }
}

/// One side of the neutral two-sided win-probability split (non-U-Cluj
/// fixtures). Renders a team name above its win percentage, with the favoured
/// side carried in the supplied positive tone and a heavier weight so the eye
/// anchors on the more likely winner. `alignEnd` mirrors the layout for the
/// away side so the two halves read symmetrically toward the centre split.
class _TwoSidedSide extends StatelessWidget {
  const _TwoSidedSide({
    required this.name,
    required this.pct,
    required this.color,
    required this.favoured,
    required this.alignEnd,
  });

  final String name;
  final int pct;
  final Color color;
  final bool favoured;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: TypographyTokens.sectionLabel.copyWith(
            color: favoured ? c.textPrimary : c.textMuted,
            fontSize: 9,
          ),
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          '$pct%',
          style: TypographyTokens.statLarge.copyWith(
            color: color,
            fontSize: 34,
            fontWeight: favoured ? FontWeight.w800 : FontWeight.w700,
          ),
          textAlign: textAlign,
        ),
      ],
    );
  }
}

// _OutcomePill and _ProbBar were removed in the PR 12 hierarchy shift.
// The dual Win + Rest pills collapsed into a single verdict tag and the
// vertical bar moved into _buildMLBlock as an inline tone-coded rail.
