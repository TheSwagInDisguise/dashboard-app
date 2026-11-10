import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:daydeck/models/task.dart';

void main() {
  DateTime nowUtc() => DateTime.utc(2026, 11, 10, 12, 0);

  test('reminderAt round-trips through JSON', () {
    final task = Task(
      id: 't1',
      title: 'renew rego',
      dueDate: '2026-11-12',
      reminderAt: nowUtc(),
      createdAt: nowUtc(),
      updatedAt: nowUtc(),
    );
    final decoded = Task.fromJson(jsonDecode(jsonEncode(task.toJson())));
    expect(decoded.reminderAt, isNotNull);
    expect(decoded.reminderAt!.isUtc, isTrue);
    expect(decoded.dueDate, '2026-11-12');
  });

  test('legacy tasks without reminderAt parse cleanly', () {
    final legacy = {
      'id': 't2',
      'title': 'old task',
      'done': false,
      'priority': 'P1',
      'due': null,
      'createdAt': nowUtc().toIso8601String(),
      'updatedAt': nowUtc().toIso8601String(),
      'deletedAt': null,
    };
    final decoded = Task.fromJson(legacy);
    expect(decoded.reminderAt, isNull);
    expect(decoded.title, 'old task');
  });

  test('clearReminder drops the reminder, reminderAt replaces it', () {
    final task = Task(
      id: 't3',
      title: 'with reminder',
      reminderAt: nowUtc(),
      createdAt: nowUtc(),
      updatedAt: nowUtc(),
    );
    expect(task.copyWith(clearReminder: true).reminderAt, isNull);
    final later = nowUtc().add(const Duration(hours: 3));
    expect(task.copyWith(reminderAt: later).reminderAt, later);
    // Unrelated edits keep the reminder.
    expect(task.copyWith(title: 'renamed').reminderAt, nowUtc());
  });
}
