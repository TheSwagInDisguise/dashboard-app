import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../widgets/terminal_chip.dart';

/// Phase 2 placeholder. The real task list (local, offline, LWW-synced)
/// replaces this screen in Phase 2 — this stub exists so the navigation,
/// theme and layout are reviewable today.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          Center(
            child: Text(
              '// TASKS',
              style: mono(context, size: 26, weight: FontWeight.w700, color: p.accent, letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'ARRIVES IN PHASE 2',
              style: mono(context, size: 10, color: p.dim, letterSpacing: 2.4),
            ),
          ),
          const SizedBox(height: 18),
          SectionHeader(palette: p, title: 'INTERFACE PREVIEW', trailing: 'read-only'),
          const SizedBox(height: 8),
          Opacity(
            opacity: 0.6,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MockRow(palette: p, label: '[ ]', text: 'add task…', chip: 'P2'),
                  Divider(color: p.border, height: 16),
                  _MockRow(palette: p, label: '[ ]', text: 'Buy oat milk', chip: 'P2'),
                  Divider(color: p.border, height: 16),
                  _MockRow(palette: p, label: '[x]', text: 'Call accountant about BAS', chip: 'P2', done: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Phase 2 wires this up: add, edit, complete, due dates,\n'
            'priority and offline storage. Synced in Phase 3.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.dim, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _MockRow extends StatelessWidget {
  const _MockRow({
    required this.palette,
    required this.label,
    required this.text,
    required this.chip,
    this.done = false,
  });

  final TerminalPalette palette;
  final String label;
  final String text;
  final String chip;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: mono(context, size: 13, weight: FontWeight.w700, color: done ? palette.good : palette.accent),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: done ? palette.dim : palette.text,
              fontSize: 12.5,
              decoration: done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        TerminalChip(label: chip, color: palette.warn),
      ],
    );
  }
}
