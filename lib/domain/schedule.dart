// Helpers for habit schedules — port of PersonalTerminal domain/Schedule.
// Pure Dart; no I/O.

import '../models/habit.dart';

class Schedule {
  Schedule._();

  /// Monday-first bit for a DateTime.weekday value (Monday=1..Sunday=7).
  static int bit(int weekday) => 1 << (weekday - 1);

  static bool isDayEnabled(int mask, int weekday) => mask & bit(weekday) != 0;

  static int toggleDay(int mask, int weekday) => mask ^ bit(weekday);

  /// Whether [habit] is due on [date]. Weekly habits are "due" every day
  /// until the quota is met.
  static bool isDue(Habit habit, DateTime date) {
    final epoch = epochDayOf(date);
    if (habit.isPausedOn(epoch)) return false;
    switch (habit.schedule) {
      case ScheduleType.daily:
        return true;
      case ScheduleType.weekly:
        return true;
      case ScheduleType.specificDays:
        return isDayEnabled(habit.daysMask, date.weekday);
      case ScheduleType.biweekly:
        return isDayEnabled(habit.daysMask, date.weekday) &&
            weekParity(habit) == weekIndex(date) % 2;
      case ScheduleType.monthly:
        return habit.monthDay > 0 &&
            date.day == habit.monthDay.clamp(1, _daysInMonth(date));
    }
  }

  static int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  /// Parity (0/1) of the habit's creation week — the biweekly anchor.
  static int weekParity(Habit habit) {
    final created = DateTime(habit.createdAt.toLocal().year, habit.createdAt.toLocal().month, habit.createdAt.toLocal().day);
    return weekIndex(created) % 2;
  }

  /// Weeks since the epoch for [date] (parity source for biweekly schedules).
  static int weekIndex(DateTime date) => epochDayOf(weekStart(date)) ~/ 7;

  /// Monday of the week containing [date].
  static DateTime weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));

  /// "paused → 01 oct" while paused, else null.
  static String? pauseLabel(Habit habit, DateTime today) {
    final epoch = epochDayOf(today);
    if (!habit.isPausedOn(epoch)) return null;
    return 'paused → ${_shortDay(dateOfEpochDay(habit.pausedUntil))}';
  }

  static String _shortDay(DateTime d) {
    const months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
  }

  /// Parse `until 2026-10-01` / `2026-10-01` / `2w` / `10d` / `1m` into a
  /// return date after [today].
  static DateTime? parseUntil(String arg, DateTime today) {
    final a = arg.trim().toLowerCase().replaceFirst(RegExp(r'^(until|till)\s*'), '').trim();
    if (a.isEmpty) return null;
    final rel = RegExp(r'^(\d+)\s*([dwm])$').firstMatch(a);
    if (rel != null) {
      final n = int.parse(rel.group(1)!);
      switch (rel.group(2)!) {
        case 'd':
          return DateTime(today.year, today.month, today.day).add(Duration(days: n));
        case 'w':
          return DateTime(today.year, today.month, today.day).add(Duration(days: 7 * n));
        case 'm':
          return DateTime(today.year, today.month + n, today.day);
      }
    }
    final d = DateTime.tryParse(a);
    if (d == null) return null;
    final day = DateTime(d.year, d.month, d.day);
    final now = DateTime(today.year, today.month, today.day);
    return day.isAfter(now) ? day : null;
  }

  /// Human label: "daily", "3x/week", "mon,wed,fri", "every 2 weeks"…
  static String describe(Habit habit) {
    switch (habit.schedule) {
      case ScheduleType.daily:
        return 'daily';
      case ScheduleType.weekly:
        return '${habit.timesPerWeek}x/week';
      case ScheduleType.biweekly:
        final days = _enabledDays(habit.daysMask);
        if (days.isEmpty) return 'never';
        if (days.length == 7) return 'every 2 weeks';
        return 'every 2w · ${_dayNames(days)}';
      case ScheduleType.monthly:
        if (habit.monthDay <= 0) return 'never';
        if (habit.monthDay > 28) return 'monthly · day ${habit.monthDay} (last day in short months)';
        return 'monthly · ${habit.monthDay}${_ordinal(habit.monthDay)}';
      case ScheduleType.specificDays:
        final days = _enabledDays(habit.daysMask);
        if (days.length == 7) return 'daily';
        if (days.isEmpty) return 'never';
        if (days.length == 2 && days.contains(6) && days.contains(7)) return 'weekends';
        if (days.length == 5 && !days.contains(6) && !days.contains(7)) return 'weekdays';
        return _dayNames(days);
    }
  }

  static List<int> _enabledDays(int mask) =>
      [1, 2, 3, 4, 5, 6, 7].where((d) => isDayEnabled(mask, d)).toList();

  static String _dayNames(List<int> days) {
    const names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    return days.map((d) => names[d - 1]).join(',');
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return 'th';
    switch (n % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  /// Weekly-quota outlook for an `x/week` habit on [date].
  static WeekOutlook weekOutlook(Habit habit, int weekCount, DateTime date) => WeekOutlook(
        done: weekCount,
        quota: habit.timesPerWeek < 1 ? 1 : habit.timesPerWeek,
        daysLeft: 7 - (date.weekday - 1),
      );
}

class WeekOutlook {
  const WeekOutlook({required this.done, required this.quota, required this.daysLeft});

  final int done;
  final int quota;
  final int daysLeft;

  int get remaining => (quota - done).clamp(0, quota);
  bool get met => remaining == 0;
  bool get lastChance => !met && remaining == daysLeft;
  bool get lost => !met && remaining > daysLeft;

  String get label {
    if (met) return '$done/$quota this week ✓';
    if (lost) return '$done/$quota · week missed';
    if (lastChance && daysLeft == 1) return '$done/$quota · last chance today';
    if (lastChance) return '$done/$quota · every day now ($daysLeft left)';
    if (remaining == 1) return '$done/$quota · 1 more, $daysLeft days left';
    return '$done/$quota · $remaining more, $daysLeft days left';
  }
}
