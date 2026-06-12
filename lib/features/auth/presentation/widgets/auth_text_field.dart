import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:umbraro/core/theme/app_colors.dart';
import 'package:umbraro/core/theme/shape_tokens.dart';
import 'package:umbraro/core/theme/spacing_tokens.dart';
import 'package:umbraro/core/theme/typography_tokens.dart';

/// The single labelled input used across every auth screen. It owns its own
/// obscure-text toggle and renders an inline [errorText] (with the border and
/// label switching to the negative colour) so validation reads next to the
/// field rather than as a single form-level banner.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    required this.controller,
    required this.label,
    this.isPassword = false,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofillHints,
    this.inputFormatters,
    this.maxLength,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool isPassword;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final List<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = widget.errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TypographyTokens.sectionLabel
              .copyWith(color: hasError ? c.negative : c.textMuted),
        ),
        const SizedBox(height: SpacingTokens.xs),
        TextField(
          controller: widget.controller,
          obscureText: widget.isPassword && _obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          maxLength: widget.maxLength,
          style: TypographyTokens.body.copyWith(color: c.textPrimary),
          cursorColor: c.accent,
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: c.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: SpacingTokens.md,
              vertical: SpacingTokens.md,
            ),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: c.textMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
            border: _border(hasError ? c.negative : c.divider),
            enabledBorder: _border(hasError ? c.negative : c.divider),
            focusedBorder:
                _border(hasError ? c.negative : c.accent, width: 1.5),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: SpacingTokens.xxs),
          Text(
            widget.errorText!,
            style: TypographyTokens.bodySmall.copyWith(color: c.negative),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1.0}) =>
      OutlineInputBorder(
        borderRadius: ShapeTokens.control,
        borderSide: BorderSide(color: color, width: width),
      );
}
