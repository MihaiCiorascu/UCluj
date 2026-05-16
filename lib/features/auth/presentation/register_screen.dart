import 'package:flutter/material.dart';

import '../../../core/branding/branding_config.dart';
import '../../../core/data/superliga_teams.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    required this.authState,
    required this.onLoginTap,
    super.key,
  });

  final AuthState authState;
  final VoidCallback onLoginTap;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  /// Default to FC Universitatea Cluj for back-compat with the previous
  /// build (which hardcoded U Cluj), but the user must explicitly confirm
  /// a team via the picker.
  SuperligaTeam? _selectedTeam = teamByShort("U Cluj");

  bool _submitting = false;
  String? _localError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    final team = _selectedTeam;

    if (name.isEmpty || email.isEmpty || pass.isEmpty || team == null) {
      setState(() => _localError = 'All fields are required');
      return;
    }
    if (pass.length < 8) {
      setState(() => _localError = 'Password must be at least 8 characters');
      return;
    }
    if (pass != confirm) {
      setState(() => _localError = 'Passwords do not match');
      return;
    }

    setState(() {
      _submitting = true;
      _localError = null;
    });

    final success = await widget.authState.register(
      email: email,
      password: pass,
      fullName: name,
      teamName: team.short,
    );

    if (mounted) {
      setState(() {
        _submitting = false;
        if (!success) _localError = widget.authState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final displayError = _localError ?? widget.authState.error;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.surfaceBaseGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: SpacingTokens.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          SizedBox(
                            height: 140,
                            width: 140,
                            child: Image.asset(
                              BrandingConfig.logoFull,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: SpacingTokens.sm),
                          Text(
                            BrandingConfig.appName.toUpperCase(),
                            style: TypographyTokens.headline.copyWith(
                              color: c.primary,
                              letterSpacing: 4,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      'CREATE YOUR ACCOUNT',
                      textAlign: TextAlign.center,
                      style: TypographyTokens.sectionLabel,
                    ),
                    const SizedBox(height: 48),
                    _buildField(context, _nameCtrl, 'FULL NAME', false),
                    const SizedBox(height: SpacingTokens.md),
                    _buildField(context, _emailCtrl, 'EMAIL', false),
                    const SizedBox(height: SpacingTokens.md),
                    _buildField(context, _passCtrl, 'PASSWORD', true),
                    const SizedBox(height: SpacingTokens.md),
                    _buildField(
                        context, _confirmCtrl, 'CONFIRM PASSWORD', true),
                    const SizedBox(height: SpacingTokens.md),
                    _buildTeamPicker(context),
                    const SizedBox(height: SpacingTokens.xl),
                    if (displayError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(SpacingTokens.sm),
                        decoration: BoxDecoration(
                          color: c.negative.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: c.negative.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          displayError,
                          style: TypographyTokens.body.copyWith(
                            color: c.negative,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.md),
                    ],
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: c.primary,
                          foregroundColor: c.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.onPrimary,
                                ),
                              )
                            : Text(
                                'REGISTER',
                                style: TypographyTokens.sectionLabel
                                    .copyWith(color: c.onPrimary),
                              ),
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ALREADY HAVE AN ACCOUNT? ',
                          style: TypographyTokens.sectionLabel,
                        ),
                        GestureDetector(
                          onTap: widget.onLoginTap,
                          child: Text(
                            'SIGN IN',
                            style: TypographyTokens.sectionLabel.copyWith(
                              color: c.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    BuildContext context,
    TextEditingController controller,
    String label,
    bool obscure,
  ) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.xs),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TypographyTokens.body.copyWith(color: c.textPrimary),
          cursorColor: c.primary,
          decoration: InputDecoration(
            filled: true,
            fillColor: c.surfaceElevatedTop,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.chrome, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.chrome, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.primary, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamPicker(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR CLUB', style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.xs),
        Container(
          decoration: BoxDecoration(
            color: c.surfaceElevatedTop,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.chrome, width: 0.8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SuperligaTeam>(
              isExpanded: true,
              value: _selectedTeam,
              icon: Icon(Icons.arrow_drop_down, color: c.primary),
              dropdownColor: c.surfaceElevatedTop,
              style: TypographyTokens.body.copyWith(color: c.textPrimary),
              hint: Text(
                'Pick your team',
                style: TypographyTokens.body.copyWith(color: c.textMuted),
              ),
              items: [
                for (final t in kSuperligaTeams)
                  DropdownMenuItem<SuperligaTeam>(
                    value: t,
                    child: _TeamRow(team: t),
                  ),
              ],
              onChanged: (t) => setState(() => _selectedTeam = t),
              selectedItemBuilder: (ctx) {
                return [
                  for (final t in kSuperligaTeams)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TeamRow(team: t, compact: true),
                    ),
                ];
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, this.compact = false});

  final SuperligaTeam team;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: c.surfaceElevatedTop,
            shape: BoxShape.circle,
            border: Border.all(color: c.chrome.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.all(2),
          child: Image.asset(team.badgeAsset, fit: BoxFit.contain),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            compact ? team.short : team.displayName,
            overflow: TextOverflow.ellipsis,
            style: TypographyTokens.body.copyWith(color: c.textPrimary),
          ),
        ),
      ],
    );
  }
}
