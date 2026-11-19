import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/habit.dart';
import '../domain/targets.dart';
import '../state/app_state.dart';
import '../state/habit_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../widgets/habit_insight_strip.dart';
import '../widgets/habit_review.dart';
import '../widgets/habit_editor_sheet.dart';
import '../widgets/terminal_card.dart';
import '../widgets/terminal_chip.dart';

/// Habits — a short daily checklist with streaks. Synced like everything
/// else; no demo data; starts empty.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final store = context.watch<HabitStore>();
    final habits = store.habits;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Text(
              '// HABITS',
              style: mono(context, size: 24, weight: FontWeight.w700, color: p.accent, letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'small things, done daily',
              style: mono(context, size: 9.5, color: p.dim, letterSpacing: 2.4),
            ),
          ),
          const SizedBox(height: 18),

          WeeklyReviewCard(palette: p),
          const SizedBox(height: 10),
          HabitsHeatmap(palette: p),
          const SizedBox(height: 14),
          SectionHeader(palette: p, title: 'YOUR HABITS', trailing: habits.isEmpty ? 'empty' : '${habits.where((h) => store.doneToday(h.id)).length}/${habits.length} today'),
          const SizedBox(height: 8),
          if (habits.isEmpty)
            TerminalCard(
              palette: p,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 6, 14),
                  child: Column(
                    children: [
                      Text('// nothing here yet', style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 2)),
                      const SizedBox(height: 10),
                      Text(
                        'Pick one tiny thing you can do most days —\n'
                        '“read 10 pages”, “walk 15 min”, “no sugar after 8”.\n'
                        'That’s the whole system.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.dim, fontSize: 12, height: 1.65),
                      ),
                      const SizedBox(height: 14),
                      _AddHabitButton(palette: p, label: 'ADD YOUR FIRST HABIT'),
                    ],
                  ),
                ),
              ],
            )
          else if (MediaQuery.sizeOf(context).width >= 700) ...[
            // Wide screens: two-column card grid instead of one long list.
            Builder(
              builder: (context) {
                final width = MediaQuery.sizeOf(context).width;
                final cardWidth = (width - 28 - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final habit in habits)
                      SizedBox(
                        width: cardWidth,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          decoration: BoxDecoration(
                            color: p.panel,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: p.border),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _HabitCardRow(
                                palette: p,
                                habit: habit,
                                doneToday: store.doneToday(habit.id),
                                streak: store.currentStreak(habit),
                                weekDots: store.thisWeekDots(habit),
                                onToggle: () => _quickLog(store, habit),
                                currentValue: store.logOn(habit.id, epochDayOf(DateTime.now()))?.value ?? 0,
                                checklistMask: store.logOn(habit.id, epochDayOf(DateTime.now()))?.items ?? 0,
                                onAdjustValue: (delta) => store.addValue(habit.id, delta),
                                onToggleChecklistItem: (index) => store.toggleItem(habit.id, index),
                                onEdit: () => _showHabitSheet(context, initial: habit),
                              ),
                              HabitInsightStrip(palette: p, habit: habit, store: store, compact: true),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _AddHabitButton(palette: p, label: '+ ADD HABIT', small: true),
          ] else
            TerminalCard(
              palette: p,
              children: [
                for (final habit in habits) ...[
                  if (habit != habits.first) TerminalCardRule(palette: p),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HabitCardRow(
                        palette: p,
                        habit: habit,
                        doneToday: store.doneToday(habit.id),
                        streak: store.currentStreak(habit),
                        weekDots: store.thisWeekDots(habit),
                        onToggle: () => _quickLog(store, habit),
                        currentValue: store.logOn(habit.id, epochDayOf(DateTime.now()))?.value ?? 0,
                        checklistMask: store.logOn(habit.id, epochDayOf(DateTime.now()))?.items ?? 0,
                        onAdjustValue: (delta) => store.addValue(habit.id, delta),
                        onToggleChecklistItem: (index) => store.toggleItem(habit.id, index),
                        onEdit: () => _showHabitSheet(context, initial: habit),
                      ),
                      HabitInsightStrip(palette: p, habit: habit, store: store, compact: true),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                _AddHabitButton(palette: p, label: '+ ADD HABIT', small: true),
              ],
            ),
          const SizedBox(height: 12),
          Text(
            'tap a habit to check it off for today · ⋯ to rename or delete\n'
            'streaks reset if you miss a day (daily) or a week (weekly)',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.dim, fontSize: 10.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================

void _quickLog(HabitStore store, Habit habit) {
  switch (habit.type) {
    case HabitType.counter:
      store.addValue(habit.id, 1);
      break;
    case HabitType.timer:
      store.addValue(habit.id, 5);
      break;
    case HabitType.checkbox:
    case HabitType.checklist:
      store.toggle(habit.id);
      break;
  }
}

String _typeTag(HabitType type) => switch (type) {
  HabitType.checkbox => 'CHK',
  HabitType.counter => 'CNT',
  HabitType.timer => 'TMR',
  HabitType.checklist => 'LIST',
};

String _scheduleTag(ScheduleType schedule) => switch (schedule) {
  ScheduleType.daily => 'DAILY',
  ScheduleType.weekly => 'WEEKLY',
  ScheduleType.specificDays => 'DAYS',
  ScheduleType.biweekly => 'BIWK',
  ScheduleType.monthly => 'MONTH',
};

class _HabitCardRow extends StatelessWidget {
  const _HabitCardRow({
    required this.palette,
    required this.habit,
    required this.doneToday,
    required this.streak,
    required this.weekDots,
    required this.onToggle,
    required this.currentValue,
    required this.checklistMask,
    required this.onAdjustValue,
    required this.onToggleChecklistItem,
    required this.onEdit,
  });

  final TerminalPalette palette;
  final Habit habit;
  final bool doneToday;
  final int streak;
  final List<bool> weekDots; // Mon..Sun
  final int currentValue;
  final int checklistMask;
  final VoidCallback onToggle;
  final ValueChanged<int> onAdjustValue;
  final ValueChanged<int> onToggleChecklistItem;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              doneToday ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 23,
              color: doneToday ? palette.good : palette.dim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          habit.name,
                          style: TextStyle(
                            color: doneToday ? palette.dim : palette.text,
                            fontSize: 12.5,
                            decoration: doneToday ? TextDecoration.lineThrough : null,
                            decorationColor: palette.dim,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TerminalChip(label: '${_typeTag(habit.type)} · ${_scheduleTag(habit.schedule)}', color: palette.dim),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (habit.type == HabitType.counter || habit.type == HabitType.timer)
                    Text('$currentValue/${Targets.target(habit, DateTime.now())} ${habit.type == HabitType.timer ? 'min' : habit.unit}'.trim(), style: mono(context, size: 8, color: doneToday ? palette.good : palette.dim))
                  else if (habit.type == HabitType.checklist)
                    Text('$currentValue/${habit.checklistItems.length} checklist items', style: mono(context, size: 8, color: doneToday ? palette.good : palette.dim))
                  else
                    Row(children: [
                      for (var i = 0; i < 7; i++)
                        Padding(padding: const EdgeInsets.only(right: 3), child: Text(weekDots[i] ? '●' : '○', style: mono(context, size: 10, color: weekDots[i] ? palette.good : palette.border))),
                      const SizedBox(width: 2),
                      Text('M T W T F S S', style: mono(context, size: 6.5, color: palette.dim, letterSpacing: 1.1)),
                    ]),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$streak',
                  style: mono(context, size: 17, weight: FontWeight.w700, color: streak > 0 ? palette.good : palette.dim),
                ),
                Text(
                  habit.schedule == ScheduleType.weekly ? 'WK STREAK' : 'DAY STREAK',
                  style: mono(context, size: 6, color: palette.dim, letterSpacing: 1.1),
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: palette.dim),
              color: palette.panel2,
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value.startsWith('adjust:')) {
                  onAdjustValue(int.parse(value.substring(7)));
                } else if (value.startsWith('item:')) {
                  onToggleChecklistItem(int.parse(value.substring(5)));
                }
              },
              itemBuilder: (context) => [
                if (habit.type == HabitType.counter || habit.type == HabitType.timer)
                  PopupMenuItem(value: 'adjust:${habit.type == HabitType.timer ? -5 : -1}', child: Text(habit.type == HabitType.timer ? 'subtract 5 minutes' : 'subtract 1 ${habit.unit}'.trim())),
                if (habit.type == HabitType.checklist)
                  for (var i = 0; i < habit.checklistItems.length; i++)
                    PopupMenuItem(value: 'item:$i', child: Text('${(checklistMask & (1 << i)) != 0 ? '✓' : '○'} ${habit.checklistItems[i]}')),
                const PopupMenuItem(value: 'edit', child: Text('edit habit')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddHabitButton extends StatelessWidget {
  const _AddHabitButton({required this.palette, required this.label, this.small = false});

  final TerminalPalette palette;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: () => _showHabitSheet(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: small ? 6 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('+', style: mono(context, size: small ? 12 : 14, weight: FontWeight.w700, color: palette.accent)),
              const SizedBox(width: 8),
              Text(
                label,
                style: mono(context, size: small ? 10 : 11, weight: FontWeight.w700, color: palette.accent, letterSpacing: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showHabitSheet(BuildContext context, {Habit? initial}) =>
    showHabitEditorSheet(context, initial: initial);
