import 'package:flutter/material.dart';

import '../primitives/skeleton_box.dart';
import '../theme/spacing_tokens.dart';

/// A list-shaped loading placeholder: a stack of shimmering rows that mirror
/// the content about to land, so the eye does not have to re-anchor when real
/// data arrives. Built from [SkeletonBox], so it shimmers (and holds still
/// under reduced motion) consistently with every other skeleton in the app.
class AppLoadingSkeleton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : gap),
            child: SkeletonBox(
              width: double.infinity,
              height: rowHeight,
              radius: 10,
            ),
          ),
      ],
    );
  }
}
