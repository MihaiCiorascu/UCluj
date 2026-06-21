import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/primitives/haptics.dart';
import '../../../core/primitives/pressable.dart';
import '../../../core/primitives/reveal.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/widgets/team_crest.dart';
import '../../../core/services/api_client.dart' show ApiException;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../core/theme/shape_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_loading_skeleton.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/config/app_config.dart';
import '../../../core/data/superliga_teams.dart';
import '../../../data/models/week_fixture.dart';
import '../../../data/repositories/match_details_repository.dart';
import '../../../data/repositories/week_repository.dart';
import '../../standings/data/standings_repository.dart';
import 'match_stats_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.authState,
    required this.onTabSelected,
    this.onProfileTap,
    super.key,
  });

  final AuthState authState;
  final ValueChanged<AppTab> onTabSelected;
  final VoidCallback? onProfileTap;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final WeekRepository _repo;
  late final MatchDetailsRepository _detailsRepo;
  late final StandingsRepository _standingsRepo;
  bool _loading = true;
  String? _error;
  // Round offset relative to the backend's current round: 0 = current round,
  // -1 = previous, +1 = next. The backend reinterprets this same value as a
  // round offset (clamped to [1, 33]) and returns that whole round's fixtures.
  int _roundOffset = 0;

  // Local 5-round cache: offset → that round's fixtures. Populated once on
  // load, cleared on refresh. Prefetched for offsets -2..2.
  static const List<int> _cachedOffsets = [-2, -1, 0, 1, 2];
  final Map<int, List<WeekFixture>> _cache = {};

  /// The analytical subject club: the signed-in user's team (registry short),
  /// defaulting to U Cluj when unset. Drives the pinned section and its label.
  String get _myTeam => widget.authState.user?.teamName ?? 'U Cluj';

  // Live Sportradar season ID, mirroring backend
  // api/v1/endpoints/standings.py::SUPERLIGA_SEASON_ID.
  static const String _seasonId = 'sr:season:131507';

  // Crest-asset sets for the two season groups, resolved once from the standings
  // group-phase endpoint via the shared crest resolver so every team-name variant
  // (short, full, Sportradar, CSV) lines up. Used to sort fixtures into the
  // Championship / Relegation group sections during the group phase. Empty until
  // loaded (or when the data is unavailable), in which case the dashboard uses the
  // regular-season layout.
  Set<String> _playoffAssets = {};
  Set<String> _playoutAssets = {};
  // Which group contains the subject club: 'playoff', 'playout', or null.
  String? _subjectGroup;

  // Every fixture the backend returned for the selected round offset. The
  // backend already scopes the response to a single resolved round (all of
  // that round's mid-week and weekend matches), so these are shown directly
  // with no client-side week-window filtering.
  List<WeekFixture> get _fixtures => _cache[_roundOffset] ?? [];

  @override
  void initState() {
    super.initState();
    _repo = WeekRepository(apiClient: widget.authState.api);
    _detailsRepo = MatchDetailsRepository(apiClient: widget.authState.api);
    _standingsRepo = StandingsRepository(apiBaseUrl: AppConfig.apiBaseUrl);
    _loadAll();
  }

  /// Silently warm the backend disk cache for completed U Cluj matches.
  void _prefetchMatchDetails() {
    final completed = _cache.values
        .expand((fixtures) => fixtures)
        .where((f) => f.isCompleted && f.involvesSubject && f.matchId.isNotEmpty)
        .map((f) => f.matchId)
        .toSet();

    for (final id in completed) {
      // Fire-and-forget prefetch: swallow failures, this only warms a cache.
      _detailsRepo.fetchMatchDetails(id).then(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
    }
  }

  /// Fetch the Championship / Relegation group membership once, so fixtures can
  /// be sorted into the two group sections during the group phase. Best effort:
  /// any failure leaves the sets empty and the dashboard uses the regular-season
  /// layout rather than crashing.
  Future<void> _loadPlayoffGroups() async {
    try {
      final groups = await _standingsRepo.fetchGroupPhase(_seasonId);
      if (!mounted) return;
      final playoff = groups.championshipRound.standings
          .map((r) => badgeAssetForName(r.teamName))
          .whereType<String>()
          .toSet();
      final playout = groups.relegationRound.standings
          .map((r) => badgeAssetForName(r.teamName))
          .whereType<String>()
          .toSet();
      // The subject's own group, by which set holds its crest.
      final subjectAsset = badgeAssetForName(_myTeam);
      String? subjectGroup;
      if (subjectAsset != null && playoff.contains(subjectAsset)) {
        subjectGroup = 'playoff';
      } else if (subjectAsset != null && playout.contains(subjectAsset)) {
        subjectGroup = 'playout';
      }
      setState(() {
        _playoffAssets = playoff;
        _playoutAssets = playout;
        _subjectGroup = subjectGroup;
      });
    } catch (_) {
      // Group data unavailable: leave sets empty, fall back to one list.
    }
  }

  /// Fetch all 5 rounds in parallel and populate the cache.
  Future<void> _loadAll({bool forceRefresh = false}) async {
    setState(() { _loading = true; _error = null; });
    if (forceRefresh) _cache.clear();
    try {
      final results = await Future.wait(
        _cachedOffsets.map((off) => _repo.fetchWeekFixtures(roundOffset: off)),
      );
      if (mounted) {
        for (var i = 0; i < _cachedOffsets.length; i++) {
          _cache[_cachedOffsets[i]] = results[i];
        }
        setState(() => _loading = false);
        _prefetchMatchDetails();
        _loadPlayoffGroups();
      }
    } catch (e) {
      if (mounted) {
        if (e is ApiException && e.statusCode == 401) {
          widget.authState.logout();
          return;
        }
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  void _changeRound(int delta) {
    final next = _roundOffset + delta;
    if (!_cachedOffsets.contains(next)) return;
    AppHaptics.selection();
    setState(() => _roundOffset = next);
  }

  void _openStats(WeekFixture f) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.colors.scrim,
      builder: (_) => MatchStatsSheet(
        fixture: f,
        myTeam: _myTeam,
        apiClient: widget.authState.api,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppScaffold(
      currentTab: AppTab.dashboard,
      onTabSelected: widget.onTabSelected,
      onProfileTap: widget.onProfileTap,
      avatarUrl: widget.authState.user?.avatarUrl,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -200) _changeRound(1);
          if (details.primaryVelocity! > 200) _changeRound(-1);
        },
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: SpacingTokens.lg),
                child: AppLoadingSkeleton(rows: 5, rowHeight: 84),
              )
            : _error != null
                ? _buildError(c)
                : _buildContent(c),
      ),
    );
  }

  Widget _buildError(AppColorTokens c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L10n.t('dashboard.errorTitle'),
              style: TypographyTokens.headline.copyWith(color: c.negative)),
          const SizedBox(height: SpacingTokens.sm),
          Text(_error!,
              style: TypographyTokens.body.copyWith(color: c.textMuted),
              textAlign: TextAlign.center),
          const SizedBox(height: SpacingTokens.lg),
          TextButton(
            onPressed: _loadAll,
            child: Text(L10n.t('dashboard.retry'),
                style: TypographyTokens.buttonLabel.copyWith(color: c.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppColorTokens c) {
    // The backend already scoped this offset to one round. During the group
    // phase every fixture is sorted into its Championship / Relegation group with
    // the subject club's group (and match) first; otherwise the subject club is
    // pinned above a single "Regular Season" list.
    final roundFixtures = _fixtures;
    var index = 0;

    final groupPhase = _weekIsPlayoffWindow() &&
        _playoffAssets.isNotEmpty &&
        _playoutAssets.isNotEmpty;
    final sections = groupPhase
        ? _buildGroupPhaseSections(roundFixtures, c, () => index++)
        : _buildRegularSections(roundFixtures, c, () => index++);

    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.surfaceHigh,
      onRefresh: () => _loadAll(forceRefresh: true),
      child: ListView(
        children: [
          _buildRoundHeader(c),
          const SizedBox(height: SpacingTokens.lg),
          ...sections,
          if (roundFixtures.isEmpty)
            AppEmptyState(
              icon: Icons.calendar_today_outlined,
              headline: L10n.t('dashboard.empty'),
              body: L10n.t('dashboard.emptyBody'),
            ),
          const SizedBox(height: SpacingTokens.xxl),
        ],
      ),
    );
  }

  /// Regular-season layout: the subject club pinned at the top (its match carries
  /// the win-chance headline), then a single "Regular Season" list of the rest.
  List<Widget> _buildRegularSections(
    List<WeekFixture> roundFixtures,
    AppColorTokens c,
    int Function() nextIndex,
  ) {
    final subjectFixtures = roundFixtures.where((f) => f.involvesSubject).toList();
    final otherFixtures = roundFixtures.where((f) => !f.involvesSubject).toList();
    final widgets = <Widget>[];
    if (subjectFixtures.isNotEmpty) {
      widgets.add(_buildSectionLabel(
        (_roundOffset < 0
                ? L10n.t('dashboard.subjectResults')
                : _roundOffset == 0
                    ? L10n.t('dashboard.subjectThisRound')
                    : L10n.t('dashboard.subjectNextRound'))
            .replaceAll('{team}', _myTeam.toUpperCase()),
        c.primary,
        c,
      ));
      widgets.add(const SizedBox(height: SpacingTokens.sm));
      widgets.addAll(subjectFixtures
          .map((f) => _buildMatchCard(f, highlight: true, c: c, index: nextIndex())));
      widgets.add(const SizedBox(height: SpacingTokens.xl));
    }
    if (otherFixtures.isNotEmpty) {
      widgets.addAll(_buildOtherList(
          L10n.t('dashboard.regularSeason'), otherFixtures, c, nextIndex));
    }
    return widgets;
  }

  /// Group-phase layout: every fixture is sorted into its Championship or
  /// Relegation group. The subject club's group leads (in the cobalt accent) and
  /// its own match is the first card of that group (and the only highlighted one),
  /// so the coach's fixture is always the first row. Cross-group or unresolved
  /// fixtures fall to a trailing "Other Matches" list rather than being dropped.
  List<Widget> _buildGroupPhaseSections(
    List<WeekFixture> roundFixtures,
    AppColorTokens c,
    int Function() nextIndex,
  ) {
    final championship = <WeekFixture>[];
    final relegation = <WeekFixture>[];
    final unclassified = <WeekFixture>[];
    for (final f in roundFixtures) {
      switch (_classifyFixture(f)) {
        case 'playoff':
          championship.add(f);
        case 'playout':
          relegation.add(f);
        default:
          unclassified.add(f);
      }
    }
    // Float the subject's own match to the top of its group.
    void subjectFirst(List<WeekFixture> list) {
      final i = list.indexWhere((f) => f.involvesSubject);
      if (i > 0) list.insert(0, list.removeAt(i));
    }
    subjectFirst(championship);
    subjectFirst(relegation);

    final widgets = <Widget>[];
    void addGroup(String label, List<WeekFixture> fixtures, Color color) {
      if (fixtures.isEmpty) return;
      widgets.add(_buildSectionLabel(label, color, c));
      widgets.add(const SizedBox(height: SpacingTokens.sm));
      for (final f in fixtures) {
        widgets.add(_buildMatchCard(
            f, highlight: f.involvesSubject, c: c, index: nextIndex()));
      }
      widgets.add(const SizedBox(height: SpacingTokens.xl));
    }

    final champLabel = L10n.t('dashboard.playoff');
    final relLabel = L10n.t('dashboard.playout');
    // The subject's own group leads in the accent tone; the other reads muted.
    // Defaults to championship-first when the subject's group is unknown.
    if (_subjectGroup == 'playout') {
      addGroup(relLabel, relegation, c.primary);
      addGroup(champLabel, championship, c.textMuted);
    } else {
      addGroup(champLabel, championship, c.primary);
      addGroup(relLabel, relegation, c.textMuted);
    }
    if (unclassified.isNotEmpty) {
      widgets.addAll(_buildOtherList(
          L10n.t('dashboard.otherMatches'), unclassified, c, nextIndex));
    }
    return widgets;
  }

  /// One labelled section of other-match cards sharing the staggered index.
  List<Widget> _buildOtherList(
    String label,
    List<WeekFixture> fixtures,
    AppColorTokens c,
    int Function() nextIndex,
  ) {
    return [
      _buildSectionLabel(label, c.textMuted, c),
      const SizedBox(height: SpacingTokens.sm),
      ...fixtures.map(
        (f) => _buildMatchCard(f, highlight: false, c: c, index: nextIndex()),
      ),
      const SizedBox(height: SpacingTokens.xl),
    ];
  }

  /// Classify a fixture by the standings groups: 'playoff' when both teams are in
  /// the championship group, 'playout' when both are in the relegation group,
  /// otherwise null. Matching is by resolved crest so every name variant (e.g.
  /// "U Craiova" vs "Universitatea Craiova") lines up.
  String? _classifyFixture(WeekFixture f) {
    final home = badgeAssetForName(f.homeTeam);
    final away = badgeAssetForName(f.awayTeam);
    if (home == null || away == null) return null;
    if (_playoffAssets.contains(home) && _playoffAssets.contains(away)) return 'playoff';
    if (_playoutAssets.contains(home) && _playoutAssets.contains(away)) return 'playout';
    return null;
  }

  // ── Round control ─────────────────────────────────────────────────────────

  Widget _buildRoundHeader(AppColorTokens c) {
    // Chevrons are bounded by what the backend prefetched (offsets -2..2); the
    // backend itself clamps the resolved round to [1, 33].
    final canBack = _roundOffset > _cachedOffsets.first;
    final canFwd = _roundOffset < _cachedOffsets.last;
    // Primary line is the matchday ("Round N"); falls back to a relative round
    // label only when no fixture carries a round. Secondary line is the round's
    // date span. The play-off / play-out phase lives in the section headers.
    final mp = _matchdayLabel();
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.control,
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          _chevron(Icons.chevron_left, canBack, () => _changeRound(-1), c),
          Expanded(
            child: Column(
              children: [
                Text(mp ?? _relativeWeekLabel(),
                    style: TypographyTokens.meta.copyWith(
                        color: mp != null ? c.textPrimary : c.textMuted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(_roundSpanLabel(),
                    style: TypographyTokens.sectionLabel.copyWith(
                        color: c.textMuted, fontSize: 9)),
              ],
            ),
          ),
          _chevron(Icons.chevron_right, canFwd, () => _changeRound(1), c),
        ],
      ),
    );
  }

  Widget _chevron(
      IconData icon, bool enabled, VoidCallback onTap, AppColorTokens c) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: enabled ? c.primary : c.textMuted.withValues(alpha: 0.4),
        padding: EdgeInsets.zero,
        onPressed: enabled ? onTap : null,
      ),
    );
  }

  /// The first fixture of the displayed round carrying a round number, used as
  /// the canonical source for the matchday label and the round's phase.
  WeekFixture? _roundFixture() {
    for (final f in _fixtures) {
      if (f.round != null) return f;
    }
    return null;
  }

  /// "Etapa N" / "Round N" for the displayed round, from the first fixture
  /// carrying a round number; null when no round is available (e.g. CSV
  /// fallback). The play-off / play-out phase is intentionally omitted here and
  /// surfaced in the section headers instead.
  String? _matchdayLabel() {
    final withRound = _roundFixture();
    if (withRound == null) return null;
    final ro = L10n.instance.isRomanian;
    final r = withRound.round;
    // Knockout phase: the play-off and play-out share a matchday number that
    // restarts at 1 after the 30-round regular season, so map round 31.. back
    // to "Round 1.." under a "Play-off / Play-out" label rather than "Round 31".
    const regularRounds = 30;
    if (r != null && r > regularRounds) {
      return L10n.t('dashboard.knockoutRound')
          .replaceAll('{n}', '${r - regularRounds}');
    }
    return ro ? 'Etapa $r' : 'Round $r';
  }

  /// True when the displayed round sits in the Romanian Superliga play-off /
  /// play-out window, judged from the round's fixture dates (any fixture in the
  /// window qualifies), so the split sections appear for the spring window.
  bool _weekIsPlayoffWindow() {
    for (final f in _fixtures) {
      if (f.matchDate.isNotEmpty && _isPlayoffWindow(f.matchDate)) return true;
    }
    return false;
  }

  /// True when the date sits in the Romanian Superliga play-off / play-out
  /// window (13 March through the end of May). The 2025-26 regular season's last
  /// round (Round 30) was played 6-9 March 2026 as one table; the Championship
  /// and Relegation groups began on 13-14 March 2026, so the window opens 13
  /// March. Kept in lockstep with the backend cutoff
  /// (``_REGULAR_SEASON_CUTOFFS["2025"] == "2026-03-13"``) so the section split
  /// only appears from 13 March onward.
  bool _isPlayoffWindow(String matchDate) {
    final d = DateTime.tryParse(matchDate);
    if (d == null) return false;
    return (d.month == 3 && d.day >= 13) || d.month == 4 || d.month == 5;
  }

  /// Relative round label ("ROUND +1" / "ROUND -1"), used only as the primary
  /// header line when no fixture carries a round number.
  String _relativeWeekLabel() {
    final roundWord = L10n.t('dashboard.weekRelative');
    return _roundOffset == 0
        ? L10n.t('dashboard.weekCurrent')
        : _roundOffset > 0
            ? '$roundWord +$_roundOffset'
            : '$roundWord $_roundOffset';
  }

  /// The round's date span: the earliest to the latest match_date of the shown
  /// fixtures (a round can straddle mid-week and weekend). Collapses to a single
  /// date when every fixture shares the day, and is empty when no fixture has a
  /// parseable date.
  String _roundSpanLabel() {
    DateTime? min;
    DateTime? max;
    for (final f in _fixtures) {
      final dt = DateTime.tryParse(f.matchDate);
      if (dt == null) continue;
      final day = DateTime.utc(dt.year, dt.month, dt.day);
      if (min == null || day.isBefore(min)) min = day;
      if (max == null || day.isAfter(max)) max = day;
    }
    if (min == null || max == null) return '';
    final ro = L10n.instance.isRomanian;
    final start = '${min.day} ${_monAbbr(min.month, ro)}';
    if (min == max) return '$start ${max.year}';
    final end = '${max.day} ${_monAbbr(max.month, ro)} ${max.year}';
    return '$start - $end';
  }

  // ── Section label ───────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text, Color color, AppColorTokens c) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: SpacingTokens.xs),
        Text(text, style: TypographyTokens.sectionLabel.copyWith(color: color)),
      ],
    );
  }

  // ── Fixture card ────────────────────────────────────────────────────────────

  Widget _buildMatchCard(
    WeekFixture f, {
    required bool highlight,
    required AppColorTokens c,
    required int index,
  }) {
    final isHome = f.isSubjectHome;
    final isUpcoming = !f.isCompleted;

    // Result for the W/D/L dot + score colour (U Cluj completed only).
    Color? resultColor;
    String? resultLetter;
    if (f.isCompleted && f.involvesSubject) {
      final myScore = isHome ? f.homeScore! : f.awayScore!;
      final theirScore = isHome ? f.awayScore! : f.homeScore!;
      final won = myScore > theirScore;
      final lost = myScore < theirScore;
      resultColor = won ? c.positive : (lost ? c.negative : c.textMuted);
      resultLetter = _resultLetter(won, lost);
    }

    return Reveal(
      delay: MotionTokens.stagger * index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
        child: Pressable(
          onTap: () => _openStats(f),
          semanticLabel: '${f.homeTeam} ${f.awayTeam}',
          child: Container(
            decoration: BoxDecoration(
              color: c.surfaceLow,
              borderRadius: ShapeTokens.card,
              border: Border.all(
                color: highlight
                    ? c.primary.withValues(alpha: 0.35)
                    : c.divider,
              ),
              boxShadow:
                  highlight && isUpcoming ? ShapeTokens.e1(context) : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cobalt top rule marks an upcoming fixture (prescriptive flow
                // available); completed fixtures omit it and read archival.
                if (isUpcoming) Container(height: 2, color: c.primary),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpacingTokens.md,
                    SpacingTokens.sm,
                    SpacingTokens.md,
                    SpacingTokens.sm,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _teamRow(f.homeTeam, highlight && isHome, c),
                                const SizedBox(height: SpacingTokens.xs),
                                _teamRow(f.awayTeam, highlight && !isHome, c),
                              ],
                            ),
                          ),
                          const SizedBox(width: SpacingTokens.sm),
                          _headline(f, highlight, resultColor, resultLetter, c),
                        ],
                      ),
                      const SizedBox(height: SpacingTokens.xs),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _fmtMeta(f),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TypographyTokens.meta
                                  .copyWith(color: c.textMuted),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 16,
                              color: c.textMuted.withValues(alpha: 0.7)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The single headline on the right of a card: final score (completed),
  /// U Cluj win chance (upcoming highlighted), or a quiet "vs" otherwise.
  Widget _headline(WeekFixture f, bool highlight, Color? resultColor,
      String? resultLetter, AppColorTokens c) {
    if (f.isCompleted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (resultColor != null && resultLetter != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: resultColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(resultLetter,
                    style: TypographyTokens.meta.copyWith(
                        color: resultColor, fontWeight: FontWeight.w700)),
              ],
            ),
          const SizedBox(height: 2),
          Text(
            '${f.homeScore} - ${f.awayScore}',
            style: TypographyTokens.statValue
                .copyWith(fontSize: 22, color: c.textPrimary),
          ),
        ],
      );
    }

    final uclProb = f.homeWinProbability;
    if (highlight && uclProb != null) {
      final band = uclProb >= 0.55
          ? c.positive
          : uclProb >= 0.40
              ? c.primary
              : c.negative;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${(uclProb * 100).round()}%',
              style: TypographyTokens.statValue
                  .copyWith(color: band, fontSize: 24)),
          Text(L10n.t('dashboard.winChance'),
              style: TypographyTokens.sectionLabel
                  .copyWith(color: c.textMuted, fontSize: 8)),
        ],
      );
    }

    return Text('vs',
        style: TypographyTokens.cardTitle.copyWith(color: c.textMuted));
  }

  String _resultLetter(bool won, bool lost) {
    final ro = L10n.instance.isRomanian;
    if (won) return ro ? 'V' : 'W';
    if (lost) return ro ? 'Î' : 'L';
    return ro ? 'E' : 'D';
  }

  Widget _teamRow(String name, bool isMine, AppColorTokens c) {
    return Row(
      children: [
        TeamCrest(teamName: name, size: 22),
        const SizedBox(width: SpacingTokens.xs),
        Flexible(
          child: Text(
            _shortName(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TypographyTokens.cardTitle.copyWith(
              fontWeight: isMine ? FontWeight.w700 : FontWeight.w500,
              color: isMine ? c.textPrimary : c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _shortName(String name) =>
      name.replaceAll('Universitatea Cluj', 'U Cluj');

  String _fmtMeta(WeekFixture f) {
    final ro = L10n.instance.isRomanian;
    final dt = DateTime.tryParse(f.matchDate);
    final datePart =
        dt != null ? '${dt.day} ${_monAbbr(dt.month, ro)}' : f.displayDate;
    if (f.venue != null && f.venue!.isNotEmpty) {
      return '$datePart  ·  ${f.venue}';
    }
    return datePart;
  }

  String _monAbbr(int month, bool ro) {
    const en = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const roMonths = [
      '', 'ian.', 'feb.', 'mar.', 'apr.', 'mai', 'iun.',
      'iul.', 'aug.', 'sep.', 'oct.', 'nov.', 'dec.',
    ];
    if (month < 1 || month > 12) return '';
    return ro ? roMonths[month] : en[month];
  }

}
