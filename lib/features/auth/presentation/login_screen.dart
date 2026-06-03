import 'package:flutter/material.dart';

import '../../../core/branding/branding_config.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shape_tokens.dart';
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
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || !email.contains('@') || pass.isEmpty) {
      setState(() => _localError = 'Enter a valid email and password.');
      return;
    }
    setState(() {
      _submitting = true;
      _localError = null;
    });
    await widget.authState.login(email: email, password: pass);
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
                  _buildField(
                    context,
                    controller: _emailCtrl,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(
                    context,
                    controller: _passCtrl,
                    label: 'Password',
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: SpacingTokens.xl),
                  if ((_localError ?? widget.authState.error) != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(SpacingTokens.sm),
                      decoration: BoxDecoration(
                        color: c.negative.withValues(alpha: 0.12),
                        borderRadius: ShapeTokens.control,
                        border:
                            Border.all(color: c.negative.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: c.negative),
                          const SizedBox(width: SpacingTokens.xs),
                          Expanded(
                            child: Text(
                              _localError ?? widget.authState.error!,
                              style: TypographyTokens.bodySmall
                                  .copyWith(color: c.negative),
                            ),
                          ),
                        ],
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
                        shape: const RoundedRectangleBorder(
                            borderRadius: ShapeTokens.control),
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
                              'Sign in',
                              style: TypographyTokens.buttonLabel
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
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    bool isPassword = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    List<String>? autofillHints,
  }) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TypographyTokens.sectionLabel.copyWith(color: c.textMuted)),
        const SizedBox(height: SpacingTokens.xs),
        TextField(
          controller: controller,
          obscureText: isPassword && _obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          autofillHints: autofillHints,
          style: TypographyTokens.body,
          cursorColor: c.accent,
          decoration: InputDecoration(
            filled: true,
            fillColor: c.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.md,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: c.textMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: ShapeTokens.control,
              borderSide: BorderSide(color: c.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: ShapeTokens.control,
              borderSide: BorderSide(color: c.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: ShapeTokens.control,
              borderSide: BorderSide(color: c.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
