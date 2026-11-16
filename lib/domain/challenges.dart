// Challenges — bounded habit windows with an optional XP stake.
// Port of PersonalTerminal domain/Challenges (settlement lives in HabitStore).

import '../models/habit.dart';
import 'schedule.dart';

class ChallengeSettlement {
  const ChallengeSettlement({required this.success, required this.xp, required this.done, required this.scheduled});

  final bool success;
  final int xp;
  final int done;
  final int scheduled;
}

class Challenges {
  Challenges._();

  static bool isActive(Habit h, DateTime today) =>
      h.chStart > 0 && !h.chResolved && epochDayOf(today) >= h.chStart && epochDayOf(today) <= h.chEnd;

  /// True once the window closed but the stake has not been settled yet.
  static bool isSettling(Habit h, DateTime today) =>
      h.chStart > 0 && !h.chResolved && h.chEnd > 0 && h.chEnd < epochDayOf(today);

  static bool hasChallenge(Habit h) => h.chStart > 0 && h.chEnd > 0;

  /// 1-based day inside the window, or null when not active today.
  static int? dayOf(Habit h, DateTime today) =>
      isActive(h, today) ? epochDayOf(today) - h.chStart + 1 : null;

  static int totalDays(Habit h) => (h.chEnd > 0 && h.chStart > 0) ? h.chEnd - h.chStart + 1 : 0;

  /// `day 12/30`
  static String? label(Habit h, DateTime today) {
    final d = dayOf(h, today);
    return d == null ? null : 'day $d/${totalDays(h)}';
  }

  /// `[####----]` progress bar of the window (time-based).
  static String progressBar(Habit h, DateTime today, {int width = 10}) {
    final total = totalDays(h);
    if (total <= 0) return '';
    final day = (epochDayOf(today) - h.chStart + 1).clamp(0, total);
    final filled = ((day * width) + total - 1) ~/ total;
    final f = filled.clamp(0, width);
    return '[${'#' * f}${'-' * (width - f)}]';
  }

  /// Half the scheduled days (rounded up) must be completed to win the stake.
  static int threshold(int scheduled) => (scheduled + 1) ~/ 2;

  /// Scheduled/completed counts inside the window up to (not including) today.
  /// [completedOn] answers "was the habit completed on this epoch day?".
  static ({int scheduled, int done}) tally(Habit h, DateTime today, bool Function(int epochDay) completedOn) {
    final tEpoch = epochDayOf(today);
    var scheduled = 0;
    var done = 0;
    var d = dateOfEpochDay(h.chStart);
    final last = dateOfEpochDay(h.chEnd < tEpoch - 1 ? h.chEnd : tEpoch - 1);
    while (!d.isAfter(last)) {
      if (Schedule.isDue(h, d)) {
        scheduled++;
        if (completedOn(epochDayOf(d))) done++;
      }
      d = d.add(const Duration(days: 1));
    }
    return (scheduled: scheduled, done: done);
  }
}
