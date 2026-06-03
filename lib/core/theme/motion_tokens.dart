import 'package:flutter/widgets.dart';

/// Motion design tokens for the UmbraRo redesign.
///
/// One global rhythm: short, ease-out on enter; a touch faster, ease-in on
/// exit. Every animated surface reads these so durations and curves stay
/// consistent across the app, and every consumer must funnel its duration
/// through [timed] so `prefers-reduced-motion` collapses the animation to
/// zero rather than ignoring the accessibility setting.
class MotionTokens {
  const MotionTokens._();

  /// Micro-interactions: press, toggle, ripple.
  static const Duration micro = Duration(milliseconds: 180);

  /// Standard transitions: cards, list items, fades.
  static const Duration standard = Duration(milliseconds: 240);

  /// Emphasised: sheets, hero numbers, arcs.
  static const Duration emphasized = Duration(milliseconds: 320);

  /// Exit animations run shorter than their enter so dismissal feels snappy.
  static const Duration exit = Duration(milliseconds: 160);

  /// Per-item delay for staggered list/grid entrance.
  static const Duration stagger = Duration(milliseconds: 36);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve leaving = Curves.easeInCubic;
  static const Curve standardCurve = Curves.easeInOutCubic;

  /// Press feedback scale for tappable cards and buttons.
  static const double pressScale = 0.97;

  /// True when the platform asks for reduced motion.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Returns [d] normally, or [Duration.zero] under reduced motion.
  static Duration timed(BuildContext context, Duration d) =>
      reduceMotion(context) ? Duration.zero : d;
}
