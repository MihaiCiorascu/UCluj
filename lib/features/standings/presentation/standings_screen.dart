import 'package:flutter/material.dart';

import '../../../core/services/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
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
          ? Center(child: CircularProgressIndicator(color: c.accent))
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
                  Text('LEAGUE',
                      style: TypographyTokens.displayHero
                          .copyWith(fontSize: 72, height: 0.9, color: c.textPrimary)),
                  Text('STANDINGS',
                      style: TypographyTokens.displayHero.copyWith(
                        fontSize: 72,
                        height: 0.9,
                        color: c.textMuted.withValues(alpha: 0.15),
                      )),
                  const SizedBox(height: SpacingTokens.sm),
                  Text('SUPERLIGA ROMANIA  ·  2025/26',
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
                labelStyle: TypographyTokens.sectionLabel.copyWith(fontSize: 11),
                unselectedLabelStyle: TypographyTokens.sectionLabel.copyWith(fontSize: 11),
                padding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
                tabs: const [
                  Tab(text: 'PRINCIPAL'),
                  Tab(text: 'GRUPĂ CAMPIONAT'),
                  Tab(text: 'GRUPĂ RETROGRADARE'),
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
              emptyLabel: 'Grupă Campionat nedisponibilă',
            ),
            _StandingsTabView(
              rows: _relegation,
              trackedTeam: _team,
              tracked: _findTracked(_relegation),
              emptyLabel: 'Grupă Retrogradare nedisponibilă',
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
    final c = context.colors;
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.table_chart_outlined, size: 32, color: c.textMuted),
              const SizedBox(height: SpacingTokens.md),
              Text(emptyLabel,
                  style: TypographyTokens.body.copyWith(color: c.textMuted),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: SpacingTokens.md),
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
        color: c.surfaceLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: c.cardGlow,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
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
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('#${team.pos}', style: TypographyTokens.displayHero.copyWith(
                  fontSize: 64, height: 0.85, color: c.accent)),
              const SizedBox(height: 2),
              Text('RANK',
                  style: TypographyTokens.sectionLabel
                      .copyWith(fontSize: 9, letterSpacing: 2.0, color: c.textMuted)),
            ]),
            const SizedBox(width: 32),
            _metric('${team.points}', 'PTS', c),
            const SizedBox(width: SpacingTokens.xl),
            _metric('${team.gd > 0 ? "+" : ""}${team.gd}', 'GD', c),
            const SizedBox(width: SpacingTokens.xl),
            _metric('${team.wins}-${team.draws}-${team.losses}', 'V-E-Î', c),
          ]),
        ],
      ),
    );
  }

  Widget _metric(String value, String label, AppColorTokens c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value,
          style: TypographyTokens.headline
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
        SizedBox(width: 26, child: Text('MJ', style: s, textAlign: TextAlign.center)),
        SizedBox(width: 26, child: Text('V', style: s, textAlign: TextAlign.center)),
        SizedBox(width: 26, child: Text('E', style: s, textAlign: TextAlign.center)),
        SizedBox(width: 26, child: Text('Î', style: s, textAlign: TextAlign.center)),
        SizedBox(width: 34, child: Text('DG', style: s, textAlign: TextAlign.center)),
        SizedBox(width: 34, child: Text('PCT', style: s, textAlign: TextAlign.end)),
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
    final numStyle = TypographyTokens.body.copyWith(
      fontSize: 12,
      color: primary,
      fontWeight: hl ? FontWeight.w700 : FontWeight.w400,
    );

    final gdColor = hl
        ? c.accent
        : team.gd > 0
            ? c.positive
            : team.gd < 0
                ? c.negative
                : primary;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                style: numStyle.copyWith(fontWeight: FontWeight.w800),
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
        borderRadius: BorderRadius.circular(6),
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
            style: TypographyTokens.displayHero.copyWith(
                fontSize: 48, height: 0.9, color: valueColor)),
        const SizedBox(height: SpacingTokens.sm),
        Text(note,
            style: TypographyTokens.body.copyWith(color: c.textSecondary, fontSize: 13)),
      ]),
    );
  }
}
