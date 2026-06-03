import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/shape_tokens.dart';
import '../theme/spacing_tokens.dart';
import '../theme/typography_tokens.dart';

/// The standard modal bottom sheet for the app: rounded top, grab handle,
/// brand scrim, swipe-down to dismiss, content scrolls and the sheet grows to
/// at most [maxHeightFraction] of the screen. Used for match detail, player
/// detail, and the formation picker so every modal feels the same.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  double maxHeightFraction = 0.92,
}) {
  final c = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: c.scrim,
    builder: (ctx) => AppSheet(
      title: title,
      maxHeightFraction: maxHeightFraction,
      child: builder(ctx),
    ),
  );
}

class AppSheet extends StatelessWidget {
  const AppSheet({
    required this.child,
    this.title,
    this.maxHeightFraction = 0.92,
    super.key,
  });

  final Widget child;
  final String? title;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxH = MediaQuery.of(context).size.height * maxHeightFraction;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: ShapeTokens.sheetTop,
        boxShadow: ShapeTokens.e3(context),
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle.
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm, bottom: 2),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.textMuted.withValues(alpha: 0.5),
                borderRadius: ShapeTokens.chip,
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.lg,
                SpacingTokens.xs,
                SpacingTokens.xs,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TypographyTokens.title.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    splashRadius: 22,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: c.textSecondary),
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                  ),
                ],
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.lg,
                SpacingTokens.sm,
                SpacingTokens.lg,
                SpacingTokens.lg,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
