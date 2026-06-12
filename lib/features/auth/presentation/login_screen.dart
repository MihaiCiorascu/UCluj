import 'package:flutter/material.dart';

import 'package:umbraro/core/l10n/strings.dart';
import 'package:umbraro/core/state/auth_state.dart';
import 'package:umbraro/core/theme/app_colors.dart';
import 'package:umbraro/core/theme/spacing_tokens.dart';
import 'package:umbraro/core/theme/typography_tokens.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_button.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_error_banner.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_text_field.dart';
import 'package:umbraro/features/auth/validation/auth_validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.authState,
    required this.onRegisterTap,
    super.key,
  });

  final AuthState authState;
  final VoidCallback onRegisterTap;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  String? _emailError;
  String? _passError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // Sign-in is lenient: a well-formed email and a non-empty password. The
  // strength rule only applies when creating an account.
  void _revalidate() {
    if (!_submitted) return;
    final emailKey = AuthValidators.email(_emailCtrl.text);
    setState(() {
      _emailError = emailKey == null ? null : L10n.t(emailKey);
      _passError =
          _passCtrl.text.isEmpty ? L10n.t('validation.passwordRequired') : null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final emailKey = AuthValidators.email(_emailCtrl.text);
    final passEmpty = _passCtrl.text.isEmpty;
    setState(() {
      _submitted = true;
      _emailError = emailKey == null ? null : L10n.t(emailKey);
      _passError = passEmpty ? L10n.t('validation.passwordRequired') : null;
    });
    if (emailKey != null || passEmpty) return;

    setState(() => _submitting = true);
    await widget.authState.login(
      email: AuthValidators.normalizeEmail(_emailCtrl.text),
      password: _passCtrl.text,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final serverError = widget.authState.error;
    return AuthScaffold(
      tagline: L10n.t('login.tagline'),
      title: L10n.t('login.title'),
      fields: [
        AuthTextField(
          controller: _emailCtrl,
          label: L10n.t('login.email'),
          errorText: _emailError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          onChanged: (_) => _revalidate(),
        ),
        const SizedBox(height: SpacingTokens.md),
        AuthTextField(
          controller: _passCtrl,
          label: L10n.t('login.password'),
          isPassword: true,
          errorText: _passError,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
          onChanged: (_) => _revalidate(),
        ),
        const SizedBox(height: SpacingTokens.xl),
        if (serverError != null) ...[
          AuthErrorBanner(message: serverError),
          const SizedBox(height: SpacingTokens.md),
        ],
        AuthButton(
          label: L10n.t('login.submit'),
          busy: _submitting,
          onPressed: _submit,
        ),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${L10n.t('login.noAccount')} ',
              style: TypographyTokens.sectionLabel),
          GestureDetector(
            onTap: widget.onRegisterTap,
            child: Text(
              L10n.t('login.register'),
              style: TypographyTokens.sectionLabel.copyWith(color: c.accent),
            ),
          ),
        ],
      ),
    );
  }
}
