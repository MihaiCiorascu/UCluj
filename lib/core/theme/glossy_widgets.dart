import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Reusable widgets for the early-2000s glossy aesthetic.
///
/// The four shapes the reference images (Italian Serie A mockup, Juventus /
/// Inter / Napoli glossy logos) demand are:
///
/// * ``GlossyCard`` — a panel with a top-light → bottom-shaded gradient,
///   a 1-pixel white inner highlight at the top edge, a hairline chrome
///   border, and a soft drop-shadow.
/// * ``GlossyButton`` — the same surface used for primary CTAs, plus an
///   accent bias on the top sheen.
/// * ``ChromeDivider`` — a thin horizontal panel with a chrome-silver
///   gradient and an optional team-accent strip.
/// * ``GlossyAppBar`` — the app's header bar, painted with the primary
///   gloss gradient + UmbraRo wordmark + per-team accent strip.
///
/// All four read the active palette via ``context.colors`` so they
/// render correctly under both light and dark themes.

/// Decorations exposed as ``BoxDecoration`` factories so callers can
/// apply the glossy look to existing widgets without wrapping them.
class GlossyDecorations {
  const GlossyDecorations._();

  static BoxDecoration card(BuildContext context, {double radius = 10}) {
    final c = context.colors;
    return BoxDecoration(
      gradient: c.surfaceElevatedGradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: c.chrome, width: 0.8),
      boxShadow: [
        // Outer drop-shadow — softer in dark mode.
        BoxShadow(
          color: c.isDark
              ? Colors.black.withValues(alpha: 0.55)
              : c.chromeDeep.withValues(alpha: 0.25),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        // Inner top-edge highlight — the "glass" hint.
        BoxShadow(
          color: c.surfaceElevatedTop.withValues(alpha: c.isDark ? 0.18 : 0.85),
          blurRadius: 1.5,
          offset: const Offset(0, -1),
          spreadRadius: -0.5,
        ),
      ],
    );
  }

  static BoxDecoration button(BuildContext context,
      {double radius = 8, Color? accentBias}) {
    final c = context.colors;
    final base = accentBias == null
        ? c.primaryGlossGradient()
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.5, 1.0],
            colors: [
              Color.alphaBlend(
                accentBias.withValues(alpha: 0.18),
                Color.alphaBlend(c.primaryGloss.withValues(alpha: 0.7), c.primary),
              ),
              c.primary,
              c.primaryDeep,
            ],
          );
    return BoxDecoration(
      gradient: base,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: c.chrome, width: 0.7),
      boxShadow: [
        BoxShadow(
          color: c.primaryDeep.withValues(alpha: 0.35),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

/// A glassy panel container — replaces flat ``Container``/``Card`` surfaces.
class GlossyCard extends StatelessWidget {
  const GlossyCard({
    required this.child,
    this.padding,
    this.radius = 10,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: GlossyDecorations.card(context, radius: radius),
      child: child,
    );
  }
}

/// Primary or secondary CTA with the gloss-gradient fill.
///
/// Accepts an optional ``accentBias`` so the per-team accent overlay can
/// tint the top sheen.
class GlossyButton extends StatelessWidget {
  const GlossyButton({
    required this.label,
    this.onPressed,
    this.isPrimary = true,
    this.accentBias,
    this.height = 48,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final Color? accentBias;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = isPrimary ? c.onPrimary : c.primary;
    final disabled = onPressed == null;
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          splashColor: c.glow.withValues(alpha: 0.25),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            alignment: Alignment.center,
            decoration: isPrimary
                ? GlossyDecorations.button(context, accentBias: accentBias)
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.chrome, width: 0.8),
                    color: c.surfaceElevatedTop.withValues(alpha: 0.6),
                  ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Opacity(
              opacity: disabled ? 0.55 : 1.0,
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin chrome-silver divider used under app bars and section breaks.
/// Optional ``accent`` paints a 2-px strip on top of the chrome — used by
/// the per-team accent overlay.
class ChromeDivider extends StatelessWidget {
  const ChromeDivider({this.accent, this.thickness = 4, super.key});

  final Color? accent;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: thickness,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                c.chrome.withValues(alpha: 0.0),
                c.chrome,
                c.chrome.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        if (accent != null)
          Container(height: 2, color: accent),
      ],
    );
  }
}

/// Multi-band accent strip used when a team has 2 or 3 official colours.
/// Renders horizontal blocks proportional to the number of colours.
class TeamAccentStrip extends StatelessWidget {
  const TeamAccentStrip({
    required this.colors,
    this.height = 3,
    super.key,
  });

  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final c in colors) Expanded(child: Container(color: c)),
        ],
      ),
    );
  }
}

/// Full-width gradient header used in ``app_scaffold.dart``.
///
/// Contains:
///   * the primary-gloss gradient (cobalt → deep cobalt) with chrome top
///     border,
///   * a leading slot (typically the UmbraRo logo + wordmark),
///   * an optional trailing slot (typically a profile button),
///   * a chrome divider at the bottom, optionally overlaid with the
///     ``accentColors`` strip (per-team accent overlay).
class GlossyAppBar extends StatelessWidget {
  const GlossyAppBar({
    required this.leading,
    this.trailing,
    this.accentColors,
    super.key,
  });

  final Widget leading;
  final Widget? trailing;
  final List<Color>? accentColors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surfaceBaseTop,
            border: Border(bottom: BorderSide(color: c.divider)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(child: leading),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        if (accentColors != null && accentColors!.isNotEmpty)
          TeamAccentStrip(colors: accentColors!),
        // Thin brand accent rule under the header (fades to transparent).
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.primary, c.primary.withValues(alpha: 0.0)],
            ),
          ),
        ),
      ],
    );
  }
}
