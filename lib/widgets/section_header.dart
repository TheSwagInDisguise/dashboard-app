import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palettes.dart';

/// A section divider in the style
///   `// TITLE ────────────────── trailing`
/// Dashed rule, monospace, bright tag — the signature DayDeck look.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.palette,
    required this.title,
    this.trailing,
  });

  final TerminalPalette palette;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('// ', style: mono(context, size: 11, weight: FontWeight.w700, color: palette.accent)),
        Text(
          title,
          style: mono(
            context,
            size: 11,
            weight: FontWeight.w600,
            color: palette.dim,
            letterSpacing: 2.2,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CustomPaint(
            painter: _DashPainter(palette.border),
            size: const Size(double.infinity, 1),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(trailing!, style: mono(context, size: 10, color: palette.dim)),
        ],
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 5.0, gap = 4.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}
