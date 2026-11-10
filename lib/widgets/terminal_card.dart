import 'package:flutter/material.dart';

import '../theme/palettes.dart';

/// The standard DayDeck card: panel background, hairline border, rounded
/// corners. Hosts rows separated by [TerminalCardRule]s.
class TerminalCard extends StatelessWidget {
  const TerminalCard({super.key, required this.palette, required this.children});

  final TerminalPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class TerminalCardRule extends StatelessWidget {
  const TerminalCardRule({super.key, required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) => Divider(color: palette.border, height: 14);
}
