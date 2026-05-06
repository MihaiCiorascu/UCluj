import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/services/api_client.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/theme/color_tokens.dart';
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

  String? _selectedTeam = 'Universitatea Cluj';
  bool _loadingTeams = false;
  bool _submitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
  }



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

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _localError = L10n.t('register.errorRequired'));
      return;
    }
    if (pass.length < 8) {
      setState(() => _localError = L10n.t('register.errorPasswordLen'));
      return;
    }
    if (pass != confirm) {
      setState(() => _localError = L10n.t('register.errorPasswordMatch'));
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
      teamName: _selectedTeam!,
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
    final displayError = _localError ?? widget.authState.error;

    return Scaffold(
      backgroundColor: ColorTokens.surface,
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
                          height: 100,
                          width: 100,
                          child: Image.asset(
                            'assets/teams/universitatea_cluj.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: SpacingTokens.sm),
                        Text(
                          'U CLUJ',
                          style: TypographyTokens.headline.copyWith(
                            color: ColorTokens.accent,
                            letterSpacing: 4,
                            fontSize: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    L10n.t('register.title'),
                    textAlign: TextAlign.center,
                    style: TypographyTokens.sectionLabel,
                  ),
                  const SizedBox(height: 48),
                  _buildField(_nameCtrl, L10n.t('register.fullName'), false),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(_emailCtrl, L10n.t('register.email'), false),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(_passCtrl, L10n.t('register.password'), true),
                  const SizedBox(height: SpacingTokens.md),
                  _buildField(_confirmCtrl, L10n.t('register.confirmPassword'), true),

                  const SizedBox(height: SpacingTokens.xl),
                  if (displayError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(SpacingTokens.sm),
                      color: ColorTokens.negative.withValues(alpha: 0.15),
                      child: Text(
                        displayError,
                        style: TypographyTokens.body.copyWith(
                          color: ColorTokens.negative,
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
                        backgroundColor: ColorTokens.accent,
                        foregroundColor: ColorTokens.onAccent,
                        shape: const RoundedRectangleBorder(),
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ColorTokens.onAccent,
                              ),
                            )
                          : Text(
                              L10n.t('register.submit'),
                              style: TypographyTokens.sectionLabel
                                  .copyWith(color: ColorTokens.onAccent),
                            ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${L10n.t('register.haveAccount')} ',
                        style: TypographyTokens.sectionLabel,
                      ),
                      GestureDetector(
                        onTap: widget.onLoginTap,
                        child: Text(
                          L10n.t('register.signIn'),
                          style: TypographyTokens.sectionLabel.copyWith(
                            color: ColorTokens.accent,
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
    TextEditingController controller,
    String label,
    bool obscure,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TypographyTokens.sectionLabel),
        const SizedBox(height: SpacingTokens.xs),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TypographyTokens.body,
          cursorColor: ColorTokens.accent,
          decoration: InputDecoration(
            filled: true,
            fillColor: ColorTokens.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.sm,
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: ColorTokens.divider),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: ColorTokens.divider),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: ColorTokens.accent),
            ),
          ),
        ),
      ],
    );
  }
}
