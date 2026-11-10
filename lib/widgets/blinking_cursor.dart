import 'package:flutter/material.dart';

/// The blocky blinking cursor used in the header wordmark. Purely decorative.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({
    super.key,
    required this.color,
    this.width = 11,
    this.height = 18,
  });

  final Color color;
  final double width;
  final double height;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    // Duty cycle: ~49% on, ~51% off, hard steps (no fading) — like a real CRT.
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 49),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 51),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) => Opacity(opacity: _opacity.value, child: child),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color,
          boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: 0.55), blurRadius: 10),
          ],
        ),
      ),
    );
  }
}
