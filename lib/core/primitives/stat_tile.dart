import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/shape_tokens.dart';
import '../theme/typography_tokens.dart';

/// Compact data cell: an optional icon, a tabular value, and a short caption.
/// Replaces the stacked ALLCAPS micro-labels (FORMĂ / PERF / PAS%). The full
/// term lives behind a long-press [tooltip] instead of cluttering the layout.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.value,
    this.icon,
    this.caption,
    this.tooltip,
    this.valueColor,
    super.key,
  });

  final String value;
  final IconData? icon;
  final String? caption;
  final String? tooltip;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: c.textMuted),
          const SizedBox(height: 4),
        ],
        Text(
          value,
          style: TypographyTokens.statValue.copyWith(
            fontSize: 18,
            color: valueColor ?? c.textPrimary,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(
            caption!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TypographyTokens.meta.copyWith(color: c.textMuted),
          ),
        ],
      ],
    );
    if (tooltip == null) return content;
    return Tooltip(
      message: tooltip!,
      triggerMode: TooltipTriggerMode.longPress,
      child: content,
    );
  }
}

/// A small pill: icon + label. Used for status badges (freshness / load) and
/// inline meta. Optionally tappable.
class StatChip extends StatelessWidget {
  const StatChip({
    required this.label,
    this.icon,
    this.color,
    this.onTap,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: ShapeTokens.chip,
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TypographyTokens.meta.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}
