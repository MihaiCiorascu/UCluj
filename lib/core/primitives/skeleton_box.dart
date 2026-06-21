import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/motion_tokens.dart';

/// A single shimmering placeholder block. Compose several to mirror the shape
/// of the content that is loading, instead of a bare spinner. Honours reduced
/// motion (holds a static tone). Use for any wait longer than ~300ms.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    this.width,
    this.height = 16,
    this.radius = 8,
    this.margin,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = c.isDark ? c.surfaceHigh : c.surfaceLow;
    final highlight = Color.alphaBlend(
      c.textMuted.withValues(alpha: c.isDark ? 0.16 : 0.22),
      base,
    );
    final reduce = MotionTokens.reduceMotion(context);
    double clampStop(double v) => v.clamp(0.0, 1.0);

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: reduce
          ? const SizedBox.shrink()
          : AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = _ctrl.value;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [base, highlight, base],
                      stops: [
                        clampStop(t - 0.3),
                        clampStop(t),
                        clampStop(t + 0.3),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
