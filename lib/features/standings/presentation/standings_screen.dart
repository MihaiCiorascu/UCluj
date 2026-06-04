import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/services/api_client.dart';
import '../../../core/state/meta_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shape_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_loading_skeleton.dart';
import '../../../core/widgets/app_scaffold.dart';

// =============================================================================
// MODEL
// =============================================================================

class _TeamStanding {
  _TeamStanding({
    required this.pos,
    required this.name,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.gf,
    required this.ga,
    required this.gd,
    required this.points,
  });

  final int pos, played, wins, draws, losses, gf, ga, gd, points;
  final String name;

  String get shortName => _nameToShort[name] ?? _srNameToShort[name] ?? name;
  String get logoAsset => _nameToLogo[name] ?? _srNameToLogo[name] ?? '';

  bool isTrackedBy(String? trackedTeam) {
    if (trackedTeam == null) return false;
    final t = trackedTeam.toLowerCase();
    final n = name.toLowerCase();
    return n == t || n.contains(t) || t.contains(n) || shortName.toLowerCase() == t;
  }

  factory _TeamStanding.fromJson(Map<String, dynamic> j, {int fallbackRank = 0}) {
    return _TeamStanding(
      pos: j['position'] as int? ?? fallbackRank,
      name: j['team'] as String? ?? '',
      played: j['played'] as int? ?? 0,
      wins: j['wins'] as int? ?? 0,
      draws: j['draws'] as int? ?? 0,
      losses: j['losses'] as int? ?? 0,
      gf: j['goals_for'] as int? ?? 0,
      ga: j['goals_against'] as int? ?? 0,
      gd: j['goal_difference'] as int? ?? 0,
      points: j['points'] as int? ?? 0,
    );
  }
}

// CSV team name → short display name
const _nameToShort = <String, String>{
  'U Cluj': 'U Cluj',
  'CFR Cluj': 'CFR Cluj',
  'FCSB': 'FCSB',
  'Rapid Bucuresti': 'Rapid',
  'Dinamo Bucuresti': 'Dinamo',
  'Farul Constanta': 'Farul',
  'FC Hermannstadt': 'Hermannstadt',
  'UTA Arad': 'UTA Arad',
  'Petrolul Ploiesti': 'Petrolul',
  'Otelul Galati': 'Oțelul',
  'Csikszereda M. Ciuc': 'Csíkszereda',
  'Unirea Slobozia': 'Unirea',
  'Metaloglobus Bucuresti': 'Metaloglobus',
  'FC Arges': 'FC Argeș',
  'Univ. Craiova': 'U Craiova',
  'FC Botosani': 'FC Botoșani',
};

// Sportradar full name → short display name
const _srNameToShort = <String, String>{
  'FC Universitatea Cluj': 'U Cluj',
  'CS Universitatea Craiova': 'U Craiova',
  'FC CFR 1907 Cluj': 'CFR Cluj',
  'Fotbal Club FCSB': 'FCSB',
  'Rapid Bucuresti 1923': 'Rapid',
  'FC Dinamo Bucuresti 1948': 'Dinamo',
  'FC Farul Constanta': 'Farul',
  'AFC Hermannstadt': 'Hermannstadt',
  'FC Uta Arad': 'UTA Arad',
  'FC Petrolul Ploiesti': 'Petrolul',
  'ASC Otelul Galati': 'Oțelul',
  'AFK Csikszereda Miercurea Ciuc': 'Csíkszereda',
  'FC Unirea 2004 Slobozia': 'Unirea',
  'ACS Champions FC Arges': 'FC Argeș',
  'FC Botosani': 'FC Botoșani',
  'Sepsi OSK Sfantu Gheorghe': 'Sepsi',
};

// CSV team name → local logo asset
const _nameToLogo = <String, String>{
  'U Cluj': 'assets/teams/universitatea_cluj.png',
  'CFR Cluj': 'assets/teams/cfr_cluj.png',
  'FCSB': 'assets/teams/fcsb.png',
  'Rapid Bucuresti': 'assets/teams/rapid_bucuresti.png',
  'Dinamo Bucuresti': 'assets/teams/dinamo_bucuresti.png',
  'Farul Constanta': 'assets/teams/farul_constanta.png',
  'FC Hermannstadt': 'assets/teams/hermannstadt.png',
  'UTA Arad': 'assets/teams/uta_arad.png',
  'Petrolul Ploiesti': 'assets/teams/petrolul_ploiesti.png',
  'Otelul Galati': 'assets/teams/otelul_galati.png',
  'Csikszereda M. Ciuc': 'assets/teams/csikszereda.png',
  'Unirea Slobozia': 'assets/teams/unirea_slobozia.png',
  'Metaloglobus Bucuresti': 'assets/teams/metaloglobus.png',
  'FC Arges': 'assets/teams/arges_pitesti.png',
  'Univ. Craiova': 'assets/teams/universitatea_craiova.png',
  'FC Botosani': 'assets/teams/botosani.png',
};

// Sportradar full name → local logo asset
const _srNameToLogo = <String, String>{
  'FC Universitatea Cluj': 'assets/teams/universitatea_cluj.png',
  'CS Universitatea Craiova': 'assets/teams/universitatea_craiova.png',
  'FC CFR 1907 Cluj': 'assets/teams/cfr_cluj.png',
  'Fotbal Club FCSB': 'assets/teams/fcsb.png',
  'Rapid Bucuresti 1923': 'assets/teams/rapid_bucuresti.png',
  'FC Dinamo Bucuresti 1948': 'assets/teams/dinamo_bucuresti.png',
  'FC Farul Constanta': 'assets/teams/farul_constanta.png',
  'AFC Hermannstadt': 'assets/teams/hermannstadt.png',
  'FC Uta Arad': 'assets/teams/uta_arad.png',
  'FC Petrolul Ploiesti': 'assets/teams/petrolul_ploiesti.png',
  'ASC Otelul Galati': 'assets/teams/otelul_galati.png',
  'AFK Csikszereda Miercurea Ciuc': 'assets/teams/csikszereda.png',
  'FC Unirea 2004 Slobozia': 'assets/teams/unirea_slobozia.png',
  'ACS Champions FC Arges': 'assets/teams/arges_pitesti.png',
  'FC Botosani': 'assets/teams/botosani.png',
};

// =============================================================================
// SCREEN
// =============================================================================

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({
    required this.onTabSelected,
    this.onProfileTap,
    this.trackedTeam,
    this.apiClient,
    super.key,
  });

  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback? onProfileTap;
  final String? trackedTeam;
  final ApiClient? apiClient;

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen>
    with SingleTickerProviderStateMixin {
  List<_TeamStanding> _regular = [];
  List<_TeamStanding> _championship = [];
  List<_TeamStanding> _relegation = [];
  bool _loading = true;
  String? _error;
  late final TabController _tabController;

  String? get _team => widget.trackedTeam;
  ApiClient get _api => widget.apiClient ?? ApiClient();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await _api.get('/standings');
      final Map<String, dynamic> data = raw;

      List<_TeamStanding> parseList(String key) {
        final list = data[key] as List<dynamic>? ?? [];
        return list.asMap().entries.map((e) =>
          _TeamStanding.fromJson(e.value as Map<String, dynamic>, fallbackRank: e.key + 1),
        ).toList();
      }

      if (mounted) {
        setState(() {
          _regular = parseList('regular');
          _championship = parseList('championship');
          _relegation = parseList('relegation');
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Season label for the hero header. The Romanian Superliga calendar runs
  /// July to May, so the season is anchored to the effective "now": in demo
  /// mode that is MetaState.demoToday (pinned to the 2024-25 window), and in
  /// production it is the wall clock. This keeps the committee from seeing a
  /// "2025/26" caption above a 2024-25 demo table.
  String _seasonLabel() {
    final meta = MetaState.instance;
    DateTime now = DateTime.now().toUtc();
    if (meta.demoMode && meta.demoToday.isNotEmpty) {
      final parsed = DateTime.tryParse('${meta.demoToday}T12:00:00Z');
      if (parsed != null) now = parsed.toUtc();
    }
    final startYear = now.month >= 7 ? now.year : now.year - 1;
    final endYy = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return 'SUPERLIGA ROMANIA  ·  $startYear/$endYy';
  }

  _TeamStanding? _findTracked(List<_TeamStanding> list) {
    if (list.isEmpty) return null;
    final t = _team;
    if (t == null) {
      for (final team in list) {
        if (team.name.toLowerCase().contains('cluj') &&
            !team.name.toLowerCase().contains('cfr')) { return team; }
      }
      return list.first;
    }
    for (final team in list) {
      if (team.isTrackedBy(t)) return team;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppScaffold(
      currentTab: AppTab.standings,
      onTabSelected: widget.onTabSelected,
      onProfileTap: widget.onProfileTap,
      body: _loading
          // PR 14 loading sweep: a table-shaped skeleton replaces the bare
          // spinner so the standings open onto a layout that already matches
          // the ledger about to land, rather than a centred dot on an empty
          // surface (the cheapest-looking moment of any data screen).
          ? const Padding(
              padding: EdgeInsets.fromLTRB(
                  SpacingTokens.md, SpacingTokens.lg, SpacingTokens.md, 0),
              child: AppLoadingSkeleton(rows: 9, rowHeight: 44),
            )
          : _error != null
              ? _buildError(c)
              : _buildContent(c),
    );
  }

  Widget _buildError(AppColorTokens c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: c.negative),
            const SizedBox(height: SpacingTokens.md),
            Text('Could not load standings',
                style: TypographyTokens.headline.copyWith(color: c.negative)),
            const SizedBox(height: SpacingTokens.sm),
            Text(_error!,
                style: TypographyTokens.body.copyWith(color: c.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: SpacingTokens.lg),
            TextButton(
              onPressed: _loadData,
              child: Text('RETRY',
                  style: TypographyTokens.sectionLabel.copyWith(color: c.accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppColorTokens c) {
    return RefreshIndicator(
      color: c.accent,
      backgroundColor: c.surfaceLow,
      onRefresh: _loadData,
      child: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PR 13 header polish: the 72 px hero title is wrapped in a
                  // scale-down FittedBox per line so it never clips or
                  // line-breaks awkwardly on a narrow phone. The display size
                  // is preserved on roomy viewports and shrinks gracefully on
                  // the tightest ones instead of overflowing.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('LEAGUE',
                        maxLines: 1,
                        style: TypographyTokens.displayHero.copyWith(
                            fontSize: 72, height: 0.9, color: c.textPrimary)),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('STANDINGS',
                        maxLines: 1,
                        style: TypographyTokens.displayHero.copyWith(
                          fontSize: 72,
                          height: 0.9,
                          color: c.textMuted.withValues(alpha: 0.15),
                        )),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(_seasonLabel(),
                      style: TypographyTokens.sectionLabel.copyWith(
                        color: c.accent,
                        letterSpacing: 2.0,
                      )),
                  const SizedBox(height: SpacingTokens.lg),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              tabBar: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicator: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: c.onAccent,
                unselectedLabelColor: c.textMuted,
                labelStyle: TypographyTokens.buttonLabel,
                unselectedLabelStyle: TypographyTokens.buttonLabel,
                padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
                tabs: [
                  Tab(text: L10n.t('standings.tabRegular')),
                  Tab(text: L10n.t('standings.tabChampionship')),
                  Tab(text: L10n.t('standings.tabRelegation')),
                ],
              ),
              surfaceColor: c.surface,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _StandingsTabView(
              rows: _regular,
              trackedTeam: _team,
              tracked: _findTracked(_regular),
            ),
            _StandingsTabView(
              rows: _championship,
              trackedTeam: _team,
              tracked: _findTracked(_championship),
              emptyLabel: L10n.t('standings.emptyChampionship'),
            ),
            _StandingsTabView(
              rows: _relegation,
              trackedTeam: _team,
              tracked: _findTracked(_relegation),
              emptyLabel: L10n.t('standings.emptyRelegation'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TAB CONTENT
// =============================================================================

class _StandingsTabView extends StatelessWidget {
  const _StandingsTabView({
    required this.rows,
    required this.trackedTeam,
    this.tracked,
    this.emptyLabel = 'No standings data available.',
  });

  final List<_TeamStanding> rows;
  final String? trackedTeam;
  final _TeamStanding? tracked;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      // PR 14 empty-state sweep: route the empty playoff-group tabs through
      // the shared AppEmptyState so they read as a deliberate "not published
      // yet" panel instead of a bare icon-over-text placeholder.
      return AppEmptyState(
        icon: Icons.table_chart_outlined,
        headline: emptyLabel,
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: SpacingTokens.md),
        if (tracked != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
            child: _HeroClubCard(team: tracked!),
          ),
        const SizedBox(height: SpacingTokens.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
          child: _TableHeader(),
        ),
        ...rows.map((t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
          child: _StandingsRow(team: t, trackedTeam: trackedTeam),
        )),
        if (tracked != null && rows.isNotEmpty) ...[
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
            child: _ContextCard(
              label: 'POINTS TO LEADER',
              value: '${rows.first.points - tracked!.points}',
              note: '${rows.first.shortName} leads with ${rows.first.points} pts.',
              isPositive: tracked!.pos == 1,
            ),
          ),
        ],
        const SizedBox(height: SpacingTokens.xl),
      ],
    );
  }
}

// =============================================================================
// PINNED TAB BAR DELEGATE
// =============================================================================

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate({required this.tabBar, required this.surfaceColor});
  final TabBar tabBar;
  final Color surfaceColor;

  @override
  double get minExtent => tabBar.preferredSize.height + 16;
  @override
  double get maxExtent => tabBar.preferredSize.height + 16;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: surfaceColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar || surfaceColor != oldDelegate.surfaceColor;
}

// =============================================================================
// WIDGETS
// =============================================================================

class _HeroClubCard extends StatelessWidget {
  const _HeroClubCard({required this.team});
  final _TeamStanding team;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: ShapeTokens.card,
        border: Border.all(color: c.accent.withValues(alpha: 0.3)),
        boxShadow: ShapeTokens.e1(context),
      ),
      padding: const EdgeInsets.fromLTRB(
        SpacingTokens.lg, SpacingTokens.xl,
        SpacingTokens.lg, SpacingTokens.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (team.logoAsset.isNotEmpty)
              SizedBox(width: 44, height: 44,
                  child: Image.asset(team.logoAsset, fit: BoxFit.contain))
            else
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: c.surfaceHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.shield_outlined, color: c.textMuted, size: 24),
              ),
            const SizedBox(width: SpacingTokens.md),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.shortName.toUpperCase(),
                    style: TypographyTokens.headline.copyWith(
                      fontSize: 18,
                      color: c.textPrimary,
                    )),
                const SizedBox(height: 2),
                Text('YOUR CLUB  ·  SUPERLIGA',
                    style: TypographyTokens.sectionLabel
                        .copyWith(fontSize: 8, letterSpacing: 1.8, color: c.textMuted)),
              ],
            )),
          ]),
          const SizedBox(height: SpacingTokens.xl),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Iteration N polish: ratio between rank (48 px) and the RANK
            // label (12 px) is now ~4:1, closer to the Stoic Analyst spec's
            // display-lg / label-sm contrast than the previous 7:1.
            //
            // PR 13 header polish: the rank sits in a pod with a 3 px cobalt
            // left rule so it reads as the anchor metric of the hero card,
            // distinct from the PTS / GD / V-E-Î metrics that follow it.
            Container(
              padding: const EdgeInsets.only(left: SpacingTokens.sm),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: c.accent, width: 3),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${team.pos}', style: TypographyTokens.statLarge.copyWith(
                    fontSize: 48, color: c.accent)),
                const SizedBox(height: SpacingTokens.xxs),
                Text('RANK',
                    style: TypographyTokens.sectionLabel
                        .copyWith(fontSize: 12, letterSpacing: 2.4, color: c.textMuted)),
              ]),
            ),
            const SizedBox(width: 28),
            _metric('${team.points}', 'PTS', c),
            const SizedBox(width: SpacingTokens.xl),
            _metric('${team.gd > 0 ? "+" : ""}${team.gd}', 'GD', c),
            const SizedBox(width: SpacingTokens.xl),
            _metric('${team.wins}-${team.draws}-${team.losses}', L10n.t('standings.recordAbbr'), c),
          ]),
        ],
      ),
    );
  }

  Widget _metric(String value, String label, AppColorTokens c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          style: TypographyTokens.statValue
              .copyWith(fontSize: 22, color: c.textPrimary)),
      const SizedBox(height: 2),
      Text(label,
          style: TypographyTokens.sectionLabel
              .copyWith(fontSize: 8, letterSpacing: 1.4, color: c.textMuted)),
    ]);
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = TypographyTokens.sectionLabel.copyWith(
      fontSize: 8,
      letterSpacing: 1.0,
      color: c.textMuted.withValues(alpha: 0.6),
    );
    return Container(
      color: c.surfaceLow,
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
      child: Row(children: [
        SizedBox(width: 28, child: Text('#', style: s, textAlign: TextAlign.center)),
        const SizedBox(width: 22),
        Expanded(child: Text('CLUB', style: s)),
        SizedBox(width: 26, child: Text(L10n.t('standings.colPlayed'), style: s, textAlign: TextAlign.center)),
        SizedBox(width: 26, child: Text(L10n.t('standings.colWins'), style: s, textAlign: TextAlign.center)),
        SizedBox(width: 26, child: Text(L10n.t('standings.colDraws'), style: s, textAlign: TextAlign.center)),
        SizedBox(width: 26, child: Text(L10n.t('standings.colLosses'), style: s, textAlign: TextAlign.center)),
        SizedBox(width: 34, child: Text(L10n.t('standings.colGD'), style: s, textAlign: TextAlign.center)),
        SizedBox(width: 34, child: Text(L10n.t('standings.colPts'), style: s, textAlign: TextAlign.end)),
      ]),
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({required this.team, this.trackedTeam});
  final _TeamStanding team;
  final String? trackedTeam;

  bool get _hl {
    if (trackedTeam != null) return team.isTrackedBy(trackedTeam);
    return team.name.toLowerCase().contains('cluj') &&
        !team.name.toLowerCase().contains('cfr');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hl = _hl;
    final bg = hl ? c.surfaceHigh : Colors.transparent;
    final primary = hl ? c.accent : c.textPrimary;
    final muted = hl ? c.accent.withValues(alpha: 0.7) : c.textMuted;

    final nameStyle = TypographyTokens.body.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: primary,
      letterSpacing: hl ? 0.6 : 0,
    );
    final numStyle = TypographyTokens.mono.copyWith(
      fontSize: 12,
      color: primary,
      fontWeight: hl ? FontWeight.w700 : FontWeight.w400,
    );

    // Iteration N polish: when GD = 0 and the row is not highlighted, drop to
    // textMuted so the neutral case does not collide with the PCT column,
    // which otherwise renders in the same `primary` colour.
    final gdColor = hl
        ? c.accent
        : team.gd > 0
            ? c.positive
            : team.gd < 0
                ? c.negative
                : c.textMuted;

    return Container(
      color: bg,
      // PR 13 header polish: tighten row height from 10 to 8 vertical so all
      // sixteen rows of the regular table read as one continuous ledger
      // rather than a loose, scroll-heavy list.
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text(
            team.pos.toString().padLeft(2, '0'),
            style: numStyle.copyWith(color: muted, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ),
        if (team.logoAsset.isNotEmpty)
          SizedBox(width: 18, height: 18,
              child: Image.asset(team.logoAsset, fit: BoxFit.contain))
        else
          SizedBox(width: 18, height: 18,
              child: Icon(Icons.shield_outlined, size: 14, color: muted)),
        const SizedBox(width: SpacingTokens.xxs),
        Expanded(
            child: Text(team.shortName.toUpperCase(),
                style: nameStyle, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 26,
            child: Text('${team.played}', style: numStyle, textAlign: TextAlign.center)),
        SizedBox(width: 26,
            child: Text('${team.wins}', style: numStyle, textAlign: TextAlign.center)),
        SizedBox(width: 26,
            child: Text('${team.draws}', style: numStyle, textAlign: TextAlign.center)),
        SizedBox(width: 26,
            child: Text('${team.losses}', style: numStyle, textAlign: TextAlign.center)),
        SizedBox(
          width: 34,
          child: Text(
            '${team.gd > 0 ? "+" : ""}${team.gd}',
            style: numStyle.copyWith(color: gdColor),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(width: 34,
            child: Text('${team.points}',
                // PCT is the dominant column in a standings row, so explicit
                // primary colour + bold weight makes it the visual anchor.
                style: numStyle.copyWith(
                  fontWeight: FontWeight.w800,
                  color: primary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.end)),
      ]),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.label,
    required this.value,
    required this.note,
    this.isPositive = false,
  });

  final String label, value, note;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final valueColor = isPositive ? c.positive : c.negative;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.card,
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.fromLTRB(
        SpacingTokens.lg, SpacingTokens.lg,
        SpacingTokens.lg, SpacingTokens.md,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TypographyTokens.sectionLabel.copyWith(color: c.textMuted)),
        const SizedBox(height: SpacingTokens.xs),
        Text(value,
            style: TypographyTokens.statLarge.copyWith(
                fontSize: 48, color: valueColor)),
        const SizedBox(height: SpacingTokens.sm),
        Text(note,
            style: TypographyTokens.body.copyWith(color: c.textSecondary, fontSize: 13)),
      ]),
    );
  }
}
