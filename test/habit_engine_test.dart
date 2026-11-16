// Locks the semantics of the v0.11 habit engine (ported from
// PersonalTerminal): schedules, streaks, avoid-habits, minimums, ramps,
// shields, XP levels and strength scoring.

import 'package:flutter_test/flutter_test.dart';

import 'package:daydeck/domain/progression.dart';
import 'package:daydeck/domain/schedule.dart';
import 'package:daydeck/domain/streak_engine.dart';
import 'package:daydeck/domain/strength.dart';
import 'package:daydeck/domain/targets.dart';
import 'package:daydeck/models/habit.dart';

DateTime day(int y, int m, int d) => DateTime(y, m, d);

Habit _habit({
  String id = 'h1',
  String name = 'test habit',
  HabitType type = HabitType.checkbox,
  int target = 1,
  ScheduleType schedule = ScheduleType.daily,
  int daysMask = 127,
  int timesPerWeek = 3,
  int monthDay = 0,
  bool negative = false,
  int minTarget = 0,
  int rampTo = 0,
  int rampWeeks = 0,
  int rampStartDay = 0,
  int pausedFrom = 0,
  int pausedUntil = 0,
  DateTime? createdAt,
}) {
  final created = createdAt ?? day(2026, 10, 1);
  return Habit(
    id: id,
    name: name,
    type: type,
    target: target,
    schedule: schedule,
    daysMask: daysMask,
    timesPerWeek: timesPerWeek,
    monthDay: monthDay,
    negative: negative,
    minTarget: minTarget,
    rampTo: rampTo,
    rampWeeks: rampWeeks,
    rampStartDay: rampStartDay,
    pausedFrom: pausedFrom,
    pausedUntil: pausedUntil,
    createdAt: created,
    updatedAt: created,
  );
}

HabitLog _log({
  required String habitId,
  required DateTime day_,
  bool completed = true,
  int value = 1,
  bool skipped = false,
}) {
  final epoch = epochDayOf(day_);
  return HabitLog(
    id: '$habitId|${dateKeyOfEpochDay(epoch)}',
    habitId: habitId,
    day: epoch,
    value: value,
    completed: completed,
    skipped: skipped,
    createdAt: day_.toUtc(),
    updatedAt: day_.toUtc(),
  );
}

ShieldUse _shield(String habitId, DateTime day_) {
  final epoch = epochDayOf(day_);
  return ShieldUse(
    id: '$habitId|${dateKeyOfEpochDay(epoch)}',
    habitId: habitId,
    day: epoch,
    usedAt: day_.toUtc(),
    createdAt: day_.toUtc(),
    updatedAt: day_.toUtc(),
  );
}

void main() {
  final today = day(2026, 11, 10); // a Tuesday

  group('epoch day math', () {
    test('round-trips through date strings', () {
      final epoch = parseEpochDay('2026-11-10');
      expect(dateKeyOfEpochDay(epoch), '2026-11-10');
      expect(epochDayOf(day(2026, 11, 10)), epoch);
    });

    test('weekStart is Monday', () {
      expect(Schedule.weekStart(day(2026, 11, 10)), day(2026, 11, 9)); // Tuesday → Monday
      expect(Schedule.weekStart(day(2026, 11, 9)), day(2026, 11, 9)); // Monday itself
      expect(Schedule.weekStart(day(2026, 11, 15)), day(2026, 11, 9)); // Sunday belongs to same week
    });
  });

  group('schedules', () {
    test('daily is due every day', () {
      final h = _habit();
      expect(Schedule.isDue(h, today), isTrue);
      expect(Schedule.isDue(h, day(2026, 10, 1)), isTrue);
    });

    test('specificDays honours the weekday mask', () {
      final fridaysOnly = _habit(schedule: ScheduleType.specificDays, daysMask: 1 << 4);
      expect(Schedule.isDue(fridaysOnly, day(2026, 11, 13)), isTrue); // Friday
      expect(Schedule.isDue(fridaysOnly, day(2026, 11, 10)), isFalse); // Tuesday
    });

    test('monthly clamps to the last day of short months', () {
      final h = _habit(schedule: ScheduleType.monthly, monthDay: 31);
      expect(Schedule.isDue(h, day(2026, 1, 31)), isTrue);
      expect(Schedule.isDue(h, day(2026, 2, 28)), isTrue); // clamps
      expect(Schedule.isDue(h, day(2026, 2, 1)), isFalse);
      expect(Schedule.isDue(h, day(2026, 3, 31)), isTrue);
    });

    test('biweekly fires only in the creation week parity', () {
      final h = _habit(
        schedule: ScheduleType.biweekly,
        daysMask: 1 << (today.weekday - 1), // today's weekday
        createdAt: today,
      );
      expect(Schedule.isDue(h, today), isTrue);
      final nextWeekSameWeekday = today.add(const Duration(days: 7));
      expect(Schedule.isDue(h, nextWeekSameWeekday), isFalse);
      final twoWeeksLater = today.add(const Duration(days: 14));
      expect(Schedule.isDue(h, twoWeeksLater), isTrue);
    });

    test('a paused habit is never due', () {
      final h = _habit(
        pausedFrom: epochDayOf(day(2026, 11, 8)),
        pausedUntil: epochDayOf(day(2026, 11, 12)),
      );
      expect(Schedule.isDue(h, day(2026, 11, 8)), isFalse);
      expect(Schedule.isDue(h, day(2026, 11, 10)), isFalse);
      expect(Schedule.isDue(h, day(2026, 11, 11)), isFalse);
      expect(Schedule.isDue(h, day(2026, 11, 12)), isTrue); // back on the 12th
      expect(Schedule.pauseLabel(h, today), isNotNull);
    });
  });

  group('streaks', () {
    Habit weekOld() => _habit(createdAt: day(2026, 11, 6));

    test('a full run counts every day', () {
      final h = weekOld();
      final logs = [
        for (final d in [day(2026, 11, 6), day(2026, 11, 7), day(2026, 11, 8), day(2026, 11, 9), today])
          _log(habitId: 'h1', day_: d),
      ];
      final info = Streaks.compute(h, logs, const [], today: today, hourNow: 9);
      expect(info.current, 5);
      expect(info.best, 5);
      expect(info.completions, 5);
    });

    test('today pending does not break the chain', () {
      final h = weekOld();
      final logs = [
        for (final d in [day(2026, 11, 6), day(2026, 11, 7), day(2026, 11, 8), day(2026, 11, 9)])
          _log(habitId: 'h1', day_: d),
      ];
      final info = Streaks.compute(h, logs, const [], today: today, hourNow: 9);
      expect(info.current, 4);
      expect(info.best, 4);
    });

    test('a miss breaks the chain and marks the day repairable', () {
      final h = weekOld();
      final logs = [
        for (final d in [day(2026, 11, 6), day(2026, 11, 7), day(2026, 11, 9), today])
          _log(habitId: 'h1', day_: d),
      ];
      final info = Streaks.compute(h, logs, const [], today: today, hourNow: 9);
      expect(info.current, 2); // today + the 9th
      expect(info.repairableDay, day(2026, 11, 8));
    });

    test('a shield bridges a single miss', () {
      final h = weekOld();
      final logs = [
        for (final d in [day(2026, 11, 6), day(2026, 11, 7), day(2026, 11, 9), today])
          _log(habitId: 'h1', day_: d),
      ];
      final info = Streaks.compute(h, logs, [_shield('h1', day(2026, 11, 8))], today: today, hourNow: 9);
      expect(info.current, 4); // Nov 6, 7, 9, today — the shield bridges but doesn't count
      expect(info.shieldedDays, 1);
    });

    test('a deliberate skip bridges the chain for free', () {
      final h = weekOld();
      final logs = [
        for (final d in [day(2026, 11, 6), day(2026, 11, 7), day(2026, 11, 9), today])
          _log(habitId: 'h1', day_: d),
        _log(habitId: 'h1', day_: day(2026, 11, 8), completed: false, value: 0, skipped: true),
      ];
      final info = Streaks.compute(h, logs, const [], today: today, hourNow: 9);
      expect(info.current, 4); // Nov 6, 7, 9, today — the skip bridges but doesn't count
    });

    test('avoid-habits are kept by default and broken by slips', () {
      final h = _habit(negative: true, createdAt: day(2026, 11, 6));
      final clean = Streaks.compute(h, const [], const [], today: today, hourNow: 9);
      expect(clean.current, 5); // Nov 6, 7, 8, 9, 10 all kept

      final slipped = Streaks.compute(
        h,
        [_log(habitId: 'h1', day_: day(2026, 11, 8), completed: false, value: 1)],
        const [],
        today: today,
        hourNow: 9,
      );
      expect(slipped.current, 2); // only the 9th and today remain after the slip
    });
  });

  group('minimums and ramps', () {
    test('minimum reached counts toward streaks but not full completion', () {
      final h = _habit(
        type: HabitType.counter,
        target: 30,
        minTarget: 10,
        createdAt: day(2026, 11, 6),
      );
      final now = today;
      expect(Targets.minimumReached(h, 9, now), isFalse);
      expect(Targets.minimumReached(h, 10, now), isTrue);
      expect(Targets.minimumReached(h, 29, now), isTrue);
      expect(Targets.minimumReached(h, 30, now), isFalse); // that's the full target
      // A minimum-only day still keeps the streak alive.
      final logs = [
        _log(habitId: 'h1', day_: day(2026, 11, 9), completed: false, value: 12),
      ];
      final info = Streaks.compute(h, logs, const [], today: today, hourNow: 9);
      expect(info.best, 1);
    });

    test('ramped targets step up weekly and land exactly on rampTo', () {
      final h = _habit(
        type: HabitType.counter,
        target: 30,
        rampTo: 50,
        rampWeeks: 4,
        rampStartDay: epochDayOf(day(2026, 11, 3)),
      );
      expect(Targets.target(h, day(2026, 11, 3)), 30);
      expect(Targets.target(h, day(2026, 11, 17)), 40); // 2 weeks in
      expect(Targets.target(h, day(2026, 12, 1)), 50); // ramp finished
      expect(Targets.ramp(h, day(2026, 11, 10))?.week, 2);
    });
  });

  group('progression', () {
    test('level curve matches the port (50·(n−1)·n)', () {
      expect(Progression.xpForLevel(1), 0);
      expect(Progression.xpForLevel(2), 100);
      expect(Progression.levelForXp(0), 1);
      expect(Progression.levelForXp(99), 1);
      expect(Progression.levelForXp(100), 2);
      expect(Progression.levelForXp(300), 3); // xpForLevel(3) == 300
    });

    test('progress reports into-level fraction', () {
      final p = Progression.progress(150);
      expect(p.level, 2);
      expect(p.xpIntoLevel, 50);
      expect(p.xpForNext, 200); // level 3 needs 300, level 2 base 100
    });

    test('shields earned every 10 completions, capped at 3 held', () {
      expect(Progression.shieldsEarned(0), 0);
      expect(Progression.shieldsEarned(25), 2);
      expect(Progression.shieldsAvailable(25, 0), 2);
      expect(Progression.shieldsAvailable(200, 0), 3); // cap
      expect(Progression.shieldsAvailable(200, 2), 3); // holding cap is 3
      expect(Progression.shieldsAvailable(0, 1), 0); // clamp at zero
    });
  });

  group('strength', () {
    test('a clean history scores high', () {
      final h = _habit(createdAt: day(2026, 10, 20));
      final logs = [
        for (var d = day(2026, 10, 20); !d.isAfter(today); d = d.add(const Duration(days: 1)))
          _log(habitId: 'h1', day_: d),
      ];
      final s = Strength.compute(h, logs, today);
      expect(s.score, greaterThanOrEqualTo(80)); // EWMA warms up from zero (afterStreak(22) ≈ 82)
      expect(s.slipping, isFalse);
    });

    test('a habit that never happens is dead or slipping', () {
      final h = _habit(createdAt: day(2026, 10, 1));
      final s = Strength.compute(h, const [], today);
      expect(s.score, lessThan(40));
    });
  });
}
