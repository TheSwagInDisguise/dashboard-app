import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

/// Phase 6 placeholder — habit streaks on the Today view come later.
/// This stub exists so the navigation, theme and layout are reviewable today.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  static const _sample = [
    ('Move 20 min', '34d'),
    ('Read 10 min', '5d'),
    ('No sugar after 8pm', '12d'),
  ];

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
              '// HABITS',
              style: mono(context, size: 26, weight: FontWeight.w700, color: p.accent, letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'ARRIVES IN PHASE 6',
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
                children: [
                  for (final (name, streak) in _sample) ...[
                    if (name != _sample.first.$1) Divider(color: p.border, height: 16),
                    Row(
                      children: [
                        Expanded(child: Text(name, style: TextStyle(color: p.text, fontSize: 12.5))),
                        Text(
                          streak,
                          style: mono(context, size: 15, weight: FontWeight.w700, color: p.good),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Phase 6 wires this up: a short daily checklist with streaks,\n'
            'shown right on the Today view.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.dim, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}
