import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';

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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await widget.authState.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 96,
                          width: 96,
                          child: Image.asset(
                            'assets/teams/universitatea_cluj.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: SpacingTokens.sm),
                        Text(
                          'U CLUJ',
                          style: TypographyTokens.headline.copyWith(
                            color: c.accent,
                            letterSpacing: 4,
                            fontSize: 28,
                          ),
                        ),
                        const SizedBox(height: SpacingTokens.xxs),
                        Text(
                          'TACTICAL INTELLIGENCE',
                          style: TypographyTokens.sectionLabel.copyWith(
                            color: c.textMuted,
                            letterSpacing: 3,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(L10n.t('login.tagline'),
                      textAlign: TextAlign.center,
                      style: TypographyTokens.sectionLabel
                          .copyWith(color: c.textMuted)),
                  const SizedBox(height: 40),
                  Text(L10n.t('login.title'),
                      style: TypographyTokens.sectionLabel
                          .copyWith(color: c.textSecondary)),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(context, _emailCtrl, L10n.t('login.email'), false),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(context, _passCtrl, L10n.t('login.password'), true),
                  const SizedBox(height: SpacingTokens.xl),

                  // Error banner
                  if (widget.authState.error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(SpacingTokens.sm),
                      decoration: BoxDecoration(
                        color: c.negativeSubtle,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.negative.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        widget.authState.error!,
                        style: TypographyTokens.body
                            .copyWith(color: c.negative, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                  ],

                  // Submit button
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.onAccent,
                              ),
                            )
                          : Text(
                              L10n.t('login.submit'),
                              style: TypographyTokens.buttonLabel
                                  .copyWith(color: c.onAccent),
                            ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.lg),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${L10n.t('login.noAccount')} ',
                        style: TypographyTokens.sectionLabel
                            .copyWith(color: c.textMuted),
                      ),
                      GestureDetector(
                        onTap: widget.onRegisterTap,
                        child: Text(
                          L10n.t('login.register'),
                          style: TypographyTokens.sectionLabel.copyWith(
                            color: c.accent,
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
        Text(label,
            style: TypographyTokens.sectionLabel.copyWith(color: c.textSecondary)),
        const SizedBox(height: SpacingTokens.xs),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TypographyTokens.body.copyWith(color: c.textPrimary),
          cursorColor: c.accent,
          decoration: InputDecoration(
            filled: true,
            fillColor: c.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: c.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: c.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: c.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
