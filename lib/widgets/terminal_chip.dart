import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tiny uppercase monospace tag with a coloured outline, e.g. `GCAL`, `P1`.
class TerminalChip extends StatelessWidget {
  const TerminalChip({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: filled ? 0 : 0.85)),
        color: filled ? color.withValues(alpha: 0.15) : null,
      ),
      child: Text(
        label,
        style: mono(context, size: 8.5, weight: FontWeight.w700, color: color, letterSpacing: 0.8),
      ),
    );
  }
}
