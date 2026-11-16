// Life areas — a tag per habit turning "8 of 10 done" into the *shape* of a
// week. Port of PersonalTerminal domain/Areas.

import '../models/habit.dart';
import 'schedule.dart';

class Area {
  const Area(this.id, this.label, this.glyph);
  final String id;
  final String label;
  final String glyph;
}

class AreaScore {
  const AreaScore({required this.area, required this.done, required this.scheduled, required this.habits});

  final Area area;
  final int done;
  final int scheduled;
  final int habits;

  double get rate => scheduled == 0 ? 0 : done / scheduled;
}

class Areas {
  Areas._();

  static const List<Area> all = [
    Area('body', 'body', '♥'),
    Area('mind', 'mind', '☯'),
    Area('work', 'work', 'λ'),
    Area('people', 'people', '☻'),
    Area('home', 'home', '⌂'),
    Area('money', 'money', '\$'),
  ];

  static Area? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Completion rate per area over [from]..[to] (areas without a habit are omitted).
  static List<AreaScore> balance(
    List<({Habit habit, List<HabitLog> logs})> habits,
    DateTime from,
    DateTime to,
  ) {
    final scores = <AreaScore>[];
    for (final area in all) {
      final hs = habits.where((h) => h.habit.area == area.id && !h.habit.archived).toList();
      if (hs.isEmpty) continue;
      var done = 0;
      var scheduled = 0;
      for (final h in hs) {
        final byDay = {for (final l in h.logs) if (!l.deleted) l.day: l};
        var d = from;
        while (!d.isAfter(to)) {
          if (Schedule.isDue(h.habit, d)) {
            final l = byDay[epochDayOf(d)];
            if (l?.skipped != true) {
              scheduled++;
              if (l?.completed == true || (h.habit.negative && l == null)) done++;
            }
          }
          d = d.add(const Duration(days: 1));
        }
      }
      scores.add(AreaScore(area: area, done: done, scheduled: scheduled, habits: hs.length));
    }
    return scores;
  }

  /// Areas with at least one habit but no completion in the last [days] days,
  /// oldest gap first.
  static List<({Area area, int daysSince})> neglected(
    List<({Habit habit, List<HabitLog> logs})> habits,
    DateTime today, {
    int days = 7,
  }) {
    final gaps = <({Area area, int daysSince})>[];
    final todayEpoch = epochDayOf(today);
    for (final area in all) {
      final hs = habits.where((h) => h.habit.area == area.id && !h.habit.archived).toList();
      if (hs.isEmpty) continue;
      var last = -1;
      for (final h in hs) {
        for (final l in h.logs) {
          if (l.completed && !l.skipped && !l.deleted && l.day > last) last = l.day;
        }
      }
      final gap = last < 0 ? 9999 : todayEpoch - last;
      if (gap >= days) gaps.add((area: area, daysSince: gap));
    }
    gaps.sort((a, b) => b.daysSince.compareTo(a.daysSince));
    return gaps;
  }
}
