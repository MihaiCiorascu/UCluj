import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:umbraro/core/l10n/strings.dart';
import 'package:umbraro/core/state/auth_state.dart';
import 'package:umbraro/core/theme/app_colors.dart';
import 'package:umbraro/core/theme/spacing_tokens.dart';
import 'package:umbraro/core/theme/typography_tokens.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_button.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_error_banner.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:umbraro/features/auth/presentation/widgets/auth_text_field.dart';

/// Shown after sign-up (and after a sign-in by an unconfirmed account). The
/// user enters the 6-digit code emailed by Cognito; until they do, they cannot
/// reach the dashboard. A resend link is gated behind a short cooldown.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({required this.authState, super.key});

  final AuthState authState;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const int _cooldownSeconds = 45;

  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  bool _resending = false;
  String? _codeError;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _verify() async {
    if (_submitting) return;
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _codeError = L10n.t('verify.codeRequired'));
      return;
    }
    setState(() {
      _submitting = true;
      _codeError = null;
    });
    // On success AuthState sets the user and clears the verify stage; the app
    // gate then swaps to the dashboard. On failure it sets authState.error,
    // which the banner below renders.
    await widget.authState.confirm(code);
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _resend() async {
    if (_resending || _cooldown > 0) return;
    setState(() => _resending = true);
    final ok = await widget.authState.resendCode();
    if (!mounted) return;
    setState(() => _resending = false);
    if (ok) {
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t('verify.resent'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = widget.authState;
    final email = auth.pendingEmail ?? '';
    return AuthScaffold(
      title: L10n.t('verify.title'),
      fields: [
        Text(
          L10n.t('verify.sentTo').replaceAll('{email}', email),
          style: TypographyTokens.body.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: SpacingTokens.md),
        AuthTextField(
          controller: _codeCtrl,
          label: L10n.t('verify.codeLabel'),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          errorText: _codeError,
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: SpacingTokens.xl),
        if (auth.error != null) ...[
          AuthErrorBanner(message: auth.error!),
          const SizedBox(height: SpacingTokens.md),
        ],
        AuthButton(
          label: L10n.t('verify.submit'),
          busy: _submitting,
          onPressed: _verify,
        ),
        const SizedBox(height: SpacingTokens.lg),
        Center(
          child: _cooldown > 0
              ? Text(
                  L10n.t('verify.resendIn').replaceAll('{s}', '$_cooldown'),
                  style: TypographyTokens.sectionLabel
                      .copyWith(color: c.textMuted),
                )
              : GestureDetector(
                  onTap: _resend,
                  child: Text(
                    L10n.t('verify.resend'),
                    style:
                        TypographyTokens.sectionLabel.copyWith(color: c.accent),
                  ),
                ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        Center(
          child: GestureDetector(
            onTap: auth.goToLogin,
            child: Text(
              L10n.t('verify.backToLogin'),
              style: TypographyTokens.sectionLabel,
            ),
          ),
        ),
      ],
    );
  }
}
