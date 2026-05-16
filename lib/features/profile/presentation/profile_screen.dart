import 'package:flutter/material.dart';

import '../../../core/state/auth_state.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/theme_mode_notifier.dart';
import '../../../core/theme/typography_tokens.dart';

// =============================================================================
// DEMO DATA — isolate here, swap for real API later
// =============================================================================

class _Demo {
  const _Demo._();
  static const String name = 'Mihai Ciorăscu';
  static const String role = 'TACTICAL ANALYST';
  static const String country = 'Romania';
  static const String memberSince = 'Apr 2026';
  static const String lastActive = 'Today';
  static const String accessLevel = 'Pro';

  static const String briefsGenerated = '18';
  static const String simulationsRun = '42';
  static const String savedBlueprints = '7';
  static const String reportsExported = '5';

  static const String tacticalStyle = 'Structured Pressure';
  static const String formationPref = '4-2-3-1';
  static const String league = 'Romanian Superliga';
  static const String season = '2025–2026';
  static const String lastAnalyzed = 'vs CFR Cluj';
  static const String exportFormat = 'PDF';
  static const String language = 'English';

  static const String plan = 'Pro — Thesis Build';
  static const String security = 'Standard JWT Access';
  static const String notifications = 'Enabled';

  static const List<_ActivityData> activities = [
    _ActivityData('Generated tactical brief', 'FCSB vs CFR Cluj', '2h ago'),
    _ActivityData('Ran Monte Carlo simulation', 'FCSB vs Rapid București', '1d ago'),
    _ActivityData('Exported match report', 'FCSB vs Universitatea Craiova', '3d ago'),
    _ActivityData('Saved tactical blueprint', 'Wide overload plan', '5d ago'),
    _ActivityData('Analyzed fixture probabilities', 'Round 28 — full batch', '1w ago'),
  ];

  static const List<_SavedData> savedBriefs = [
    _SavedData('vs CFR Cluj — Match Brief', 'Mar 28, 2026'),
    _SavedData('vs Rapid — Tactical Blueprint', 'Mar 21, 2026'),
    _SavedData('vs U Craiova — Key Drivers Report', 'Mar 14, 2026'),
  ];
}

class _ActivityData {
  const _ActivityData(this.action, this.detail, this.time);
  final String action, detail, time;
}

class _SavedData {
  const _SavedData(this.title, this.date);
  final String title, date;
}

// =============================================================================
// PROFILE SCREEN
// =============================================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.authState,
    this.themeMode,
    super.key,
  });
  final AuthState authState;

  /// Iteration N — optional theme-mode notifier. When present, the
  /// profile screen exposes a sun/moon toggle in the AppBar.
  final ThemeModeNotifier? themeMode;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tabIndex = 0;
  static const _tabs = ['OVERVIEW', 'ACTIVITY', 'ACCOUNT'];

  AuthUser? get _user => widget.authState.user;
  String get _team => _user?.teamName ?? 'No Team';
  String get _email => _user?.email ?? '—';
  String get _userRole => _user?.role.toUpperCase() ?? 'COACH';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.surfaceBaseGradient),
        child: SafeArea(
          child: Column(
            children: [
              _ProfileHeader(
                onBack: () => Navigator.of(context).pop(),
                themeMode: widget.themeMode,
              ),
              Divider(height: 1, color: c.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.xl, SpacingTokens.xl,
                  SpacingTokens.xl, 40,
                ),
                children: [
                  _ProfileHero(team: _team),
                  const SizedBox(height: SpacingTokens.lg),
                  _IdentitySummary(
                    memberSince: _Demo.memberSince,
                    lastActive: _Demo.lastActive,
                    club: _team,
                    access: _Demo.accessLevel,
                  ),
                  const SizedBox(height: SpacingTokens.xl),
                  _SegmentedControl(
                    tabs: _tabs,
                    selected: _tabIndex,
                    onChanged: (i) => setState(() => _tabIndex = i),
                  ),
                  const SizedBox(height: SpacingTokens.xl),
                  if (_tabIndex == 0) _buildOverview(context),
                  if (_tabIndex == 1) _buildActivity(context),
                  if (_tabIndex == 2) _buildAccount(context),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OVERVIEW
  // ---------------------------------------------------------------------------

  Widget _buildOverview(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PLATFORM USAGE  ·  LAST 30 DAYS',
            style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        const Row(children: [
          Expanded(child: _StatCard(value: _Demo.briefsGenerated, label: 'BRIEFS\nGENERATED')),
          SizedBox(width: SpacingTokens.sm),
          Expanded(child: _StatCard(value: _Demo.simulationsRun, label: 'SIMULATIONS\nRUN')),
        ]),
        const SizedBox(height: SpacingTokens.sm),
        const Row(children: [
          Expanded(child: _StatCard(value: _Demo.savedBlueprints, label: 'SAVED\nBLUEPRINTS')),
          SizedBox(width: SpacingTokens.sm),
          Expanded(child: _StatCard(value: _Demo.reportsExported, label: 'REPORTS\nEXPORTED')),
        ]),

        const SizedBox(height: SpacingTokens.xl),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: SpacingTokens.xl),

        Text('RECENT ACTIVITY', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        for (final a in _Demo.activities.take(3))
          _ActivityItem(action: a.action, detail: a.detail, time: a.time),

        const SizedBox(height: SpacingTokens.xl),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: SpacingTokens.xl),

        Text('WORKSPACE', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        _InfoRow(label: 'DEFAULT CLUB', value: _team),
        _InfoRow(label: 'PREFERRED TEAM', value: _team),
        const _InfoRow(label: 'LAST ANALYZED', value: _Demo.lastAnalyzed),
        const _InfoRow(label: 'LEAGUE', value: _Demo.league),
        const _InfoRow(label: 'SEASON', value: _Demo.season),
        const _InfoRow(label: 'LANGUAGE', value: _Demo.language),
        const _InfoRow(label: 'EXPORT FORMAT', value: _Demo.exportFormat),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIVITY
  // ---------------------------------------------------------------------------

  Widget _buildActivity(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECENT ACTIVITY', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        for (final a in _Demo.activities)
          _ActivityItem(action: a.action, detail: a.detail, time: a.time),

        const SizedBox(height: SpacingTokens.xl),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: SpacingTokens.xl),

        Text('SAVED BRIEFS', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        for (final s in _Demo.savedBriefs)
          _SavedItem(title: s.title, date: s.date),

        const SizedBox(height: SpacingTokens.xl),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: SpacingTokens.xl),

        Text('SAVED ASSETS', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        const Row(children: [
          Expanded(child: _StatCard(value: '3', label: 'SAVED\nBRIEFS')),
          SizedBox(width: SpacingTokens.sm),
          Expanded(child: _StatCard(value: _Demo.savedBlueprints, label: 'SAVED\nBLUEPRINTS')),
          SizedBox(width: SpacingTokens.sm),
          Expanded(child: _StatCard(value: '2', label: 'WATCHLIST\nTEAMS')),
        ]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ACCOUNT
  // ---------------------------------------------------------------------------

  Widget _buildAccount(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PLAN & ACCESS', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        const _InfoRow(label: 'PLAN', value: _Demo.plan),
        _InfoRow(label: 'EMAIL', value: _email),
        _InfoRow(label: 'ROLE', value: _userRole),
        const _InfoRow(label: 'SECURITY', value: _Demo.security),
        const _InfoRow(label: 'NOTIFICATIONS', value: _Demo.notifications),

        const SizedBox(height: SpacingTokens.xl),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: SpacingTokens.xl),

        Text('PREFERENCES', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        const _InfoRow(label: 'LANGUAGE', value: _Demo.language),
        const _InfoRow(label: 'EXPORT FORMAT', value: _Demo.exportFormat),
        const _InfoRow(label: 'DEFAULT VIEW', value: 'Dashboard'),
        _InfoRow(label: 'DEFAULT CLUB', value: _team),

        const SizedBox(height: SpacingTokens.xl),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: SpacingTokens.xl),

        Text('SAVED ASSETS', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        const Row(children: [
          Expanded(child: _StatCard(value: '3', label: 'SAVED\nBRIEFS')),
          SizedBox(width: SpacingTokens.sm),
          Expanded(child: _StatCard(value: _Demo.savedBlueprints, label: 'SAVED\nBLUEPRINTS')),
          SizedBox(width: SpacingTokens.sm),
          Expanded(child: _StatCard(value: '2', label: 'WATCHLIST\nTEAMS')),
        ]),

        const SizedBox(height: SpacingTokens.xl),
        Divider(height: 1, color: c.divider),
        const SizedBox(height: SpacingTokens.xl),

        Text('SECURITY', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        const _InfoRow(label: 'PASSWORD', value: '••••••••'),
        const _InfoRow(label: 'TWO-FACTOR', value: 'Not enabled'),
        const _InfoRow(label: 'LAST LOGIN', value: 'Today'),

        const SizedBox(height: SpacingTokens.xxl),

        _ActionButton(
          label: 'EDIT PROFILE',
          icon: Icons.edit_outlined,
          onTap: () {},
        ),
        const SizedBox(height: SpacingTokens.sm),
        _ActionButton(
          label: 'MANAGE PREFERENCES',
          icon: Icons.tune_outlined,
          onTap: () {},
        ),
        const SizedBox(height: SpacingTokens.sm),
        _ActionButton(
          label: 'LOG OUT',
          icon: Icons.logout,
          isDestructive: true,
          onTap: () async {
            await widget.authState.logout();
            if (context.mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),

        const SizedBox(height: SpacingTokens.xl),
        Center(
          child: Text(
            'UMBRARO v0.1.0  ·  THESIS BUILD',
            style: TypographyTokens.sectionLabel.copyWith(
              color: c.textMuted.withValues(alpha: 0.4),
              fontSize: 9,
              letterSpacing: 2.0,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// REUSABLE PROFILE WIDGETS
// =============================================================================

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onBack, this.themeMode});
  final VoidCallback onBack;
  final ThemeModeNotifier? themeMode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = themeMode?.mode ?? ThemeMode.light;
    final isDark = mode == ThemeMode.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpacingTokens.md, SpacingTokens.md,
        SpacingTokens.md, SpacingTokens.sm,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Icon(Icons.arrow_back, size: 20, color: c.primary),
          ),
          const SizedBox(width: SpacingTokens.sm),
          Text(
            'PROFILE',
            style: TypographyTokens.sectionLabel.copyWith(
              color: c.textPrimary,
              letterSpacing: 2.4,
            ),
          ),
          const Spacer(),
          if (themeMode != null)
            IconButton(
              tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                size: 22,
                color: c.primary,
              ),
              onPressed: () => themeMode!.toggle(),
            ),
          GestureDetector(
            onTap: onBack,
            child: Icon(Icons.close, size: 20, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.team});
  final String team;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: c.surfaceHigh,
            border: Border.all(color: c.accent, width: 2),
          ),
          padding: const EdgeInsets.all(10),
          child: Image.asset('assets/branding/logo_icon.png', fit: BoxFit.contain),
        ),
        const SizedBox(height: SpacingTokens.md),
        Text(
          _Demo.name.toUpperCase(),
          style: TypographyTokens.headline.copyWith(fontSize: 22),
        ),
        const SizedBox(height: SpacingTokens.xxs),
        Text(_Demo.role, style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          team,
          style: TypographyTokens.body.copyWith(
            color: c.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: SpacingTokens.xxs),
        Text(
          _Demo.country.toUpperCase(),
          style: TypographyTokens.sectionLabel.copyWith(
            fontSize: 9,
            letterSpacing: 2.5,
            color: c.textMuted.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _IdentitySummary extends StatelessWidget {
  const _IdentitySummary({
    required this.memberSince,
    required this.lastActive,
    required this.club,
    required this.access,
  });

  final String memberSince, lastActive, club, access;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: c.divider),
          bottom: BorderSide(color: c.divider),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _cell('MEMBER SINCE', memberSince),
            VerticalDivider(width: 1, color: c.divider),
            _cell('LAST ACTIVE', lastActive),
            VerticalDivider(width: 1, color: c.divider),
            _cell('CLUB', club),
            VerticalDivider(width: 1, color: c.divider),
            _cell('ACCESS', access),
          ],
        ),
      ),
    );
  }

  Widget _cell(String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: SpacingTokens.sm,
          horizontal: SpacingTokens.xs,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TypographyTokens.sectionLabel.copyWith(fontSize: 8, letterSpacing: 1.2),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: SpacingTokens.xxs),
            Text(
              value,
              style: TypographyTokens.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.surfaceLow,
        border: Border.all(color: c.divider),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = selected == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? c.surfaceHigh : Colors.transparent,
                  border: active
                      ? Border(bottom: BorderSide(color: c.accent, width: 2))
                      : null,
                ),
                child: Text(
                  tabs[i],
                  style: TypographyTokens.sectionLabel.copyWith(
                    color: active ? c.accent : c.textMuted,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(SpacingTokens.md),
      color: c.surfaceLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TypographyTokens.headline.copyWith(
              fontSize: 28,
              color: c.accent,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(label, style: TypographyTokens.sectionLabel),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TypographyTokens.sectionLabel),
          const SizedBox(width: SpacingTokens.md),
          Flexible(
            child: Text(
              value,
              style: TypographyTokens.body.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({
    required this.action,
    required this.detail,
    required this.time,
  });

  final String action, detail, time;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: SpacingTokens.sm),
      padding: const EdgeInsets.all(SpacingTokens.md),
      color: c.surfaceLow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 3, height: 36, color: c.accent),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.toUpperCase(),
                  style: TypographyTokens.sectionLabel.copyWith(
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: SpacingTokens.xxs),
                Text(detail, style: TypographyTokens.body),
              ],
            ),
          ),
          Text(time, style: TypographyTokens.sectionLabel.copyWith(fontSize: 9)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _SavedItem extends StatelessWidget {
  const _SavedItem({required this.title, required this.date});
  final String title, date;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 14, color: c.accent),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Text(
              title,
              style: TypographyTokens.body.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(date, style: TypographyTokens.sectionLabel.copyWith(fontSize: 9)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = isDestructive ? c.negative : c.accent;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          shape: const RoundedRectangleBorder(),
          side: BorderSide(color: color.withValues(alpha: isDestructive ? 1.0 : 0.3)),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: SpacingTokens.xs),
            Text(
              label,
              style: TypographyTokens.sectionLabel.copyWith(
                color: color,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
