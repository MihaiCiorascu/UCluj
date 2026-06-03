import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/motion_tokens.dart';
import '../theme/typography_tokens.dart';

/// A calm radial gauge for a win probability: a 270° track open at the bottom,
/// a filled sweep for the value, the big tabular percentage in the centre and
/// a one-word label beneath. Animates the sweep on appear (reduced-motion
/// safe). Replaces the rotated linear progress bar.
class WinProbabilityArc extends StatelessWidget {
  const WinProbabilityArc({
    required this.probability,
    this.label,
    this.size = 176,
    this.color,
    super.key,
  });

  /// 0..1.
  final double probability;
  final String? label;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = color ?? c.primary;
    final pct = (probability.clamp(0.0, 1.0) * 100).round();
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: probability.clamp(0.0, 1.0)),
        duration: MotionTokens.timed(context, MotionTokens.emphasized),
        curve: MotionTokens.enter,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _ArcPainter(
              value: value,
              track: c.track,
              fill: fill,
              stroke: size * 0.085,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pct%',
                    style: TypographyTokens.statLarge.copyWith(
                      color: c.textPrimary,
                      fontSize: size * 0.26,
                    ),
                  ),
                  if (label != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        label!,
                        style: TypographyTokens.sectionLabel.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.value,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  final double value;
  final Color track;
  final Color fill;
  final double stroke;

  // 270° gauge, opening centred at the bottom.
  static const double _start = math.pi * 0.75; // 135°
  static const double _sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = track;
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = fill;

    canvas.drawArc(rect, _start, _sweep, false, trackPaint);
    canvas.drawArc(rect, _start, _sweep * value.clamp(0.0, 1.0), false,
        fillPaint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.value != value ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}
