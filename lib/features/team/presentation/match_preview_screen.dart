import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/widgets/app_loading_skeleton.dart';
import '../../../core/widgets/team_crest.dart';
import '../../../data/models/match_preview.dart';
import '../../../data/repositories/xi_repository.dart';

class MatchPreviewScreen extends StatefulWidget {
  const MatchPreviewScreen({
    required this.opponentName,
    required this.myTeam,
    super.key,
  });

  final String opponentName;
  final String myTeam;

  @override
  State<MatchPreviewScreen> createState() => _MatchPreviewScreenState();
}

class _MatchPreviewScreenState extends State<MatchPreviewScreen> {
  final _repo = XiRepository();

  bool _loading = true;
  String? _error;
  MatchPreviewResponse? _preview;

  // The REQUESTED formation: the "auto" sentinel (default) lets the optimiser
  // score the pool once and pick the highest-objective curated shape; otherwise
  // one of the nine curated keys forces that shape. The pitch always renders
  // from the RESOLVED formation the backend reports, not from this value.
  String _formation = kFormationAuto;

  // Selector entries: AUTO first, then the curated shapes (the only keys the
  // optimiser resolves to; the backend coerces anything else to "auto").
  static const _formations = [kFormationAuto, ...kCuratedFormations];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await _repo.postMatchPreview(
        opponentName: widget.opponentName,
        formation: _formation,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(
          '${widget.myTeam.toUpperCase()} VS ${widget.opponentName.toUpperCase()}',
          style: TypographyTokens.sectionLabel,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: SpacingTokens.md),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _formation,
                dropdownColor: c.surfaceLow,
                style: TypographyTokens.body
                    .copyWith(color: c.textPrimary),
                icon: Icon(Icons.arrow_drop_down, color: c.accent),
                onChanged: (v) {
                  if (v != null && v != _formation) {
                    setState(() => _formation = v);
                    _load();
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
          ),
        ],
      ),
      body: _loading
          // PR 14 loading sweep: a skeleton stack matches the match-preview
          // layout (stats row, pitch, player list) as it loads instead of a
          // bare centred spinner.
          ? const Padding(
              padding: EdgeInsets.all(SpacingTokens.md),
              child: AppLoadingSkeleton(rows: 6, rowHeight: 56),
            )
          : _error != null
              ? _buildError(context)
              : _buildBody(context),
    );
  }

  Widget _buildError(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load preview',
                style: TypographyTokens.headline
                    .copyWith(color: c.negative)),
            const SizedBox(height: SpacingTokens.sm),
            Text(_error!,
                style: TypographyTokens.body
                    .copyWith(color: c.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: SpacingTokens.lg),
            TextButton(
              onPressed: _load,
              child: Text('RETRY',
                  style: TypographyTokens.sectionLabel
                      .copyWith(color: c.accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final p = _preview!;
    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.md),
      children: [
        _buildCrestHeader(context),
        const SizedBox(height: SpacingTokens.sm),
        _buildResolvedFormation(context, p),
        const SizedBox(height: SpacingTokens.lg),
        _buildStatsRow(context, p),
        const SizedBox(height: SpacingTokens.xl),
        _buildOpponentStatsRow(context, p),
        const SizedBox(height: SpacingTokens.xl),
        if (p.headToHead.total > 0) ...[
          _buildH2H(context, p.headToHead),
          const SizedBox(height: SpacingTokens.xl),
        ],
        _buildXI(context, p),
        const SizedBox(height: SpacingTokens.xl),
        _buildBench(context, p.bench),
        const SizedBox(height: SpacingTokens.xl),
      ],
    );
  }

  Widget _buildCrestHeader(BuildContext context) {
    final c = context.colors;
    final opp = _preview?.opponentName ?? '';
    Widget side(String name) => Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TeamCrest(teamName: name, size: 24),
              const SizedBox(width: SpacingTokens.xs),
              Flexible(
                child: Text(
                  name.replaceAll('Universitatea Cluj', 'U CLUJ').toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TypographyTokens.body.copyWith(
                      fontWeight: FontWeight.w800, fontSize: 13, color: c.textPrimary),
                ),
              ),
            ],
          ),
        );
    return Row(
      children: [
        side(widget.myTeam),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
          color: c.surfaceHigh,
          child: Text('VS',
              style: TypographyTokens.sectionLabel.copyWith(color: c.accent)),
        ),
        side(opp),
      ],
    );
  }

  // When AUTO is requested the algorithm picks the shape, so we surface the
  // RESOLVED formation (from the response) next to an AUTO tag, so staff see
  // which shape was chosen. When an explicit shape was requested we still echo
  // the resolved key for confirmation but drop the AUTO tag.
  Widget _buildResolvedFormation(BuildContext context, MatchPreviewResponse p) {
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
              style: TypographyTokens.sectionLabel
                  .copyWith(color: c.textMuted, fontSize: 9, letterSpacing: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context, MatchPreviewResponse p) {
    final c = context.colors;
    final s = p.teamStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SQUAD ANALYTICS', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.sm),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: SpacingTokens.md),
        Row(
          children: [
            _StatCell(
                label: 'AVG FORM',
                value: s.avgRecentForm.toStringAsFixed(1)),
            _StatCell(
                label: 'AVG PERF',
                value: s.avgPerformanceScore.toStringAsFixed(1)),
            _StatCell(
                label: 'PASS %',
                value: '${s.avgPassAccuracy.toStringAsFixed(0)}%'),
            _StatCell(
                label: 'DUEL %',
                value: '${s.avgDuelWinRate.toStringAsFixed(0)}%'),
          ],
        ),
        if (s.topScorer.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.md),
          Row(
            children: [
              Expanded(
                child: _NameStatCell(
                  label: 'TOP SCORER',
                  name: s.topScorer,
                  value: '${s.topScorerStat.toStringAsFixed(2)} G/90',
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              if (s.topCreator.isNotEmpty)
                Expanded(
                  child: _NameStatCell(
                    label: 'TOP CREATOR',
                    name: s.topCreator,
                    value: '${s.topCreatorStat.toStringAsFixed(2)} KP/90',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildOpponentStatsRow(BuildContext context, MatchPreviewResponse p) {
    final c = context.colors;
    final s = p.opponentStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${p.opponentName.toUpperCase()} RECENT FORM', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.sm),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: SpacingTokens.md),
        Row(
          children: [
            _StatCell(
                label: 'AVG FORM',
                value: s.avgRecentForm.toStringAsFixed(1)),
            _StatCell(
                label: 'AVG PERF',
                value: s.avgPerformanceScore.toStringAsFixed(1)),
            _StatCell(
                label: 'PASS %',
                value: '${s.avgPassAccuracy.toStringAsFixed(0)}%'),
            _StatCell(
                label: 'DUEL %',
                value: '${s.avgDuelWinRate.toStringAsFixed(0)}%'),
          ],
        ),
        if (s.topScorer.isNotEmpty) ...[
          const SizedBox(height: SpacingTokens.md),
          Row(
            children: [
              Expanded(
                child: _NameStatCell(
                  label: 'TOP SCORER',
                  name: s.topScorer,
                  value: '${s.topScorerStat.toStringAsFixed(2)} G/90',
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              if (s.topCreator.isNotEmpty)
                Expanded(
                  child: _NameStatCell(
                    label: 'TOP CREATOR',
                    name: s.topCreator,
                    value: '${s.topCreatorStat.toStringAsFixed(2)} KP/90',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildH2H(BuildContext context, H2HStats h) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HEAD TO HEAD (LAST ${h.total})',
            style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.sm),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: SpacingTokens.md),
        Row(
          children: [
            _StatCell(label: 'WINS', value: '${h.ourWins}'),
            _StatCell(label: 'DRAWS', value: '${h.draws}'),
            _StatCell(label: 'LOSSES', value: '${h.theirWins}'),
            _StatCell(
                label: 'AVG SCORE',
                value:
                    '${h.ourAvgGoals.toStringAsFixed(1)}-${h.theirAvgGoals.toStringAsFixed(1)}'),
          ],
        ),
      ],
    );
  }

  Widget _buildXI(BuildContext context, MatchPreviewResponse p) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('STARTING XI', style: TypographyTokens.sectionLabel
                .copyWith(color: c.accent)),
            Text(p.formation,
                style: TypographyTokens.sectionLabel),
          ],
        ),
        const SizedBox(height: SpacingTokens.sm),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: SpacingTokens.sm),
        for (final group in ['GK', 'DEF', 'MID', 'FWD']) ...[
          ..._playersForGroup(p.startingXi, group).map((pl) => _buildPlayerRow(context, pl)),
        ],
      ],
    );
  }

  Widget _buildBench(BuildContext context, List<MatchPreviewPlayer> bench) {
    final c = context.colors;
    if (bench.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BENCH', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.sm),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: SpacingTokens.sm),
        ...bench.map((pl) => _buildPlayerRow(context, pl)),
      ],
    );
  }

  List<MatchPreviewPlayer> _playersForGroup(
      List<MatchPreviewPlayer> players, String group) {
    return players.where((p) => p.roleGroup == group).toList();
  }

  Widget _buildPlayerRow(BuildContext context, MatchPreviewPlayer p) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      color: c.surfaceLow,
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              p.roleGroup,
              style: TypographyTokens.body.copyWith(
                  color: c.textMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.shortName,
                    style: TypographyTokens.body
                        .copyWith(fontWeight: FontWeight.w700)),
                Text(p.role,
                    style: TypographyTokens.body
                        .copyWith(color: c.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                p.predictedScore.toStringAsFixed(2),
                style: TypographyTokens.headline
                    .copyWith(color: c.accent, fontSize: 14),
              ),
              Text(
                '${p.keyStatLabel} ${p.keyStatValue.toStringAsFixed(2)}',
                style: TypographyTokens.body
                    .copyWith(color: c.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Container(
        color: c.surfaceLow,
        margin: const EdgeInsets.only(right: 2),
        padding: const EdgeInsets.symmetric(
            vertical: SpacingTokens.sm, horizontal: SpacingTokens.xs),
        child: Column(
          children: [
            Text(value,
                style: TypographyTokens.headline.copyWith(fontSize: 16)),
            const SizedBox(height: 2),
            Text(label,
                style: TypographyTokens.body
                    .copyWith(color: c.textMuted, fontSize: 9),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _NameStatCell extends StatelessWidget {
  const _NameStatCell(
      {required this.label, required this.name, required this.value});
  final String label;
  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surfaceLow,
      padding: const EdgeInsets.all(SpacingTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TypographyTokens.body
                  .copyWith(color: c.textMuted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(name,
              style: TypographyTokens.body
                  .copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(value,
              style: TypographyTokens.body
                  .copyWith(color: c.accent, fontSize: 11)),
        ],
      ),
    );
  }
}
