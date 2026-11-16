// Habit *strength* — port of PersonalTerminal domain/Strength.
//
// An exponentially weighted completion rate over the habit's scheduled days;
// a single miss dents a strong habit by a few points instead of zeroing a
// streak. Skipped, paused and shielded days are neutral (score carried
// over); a partial completion (minimum reached) counts as 0.5.
// Score ∈ 0..100; a habit at 100 that misses one day lands on ~93.

import 'dart:math' as math;

import '../models/habit.dart';
import 'schedule.dart';
import 'targets.dart';

class StrengthResult {
  const StrengthResult({
    required this.score,
    required this.weekAgo,
    required this.history,
  });

  /// 0..100 today.
  final int score;

  /// Score seven scheduled days ago (trend comparison).
  final int weekAgo;

  /// Daily scores for the last [historyLength] scheduled days (oldest first).
  final List<int> history;

  int get trend => score - weekAgo;

  /// True while the habit is slipping but not dead.
  bool get slipping => score >= 1 && score < 40;

  /// ▲ improving, ▼ falling, = flat.
  String get arrow => trend >= 5 ? '▲' : (trend <= -5 ? '▼' : '=');
}

class Strength {
  Strength._();

  /// Per-day learning rate (~a two-week half-life for an established habit).
  static const double alpha = 0.075;

  /// Below this the row shows a warning glyph.
  static const int slippingThreshold = 40;

  static const int historyLength = 28;

  static StrengthResult compute(
    Habit habit,
    List<HabitLog> logs,
    DateTime today, {
    Set<int> shieldedDays = const {},
  }) {
    final byDay = <int, HabitLog>{
      for (final l in logs)
        if (!l.deleted) l.day: l,
    };
    var created = dateOfEpochDay(epochDayOf(today));
    final own = habit.createdAt.toLocal();
    var minDay = epochDayOf(own);
    for (final d in byDay.keys) {
      if (d < minDay) minDay = d;
    }
    if (minDay < epochDayOf(created)) created = dateOfEpochDay(minDay);
    // also never start before the first log
    if (minDay > epochDayOf(created) && byDay.isNotEmpty) created = dateOfEpochDay(minDay);

    var s = 0.0;
    final history = <int>[];
    var d = created;
    final today0 = DateTime(today.year, today.month, today.day);
    while (!d.isAfter(today0)) {
      final e = epochDayOf(d);
      final log = byDay[e];
      final outcome = habit.schedule == ScheduleType.weekly
          ? _weeklyOutcome(habit, byDay, d, today0)
          : _outcome(habit, log, d, today0, shieldedDays.contains(e));
      if (outcome != null) {
        s += alpha * (outcome - s);
        history.add((s * 100).round());
      }
      d = d.add(const Duration(days: 1));
    }
    final score = (s * 100).round().clamp(0, 100);
    final weekAgo = history.length >= 8 ? history[history.length - 8] : 0;
    return StrengthResult(score: score, weekAgo: weekAgo, history: history.length > historyLength ? history.sublist(history.length - historyLength) : history);
  }

  /// Weekly-quota habits are scored per *week*.
  static double? _weeklyOutcome(Habit habit, Map<int, HabitLog> byDay, DateTime day, DateTime today) {
    final log = byDay[epochDayOf(day)];
    if (log != null && log.completed && !log.skipped) return 1.0;
    // the current week is still open (Sunday may close it)
    if (day.weekday != DateTime.sunday || _sameDay(day, today)) return null;
    if (habit.isPausedOn(epochDayOf(day))) return null;
    final start = epochDayOf(Schedule.weekStart(day));
    final weekDays = List<int>.generate(7, (i) => start + i);
    final done = weekDays.where((e) => byDay[e]?.completed == true && byDay[e]?.skipped != true).length;
    final skippedWeek = weekDays.any((e) => byDay[e]?.skipped == true);
    return (done >= habit.timesPerWeek || skippedWeek) ? null : 0.0;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 1.0 done · 0.5 minimum reached · 0.0 missed · null neutral.
  static double? _outcome(Habit habit, HabitLog? log, DateTime day, DateTime today, bool shielded) {
    if (!Schedule.isDue(habit, day)) return null;
    if (log != null && log.skipped) return null;
    if (shielded) return null;
    if (habit.negative) {
      final slipped = log != null && !log.completed && log.value > 0;
      return slipped ? 0.0 : 1.0;
    }
    if (log != null && log.completed) return 1.0;
    if (log != null && Targets.minimumReached(habit, log.value, day)) return 0.5;
    if (_sameDay(day, today)) return null;
    return 0.0;
  }

  /// `87%` or `87% ▼`.
  static String label(StrengthResult r, {bool withTrend = true}) =>
      '${r.score}%${withTrend && r.arrow != '=' ? ' ${r.arrow}' : ''}';

  /// Eight-cell sparkline from the history (`▁▂▃▄▅▆▇█`).
  static String sparkline(List<int> history, {int cells = 8}) {
    if (history.isEmpty) return '░' * cells;
    const bars = '▁▂▃▄▅▆▇█';
    final step = history.length / cells;
    final sb = StringBuffer();
    for (var i = 0; i < cells; i++) {
      final idx = math.min(history.length - 1, (i * step).floor());
      final v = history[idx].clamp(0, 100);
      sb.write(bars[((v / 100.0) * (bars.length - 1)).round()]);
    }
    return sb.toString();
  }

  /// Expected score after [n] straight completions from zero.
  static int afterStreak(int n) =>
      ((1 - math.pow(1 - alpha, n)) * 100).round();
}
