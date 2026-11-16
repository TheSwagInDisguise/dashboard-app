// Minimum version & ramp targets — port of PersonalTerminal domain/Targets.

import 'dart:math' as math;

import '../models/habit.dart';

class RampState {
  const RampState({
    required this.week,
    required this.weeks,
    required this.current,
    required this.end,
    required this.nextStepIn,
  });

  final int week;
  final int weeks;
  final int current;
  final int end;
  final int nextStepIn;
}

class Targets {
  Targets._();

  /// Effective target for [habit] on [day] (counter/timer only; checkbox
  /// and checklist are fixed).
  static int target(Habit habit, DateTime day) {
    final base = math.max(1, habit.target);
    if (habit.type == HabitType.checkbox || habit.type == HabitType.checklist) return base;
    if (habit.rampTo <= 0 || habit.rampWeeks <= 0 || habit.rampTo == base) return base;
    final start = habit.rampStartDay > 0 ? habit.rampStartDay : null;
    if (start == null) return base;
    final weeks = (epochDayOf(day) - start) / 7.0;
    if (weeks < 0) return base;
    final f = (weeks / habit.rampWeeks).clamp(0.0, 1.0);
    // step per week, rounded to whole units so a target reads "12", never "11.7"
    final stepped = (f * habit.rampWeeks).floor() / habit.rampWeeks;
    return math.max(1, (base + (habit.rampTo - base) * stepped).round());
  }

  /// Ramp state for labels: week n of m, next step, or null when no ramp is
  /// configured / finished.
  static RampState? ramp(Habit habit, DateTime day) {
    if (habit.rampTo <= 0 || habit.rampWeeks <= 0 || habit.rampStartDay <= 0) return null;
    final elapsedDays = epochDayOf(day) - habit.rampStartDay;
    if (elapsedDays < 0) return null;
    final week = elapsedDays ~/ 7 + 1;
    if (week > habit.rampWeeks) return null;
    return RampState(
      week: week,
      weeks: habit.rampWeeks,
      current: target(habit, day),
      end: habit.rampTo,
      nextStepIn: 7 - elapsedDays % 7,
    );
  }

  /// `10 → 30 · week 3/8`
  static String? rampLabel(Habit habit, DateTime day) {
    final r = ramp(habit, day);
    return r == null ? null : '${habit.target} → ${r.end} · week ${r.week}/${r.weeks}';
  }

  /// True when the minimum is set and [value] reaches it without reaching the full target.
  static bool minimumReached(Habit habit, int value, [DateTime? day]) {
    if (habit.minTarget <= 0) return false;
    if (habit.type == HabitType.checkbox || habit.type == HabitType.checklist) return false;
    final full = day != null ? target(habit, day) : math.max(1, habit.target);
    return value >= habit.minTarget && value < full;
  }

  /// True when the day counts for the streak.
  static bool keepsStreak(Habit habit, int value, bool completed, [DateTime? day]) =>
      completed || minimumReached(habit, value, day);
}
