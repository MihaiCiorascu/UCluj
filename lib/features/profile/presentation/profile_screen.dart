import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';

// =============================================================================
// PROFILE SCREEN
// =============================================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.authState, super.key});
  final AuthState authState;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tabIndex = 0;
  bool _uploadingAvatar = false;

  AuthUser? get _user => widget.authState.user;
  String get _name => _user?.fullName ?? _user?.email ?? '—';
  String get _team => _user?.teamName ?? 'Universitatea Cluj';
  String get _email => _user?.email ?? '—';
  String get _userRole =>
      _user?.role.toUpperCase() ?? L10n.t('profile.coach');
  String? get _avatarUrl => _user?.avatarUrl;

  String _fullAvatarUrl(String relative) {
    final base = AppConfig.apiBaseUrl;
    const suffix = '/api/v1';
    final serverBase = base.endsWith(suffix)
        ? base.substring(0, base.length - suffix.length)
        : base;
    return '$serverBase$relative';
  }

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final res = await widget.authState.api.uploadMultipart(
        '/auth/me/avatar',
        fileBytes: file.bytes!,
        fileName: file.name,
      );
      widget.authState.updateAvatarUrl(res['avatar_url'] as String);
    } catch (e) {
      debugPrint('Avatar upload error: $e');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [L10n.t('profile.tabOverview'), L10n.t('profile.tabAccount')];
    return Scaffold(
      backgroundColor: ColorTokens.surface,
      body: SafeArea(
        child: Column(
          children: [
            _ProfileHeader(onBack: () => Navigator.of(context).pop()),
            const Divider(height: 1, color: ColorTokens.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.xl, SpacingTokens.xl,
                  SpacingTokens.xl, 40,
                ),
                children: [
                  _ProfileHero(
                    name: _name,
                    role: _userRole,
                    team: _team,
                    avatarUrl: _avatarUrl != null
                        ? _fullAvatarUrl(_avatarUrl!)
                        : null,
                    uploadingAvatar: _uploadingAvatar,
                    onAvatarTap: _pickAndUploadAvatar,
                  ),
                  const SizedBox(height: SpacingTokens.lg),
                  _IdentitySummary(
                    club: _team,
                  ),
                  const SizedBox(height: SpacingTokens.xl),
                  _SegmentedControl(
                    tabs: tabs,
                    selected: _tabIndex,
                    onChanged: (i) => setState(() => _tabIndex = i),
                  ),
                  const SizedBox(height: SpacingTokens.xl),
                  if (_tabIndex == 0) _buildOverview(),
                  if (_tabIndex == 1) _buildAccount(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OVERVIEW
  // ---------------------------------------------------------------------------

  Widget _buildOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t('profile.workspace'), style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        _InfoRow(label: L10n.t('profile.defaultClub'), value: _team),
        _InfoRow(label: L10n.t('profile.email'), value: _email),
        _InfoRow(label: L10n.t('profile.role'), value: _userRole),
        const SizedBox(height: SpacingTokens.md),
        const _LanguageSelector(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ACCOUNT
  // ---------------------------------------------------------------------------

  Widget _buildAccount(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t('profile.planAccess'), style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.md),
        _InfoRow(label: L10n.t('profile.email'), value: _email),
        _InfoRow(label: L10n.t('profile.role'), value: _userRole),
        _InfoRow(label: L10n.t('profile.club'), value: _team),
        _InfoRow(
            label: L10n.t('profile.security'),
            value: L10n.t('profile.securityValue')),
        _InfoRow(
            label: L10n.t('profile.notifications'),
            value: L10n.t('profile.notificationsValue')),

        const SizedBox(height: SpacingTokens.xxl),

        _ActionButton(
          label: L10n.t('profile.logout'),
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
            L10n.t('profile.footer'),
            style: TypographyTokens.sectionLabel.copyWith(
              color: ColorTokens.textMuted.withValues(alpha: 0.4),
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
// LANGUAGE SELECTOR
// =============================================================================

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context) {
    final isRo = L10n.instance.isRomanian;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(L10n.t('profile.language'),
              style: TypographyTokens.sectionLabel),
          const SizedBox(height: SpacingTokens.sm),
          Container(
            decoration: BoxDecoration(
              color: ColorTokens.surfaceLow,
              border: Border.all(color: ColorTokens.divider),
            ),
            child: Row(
              children: [
                _langOption(
                  label: L10n.t('profile.languageRomanian'),
                  short: 'RO',
                  active: isRo,
                  onTap: () => L10n.instance.setLocale('ro'),
                ),
                Container(width: 1, color: ColorTokens.divider),
                _langOption(
                  label: L10n.t('profile.languageEnglish'),
                  short: 'EN',
                  active: !isRo,
                  onTap: () => L10n.instance.setLocale('en'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _langOption({
    required String label,
    required String short,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: active ? ColorTokens.surfaceHigh : Colors.transparent,
          padding: const EdgeInsets.symmetric(
              vertical: SpacingTokens.md, horizontal: SpacingTokens.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(short,
                  style: TypographyTokens.sectionLabel.copyWith(
                    color: active ? ColorTokens.accent : ColorTokens.textMuted,
                    fontSize: 11,
                    letterSpacing: 1.6,
                  )),
              const SizedBox(width: SpacingTokens.xs),
              Text(label,
                  style: TypographyTokens.body.copyWith(
                    color:
                        active ? ColorTokens.textPrimary : ColorTokens.textMuted,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// REUSABLE PROFILE WIDGETS
// =============================================================================

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpacingTokens.md, SpacingTokens.md,
        SpacingTokens.md, SpacingTokens.sm,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Icon(Icons.arrow_back, size: 20, color: ColorTokens.accent),
          ),
          const SizedBox(width: SpacingTokens.sm),
          Text(
            L10n.t('profile.title'),
            style: TypographyTokens.sectionLabel.copyWith(
              color: ColorTokens.textPrimary,
              letterSpacing: 2.4,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onBack,
            child: const Icon(Icons.close, size: 20, color: ColorTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.role,
    required this.team,
    required this.onAvatarTap,
    this.avatarUrl,
    this.uploadingAvatar = false,
  });

  final String name;
  final String role;
  final String team;
  final String? avatarUrl;
  final bool uploadingAvatar;
  final VoidCallback onAvatarTap;

  String _initials() {
    final trimmed = name.trim();
    final parts = trimmed.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: uploadingAvatar ? null : onAvatarTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ColorTokens.surfaceHigh,
                  border: Border.all(color: ColorTokens.accent, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: uploadingAvatar
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: ColorTokens.accent,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : avatarUrl != null
                        ? Image.network(
                            avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _InitialsAvatar(initials: _initials()),
                          )
                        : _InitialsAvatar(initials: _initials()),
              ),
              if (!uploadingAvatar)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: ColorTokens.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: ColorTokens.surface, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 13, color: Colors.black),
                  ),
                ),
            ],
          ),
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
            color: ColorTokens.accent,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SpacingTokens.xxs),
        Text(
          'UNIVERSITATEA CLUJ',
          style: TypographyTokens.sectionLabel.copyWith(
            fontSize: 9,
            letterSpacing: 2.5,
            color: ColorTokens.textMuted.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: TypographyTokens.headline.copyWith(
          fontSize: 28,
          color: ColorTokens.accent,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _IdentitySummary extends StatelessWidget {
  const _IdentitySummary({required this.club});
  final String club;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: ColorTokens.divider),
          bottom: BorderSide(color: ColorTokens.divider),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _cell(L10n.t('profile.club'), club),
            const VerticalDivider(width: 1, color: ColorTokens.divider),
            _cell(L10n.t('profile.access'), 'Pro'),
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
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: ColorTokens.surfaceLow,
        border: Border.all(color: ColorTokens.divider),
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
                  color: active ? ColorTokens.surfaceHigh : Colors.transparent,
                  border: active
                      ? const Border(bottom: BorderSide(color: ColorTokens.accent, width: 2))
                      : null,
                ),
                child: Text(
                  tabs[i],
                  style: TypographyTokens.sectionLabel.copyWith(
                    color: active ? ColorTokens.accent : ColorTokens.textMuted,
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
    final color = isDestructive ? ColorTokens.negative : ColorTokens.accent;

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
