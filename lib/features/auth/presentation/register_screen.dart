import 'package:flutter/material.dart';

import 'package:umbraro/core/data/superliga_teams.dart';
import 'package:umbraro/core/l10n/strings.dart';
import 'package:umbraro/core/state/auth_state.dart';
import 'package:umbraro/core/theme/app_colors.dart';
import 'package:umbraro/core/theme/shape_tokens.dart';
import 'package:umbraro/core/theme/spacing_tokens.dart';
import 'package:umbraro/core/theme/typography_tokens.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_button.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_error_banner.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_text_field.dart';
import 'package:umbraro/features/auth/validation/auth_validators.dart';

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

  /// Default to FC Universitatea Cluj for back-compat with the previous build
  /// (which hardcoded U Cluj), but the user can pick any club.
  SuperligaTeam? _selectedTeam = teamByShort('U Cluj');

  bool _submitting = false;
  bool _submitted = false;
  String? _nameError;
  String? _emailError;
  String? _passError;
  String? _confirmError;
  String? _teamError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _revalidate() {
    if (!_submitted) return;
    setState(() {
      _nameError = _key(AuthValidators.fullName(_nameCtrl.text));
      _emailError = _key(AuthValidators.email(_emailCtrl.text));
      _passError = _key(AuthValidators.password(_passCtrl.text));
      _confirmError =
          _key(AuthValidators.confirm(_passCtrl.text, _confirmCtrl.text));
    });
  }

  String? _key(String? k) => k == null ? null : L10n.t(k);

  Future<void> _submit() async {
    if (_submitting) return;
    final nameKey = AuthValidators.fullName(_nameCtrl.text);
    final emailKey = AuthValidators.email(_emailCtrl.text);
    final passKey = AuthValidators.password(_passCtrl.text);
    final confirmKey = AuthValidators.confirm(_passCtrl.text, _confirmCtrl.text);
    final noTeam = _selectedTeam == null;
    setState(() {
      _submitted = true;
      _nameError = _key(nameKey);
      _emailError = _key(emailKey);
      _passError = _key(passKey);
      _confirmError = _key(confirmKey);
      _teamError = noTeam ? L10n.t('validation.teamRequired') : null;
    });
    if (nameKey != null ||
        emailKey != null ||
        passKey != null ||
        confirmKey != null ||
        noTeam) {
      return;
    }

    setState(() => _submitting = true);
    await widget.authState.register(
      email: AuthValidators.normalizeEmail(_emailCtrl.text),
      password: _passCtrl.text,
      fullName: _nameCtrl.text.trim(),
      teamName: _selectedTeam!.short,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final serverError = widget.authState.error;
    return AuthScaffold(
      title: L10n.t('register.title'),
      fields: [
        AuthTextField(
          controller: _nameCtrl,
          label: L10n.t('register.fullName'),
          errorText: _nameError,
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onChanged: (_) => _revalidate(),
        ),
        const SizedBox(height: SpacingTokens.md),
        AuthTextField(
          controller: _emailCtrl,
          label: L10n.t('register.email'),
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          onChanged: (_) => _revalidate(),
        ),
        const SizedBox(height: SpacingTokens.md),
        AuthTextField(
          controller: _passCtrl,
          label: L10n.t('register.password'),
          isPassword: true,
          errorText: _passError,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => _revalidate(),
        ),
        const SizedBox(height: SpacingTokens.md),
        AuthTextField(
          controller: _confirmCtrl,
          label: L10n.t('register.confirmPassword'),
          isPassword: true,
          errorText: _confirmError,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => _revalidate(),
        ),
        const SizedBox(height: SpacingTokens.md),
        _buildTeamPicker(context),
        const SizedBox(height: SpacingTokens.xl),
        if (serverError != null) ...[
          AuthErrorBanner(message: serverError),
          const SizedBox(height: SpacingTokens.md),
        ],
        AuthButton(
          label: L10n.t('register.submit'),
          busy: _submitting,
          onPressed: _submit,
        ),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${L10n.t('register.haveAccount')} ',
              style: TypographyTokens.sectionLabel),
          GestureDetector(
            onTap: widget.onLoginTap,
            child: Text(
              L10n.t('register.signIn'),
              style: TypographyTokens.sectionLabel.copyWith(
                color: context.colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamPicker(BuildContext context) {
    final c = context.colors;
    final hasError = _teamError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t('register.club'),
          style: TypographyTokens.sectionLabel
              .copyWith(color: hasError ? c.negative : c.textMuted),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Container(
          decoration: BoxDecoration(
            color: c.surfaceLow,
            borderRadius: ShapeTokens.control,
            border: Border.all(color: hasError ? c.negative : c.divider),
          ),
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SuperligaTeam>(
              isExpanded: true,
              value: _selectedTeam,
              icon: Icon(Icons.arrow_drop_down, color: c.accent),
              dropdownColor: c.surfaceElevatedTop,
              style: TypographyTokens.body.copyWith(color: c.textPrimary),
              hint: Text(
                L10n.t('register.clubHint'),
                style: TypographyTokens.body.copyWith(color: c.textMuted),
              ),
              items: [
                for (final t in kSuperligaTeams)
                  DropdownMenuItem<SuperligaTeam>(
                    value: t,
                    child: _TeamRow(team: t),
                  ),
              ],
              onChanged: (t) => setState(() {
                _selectedTeam = t;
                if (_submitted) _teamError = null;
              }),
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
        if (hasError) ...[
          const SizedBox(height: SpacingTokens.xxs),
          Text(_teamError!,
              style: TypographyTokens.bodySmall.copyWith(color: c.negative)),
        ],
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
            border: Border.all(color: c.divider),
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
