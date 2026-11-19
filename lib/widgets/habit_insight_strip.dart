import 'package:flutter/material.dart';

import '../domain/schedule.dart';
import '../domain/strength.dart';
import '../models/habit.dart';
import '../state/habit_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';

/// Compact v2 habit feedback: quota, durable strength, the free late-log
/// window, minimum completion and shield repair.
class HabitInsightStrip extends StatelessWidget {
  const HabitInsightStrip({
    super.key,
    required this.palette,
    required this.habit,
    required this.store,
    this.compact = false,
  });

  final TerminalPalette palette;
  final Habit habit;
  final HabitStore store;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final info = store.streakOf(habit, today: now);
    final strength = store.strengthOf(habit, today: now);
    final children = <Widget>[];

    if (habit.schedule == ScheduleType.weekly) {
      final done = store.weekCount(habit, date: today);
      final outlook = Schedule.weekOutlook(habit, done, today);
      final label = outlook.met
          ? '$done/${habit.timesPerWeek} ✓'
          : outlook.lost
          ? '$done/${habit.timesPerWeek} MISSED'
          : outlook.lastChance
          ? '$done/${habit.timesPerWeek} LAST CHANCE'
          : '$done/${habit.timesPerWeek} · ${outlook.remaining} left';
      children.add(_badge(context, 'WK $label', palette.accent));
    }

    final strengthColor = strength.score >= 70
        ? palette.good
        : strength.score >= Strength.slippingThreshold
        ? palette.warn
        : palette.bad;
    children.add(
      _badge(
        context,
        '${compact ? 'STR ' : 'STRENGTH '}${Strength.label(strength)} ${Strength.sparkline(strength.history, cells: 6)}',
        strengthColor,
      ),
    );

    if (habit.minTarget > 0 &&
        (habit.type == HabitType.counter || habit.type == HabitType.timer) &&
        !store.doneToday(habit.id) &&
        (store.logOn(habit.id, epochDayOf(today))?.value ?? 0) <
            habit.minTarget) {
      children.add(
        _action(
          context,
          '[~] ${habit.minTarget} ${habit.unit}'.trimRight(),
          palette.warn,
          () => store.logMinimum(habit.id, date: today),
        ),
      );
    }

    final lateDay = info.lateLogDay;
    if (lateDay != null) {
      children.add(
        _action(
          context,
          'LOG LATE · ${_dateLabel(lateDay)}',
          palette.accent,
          () => store.toggle(habit.id, date: lateDay),
        ),
      );
    }

    final repairDay = info.repairableDay;
    if (repairDay != null) {
      if (store.shieldsAvailable > 0) {
        children.add(
          _action(
            context,
            'REPAIR · ${store.shieldsAvailable} shield${store.shieldsAvailable == 1 ? '' : 's'}',
            palette.warn,
            () => _confirmRepair(context),
          ),
        );
      } else {
        children.add(_badge(context, 'REPAIRABLE · NO SHIELDS', palette.dim));
      }
    }

    return Padding(
      padding: EdgeInsets.only(top: compact ? 3 : 6, left: compact ? 30 : 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }

  Future<void> _confirmRepair(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('USE A STREAK SHIELD?'),
        content: Text(
          'Spend one shield to bridge the missed day for “${habit.name}”?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REPAIR'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final repaired = await store.repairWithShield(habit.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          repaired
              ? 'streak repaired · one shield spent'
              : 'could not repair · no shield or gap remains',
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: mono(
        context,
        size: compact ? 7 : 8,
        weight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  Widget _action(
    BuildContext context,
    String label,
    Color color,
    VoidCallback onTap,
  ) => Material(
    color: color.withValues(alpha: .10),
    borderRadius: BorderRadius.circular(6),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: mono(
            context,
            size: compact ? 7 : 8,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    ),
  );

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}
