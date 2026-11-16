import 'package:flutter_test/flutter_test.dart';

import 'package:daydeck/models/habit.dart';

void main() {
  test('v0.10 habit row migrates: title → name, cadence → schedule', () {
    final legacy = {
      'id': 'habit-1',
      'title': 'read 20 pages',
      'cadence': 'daily',
      'createdAt': '2026-10-01T00:00:00.000Z',
      'updatedAt': '2026-10-02T00:00:00.000Z',
      'deletedAt': null,
    };
    final habit = Habit.fromJson(legacy);
    expect(habit.name, 'read 20 pages');
    expect(habit.schedule, ScheduleType.daily);
    expect(habit.target, 1);
    expect(habit.timesPerWeek, 3);
    expect(habit.type, HabitType.checkbox);
    expect(habit.id, 'habit-1');
  });

  test('v0.10 weekly habit keeps weekly meaning with one slot per week', () {
    final legacy = {
      'id': 'habit-2',
      'title': 'mow the lawn',
      'cadence': 'weekly',
      'createdAt': '2026-10-01T00:00:00.000Z',
      'updatedAt': '2026-10-02T00:00:00.000Z',
    };
    final habit = Habit.fromJson(legacy);
    expect(habit.schedule, ScheduleType.weekly);
    expect(habit.timesPerWeek, 1);
  });

  test('v0.10 habit log migrates: date+done → day+completed', () {
    final legacy = {
      'id': 'habit-1|2026-10-05',
      'habitId': 'habit-1',
      'date': '2026-10-05',
      'done': true,
      'createdAt': '2026-10-05T09:00:00.000Z',
      'updatedAt': '2026-10-05T09:00:00.000Z',
    };
    final log = HabitLog.fromJson(legacy);
    expect(log.day, parseEpochDay('2026-10-05'));
    expect(log.completed, isTrue);
    expect(log.value, 1);
    expect(log.skipped, isFalse);
    expect(log.id, 'habit-1|2026-10-05');
  });

  test('new-format habit round-trips losslessly', () {
    final now = DateTime.utc(2026, 11, 10, 8, 30);
    final original = Habit(
      id: 'h-new',
      name: 'walk the dog',
      type: HabitType.counter,
      target: 8000,
      unit: 'steps',
      schedule: ScheduleType.specificDays,
      daysMask: 31,
      color: 'cyan',
      area: 'body',
      minTarget: 2000,
      reminderMinutes: 7 * 60 + 45,
      createdAt: now,
      updatedAt: now,
    );
    final decoded = Habit.fromJson(original.toJson());
    expect(decoded.name, 'walk the dog');
    expect(decoded.type, HabitType.counter);
    expect(decoded.target, 8000);
    expect(decoded.daysMask, 31);
    expect(decoded.area, 'body');
    expect(decoded.minTarget, 2000);
    expect(decoded.reminderMinutes, 7 * 60 + 45);
  });

  test('negative habit round-trips: avoid-habit flag survives sync', () {
    final now = DateTime.utc(2026, 11, 10);
    final original = Habit(
      id: 'h-neg',
      name: 'no sugar',
      negative: true,
      createdAt: now,
      updatedAt: now,
    );
    final decoded = Habit.fromJson(original.toJson());
    expect(decoded.negative, isTrue);
  });
}
