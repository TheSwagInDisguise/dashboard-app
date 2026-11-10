import 'package:flutter_test/flutter_test.dart';

import 'package:daydeck/utils/streaks.dart';

String key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final today = DateTime(2026, 11, 10); // a Tuesday

  group('daily streaks', () {
    test('today + previous days all done', () {
      final done = {key(today), key(today.subtract(const Duration(days: 1))), key(today.subtract(const Duration(days: 2)))};
      expect(currentStreak(cadence: 'daily', today: today, doneOn: done.contains), 3);
    });

    test('today not done yet, but yesterday + before are', () {
      final done = {key(today.subtract(const Duration(days: 1))), key(today.subtract(const Duration(days: 2)))};
      expect(currentStreak(cadence: 'daily', today: today, doneOn: done.contains), 2);
    });

    test('a gap day ends the streak', () {
      final done = {key(today), key(today.subtract(const Duration(days: 2)))};
      expect(currentStreak(cadence: 'daily', today: today, doneOn: done.contains), 1);
    });

    test('nothing done → 0', () {
      expect(currentStreak(cadence: 'daily', today: today, doneOn: (_) => false), 0);
    });
  });

  group('weekly streaks', () {
    test('this week done counts, plus previous weeks', () {
      final thisWeek = today.subtract(Duration(days: today.weekday - DateTime.monday));
      final lastWeek = thisWeek.subtract(const Duration(days: 7));
      final done = {key(thisWeek.add(const Duration(days: 2))), key(lastWeek.add(const Duration(days: 1)))};
      expect(currentStreak(cadence: 'weekly', today: today, doneOn: done.contains), 2);
    });

    test('empty current week falls back to last week', () {
      final thisWeek = today.subtract(Duration(days: today.weekday - DateTime.monday));
      final lastWeek = thisWeek.subtract(const Duration(days: 7));
      final weekBefore = lastWeek.subtract(const Duration(days: 7));
      final done = {key(lastWeek.add(const Duration(days: 3))), key(weekBefore.add(const Duration(days: 0)))};
      expect(currentStreak(cadence: 'weekly', today: today, doneOn: done.contains), 2);
    });

    test('nothing done → 0', () {
      expect(currentStreak(cadence: 'weekly', today: today, doneOn: (_) => false), 0);
    });
  });

  test('currentWeekDots returns Mon..Sun', () {
    final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    final dots = currentWeekDots(today: today, doneOn: (d) => d == key(monday));
    expect(dots, [true, false, false, false, false, false, false]);
  });
}
