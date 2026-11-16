// Pure streak engine — port of PersonalTerminal domain/Streaks.
//
// Rules:
//  • A streak counts consecutive *scheduled* days on which the habit was
//    completed (full target, or the minimum version when one is set).
//  • Unscheduled days neither add to nor break the chain.
//  • A missed scheduled day breaks the chain unless a shield was used on
//    that exact day or the day was deliberately skipped (skips bridge free).
//  • Today does not break the chain if it isn't completed yet.
//  • Weekly quotas: a week counts once the quota is met; the streak is
//    reported in days for display simplicity (consecutive completed days).
//  • Avoid-habits: every scheduled day is kept unless a slip was logged.

import '../models/habit.dart';
import 'schedule.dart';
import 'targets.dart';

class StreakInfo {
  const StreakInfo({
    required this.current,
    required this.best,
    required this.completions,
    required this.shieldedDays,
    this.repairableDay,
    this.lateLogDay,
  });

  final int current;
  final int best;

  /// Total scheduled days completed.
  final int completions;

  /// Missed scheduled days in the current run bridged by a shield.
  final int shieldedDays;

  /// A broken gap within the last 7 days that a shield could repair.
  final DateTime? repairableDay;

  /// The *repair window*: the previous scheduled day may be ticked late
  /// (before [lateLogCutoffHour] local time) without spending a shield.
  final DateTime? lateLogDay;
}

class Streaks {
  Streaks._();

  /// Late logs for the previous scheduled day are accepted until this hour.
  static const int lateLogCutoffHour = 12;

  static DateTime? _createdFloor(Habit habit, List<HabitLog> logs, List<int> extraDays, DateTime today) {
    var min = epochDayOf(today);
    final own = epochDayOf(habit.createdAt.toLocal());
    if (own < min) min = own;
    for (final l in logs) {
      if (l.day < min) min = l.day;
    }
    for (final d in extraDays) {
      if (d < min) min = d;
    }
    return dateOfEpochDay(min);
  }

  /// The previous scheduled day if it is still inside the repair window.
  static DateTime? lateLogDay(
    Habit habit,
    List<HabitLog> logs,
    List<ShieldUse> shields,
    DateTime today,
    int hourNow,
  ) {
    if (hourNow >= lateLogCutoffHour) return null;
    if (habit.negative || habit.schedule == ScheduleType.weekly) return null;
    final created = _createdFloor(habit, logs, logs.map((l) => l.day).toList(), today)!;
    // last due day strictly before today, looking back at most a week
    var d = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1));
    DateTime? prev;
    for (var i = 0; i < 7 && prev == null; i++) {
      if (!d.isBefore(created) && Schedule.isDue(habit, d)) {
        prev = d;
      } else {
        d = d.subtract(const Duration(days: 1));
      }
    }
    final day = prev;
    if (day == null) return null;
    final e = epochDayOf(day);
    final log = _logOn(logs, e);
    if (log != null && (log.completed || log.skipped)) return null;
    if (log != null && Targets.minimumReached(habit, log.value, day)) return null;
    if (shields.any((s) => s.day == e && !s.deleted)) return null;
    return day;
  }

  static HabitLog? _logOn(List<HabitLog> logs, int day) {
    for (final l in logs) {
      if (l.day == day && !l.deleted) return l;
    }
    return null;
  }

  static StreakInfo compute(
    Habit habit,
    List<HabitLog> logs,
    List<ShieldUse> shields, {
    required DateTime today,
    int? hourNow,
  }) {
    final hour = hourNow ?? DateTime.now().hour;
    final activeLogs = logs.where((l) => !l.deleted).toList();
    // A day counts when the target was reached *or* the minimum version was.
    final completedDays = <int>{
      for (final l in activeLogs)
        if (!l.skipped &&
            (l.completed || Targets.minimumReached(habit, l.value, dateOfEpochDay(l.day))))
          l.day,
    };
    // Skipped days bridge the chain for free.
    final skippedDays = {
      for (final l in activeLogs)
        if (l.skipped) l.day,
    };
    final shieldDays = {
      for (final s in shields)
        if (!s.deleted) s.day,
    };
    final created = _createdFloor(habit, activeLogs, completedDays.toList(), today)!;

    if (habit.negative) {
      return _negative(habit, activeLogs, shieldDays.union(skippedDays), created, today, completedDays.length);
    }
    if (habit.schedule == ScheduleType.weekly) {
      return _weekly(habit, completedDays, shieldDays.union(skippedDays), created, today, completedDays.length);
    }

    // ---- current streak: walk backwards from today ----
    var current = 0;
    var shieldedInCurrent = 0;
    var cursor = DateTime(today.year, today.month, today.day);
    final today0 = cursor;
    DateTime? repairable;
    var first = true;
    while (!cursor.isBefore(created)) {
      if (Schedule.isDue(habit, cursor)) {
        final e = epochDayOf(cursor);
        if (completedDays.contains(e)) {
          current++;
        } else if (shieldDays.contains(e)) {
          shieldedInCurrent++;
        } else if (skippedDays.contains(e)) {
          // deliberate skip bridges the chain
        } else if (first) {
          // today not done yet — chain still alive
        } else {
          repairable = cursor;
          break;
        }
        first = false;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    if (repairable != null && repairable.isBefore(today0.subtract(const Duration(days: 7)))) {
      repairable = null;
    }

    // ---- best streak: forward scan ----
    var best = 0;
    var run = 0;
    var d = created;
    final todayEnd = DateTime(today.year, today.month, today.day);
    while (!d.isAfter(todayEnd)) {
      if (Schedule.isDue(habit, d)) {
        final e = epochDayOf(d);
        if (completedDays.contains(e)) {
          run++;
          if (run > best) best = run;
        } else if (shieldDays.contains(e) || skippedDays.contains(e)) {
          // bridge
        } else if (epochDayOf(d) == epochDayOf(todayEnd)) {
          // pending
        } else {
          run = 0;
        }
      }
      d = d.add(const Duration(days: 1));
    }
    if (current > best) best = current;

    return StreakInfo(
      current: current,
      best: best,
      completions: completedDays.length,
      shieldedDays: shieldedInCurrent,
      repairableDay: repairable,
      lateLogDay: lateLogDay(habit, activeLogs, shields, today, hour),
    );
  }

  /// Avoid-habits: every scheduled day is kept unless a slip was logged
  /// (`completed = false, value > 0`).
  static StreakInfo _negative(
    Habit habit,
    List<HabitLog> logs,
    Set<int> bridgeDays,
    DateTime created,
    DateTime today,
    int keptCountFallback,
  ) {
    final slipDays = {
      for (final l in logs)
        if (!l.completed && l.value > 0 && !l.skipped) l.day,
    };
    bool? kept(DateTime d) {
      if (!Schedule.isDue(habit, d)) return null;
      final e = epochDayOf(d);
      if (bridgeDays.contains(e)) return null;
      return slipDays.contains(e) ? false : true;
    }

    var current = 0;
    var shielded = 0;
    DateTime? repairable;
    var cursor = DateTime(today.year, today.month, today.day);
    final today0 = cursor;
    while (!cursor.isBefore(created)) {
      final k = kept(cursor);
      if (k == true) {
        current++;
      } else if (k == null) {
        if (slipDays.contains(epochDayOf(cursor))) shielded++;
      } else {
        repairable = cursor;
        break;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    if (repairable != null && repairable.isBefore(today0.subtract(const Duration(days: 7)))) {
      repairable = null;
    }
    var best = 0;
    var run = 0;
    var d = created;
    while (!d.isAfter(today0)) {
      final k = kept(d);
      if (k == true) {
        run++;
        if (run > best) best = run;
      } else if (k == false) {
        run = 0;
      }
      d = d.add(const Duration(days: 1));
    }
    if (current > best) best = current;
    final keptDays = _countWhere(created, today0, (d) => kept(d) == true);
    return StreakInfo(
      current: current,
      best: best,
      completions: keptDays,
      shieldedDays: shielded,
      repairableDay: repairable,
    );
  }

  static StreakInfo _weekly(
    Habit habit,
    Set<int> completedDays,
    Set<int> shieldDays,
    DateTime created,
    DateTime today,
    int completions,
  ) {
    DateTime weekOf(int epoch) => Schedule.weekStart(dateOfEpochDay(epoch));
    final perWeek = <DateTime, int>{};
    for (final e in completedDays) {
      final w = weekOf(e);
      perWeek[w] = (perWeek[w] ?? 0) + 1;
    }
    final shieldedWeeks = {for (final e in shieldDays) weekOf(e)};
    final quota = habit.timesPerWeek < 1 ? 1 : habit.timesPerWeek;

    final thisWeek = Schedule.weekStart(today);
    final firstWeek = Schedule.weekStart(created);
    final today0 = DateTime(today.year, today.month, today.day);

    bool pausedWeek(DateTime weekStartDate) {
      for (var i = 0; i < 7; i++) {
        if (habit.isPausedOn(epochDayOf(weekStartDate.add(Duration(days: i))))) return true;
      }
      return false;
    }

    var current = 0;
    var shielded = 0;
    DateTime? repairable;
    var week = thisWeek;
    var firstIteration = true;
    while (!week.isBefore(firstWeek)) {
      final done = (perWeek[week] ?? 0) >= quota;
      if (done) {
        current += 7;
      } else if (shieldedWeeks.contains(week)) {
        shielded++;
      } else if (pausedWeek(week)) {
        // paused week bridges
      } else if (firstIteration && week == thisWeek) {
        // current week still open
      } else {
        repairable = week;
        break;
      }
      firstIteration = false;
      week = week.subtract(const Duration(days: 7));
    }
    if (repairable != null && repairable.isBefore(today0.subtract(const Duration(days: 28)))) {
      repairable = null;
    }

    // best: forward scan over weeks
    var best = 0;
    var run = 0;
    var w = firstWeek;
    while (!w.isAfter(thisWeek)) {
      final done = (perWeek[w] ?? 0) >= quota;
      if (done) {
        run++;
        if (run > best) best = run;
      } else if (shieldedWeeks.contains(w) || pausedWeek(w)) {
        // bridge
      } else if (w == thisWeek) {
        // pending
      } else {
        run = 0;
      }
      w = w.add(const Duration(days: 7));
    }
    if (current > best * 7) best = (current / 7).ceil();

    return StreakInfo(
      current: current,
      best: best * 7,
      completions: completions,
      shieldedDays: shielded,
      repairableDay: repairable,
    );
  }

  static int _countWhere(DateTime from, DateTime to, bool Function(DateTime) predicate) {
    var count = 0;
    var d = from;
    while (!d.isAfter(to)) {
      if (predicate(d)) count++;
      d = d.add(const Duration(days: 1));
    }
    return count;
  }
}
