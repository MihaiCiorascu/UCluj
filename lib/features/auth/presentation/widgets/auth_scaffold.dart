import 'package:flutter/material.dart';
import 'package:umbraro/core/branding/branding_config.dart';
import 'package:umbraro/core/theme/app_colors.dart';
import 'package:umbraro/core/theme/spacing_tokens.dart';
import 'package:umbraro/core/theme/typography_tokens.dart';

/// Shared chrome for the three auth screens (login, register, verify): the
/// gradient base, a centred 380-wide column, the logo, an optional tagline,
/// a section title, the body fields, and an optional footer row. Keeps the
/// screens visually identical and removes the layout boilerplate they used to
/// duplicate.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.fields,
    this.tagline,
    this.footer,
    super.key,
  });

  final String title;
  final String? tagline;
  final List<Widget> fields;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.surfaceBaseGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.xxl,
                vertical: SpacingTokens.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        height: 140,
                        width: 140,
                        child: Image.asset(
                          BrandingConfig.logoFull,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    if (tagline != null) ...[
                      const SizedBox(height: SpacingTokens.sm),
                      Text(
                        tagline!,
                        textAlign: TextAlign.center,
                        style: TypographyTokens.sectionLabel,
                      ),
                    ],
                    const SizedBox(height: 48),
                    Text(title, style: TypographyTokens.sectionLabel),
                    const SizedBox(height: SpacingTokens.md),
                    ...fields,
                    if (footer != null) ...[
                      const SizedBox(height: SpacingTokens.lg),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
