import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/motion_tokens.dart';
import '../theme/shape_tokens.dart';
import '../theme/typography_tokens.dart';

/// A center-origin horizontal bar showing magnitude and direction: positive
/// drivers grow right in the positive colour, negative risks grow left in the
/// negative colour, both scaled against [maxMagnitude]. Replaces the up/down
/// arrow rows for drivers and risks. A full row: label, the bar, the value.
class SignedBar extends StatelessWidget {
  const SignedBar({
    required this.label,
    required this.magnitude,
    required this.maxMagnitude,
    required this.positive,
    this.valueLabel,
    this.tooltip,
    super.key,
  });

  final String label;

  /// Absolute size of this driver (>= 0).
  final double magnitude;

  /// The largest magnitude in the set, used to normalise the bar.
  final double maxMagnitude;

  final bool positive;
  final String? valueLabel;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = positive ? c.positive : c.negative;
    final frac = maxMagnitude <= 0
        ? 0.0
        : (magnitude.abs() / maxMagnitude).clamp(0.0, 1.0);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypographyTokens.bodySmall.copyWith(
                color: c.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 10,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final half = constraints.maxWidth / 2;
                  final w = half * frac;
                  return Stack(
                    children: [
                      // Track.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.track,
                            borderRadius: ShapeTokens.chip,
                          ),
                        ),
                      ),
                      // Center tick.
                      Positioned(
                        left: half - 0.5,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: c.divider,
                        ),
                      ),
                      // Fill.
                      AnimatedPositioned(
                        duration:
                            MotionTokens.timed(context, MotionTokens.standard),
                        curve: MotionTokens.enter,
                        left: positive ? half : half - w,
                        width: w,
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: ShapeTokens.chip,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              valueLabel ?? '',
              textAlign: TextAlign.right,
              style: TypographyTokens.mono.copyWith(color: color),
            ),
          ),
        ],
      ),
    );

    if (tooltip == null) return row;
    return Tooltip(
      message: tooltip!,
      triggerMode: TooltipTriggerMode.longPress,
      child: row,
    );
  }
}
