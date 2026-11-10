// Pure streak maths — no IO, fully unit-testable.
//
// [doneOn] answers "was dateKey done?" for a given local day 'YYYY-MM-DD'.

import '../utils/dates.dart';

/// Current streak for a habit.
///
/// Daily: consecutive done days ending today (today not yet done doesn't
/// break the streak — it just isn't counted yet) or yesterday.
/// Weekly: consecutive weeks (Mon–Sun) with at least one done day, ending
/// this week (an empty current week doesn't break it) or last week.
int currentStreak({
  required String cadence,
  required DateTime today,
  required bool Function(String dateKey) doneOn,
}) {
  if (cadence == 'weekly') return _weeklyStreak(today, doneOn);
  return _dailyStreak(today, doneOn);
}

int _dailyStreak(DateTime today, bool Function(String) doneOn) {
  var day = DateTime(today.year, today.month, today.day);
  // Today doesn't count against you — start from yesterday if it's empty.
  if (!doneOn(dateKey(day))) {
    day = day.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (doneOn(dateKey(day))) {
    streak++;
    day = day.subtract(const Duration(days: 1));
    if (streak > 10000) break; // paranoia cap
  }
  return streak;
}

int _weeklyStreak(DateTime today, bool Function(String) doneOn) {
  // Monday-start week containing [today].
  var weekStart = DateTime(today.year, today.month, today.day)
      .subtract(Duration(days: today.weekday - DateTime.monday));

  bool weekHasDone(DateTime start) {
    for (var i = 0; i < 7; i++) {
      if (doneOn(dateKey(start.add(Duration(days: i))))) return true;
    }
    return false;
  }

  if (!weekHasDone(weekStart)) {
    weekStart = weekStart.subtract(const Duration(days: 7));
  }
  var streak = 0;
  while (weekHasDone(weekStart)) {
    streak++;
    weekStart = weekStart.subtract(const Duration(days: 7));
    if (streak > 5200) break; // paranoia cap (~100 years of weeks)
  }
  return streak;
}

/// This week (Mon..Sun) as a list of done-flags — Monday first.
List<bool> currentWeekDots({required DateTime today, required bool Function(String dateKey) doneOn}) {
  final monday = DateTime(today.year, today.month, today.day)
      .subtract(Duration(days: today.weekday - DateTime.monday));
  return List<bool>.generate(7, (i) => doneOn(dateKey(monday.add(Duration(days: i)))));
}
