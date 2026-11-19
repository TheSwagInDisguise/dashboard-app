import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/schedule.dart';
import '../models/habit.dart';
import '../state/habit_store.dart';
import '../state/tasks_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import 'terminal_card.dart';

class WeeklyReviewCard extends StatelessWidget {
  const WeeklyReviewCard({super.key, required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final habits = context.watch<HabitStore>();
    final tasks = context.watch<TasksStore>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = Schedule.weekStart(today);
    var due = 0;
    var done = 0;

    for (final habit in habits.habits) {
      if (habit.schedule == ScheduleType.weekly) {
        due += habit.timesPerWeek;
        done += habits
            .weekCount(habit, date: today)
            .clamp(0, habit.timesPerWeek);
        continue;
      }
      for (
        var day = start;
        !day.isAfter(today);
        day = day.add(const Duration(days: 1))
      ) {
        if (epochDayOf(day) < epochDayOf(habit.createdAt.toLocal()) ||
            !Schedule.isDue(habit, day)) {
          continue;
        }
        final log = habits.logOn(habit.id, epochDayOf(day));
        if (log?.skipped == true) {
          continue; // deliberate skips are neutral
        }
        due++;
        if (habits.isDoneOn(habit, epochDayOf(day)) ||
            (log != null && log.completed)) {
          done++;
        }
      }
    }

    final pct = due == 0 ? 0 : (done * 100 / due).round();
    final completedTasks = tasks.doneTasks.where((task) {
      final d = task.updatedAt.toLocal();
      return !d.isBefore(start) &&
          !d.isAfter(today.add(const Duration(days: 1)));
    }).length;
    final accent = pct >= 70
        ? palette.good
        : pct >= 40
        ? palette.warn
        : palette.accent;

    return TerminalCard(
      palette: palette,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'WEEK IN REVIEW',
                style: mono(
                  context,
                  size: 9,
                  weight: FontWeight.w800,
                  color: palette.accent,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            Text(
              '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')} – ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}',
              style: mono(context, size: 8, color: palette.dim),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$done',
              style: mono(
                context,
                size: 24,
                weight: FontWeight.w800,
                color: accent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                ' / $due habit check-ins · $pct%',
                style: mono(context, size: 9, color: palette.dim),
              ),
            ),
            const Spacer(),
            Text(
              '$completedTasks tasks',
              style: mono(
                context,
                size: 9,
                weight: FontWeight.w700,
                color: palette.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: due == 0 ? 0 : (done / due).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: palette.panel2,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          due == 0 ? 'no scheduled habit check-ins this week yet' : 'skipped days are neutral · weekly quotas count once per quota slot',
          style: mono(context, size: 7.5, color: palette.dim),
        ),
      ],
    );
  }
}

/// Twelve-week adherence heatmap. A cell counts how many scheduled habits
/// were completed (negative habits count clean days); paused and skipped days
/// remain neutral. This is derived from synced habit/log data, never cached.
class HabitsHeatmap extends StatelessWidget {
  const HabitsHeatmap({super.key, required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HabitStore>();
    final today = DateTime.now();
    final start = Schedule.weekStart(today).subtract(const Duration(days: 77));
    final counts = <int, int>{};
    final dueCounts = <int, int>{};

    for (var offset = 0; offset < 84; offset++) {
      final day = start.add(Duration(days: offset));
      final epoch = epochDayOf(day);
      for (final habit in store.habits) {
        if (epoch < epochDayOf(habit.createdAt.toLocal()) ||
            !Schedule.isDue(habit, day)) {
          continue;
        }
        final log = store.logOn(habit.id, epoch);
        if (log?.skipped == true) continue;
        dueCounts[epoch] = (dueCounts[epoch] ?? 0) + 1;
        if (store.isDoneOn(habit, epoch) || (log != null && log.completed)) {
          counts[epoch] = (counts[epoch] ?? 0) + 1;
        }
      }
    }

    Color cellColor(int epoch) {
      final due = dueCounts[epoch] ?? 0;
      final count = counts[epoch] ?? 0;
      if (due == 0 || count == 0) return palette.panel2;
      final ratio = count / due;
      return palette.good.withValues(
        alpha: ratio >= 1
            ? .95
            : ratio >= .66
            ? .66
            : ratio >= .33
            ? .42
            : .22,
      );
    }

    return TerminalCard(
      palette: palette,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'HABIT HEATMAP',
                style: mono(
                  context,
                  size: 9,
                  weight: FontWeight.w800,
                  color: palette.accent,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Text('12 WEEKS', style: mono(context, size: 8, color: palette.dim)),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var week = 0; week < 12; week++)
              Column(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++) ...[
                    if (weekday > 0) const SizedBox(height: 3),
                    Builder(
                      builder: (context) {
                        final date = start.add(
                          Duration(days: week * 7 + weekday),
                        );
                        final epoch = epochDayOf(date);
                        return Tooltip(
                          message:
                              '${date.day}/${date.month}: ${counts[epoch] ?? 0}/${dueCounts[epoch] ?? 0}',
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: cellColor(epoch),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: palette.border.withValues(alpha: .65),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('less', style: mono(context, size: 7, color: palette.dim)),
            const SizedBox(width: 5),
            for (final alpha in [.10, .30, .55, .90]) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: palette.good.withValues(alpha: alpha),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 3),
            ],
            Text(
              'more · tap a day for counts',
              style: mono(context, size: 7, color: palette.dim),
            ),
          ],
        ),
      ],
    );
  }
}
