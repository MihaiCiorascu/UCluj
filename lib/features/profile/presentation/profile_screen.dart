import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/primitives/haptics.dart';
import '../../../core/primitives/segmented_toggle.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shape_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/theme_mode_notifier.dart';
import '../../../core/theme/typography_tokens.dart';

// =============================================================================
// PROFILE SCREEN
//
// Shows only data the app actually has: the authenticated user's identity and
// account fields, the active language and theme, and sign-out. The previous
// build carried fabricated usage counts, an activity feed, saved briefs, a
// plan tier, and a two-factor row, none of which had a backing data source;
// per AGENTS.md (no fake fields to fill the UI) they have been removed.
// =============================================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.authState,
    this.themeMode,
    super.key,
  });
  final AuthState authState;

  /// Optional theme-mode notifier. When present, the profile screen exposes a
  /// sun/moon toggle in the header.
  final ThemeModeNotifier? themeMode;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AuthUser? get _user => widget.authState.user;
  String get _team => (_user?.teamName?.isNotEmpty ?? false) ? _user!.teamName! : '—';
  String get _email => _user?.email ?? '—';
  String get _userRole =>
      (_user?.role.isNotEmpty ?? false) ? _user!.role.toUpperCase() : 'COACH';

  String get _name {
    final full = _user?.fullName;
    if (full != null && full.trim().isNotEmpty) return full.trim();
    final email = _user?.email ?? '';
    if (email.contains('@')) return email.split('@').first;
    return email.isNotEmpty ? email : 'COACH';
  }

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
                    _ProfileHero(name: _name, role: _userRole, team: _team),
                    const SizedBox(height: SpacingTokens.xl),

                    Text(L10n.t('profile.tabAccount'),
                        style: TypographyTokens.sectionLabel),
                    const SizedBox(height: SpacingTokens.md),
                    _InfoRow(label: L10n.t('profile.email'), value: _email),
                    _InfoRow(label: L10n.t('profile.role'), value: _userRole),
                    _InfoRow(label: L10n.t('profile.club'), value: _team),
                    _buildLanguageRow(),

                    const SizedBox(height: SpacingTokens.xxl),
                    _ActionButton(
                      label: L10n.t('profile.logout'),
                      icon: Icons.logout,
                      isDestructive: true,
                      onTap: () async {
                        AppHaptics.medium();
                        final confirmed = await _confirmLogout(context);
                        if (!confirmed) return;
                        await widget.authState.logout();
                        if (context.mounted) {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                      },
                    ),

                    const SizedBox(height: SpacingTokens.xl),
                    Center(
                      child: Text(
                        L10n.t('profile.footer'),
                        style: TypographyTokens.sectionLabel.copyWith(
                          color: c.textMuted.withValues(alpha: 0.4),
                          fontSize: 9,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Language row rendered as a compact EN/RO segmented toggle. English is the
  /// default; switching persists via L10n and rebuilds this screen.
  Widget _buildLanguageRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(L10n.t('profile.language'),
              style: TypographyTokens.sectionLabel),
          SizedBox(
            width: 128,
            child: SegmentedToggle<String>(
              height: 38,
              value: L10n.instance.locale,
              onChanged: (v) async {
                await L10n.instance.setLocale(v);
                if (mounted) setState(() {});
              },
              segments: const [
                SegmentOption(value: 'en', label: 'EN'),
                SegmentOption(value: 'ro', label: 'RO'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    final ro = L10n.instance.isRomanian;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.surfaceHigh,
          shape: RoundedRectangleBorder(borderRadius: ShapeTokens.control),
          title: Text(ro ? 'Deconectare' : 'Log out',
              style: TypographyTokens.title.copyWith(color: c.textPrimary)),
          content: Text(
              ro
                  ? 'Sigur vrei să închizi sesiunea?'
                  : 'Are you sure you want to sign out?',
              style: TypographyTokens.body.copyWith(color: c.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ro ? 'Anulează' : 'Cancel',
                  style: TypographyTokens.buttonLabel
                      .copyWith(color: c.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ro ? 'Deconectează-te' : 'Sign out',
                  style: TypographyTokens.buttonLabel
                      .copyWith(color: c.negative)),
            ),
          ],
        );
      },
    );
    return result ?? false;
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
            L10n.t('profile.title'),
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

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.name, required this.role, required this.team});
  final String name;
  final String role;
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
          name.toUpperCase(),
          style: TypographyTokens.headline.copyWith(fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SpacingTokens.xxs),
        Text(role, style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          team,
          style: TypographyTokens.body.copyWith(
            color: c.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

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
          shape: const RoundedRectangleBorder(borderRadius: ShapeTokens.control),
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
