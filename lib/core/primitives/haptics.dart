import 'package:flutter/services.dart';

/// Thin wrapper over [HapticFeedback] so haptic intent reads clearly at the
/// call site and is trivial to mute globally. No-op on web and on platforms
/// without a vibrator, so calling these is always safe.
class AppHaptics {
  const AppHaptics._();

  /// Light tap — card / fixture selection, primary tap feedback.
  static void light() => HapticFeedback.lightImpact();

  /// Selection click — segmented toggles, chevrons, pickers.
  static void selection() => HapticFeedback.selectionClick();

  /// Medium impact — committing a meaningful action.
  static void medium() => HapticFeedback.mediumImpact();

  /// Confirmation feedback (kept light so it does not feel like an error).
  static void success() => HapticFeedback.lightImpact();

  /// Error / rejection feedback.
  static void error() => HapticFeedback.heavyImpact();
}
