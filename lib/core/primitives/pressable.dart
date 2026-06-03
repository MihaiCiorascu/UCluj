import 'package:flutter/material.dart';

import '../theme/motion_tokens.dart';
import 'haptics.dart';

/// A tap target that scales down slightly while pressed (scale-feedback) and
/// fires a light haptic on tap. Use it to wrap cards, fixture rows, and other
/// custom tappable surfaces so press feedback is uniform. Honours reduced
/// motion (no scale) and exposes a button [Semantics] node for screen readers.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = MotionTokens.pressScale,
    this.haptic = true,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setDown(bool value) {
    if (!_enabled || _down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionTokens.reduceMotion(context);
    final target = (!_enabled || reduce || !_down) ? 1.0 : widget.scale;
    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        onTap: _enabled
            ? () {
                if (widget.haptic) AppHaptics.light();
                widget.onTap?.call();
              }
            : null,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                if (widget.haptic) AppHaptics.selection();
                widget.onLongPress!.call();
              },
        child: AnimatedScale(
          scale: target,
          duration: MotionTokens.micro,
          curve: MotionTokens.standardCurve,
          child: widget.child,
        ),
      ),
    );
  }
}
