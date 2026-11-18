import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/areas.dart';
import '../domain/progression.dart';
import '../models/habit.dart' show XpEvent, dateOfEpochDay;
import '../state/app_state.dart';
import '../state/habit_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../widgets/terminal_card.dart';

/// whoami — the operator profile. Level + XP from the ledger, life-area
/// balance from the last 30 days, and the XP feed.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final app = context.watch<AppState>();
    final store = context.watch<HabitStore>();
    final progress = store.levelProgress;
    final balance = store.areaBalance();
    final neglected = store.neglectedAreas();
    final xpLog = store.xpLog(limit: 14);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Text(
              '// WHOAMI',
              style: mono(context, size: 24, weight: FontWeight.w700, color: p.accent, letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'the operator · ${app.username}',
              style: mono(context, size: 9.5, color: p.dim, letterSpacing: 2.4),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune, size: 16),
              label: Text('PREFERENCES & SYNC', style: mono(context, size: 9, weight: FontWeight.w700, letterSpacing: 1.2)),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.border),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _LevelCard(palette: p, progress: progress, totalCompletions: store.totalCompletions, shieldsAvailable: store.shieldsAvailable, shieldsUsed: store.shieldsUsed),
          const SizedBox(height: 14),
          SectionHeader(palette: p, title: 'LIFE AREAS', trailing: 'last 30 days'),
          const SizedBox(height: 8),
          _AreasCard(palette: p, balance: balance, neglected: neglected),
          const SizedBox(height: 14),
          SectionHeader(palette: p, title: 'XP LEDGER', trailing: 'last ${xpLog.length}'),
          const SizedBox(height: 8),
          _XpLedger(palette: p, entries: xpLog, store: store),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.palette,
    required this.progress,
    required this.totalCompletions,
    required this.shieldsAvailable,
    required this.shieldsUsed,
  });

  final TerminalPalette palette;
  final LevelProgress progress;
  final int totalCompletions;
  final int shieldsAvailable;
  final int shieldsUsed;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final title = _titleForLevel(progress.level);
    final span = progress.xpForNext <= 0 ? 1 : progress.xpForNext;

    return TerminalCard(
      palette: p,
      children: [
        Row(
          children: [
            Container(
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accent.withValues(alpha: 0.12),
                border: Border.all(color: p.accent, width: 1.6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${progress.level}',
                      style: mono(context, size: 26, weight: FontWeight.w800, color: p.accent)),
                  Text('LVL', style: mono(context, size: 7, color: p.dim, letterSpacing: 2)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(title.toUpperCase(),
                          style: mono(context, size: 14, weight: FontWeight.w800, color: p.text, letterSpacing: 2)),
                      const SizedBox(width: 8),
                      Text('${progress.xp} XP total',
                          style: mono(context, size: 9, color: p.dim)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: progress.fraction.clamp(0.0, 1.0),
                      backgroundColor: p.panel2,
                      valueColor: AlwaysStoppedAnimation(p.accent),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${progress.xpIntoLevel} / $span XP to level ${progress.level + 1}',
                    style: mono(context, size: 8.5, color: p.dim),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TerminalCardRule(palette: p),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: _StatCell(palette: p, value: '$totalCompletions', label: 'COMPLETIONS'),
              ),
              Container(width: 1, height: 28, color: p.border),
              Expanded(
                child: _StatCell(palette: p, value: '$shieldsAvailable', label: 'SHIELDS HELD'),
              ),
              Container(width: 1, height: 28, color: p.border),
              Expanded(
                child: _StatCell(palette: p, value: '$shieldsUsed', label: 'SHIELDS SPENT'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _titleForLevel(int level) {
  if (level >= 50) return 'kernel';
  if (level >= 40) return 'root';
  if (level >= 30) return 'sysadmin';
  if (level >= 20) return 'daemon';
  if (level >= 15) return 'maintainer';
  if (level >= 10) return 'contributor';
  if (level >= 5) return 'committer';
  if (level >= 2) return 'user';
  return 'guest';
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.palette, required this.value, required this.label});

  final TerminalPalette palette;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      children: [
        Text(value, style: mono(context, size: 14, weight: FontWeight.w800, color: p.accent)),
        const SizedBox(height: 2),
        Text(label, style: mono(context, size: 7, color: p.dim, letterSpacing: 1.4)),
      ],
    );
  }
}

class _AreasCard extends StatelessWidget {
  const _AreasCard({required this.palette, required this.balance, required this.neglected});

  final TerminalPalette palette;
  final List<AreaScore> balance;
  final List<({Area area, int daysSince})> neglected;

  @override
  Widget build(BuildContext context) {
    final p = palette;

    if (balance.isEmpty) {
      return TerminalCard(
        palette: p,
        children: [
          Text('// no areas tagged yet', style: mono(context, size: 12, weight: FontWeight.w700, color: p.accent)),
          const SizedBox(height: 6),
          Text(
            'Tag habits with a life area (body, mind, work, people, home, money)\n'
            'in the habit editor and this chart fills in.',
            style: TextStyle(color: p.dim, fontSize: 11, height: 1.6),
          ),
        ],
      );
    }

    final neglectedIds = {for (final n in neglected) n.area.id};

    return TerminalCard(
      palette: p,
      children: [
        for (final entry in balance) ...[
          if (entry != balance.first) TerminalCardRule(palette: p),
          Builder(
            builder: (context) {
              final area = entry.area;
              final rate = entry.rate.clamp(0.0, 1.0);
              final isNeglected = neglectedIds.contains(area.id);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(area.glyph, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: p.text)),
                    ),
                    SizedBox(
                      width: 74,
                      child: Text(area.label.toUpperCase(),
                          style: mono(context, size: 9.5, weight: FontWeight.w700, color: isNeglected ? p.warn : p.text, letterSpacing: 1.6)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: rate,
                          backgroundColor: p.panel2,
                          valueColor: AlwaysStoppedAnimation(isNeglected ? p.warn : p.accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${entry.done}/${entry.scheduled}', style: mono(context, size: 9, color: p.dim)),
                  ],
                ),
              );
            },
          ),
        ],
        if (neglected.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'neglected ≥ 7 days: ${neglected.map((n) => n.area.label).join(', ')}',
            style: mono(context, size: 8.5, color: p.warn),
          ),
        ],
      ],
    );
  }
}

class _XpLedger extends StatelessWidget {
  const _XpLedger({required this.palette, required this.entries, required this.store});

  final TerminalPalette palette;
  final List<XpEvent> entries; // newest first
  final HabitStore store;

  @override
  Widget build(BuildContext context) {
    final p = palette;

    if (entries.isEmpty) {
      return TerminalCard(
        palette: p,
        children: [
          Text('no XP yet — check off a habit to begin.', style: mono(context, size: 10, color: p.dim)),
        ],
      );
    }

    return TerminalCard(
      palette: p,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) TerminalCardRule(palette: p),
          Builder(
            builder: (context) {
              final e = entries[i];
              final habit = e.habitId == '0' ? null : store.habitById(e.habitId);
              final day = dateOfEpochDay(e.day);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text('+${e.amount}',
                          style: mono(context, size: 12, weight: FontWeight.w800, color: p.good)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _reasonLabel(e.reason),
                            style: TextStyle(color: p.text, fontSize: 11),
                          ),
                          if (habit != null)
                            Text(habit.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.dim, fontSize: 9.5)),
                        ],
                      ),
                    ),
                    Text('${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
                        style: mono(context, size: 8.5, color: p.dim)),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}


String _reasonLabel(String reason) {
  switch (reason) {
    case 'complete':
      return 'habit completed';
    case 'streak':
      return 'streak held';
    case 'perfect_day':
      return 'perfect day';
    case 'minimum':
      return 'minimum met';
    case 'challenge':
      return 'challenge resolved';
    default:
      return reason;
  }
}
