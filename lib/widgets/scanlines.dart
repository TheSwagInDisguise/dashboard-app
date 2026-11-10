import 'package:flutter/material.dart';

/// Paints a barely-there CRT scanline texture over the whole app.
/// Purely decorative — pointer events pass straight through.
class Scanlines extends StatelessWidget {
  const Scanlines({super.key, required this.alpha});

  /// 0 = invisible, 1 = solid black lines. Themes ship with ~0.03–0.055.
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanlinePainter(alpha),
        size: Size.infinite,
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter(this.alpha);

  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: alpha);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) => oldDelegate.alpha != alpha;
}
