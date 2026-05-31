import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/spacing_tokens.dart';

/// Stoic Analyst loading skeleton. Replaces generic `CircularProgressIndicator`
/// on list-shaped surfaces (dashboard fixture list, standings table) with a
/// stack of tonal rows that match the actual content layout, so the eye does
/// not have to re-anchor when real data lands. Sharp edges, no shadows, tonal
/// layering via `surfaceLow` against the base gradient.
///
/// The skeleton animates a subtle opacity sweep so it does not look frozen,
/// but the motion is deliberately slow (1.2 s cycle) to stay editorial.
class AppLoadingSkeleton extends StatefulWidget {
  const AppLoadingSkeleton({
    this.rows = 4,
    this.rowHeight = 64,
    this.gap = SpacingTokens.sm,
    super.key,
  });

  final int rows;
  final double rowHeight;
  final double gap;

  @override
  State<AppLoadingSkeleton> createState() => _AppLoadingSkeletonState();
}

class _AppLoadingSkeletonState extends State<AppLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final alpha = 0.55 + t * 0.25;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(widget.rows, (i) {
            return Padding(
              padding: EdgeInsets.only(bottom: i == widget.rows - 1 ? 0 : widget.gap),
              child: Container(
                height: widget.rowHeight,
                decoration: BoxDecoration(
                  color: c.surfaceLow.withValues(alpha: alpha),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
