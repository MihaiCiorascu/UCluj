import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/motion_tokens.dart';
import '../theme/shape_tokens.dart';
import '../theme/typography_tokens.dart';
import 'haptics.dart';

class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// An accessible segmented control: a single track with an animated selected
/// pill. Replaces the ad-hoc two-button toggles (predicted vs best XI,
/// profile tabs, standings groups). Each segment is a >= 44dp touch target and
/// fires a selection haptic on change.
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 44,
    super.key,
  });

  final List<SegmentOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: ShapeTokens.control,
        border: Border.all(color: c.divider),
      ),
      child: Row(
        children: [
          for (final option in segments)
            Expanded(
              child: _Segment<T>(
                option: option,
                selected: option.value == value,
                onTap: () {
                  if (option.value == value) return;
                  AppHaptics.selection();
                  onChanged(option.value);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SegmentOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onPrimary : c.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: MotionTokens.timed(context, MotionTokens.micro),
        curve: MotionTokens.standardCurve,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(ShapeTokens.radiusControl - 3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (option.icon != null) ...[
              Icon(option.icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypographyTokens.buttonLabel.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
