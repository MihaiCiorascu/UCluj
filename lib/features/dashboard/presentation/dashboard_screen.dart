import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/primitives/haptics.dart';
import '../../../core/primitives/pressable.dart';
import '../../../core/primitives/reveal.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/state/meta_state.dart';
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
import '../../../data/models/week_fixture.dart';
import '../../../data/repositories/match_details_repository.dart';
import '../../../data/repositories/week_repository.dart';
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
  bool _loading = true;
  String? _error;
  int _weekOffset = 0;

  // Local 5-week cache: offset → fixtures. Populated once on load, cleared on refresh.
  static const List<int> _cachedOffsets = [-2, -1, 0, 1, 2];
  final Map<int, List<WeekFixture>> _cache = {};

  static const String _myTeam = 'Universitatea Cluj';

  // All fixtures returned by the backend for this offset
  List<WeekFixture> get _fixtures => _cache[_weekOffset] ?? [];

  /// Server's effective notion of "now" mirrored on the client. When demo
  /// mode is on (MetaState.demoMode), pivots the dashboard week math around
  /// the demo date at noon UTC so the displayed Monday-Sunday window matches
  /// what /api/v1/week-fixtures actually slices server-side. In production
  /// this falls back to the real wall-clock time and behaves as before.
  DateTime _effectiveNow() {
    final meta = MetaState.instance;
    if (meta.demoMode && meta.demoToday.isNotEmpty) {
      final parts = meta.demoToday.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          return DateTime.utc(y, m, d, 12, 0);
        }
      }
    }
    return DateTime.now().toUtc();
  }

  // The Monday (UTC midnight) of the currently displayed week
  DateTime _weekMonday() {
    final now = _effectiveNow();
    final today = DateTime.utc(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    return thisMonday.add(Duration(days: _weekOffset * 7));
  }

  // Only fixtures whose match date falls within the displayed Mon–Sun window
  List<WeekFixture> get _thisWeekFixtures {
    final monday = _weekMonday();
    final nextMonday = monday.add(const Duration(days: 7));
    return _fixtures.where((f) {
      final dt = DateTime.tryParse(f.matchDate)?.toUtc();
      if (dt == null) return false;
      final matchDay = DateTime.utc(dt.year, dt.month, dt.day);
      return !matchDay.isBefore(monday) && matchDay.isBefore(nextMonday);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _repo = WeekRepository(apiClient: widget.authState.api);
    _detailsRepo = MatchDetailsRepository(apiClient: widget.authState.api);
    _loadAll();
  }

  /// Silently warm the backend disk cache for completed U Cluj matches.
  void _prefetchMatchDetails() {
    final completed = _cache.values
        .expand((fixtures) => fixtures)
        .where((f) => f.isCompleted && f.involvesUCluj && f.matchId.isNotEmpty)
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

  /// Fetch all 5 weeks in parallel and populate the cache.
  Future<void> _loadAll({bool forceRefresh = false}) async {
    setState(() { _loading = true; _error = null; });
    if (forceRefresh) _cache.clear();
    try {
      final results = await Future.wait(
        _cachedOffsets.map((off) => _repo.fetchWeekFixtures(weekOffset: off)),
      );
      if (mounted) {
        for (var i = 0; i < _cachedOffsets.length; i++) {
          _cache[_cachedOffsets[i]] = results[i];
        }
        setState(() => _loading = false);
        _prefetchMatchDetails();
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

  void _changeWeek(int delta) {
    final next = _weekOffset + delta;
    if (!_cachedOffsets.contains(next)) return;
    AppHaptics.selection();
    setState(() => _weekOffset = next);
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
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -200) _changeWeek(1);
          if (details.primaryVelocity! > 200) _changeWeek(-1);
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
    final weekFixtures = _thisWeekFixtures;
    final uclFixtures   = weekFixtures.where((f) => f.involvesUCluj).toList();
    final otherFixtures = weekFixtures.where((f) => !f.involvesUCluj).toList();

    // Continuous index so the whole list staggers in as one sequence.
    var index = 0;

    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.surfaceHigh,
      onRefresh: () => _loadAll(forceRefresh: true),
      child: ListView(
        children: [
          _buildWeekHeader(c),
          const SizedBox(height: SpacingTokens.lg),

          // U Cluj section
          if (uclFixtures.isNotEmpty) ...[
            _buildSectionLabel(
              _weekOffset < 0
                  ? L10n.t('dashboard.uclujResults')
                  : _weekOffset == 0
                      ? L10n.t('dashboard.uclujThisWeek')
                      : L10n.t('dashboard.uclujNextRound'),
              c.primary,
              c,
            ),
            const SizedBox(height: SpacingTokens.sm),
            ...uclFixtures.map(
                (f) => _buildMatchCard(f, highlight: true, c: c, index: index++)),
            const SizedBox(height: SpacingTokens.xl),
          ],

          // Other Liga 1 matches
          if (otherFixtures.isNotEmpty) ...[
            _buildSectionLabel(L10n.t('dashboard.otherMatches'), c.textMuted, c),
            const SizedBox(height: SpacingTokens.sm),
            ...otherFixtures.map(
                (f) => _buildMatchCard(f, highlight: false, c: c, index: index++)),
          ],

          if (weekFixtures.isEmpty)
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

  // ── Week control ──────────────────────────────────────────────────────────

  Widget _buildWeekHeader(AppColorTokens c) {
    final canBack = _weekOffset > _cachedOffsets.first;
    final canFwd = _weekOffset < _cachedOffsets.last;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.control,
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          _chevron(Icons.chevron_left, canBack, () => _changeWeek(-1), c),
          Expanded(
            child: Column(
              children: [
                Text(_visibleRangeLabel(),
                    style: TypographyTokens.meta.copyWith(
                        color: c.textPrimary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(_relativeWeekLabel(),
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: c.textMuted, fontSize: 9)),
              ],
            ),
          ),
          _chevron(Icons.chevron_right, canFwd, () => _changeWeek(1), c),
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

  String _relativeWeekLabel() {
    final weekWord = L10n.t('dashboard.weekRelative');
    return _weekOffset == 0
        ? L10n.t('dashboard.weekCurrent')
        : _weekOffset > 0
            ? '$weekWord +$_weekOffset'
            : '$weekWord $_weekOffset';
  }

  String _visibleRangeLabel() {
    final monday = _weekMonday();
    final sunday = monday.add(const Duration(days: 6));
    final ro = L10n.instance.isRomanian;
    return '${monday.day} ${_monAbbr(monday.month, ro)} - '
        '${sunday.day} ${_monAbbr(sunday.month, ro)} ${sunday.year}';
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
    final isHome = f.isUCLujHome;
    final isUpcoming = !f.isCompleted;

    // Result for the W/D/L dot + score colour (U Cluj completed only).
    Color? resultColor;
    String? resultLetter;
    if (f.isCompleted && f.involvesUCluj) {
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
