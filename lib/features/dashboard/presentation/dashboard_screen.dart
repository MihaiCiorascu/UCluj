import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/state/meta_state.dart';
import '../../../core/services/api_client.dart' show ApiException;
import '../../../core/theme/app_colors.dart';
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
      _detailsRepo.fetchMatchDetails(id).catchError((_) => throw _);
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
    setState(() => _weekOffset = next);
  }

  void _openStats(WeekFixture f) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                child: AppLoadingSkeleton(rows: 5, rowHeight: 72),
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
                style: TypographyTokens.sectionLabel.copyWith(color: c.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppColorTokens c) {
    final weekFixtures = _thisWeekFixtures;
    final uclFixtures   = weekFixtures.where((f) => f.involvesUCluj).toList();
    final otherFixtures = weekFixtures.where((f) => !f.involvesUCluj).toList();

    return RefreshIndicator(
      color: c.accent,
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
              c.accent,
              c,
            ),
            const SizedBox(height: SpacingTokens.sm),
            ...uclFixtures.map((f) => _buildMatchCard(f, highlight: true, c: c)),
            const SizedBox(height: SpacingTokens.xl),
          ],

          // Other Liga 1 matches
          if (otherFixtures.isNotEmpty) ...[
            _buildSectionLabel(L10n.t('dashboard.otherMatches'), c.textMuted, c),
            const SizedBox(height: SpacingTokens.sm),
            ...otherFixtures.map((f) => _buildMatchCard(f, highlight: false, c: c)),
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

  Widget _buildWeekHeader(AppColorTokens c) {
    final label = _visibleRangeLabel();
    final weekWord = L10n.t('dashboard.weekRelative');
    final weekLabel = _weekOffset == 0
        ? L10n.t('dashboard.weekCurrent')
        : _weekOffset > 0
            ? '$weekWord +$_weekOffset'
            : '$weekWord $_weekOffset';

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.divider),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.xs, vertical: SpacingTokens.xs),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left,
                color: _weekOffset > _cachedOffsets.first
                    ? c.accent
                    : c.textMuted,
                size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _weekOffset > _cachedOffsets.first ? () => _changeWeek(-1) : null,
          ),
          Icon(Icons.calendar_today, color: c.accent, size: 13),
          const SizedBox(width: SpacingTokens.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(weekLabel,
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: c.textMuted, fontSize: 9)),
                Text(label,
                    style: TypographyTokens.sectionLabel
                        .copyWith(color: c.accent, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                color: _weekOffset < _cachedOffsets.last
                    ? c.accent
                    : c.textMuted,
                size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _weekOffset < _cachedOffsets.last ? () => _changeWeek(1) : null,
          ),
        ],
      ),
    );
  }

  String _visibleRangeLabel() {
    final monday = _weekMonday();
    final sunday = monday.add(const Duration(days: 6));
    return '${_fmtDate(monday)} — ${_fmtDate(sunday, withYear: true)}';
  }

  String _fmtDate(DateTime d, {bool withYear = false}) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    if (withYear) return '$dd.$mm.${d.year}';
    return '$dd.$mm';
  }

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

  Widget _buildMatchCard(WeekFixture f, {required bool highlight, required AppColorTokens c}) {
    final isHome = f.isUCLujHome;
    final prob = f.homeWinProbability;
    final uclProb = highlight ? prob : prob;

    final probPct = uclProb != null ? '${(uclProb * 100).round()}%' : '--';
    final probColor = uclProb == null
        ? c.textMuted
        : uclProb >= 0.55
            ? c.positive
            : uclProb >= 0.40
                ? c.accent
                : c.negative;

    String result = '';
    Color resultColor = c.textMuted;
    if (f.isCompleted && highlight) {
      final myScore = isHome ? f.homeScore! : f.awayScore!;
      final theirScore = isHome ? f.awayScore! : f.homeScore!;
      if (myScore > theirScore) { result = 'V'; resultColor = c.positive; }
      else if (myScore < theirScore) { result = 'Î'; resultColor = c.negative; }
      else { result = 'E'; resultColor = c.accent; }
    }

    return GestureDetector(
      onTap: () => _openStats(f),
      child: Container(
        // Iteration N polish: lift the inter-card gap from 3 px to 12 px so
        // the fixture list reads with editorial rhythm instead of compressed.
        margin: const EdgeInsets.only(bottom: SpacingTokens.sm),
        decoration: BoxDecoration(
          color: c.surfaceLow,
          borderRadius: BorderRadius.circular(6),
          border: highlight
              ? Border.all(color: c.accent.withValues(alpha: 0.4))
              : Border.all(color: c.divider),
          boxShadow: highlight
              ? [
                  BoxShadow(
                    color: c.cardGlow,
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gold accent left bar for highlighted card
                if (highlight)
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [c.accent, c.accentStrong],
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Result badge
                            if (result.isNotEmpty) ...[
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: resultColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Center(
                                  child: Text(result,
                                      style: TypographyTokens.sectionLabel
                                          .copyWith(color: resultColor, fontSize: 10)),
                                ),
                              ),
                              const SizedBox(width: SpacingTokens.sm),
                            ],

                            // Teams
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _teamRow(f.homeTeam, highlight && isHome, c),
                                  const SizedBox(height: 3),
                                  _teamRow(f.awayTeam, highlight && !isHome, c),
                                ],
                              ),
                            ),

                            // Score or probability
                            f.isCompleted
                                ? _scoreBlock(f, c)
                                : _probabilityBlock(probPct, probColor, highlight, c),
                          ],
                        ),

                        // Date + venue
                        const SizedBox(height: SpacingTokens.xs),
                        Row(
                          children: [
                            Text(f.displayDate,
                                style: TypographyTokens.meta
                                    .copyWith(color: c.textMuted, fontSize: 10)),
                            if (f.venue != null) ...[
                              Text('  ·  ${f.venue}',
                                  style: TypographyTokens.meta
                                      .copyWith(color: c.textMuted, fontSize: 10)),
                            ],
                            const Spacer(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(L10n.t('dashboard.analysis'),
                                    style: TypographyTokens.sectionLabel
                                        .copyWith(color: c.accent, fontSize: 9)),
                                Icon(Icons.chevron_right, size: 10, color: c.accent),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _teamRow(String name, bool isMine, AppColorTokens c) {
    final display = name.replaceAll('Universitatea Cluj', 'U CLUJ');
    return Text(
      display.toUpperCase(),
      style: TypographyTokens.cardTitle.copyWith(
        fontWeight: isMine ? FontWeight.w800 : FontWeight.w400,
        color: isMine ? c.textPrimary : c.textSecondary,
        fontSize: 12,
      ),
    );
  }

  Widget _scoreBlock(WeekFixture f, AppColorTokens c) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.divider),
      ),
      child: Text(
        '${f.homeScore} — ${f.awayScore}',
        style: TypographyTokens.statValue.copyWith(
            fontSize: 16, letterSpacing: 2, color: c.textPrimary),
      ),
    );
  }

  Widget _probabilityBlock(String pct, Color color, bool highlight, AppColorTokens c) {
    if (!highlight) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(pct,
            style: TypographyTokens.statValue.copyWith(
                color: color, fontSize: 20, letterSpacing: 0)),
        Text(L10n.t('dashboard.winChance'),
            style: TypographyTokens.sectionLabel
                .copyWith(color: c.textMuted, fontSize: 8)),
      ],
    );
  }
}
