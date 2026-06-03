import 'package:flutter/material.dart';

import '../theme/motion_tokens.dart';

/// Entrance animation: fade + a short upward slide, optionally delayed so a
/// list can stagger its children. Honours reduced motion (renders instantly).
/// Use with `delay: MotionTokens.stagger * index` for list entrances.
class Reveal extends StatefulWidget {
  const Reveal({
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 12,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final double offsetY;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: MotionTokens.standard,
  );
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _ctrl, curve: MotionTokens.enter);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MotionTokens.reduceMotion(context)) {
      _ctrl.value = 1;
    } else if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.offsetY),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
