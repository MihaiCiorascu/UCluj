import 'package:flutter/material.dart';

import '../../../core/constants/formation_slots.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/widgets/team_crest.dart';
import '../../../core/widgets/player_photo_avatar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/theme/shape_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
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

// ── Player-grade helpers ────────────────────────────────────────────────────
//
// Completed-match player grades arrive on a 0-10 scale (one decimal). The
// scale is position-fair, so a typical appearance lands near 6.x. We band the
// colour the same way the upcoming-XI percentile rating does (strong / neutral
// / weak), so the completed pitch reads in the same Stoic-Analyst language as
// the predicted pitch while staying accent-forward for the headline number.

/// Tone for a 0-10 match grade: green for a strong showing, cobalt accent for
/// a solid-to-average one, red for a weak one. Mirrors the band thresholds the
/// FIFA rating bars use, scaled to the 0-10 grade range.
Color gradeColor(double grade, AppColorTokens c) {
  if (grade >= 7.0) return c.positive;
  if (grade >= 6.0) return c.accent;
  return c.negative;
}

/// One-decimal display string for a grade (e.g. 7.6).
String gradeLabel(double grade) => grade.toStringAsFixed(1);

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
  // The REQUESTED formation: the "auto" sentinel (default) lets the optimiser
  // score the nine curated shapes once and pick the highest-objective one;
  // otherwise one curated key forces that shape. The pitch and the sheet's own
  // label always read from the RESOLVED formation the backend reports, never
  // from this requested value.
  String _formation = kFormationAuto;
  // The opponent short label for the loaded preview, kept so the interactive
  // pitch can re-request the flexible-XI POST when staff edit the lineup.
  String? _xiOpponent;

  // Lineup team selector (completed matches): 0=home, 1=away
  int _lineupTeamIndex = 0;

  // Match details (completed matches)
  MatchDetailsRepository? _detailsRepo;
  bool _loadingDetails = false;
  MatchDetails? _matchDetails;

  // Selector entries: AUTO first, then the nine curated shapes (the only keys
  // the optimiser resolves to; the backend coerces anything else to "auto").
  static const _formations = [kFormationAuto, ...kCuratedFormations];

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
      // Use the flexible-XI POST so "auto" (the default) lets the optimiser
      // score the nine curated shapes and return the best one; an explicit
      // curated key forces that shape instead. The panel renders from the
      // RESOLVED formation the response carries, never from [_formation].
      final preview = await _xiRepo.postMatchPreview(
        opponentName: opponent,
        formation: _formation,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _xiOpponent = opponent;
          _loadingXi = false;
        });
      }
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
                  // single U-Cluj-framed arc gauge reads a correct P(U Cluj win)
                  // (the backend now runs the binary model with U Cluj as the
                  // home subject, whether they play home or away). For every
                  // other fixture the home/away framing is what matters, so we
                  // show a neutral three-way split (home win / draw / away win)
                  // from the per-team odds the backend attaches there instead.
                  if (f.involvesUCluj) ...[
                    if (uclProb != null) ...[
                      _buildMLBlock(f, uclProb),
                      const SizedBox(height: SpacingTokens.xl),
                    ],
                  ] else if (f.homeTeamWinProb != null ||
                      f.awayTeamWinProb != null) ...[
                    _buildThreeWayWinProbability(f),
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
                  // The U-Cluj-centric AI key drivers + tactical diagnostic are
                  // meaningful only for the tracked team. On non-U-Cluj fixtures
                  // the backend nulls these (and the new 3-way odds carry the
                  // story instead), so both blocks are gated behind involvesUCluj.
                  if (f.involvesUCluj) ...[
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
    final homeDisplay = f.homeTeam.replaceAll('Universitatea Cluj', 'U Cluj');
    final awayDisplay = f.awayTeam.replaceAll('Universitatea Cluj', 'U Cluj');

    return Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.sm,
          SpacingTokens.md, SpacingTokens.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _headerTeam(
              teamName: f.homeTeam,
              display: homeDisplay,
              isUCluj: f.isUCLujHome,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('vs',
                style: TypographyTokens.meta
                    .copyWith(color: context.colors.textMuted)),
          ),
          Expanded(
            child: _headerTeam(
              teamName: f.awayTeam,
              display: awayDisplay,
              isUCluj: !f.isUCLujHome && f.involvesUCluj,
            ),
          ),
        ],
      ),
    );
  }

  /// One side of the editorial header: a larger crest stacked over the team
  /// name (cardTitle). The tracked team's name is carried in the cobalt accent
  /// so the eye anchors on U Cluj first.
  Widget _headerTeam({
    required String teamName,
    required String display,
    required bool isUCluj,
  }) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamCrest(teamName: teamName, size: 40),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          display,
          style: TypographyTokens.cardTitle.copyWith(
            color: isUCluj ? c.accent : c.textPrimary,
            fontWeight: isUCluj ? FontWeight.w700 : FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMatchStatus(WeekFixture f) {
    final c = context.colors;
    if (f.isCompleted) {
      final isHome = f.isUCLujHome;
      final myScore = isHome ? f.homeScore! : f.awayScore!;
      final theirScore = isHome ? f.awayScore! : f.homeScore!;
      String result;
      Color col;
      if (myScore > theirScore) {
        result = L10n.t('sheet.win');
        col = c.positive;
      } else if (myScore < theirScore) {
        result = L10n.t('sheet.loss');
        col = c.negative;
      } else {
        result = L10n.t('sheet.draw');
        col = c.accent;
      }

      // From the U-Cluj perspective each scoreline glyph is tinted by whether
      // it belongs to the tracked team: the tracked side keeps the strong
      // primary tone, the opponent drops to the muted tone, so the result
      // reads even before the pill below it.
      final homeIsUCluj = f.isUCLujHome;
      final neutral = !f.involvesUCluj;

      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${f.homeScore}',
                style: TypographyTokens.displayHero.copyWith(
                  fontSize: 64,
                  color: neutral || homeIsUCluj
                      ? c.textPrimary
                      : c.textMuted,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
                child: Text(
                  '–',
                  style: TypographyTokens.statLarge
                      .copyWith(fontSize: 28, color: c.textMuted),
                ),
              ),
              Text(
                '${f.awayScore}',
                style: TypographyTokens.displayHero.copyWith(
                  fontSize: 64,
                  color: neutral || !homeIsUCluj
                      ? c.textPrimary
                      : c.textMuted,
                ),
              ),
            ],
          ),
          if (f.involvesUCluj) ...[
            const SizedBox(height: SpacingTokens.sm),
            Container(
              color: col.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, color: col),
                  const SizedBox(width: SpacingTokens.xs),
                  Text(
                    result,
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: col, letterSpacing: 1.6),
                  ),
                ],
              ),
            ),
          ],
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
          // Header row: crest + team name on each side, the tracked team
          // carried in the cobalt accent so the eye anchors on U Cluj first.
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    TeamCrest(teamName: f.homeTeam, size: 18),
                    const SizedBox(width: SpacingTokens.xs),
                    Flexible(
                      child: Text(
                        f.homeTeam
                            .replaceAll('Universitatea Cluj', 'U CLUJ')
                            .toUpperCase(),
                        style: TypographyTokens.sectionLabel.copyWith(
                          color: f.involvesUCluj && f.isUCLujHome
                              ? context.colors.accent
                              : context.colors.textPrimary,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        f.awayTeam
                            .replaceAll('Universitatea Cluj', 'U CLUJ')
                            .toUpperCase(),
                        style: TypographyTokens.sectionLabel.copyWith(
                          color: f.involvesUCluj && !f.isUCLujHome
                              ? context.colors.accent
                              : context.colors.textPrimary,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: SpacingTokens.xs),
                    TeamCrest(teamName: f.awayTeam, size: 18),
                  ],
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
    final c = context.colors;
    final total = homeVal + awayVal;
    final homeRatio = total > 0 ? (homeVal / total).clamp(0.0, 1.0) : 0.5;

    // Which side leads this stat (respecting whether higher or lower is the
    // better outcome). The leading side keeps its team tone; the trailing side
    // reads in the muted track tone so the comparison resolves at a glance.
    final homeLeads = higherIsBetter ? homeVal >= awayVal : homeVal <= awayVal;
    final awayLeads = higherIsBetter ? awayVal >= homeVal : awayVal <= homeVal;
    final tie = homeVal == awayVal;

    // Team tones: the tracked side carries cobalt, the opponent steel, so the
    // bar speaks the same role language as the rest of the sheet.
    final homeTone = isUCLujHome ? c.accent : c.roleDefender;
    final awayTone = !isUCLujHome ? c.accent : c.roleDefender;
    final muted = c.textMuted.withValues(alpha: 0.35);

    final homeBar = tie ? muted : (homeLeads ? homeTone : muted);
    final awayBar = tie ? muted : (awayLeads ? awayTone : muted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Column(
        children: [
          // home value (left) | centred label | away value (right)
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  homeStr,
                  style: TypographyTokens.statValue.copyWith(
                    fontSize: 15,
                    color: tie || homeLeads ? c.textPrimary : c.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TypographyTokens.sectionLabel.copyWith(
                        fontSize: 9, color: c.textMuted, letterSpacing: 1.2),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  awayStr,
                  style: TypographyTokens.statValue.copyWith(
                    fontSize: 15,
                    color: tie || awayLeads ? c.textPrimary : c.textMuted,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          // One center-split comparison bar on a tonal track: the home segment
          // fills from the left and the away segment from the right, meeting at
          // the proportional split point. The leading side carries its team
          // tone, the trailing side stays muted.
          SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: (homeRatio * 1000).round().clamp(1, 1000),
                  child: Container(
                    color: homeBar,
                    margin: const EdgeInsets.only(right: 1),
                  ),
                ),
                Expanded(
                  flex: ((1 - homeRatio) * 1000).round().clamp(1, 1000),
                  child: Container(
                    color: awayBar,
                    margin: const EdgeInsets.only(left: 1),
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

    // Which side is the tracked team. Each side is U Cluj only when the fixture
    // actually involves U Cluj AND that side is the U-Cluj side — so on a
    // neutral fixture neither tab nor the formation label takes the accent, and
    // the away tab correctly takes it when U Cluj plays away.
    final homeIsUCluj = f.involvesUCluj && f.isUCLujHome;
    final awayIsUCluj = f.involvesUCluj && !f.isUCLujHome;
    final isUCluj = isShowingHome ? homeIsUCluj : awayIsUCluj;

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
            _teamTab(homeDisplay, homeIsUCluj, _lineupTeamIndex == 0,
                () => setState(() => _lineupTeamIndex = 0)),
            _teamTab(awayDisplay, awayIsUCluj, _lineupTeamIndex == 1,
                () => setState(() => _lineupTeamIndex = 1)),
          ],
        ),

        // ── Formation label ──────────────────────────────────────────────
        // Accent for whichever side is the TRACKED team (U Cluj), regardless of
        // home/away; primary tone otherwise; never accent on a neutral fixture.
        if (formation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SpacingTokens.md, SpacingTokens.sm, SpacingTokens.md, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SpacingTokens.xs, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isUCluj
                            ? context.colors.accent
                            : context.colors.textMuted)
                        .withValues(alpha: 0.14),
                    borderRadius: ShapeTokens.chip,
                  ),
                  child: Text(
                    formation,
                    style: TypographyTokens.sectionLabel.copyWith(
                      color: isUCluj
                          ? context.colors.accent
                          : context.colors.textPrimary,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
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
          const SizedBox(height: SpacingTokens.sm),
          Container(
            color: context.colors.surfaceLow,
            padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md, vertical: 6),
            child: Row(
              children: [
                Container(width: 2, height: 11, color: context.colors.textMuted),
                const SizedBox(width: SpacingTokens.xs),
                Text(L10n.t('sheet.subs'),
                    style: TypographyTokens.sectionLabel.copyWith(
                        fontSize: 9,
                        color: context.colors.textMuted,
                        letterSpacing: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.xxs),
          ...subs.map((p) => _buildPlayerRow(p, isSub: true)),
        ],
      ],
    );
  }

  Widget _teamTab(
      String name, bool isUCluj, bool selected, VoidCallback onTap) {
    final c = context.colors;
    // The selected tab reads clearly distinct: a tonal fill plus a 2 px accent
    // underline (cobalt for the tracked team, primary text tone otherwise).
    // Unselected tabs stay flat and muted with a hairline rule beneath.
    final underline = isUCluj ? c.accent : c.textPrimary;
    final selectedText = isUCluj ? c.accent : c.textPrimary;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: MotionTokens.timed(context, MotionTokens.micro),
          curve: MotionTokens.standardCurve,
          padding: const EdgeInsets.symmetric(
              vertical: SpacingTokens.sm, horizontal: SpacingTokens.xs),
          decoration: BoxDecoration(
            color: selected ? c.surfaceLow : c.surfaceHigh,
            border: Border(
              bottom: BorderSide(
                color: selected ? underline : c.divider,
                width: selected ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isUCluj) ...[
                Icon(Icons.shield,
                    color: selected ? c.accent : c.textMuted, size: 11),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  name,
                  style: TypographyTokens.sectionLabel.copyWith(
                    fontSize: 9.5,
                    color: selected ? selectedText : c.textMuted,
                    letterSpacing: 1.2,
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

  Widget _buildPlayerRow(MatchPlayer p, {bool isSub = false}) {
    final c = context.colors;
    final posColor = _positionColor(p.position);
    // Modern completed-match row, aligned with the upcoming-XI player rows: a
    // role-coloured left rule, headshot, name + role code, the stat badges, and
    // a dominant accent-coloured match grade on the right (the same hierarchy
    // the predicted-score column uses on the preview screen).
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: isSub ? c.surface : c.surfaceLow.withValues(alpha: 0.6),
        border: Border(left: BorderSide(color: posColor, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
      child: Row(
        children: [
          // Jersey number
          SizedBox(
            width: 22,
            child: Text(
              p.jerseyNumber != null ? '${p.jerseyNumber}' : '—',
              style: TypographyTokens.sectionLabel.copyWith(
                fontSize: 10,
                color: c.textMuted,
              ),
            ),
          ),
          // Headshot (initials when unmatched), ringed in the role colour.
          PlayerPhotoAvatar(
            photoUrl: p.photoUrl,
            name: p.name,
            ringColor: posColor,
            size: 30,
          ),
          const SizedBox(width: SpacingTokens.sm),
          // Name + role + inline stat badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.name,
                  style: TypographyTokens.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (_hasPlayerBadges(p)) ...[
                  const SizedBox(height: 4),
                  _buildPlayerBadges(p),
                ],
              ],
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          // Dominant match grade, accent-coloured like the upcoming-XI score.
          _buildGradeColumn(p),
        ],
      ),
    );
  }

  /// Right-hand grade column for a completed-match player row: a large
  /// band-coloured grade over a small caption, or a muted dash when the player
  /// could not be matched to Wyscout stats. The column is fixed at 48 px wide so
  /// a two-digit "10.0" and the GRADE caption never clip or shift the row.
  Widget _buildGradeColumn(MatchPlayer p) {
    final c = context.colors;
    if (p.grade == null) {
      return SizedBox(
        width: 48,
        child: Text(
          '—',
          textAlign: TextAlign.right,
          style: TypographyTokens.statValue
              .copyWith(color: c.textMuted, fontSize: 18),
        ),
      );
    }
    final tone = gradeColor(p.grade!, c);
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            gradeLabel(p.grade!),
            textAlign: TextAlign.right,
            style: TypographyTokens.statValue.copyWith(
              color: tone,
              fontSize: 20,
            ),
          ),
          Text(
            L10n.t('sheet.playerGrade'),
            textAlign: TextAlign.right,
            style: TypographyTokens.sectionLabel
                .copyWith(color: c.textMuted, fontSize: 7, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }

  bool _hasPlayerBadges(MatchPlayer p) =>
      p.goalsScored > 0 ||
      p.assists > 0 ||
      p.yellowCards > 0 ||
      p.redCards > 0 ||
      (p.minutesPlayed != null && p.minutesPlayed! < 90 && !p.isStarter);

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

  // ── Three-way win probability (upcoming, non-U-Cluj) ─────────────────────
  //
  // For neutral fixtures the U-Cluj arc framing is wrong: neither side is the
  // tracked team. The backend runs the binary model once per team (each as the
  // home subject) and reports a documented residual draw, so the sheet shows an
  // explicit home-win / draw / away-win split. Each value is a 0..1 share; the
  // favoured outcome (the largest of the three) is carried in the positive
  // green token while the others read in the muted track tone, and a single
  // flat split bar mirrors the proportions. No "U CLUJ" text appears here.

  Widget _buildThreeWayWinProbability(WeekFixture f) {
    final c = context.colors;
    final home = (f.homeTeamWinProb ?? 0).clamp(0.0, 1.0);
    final away = (f.awayTeamWinProb ?? 0).clamp(0.0, 1.0);
    // Trust the backend's documented residual draw when present; otherwise fall
    // back to the clamped complement so the bar still fills.
    final draw = (f.drawProb ?? (1.0 - home - away)).clamp(0.0, 1.0);

    final homePct = (home * 100).round();
    final drawPct = (draw * 100).round();
    final awayPct = (away * 100).round();

    final homeName = f.homeTeam.replaceAll('Universitatea Cluj', 'U Cluj');
    final awayName = f.awayTeam.replaceAll('Universitatea Cluj', 'U Cluj');

    // Emphasise the single most likely outcome (home win / draw / away win).
    final maxShare = [home, draw, away].reduce((a, b) => a > b ? a : b);
    final homeFavoured = home >= maxShare;
    final drawFavoured = !homeFavoured && draw >= maxShare;
    final awayFavoured = !homeFavoured && !drawFavoured;

    final homeColor = homeFavoured ? c.positive : c.textMuted;
    final drawColor = drawFavoured ? c.accent : c.textMuted;
    final awayColor = awayFavoured ? c.positive : c.textMuted;

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

          // ── Home win / draw / away win, favoured outcome emphasised ──────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ThreeWaySide(
                  name: homeName,
                  pct: homePct,
                  color: homeColor,
                  favoured: homeFavoured,
                  align: CrossAxisAlignment.start,
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: _ThreeWaySide(
                  name: L10n.t('sheet.drawShort'),
                  pct: drawPct,
                  color: drawColor,
                  favoured: drawFavoured,
                  align: CrossAxisAlignment.center,
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: _ThreeWaySide(
                  name: awayName,
                  pct: awayPct,
                  color: awayColor,
                  favoured: awayFavoured,
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),

          // ── Flat split bar, proportional to the three outcomes ───────────
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
                  flex: (draw * 1000).round().clamp(1, 1000),
                  child: Container(color: drawColor),
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
                    // A formation change invalidates any slot pins: the new
                    // preview the POST returns is a genuinely fresh object, so
                    // the interactive panel clears its locks in didUpdateWidget
                    // when the parent passes it down.
                    setState(() => _formation = v);
                    _loadXi();
                  }
                },
                items: _formations
                    .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f == kFormationAuto
                              ? L10n.t('team.formationAuto')
                              : f),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        // Surface the RESOLVED shape next to the selector (with an AUTO tag when
        // AUTO was requested), so staff see which shape the optimiser chose.
        if (_preview!.formation.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.xs),
          _buildResolvedFormation(_preview!),
        ],
        const SizedBox(height: SpacingTokens.sm),
        RecommendedXiFifaPanel(
          preview: _preview!,
          formation: _preview!.formation.isNotEmpty
              ? _preview!.formation
              : _formation,
          opponentName: _xiOpponent,
          xiRepository: _xiRepo,
          onPreviewChanged: (updated) {
            // Keep the sheet's copy in sync so a formation switch after an edit
            // re-fetches from the latest resolved shape, not a stale one.
            if (mounted) setState(() => _preview = updated);
          },
        ),
      ],
    );
  }

  // When AUTO is requested the optimiser picks the shape, so we surface the
  // RESOLVED formation (from the response) next to an AUTO tag, so staff see
  // which shape was chosen. When an explicit shape was requested we still echo
  // the resolved key for confirmation but drop the AUTO tag.
  Widget _buildResolvedFormation(MatchPreviewResponse p) {
    final c = context.colors;
    final isAuto = _formation == kFormationAuto;
    return Row(
      children: [
        Text(
          isAuto ? L10n.t('team.formationChosen') : L10n.t('team.formation'),
          style: TypographyTokens.sectionLabel.copyWith(color: c.textMuted),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.sm, vertical: 3),
          color: c.accent.withValues(alpha: 0.14),
          child: Text(
            p.formation,
            style: TypographyTokens.sectionLabel
                .copyWith(color: c.accent, letterSpacing: 1.2),
          ),
        ),
        if (isAuto) ...[
          const SizedBox(width: SpacingTokens.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: c.surfaceHigh,
            child: Text(
              L10n.t('team.formationAutoTag'),
              style: TypographyTokens.sectionLabel.copyWith(
                  color: c.textMuted, fontSize: 9, letterSpacing: 1.4),
            ),
          ),
        ],
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

  /// How many chips share the densest pitch line, derived from the ACTUAL
  /// placements (slot geometry or coarse fallback) rather than the coarse
  /// D/M/F counts, so a 5-wide back line or a wide double-pivot is measured
  /// correctly and the chips can be sized to never overlap.
  int _densestLine(
      List<({MatchPlayer player, Offset offset, String? label})> placements) {
    final byRow = <int, int>{};
    for (final p in placements) {
      // Quantise the y offset into ~5% bands so players nominally on the same
      // line group together even when their y differs by a hair.
      final band = (p.offset.dy * 20).round();
      byRow[band] = (byRow[band] ?? 0) + 1;
    }
    return byRow.values.fold(1, (a, b) => a > b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final placements = _placements();
    final tokens = context.colors;
    final maxLineCount = _densestLine(placements);

    return AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, c) {
          // The slot xs run from 0.18 to 0.82, so the densest line spreads its
          // chips across ~0.64 of the width over (maxLineCount - 1) gaps. The
          // true horizontal spacing between two adjacent chip CENTRES on that
          // line is therefore 0.64 * width / (n - 1); sizing each chip cell to
          // that spacing (minus an inter-chip pad) is what guarantees 4-5-wide
          // lines never bleed into each other. For a single-chip line we just
          // allow the full pitch width.
          const interChipPad = 6.0;
          const lineSpan = 0.82 - 0.18; // matches _distributedXs / slot geometry
          final adjacentSpacing = maxLineCount <= 1
              ? c.maxWidth * 0.92
              : (lineSpan * c.maxWidth) / (maxLineCount - 1);
          final boxFromCell = adjacentSpacing - interChipPad;

          // Keep the chip within a sane visual range and shrink it to whatever
          // the densest line can afford.
          final base = c.maxWidth < 430 ? 46.0 : 52.0;
          final chipBoxW = boxFromCell.clamp(34.0, base * 1.5).toDouble();
          // The avatar itself is narrower than its caption box.
          final chipSize = (chipBoxW / 1.5).clamp(28.0, base).toDouble();
          // Box height covers the square avatar plus the surname and the event
          // markers beneath it, so the chip is vertically centred on its slot.
          final chipBoxH = chipSize * 1.55;

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
                  left: (p.offset.dx * c.maxWidth - chipBoxW / 2)
                      .clamp(2.0, (c.maxWidth - chipBoxW - 2.0).clamp(2.0, double.infinity))
                      .toDouble(),
                  top: p.offset.dy * c.maxHeight - chipBoxH / 2,
                  width: chipBoxW,
                  child: _ActualPlayerChip(
                      player: p.player,
                      chipSize: chipSize,
                      cellWidth: chipBoxW,
                      positionLabel: p.label),
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
    required this.cellWidth,
    this.positionLabel,
  });
  final MatchPlayer player;
  final double chipSize;

  /// The full horizontal cell this chip owns on the pitch. The surname caption
  /// and the event-marker row are constrained to this width so a dense 4-5-wide
  /// line never lets one chip's text bleed into its neighbour.
  final double cellWidth;

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

  /// Short slot/position caption for the badge (RB, DM, ST, ...), falling back
  /// to the coarse one-letter code.
  String get _posLabel {
    if (positionLabel != null && positionLabel!.isNotEmpty) return positionLabel!;
    if (player.officialPosition.isNotEmpty) return player.officialPosition;
    return player.position.toUpperCase();
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
    final grade = player.grade;
    final gradeTone = grade != null ? gradeColor(grade, c) : posColor;
    final r = chipSize * 0.1; // rounded-badge radius, mirrors the predictor chip

    // Modern completed-match chip, mirroring the upcoming-XI FifaPitchPlayerChip:
    // a role-ringed headshot, a rounded role-coloured corner badge carrying the
    // dominant match grade over the position label, the shirt number on the
    // opposite corner, event markers below, and the surname captioned beneath.
    // Everything is constrained to [cellWidth] so dense lines never overlap.
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: chipSize,
          height: chipSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: PlayerPhotoAvatar(
                  photoUrl: player.photoUrl,
                  name: _lastName,
                  ringColor: posColor,
                  size: chipSize,
                ),
              ),
              // Grade + position badge (top-left), the prominent corner glyph
              // that anchors the chip — grade tone by band, position beneath.
              Positioned(
                top: chipSize * 0.04,
                left: chipSize * 0.04,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: chipSize * 0.07,
                    vertical: chipSize * 0.02,
                  ),
                  decoration: BoxDecoration(
                    color: gradeTone,
                    borderRadius: BorderRadius.circular(r),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        grade != null ? gradeLabel(grade) : '—',
                        style: TypographyTokens.statValue.copyWith(
                          color: Colors.white,
                          fontSize: chipSize * 0.22,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        _posLabel,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TypographyTokens.sectionLabel.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: chipSize * 0.1,
                          height: 1.15,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Shirt number badge (bottom-right) in the role colour.
              if (player.jerseyNumber != null)
                Positioned(
                  bottom: chipSize * 0.04,
                  right: chipSize * 0.04,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: posColor,
                      borderRadius: BorderRadius.circular(r * 0.6),
                    ),
                    child: Text(
                      '${player.jerseyNumber}',
                      style: TypographyTokens.sectionLabel.copyWith(
                        fontSize: chipSize * 0.13,
                        color: c.onPrimary,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: chipSize * 0.06),
        SizedBox(
          width: cellWidth,
          child: Text(
            _lastName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TypographyTokens.body.copyWith(
              fontSize: chipSize * 0.2,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              height: 1.05,
            ),
          ),
        ),
        if (hasGoal || hasYellow || hasRed)
          SizedBox(
            width: cellWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                if (hasGoal) ...[
                  Text('⚽', style: TextStyle(fontSize: chipSize * 0.18)),
                  if (player.goalsScored > 1)
                    Text(
                      '×${player.goalsScored}',
                      style: TypographyTokens.mono.copyWith(
                        fontSize: chipSize * 0.16,
                        color: c.textPrimary,
                      ),
                    ),
                ],
                if (hasYellow)
                  Container(
                    width: chipSize * 0.12,
                    height: chipSize * 0.17,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(1),
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  ),
                if (hasRed)
                  Container(
                    width: chipSize * 0.12,
                    height: chipSize * 0.17,
                    decoration: BoxDecoration(
                      color: c.negative,
                      borderRadius: BorderRadius.circular(1),
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  ),
              ],
            ),
          ),
      ],
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

/// One column of the neutral three-way win-probability split (non-U-Cluj
/// fixtures): home win, draw, or away win. Renders an outcome label above its
/// percentage, with the favoured outcome carried in the supplied tone and a
/// heavier weight so the eye anchors on the most likely result. `align`
/// positions the home column to the start, the draw to the centre, and the
/// away column to the end so the three read symmetrically across the split bar.
class _ThreeWaySide extends StatelessWidget {
  const _ThreeWaySide({
    required this.name,
    required this.pct,
    required this.color,
    required this.favoured,
    required this.align,
  });

  final String name;
  final int pct;
  final Color color;
  final bool favoured;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textAlign = align == CrossAxisAlignment.end
        ? TextAlign.right
        : align == CrossAxisAlignment.center
            ? TextAlign.center
            : TextAlign.left;
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
            fontSize: 30,
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
