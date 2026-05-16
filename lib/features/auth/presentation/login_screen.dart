import 'package:flutter/material.dart';

import '../../../core/branding/branding_config.dart';
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
      body: Container(
        decoration: BoxDecoration(gradient: c.surfaceBaseGradient),
        child: SafeArea(
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
                          height: 140,
                          width: 140,
                          child: Image.asset(
                            BrandingConfig.logoFull,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    'TACTICAL INTELLIGENCE PLATFORM',
                    textAlign: TextAlign.center,
                    style: TypographyTokens.sectionLabel,
                  ),
                  const SizedBox(height: 48),
                  Text('SIGN IN', style: TypographyTokens.sectionLabel),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(context, _emailCtrl, 'EMAIL', false),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(context, _passCtrl, 'PASSWORD', true),
                  const SizedBox(height: SpacingTokens.xl),
                  if (widget.authState.error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(SpacingTokens.sm),
                      color: c.negative.withValues(alpha: 0.15),
                      child: Text(
                        widget.authState.error!,
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
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                        shape: const RoundedRectangleBorder(),
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
                              'LOGIN',
                              style: TypographyTokens.sectionLabel
                                  .copyWith(color: c.onAccent),
                            ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'NO ACCOUNT? ',
                        style: TypographyTokens.sectionLabel,
                      ),
                      GestureDetector(
                        onTap: widget.onRegisterTap,
                        child: Text(
                          'REGISTER',
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
          style: TypographyTokens.body,
          cursorColor: c.accent,
          decoration: InputDecoration(
            filled: true,
            fillColor: c.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: c.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: c.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: c.accent),
            ),
          ),
        ),
      ],
    );
  }
}
