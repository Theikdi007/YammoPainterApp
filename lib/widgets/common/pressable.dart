import 'package:flutter/material.dart';

/// Wraps [child] with a subtle scale-down press animation and tap handling, for
/// tactile feedback on cards (over images, where a ripple wouldn't be visible).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback onTap;

  /// How far the child scales down while pressed (1.0 = none).
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );

  void _set(bool down) => down ? _ctrl.forward() : _ctrl.reverse();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: widget.scale).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
        ),
        child: widget.child,
      ),
    );
  }
}
