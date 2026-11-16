// Streak-insurance rules — port of PersonalTerminal domain/SkipRules.

import '../models/habit.dart';

class SkipRules {
  SkipRules._();

  /// Range: fromDay..toDay inclusive (null toDay = open-ended). Weekly: weekdayMask.
  static bool matchesDay(SkipRule rule, DateTime date) {
    if (!rule.enabled || rule.deleted) return false;
    final e = epochDayOf(date);
    if (rule.kind == SkipRule.kindRange) {
      final from = rule.fromDay ?? 0;
      final to = rule.toDay;
      if (from > 0 && e < from) return false;
      if (to != null && e > to) return false;
      return true;
    }
    if (rule.kind == SkipRule.kindWeekly) {
      return (rule.weekdayMask >> (date.weekday - 1)) & 1 == 1;
    }
    return false;
  }

  static bool appliesTo(SkipRule rule, Habit habit) {
    final set = rule.habitIdSet;
    return set.isEmpty || set.contains(habit.id);
  }

  /// First enabled rule covering [habit] on [date], or null.
  static SkipRule? covering(List<SkipRule> rules, Habit habit, DateTime date) {
    for (final rule in rules) {
      if (matchesDay(rule, date) && appliesTo(rule, habit)) return rule;
    }
    return null;
  }
}
