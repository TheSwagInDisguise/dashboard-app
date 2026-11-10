import 'package:flutter/foundation.dart';

import '../models/habit.dart';
import '../utils/dates.dart';
import '../utils/streaks.dart' as streaks;
import 'json_doc_store.dart';

/// Habit store — habits and their daily logs live in two synced documents
/// (habits.json, habit_logs.json) managed here behind one notifier.
class HabitStore extends ChangeNotifier {
  HabitStore()
      : _habits = JsonDocStore<Habit>(
          mainKey: 'habits_json',
          backupKey: 'habits_json_backup',
          fromJson: Habit.fromJson,
          toJson: (h) => h.toJson(),
          idOf: (h) => h.id,
        ),
        _logs = JsonDocStore<HabitLog>(
          mainKey: 'habit_logs_json',
          backupKey: 'habit_logs_json_backup',
          fromJson: HabitLog.fromJson,
          toJson: (l) => l.toJson(),
          idOf: (l) => l.id,
        );

  final JsonDocStore<Habit> _habits;
  final JsonDocStore<HabitLog> _logs;

  String? get recoveryNotice => _habits.recoveryNotice ?? _logs.recoveryNotice;
  void clearRecoveryNotice() {
    _habits.clearRecoveryNotice();
    _logs.clearRecoveryNotice();
    notifyListeners();
  }

  Future<void> load() async {
    await _habits.load();
    await _logs.load();
  }

  // ---- sync engine views ----
  List<Habit> snapshotHabits() => _habits.snapshotItems();
  List<HabitLog> snapshotLogs() => _logs.snapshotItems();

  Future<void> replaceAllHabits(List<Habit> items) async {
    await _habits.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllLogs(List<HabitLog> items) async {
    await _logs.replaceAll(items);
    notifyListeners();
  }

  // ---- queries ----

  List<Habit> get habits {
    final list = _habits.items.where((h) => !h.deleted).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  bool doneOn(String habitId, String date) {
    final id = HabitLog.idFor(habitId, date);
    for (final log in _logs.items) {
      if (log.id == id) return !log.deleted && log.done;
    }
    return false;
  }

  int currentStreak(Habit habit) => streaks.currentStreak(
        cadence: habit.cadence,
        today: DateTime.now(),
        doneOn: (d) => doneOn(habit.id, d),
      );

  List<bool> thisWeekDots(Habit habit) =>
      streaks.currentWeekDots(today: DateTime.now(), doneOn: (d) => doneOn(habit.id, d));

  bool doneToday(String habitId) => doneOn(habitId, todayKey());

  // ---- mutations ----

  Future<Habit> addHabit({required String title, String cadence = 'daily'}) async {
    final trimmed = title.trim();
    final now = DateTime.now().toUtc();
    final habit = Habit(
      id: JsonDocStore.newId(),
      title: trimmed,
      cadence: cadence == 'weekly' ? 'weekly' : 'daily',
      createdAt: now,
      updatedAt: now,
    );
    await _habits.mutate((items) => items.add(habit));
    notifyListeners();
    return habit;
  }

  Future<void> updateHabit(String id, {String? title, String? cadence}) async {
    final now = DateTime.now().toUtc();
    await _habits.mutate((items) {
      final index = items.indexWhere((h) => h.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(
        title: title?.trim(),
        cadence: cadence,
        updatedAt: now,
      );
    });
    notifyListeners();
  }

  Future<void> deleteHabit(String id) async {
    final now = DateTime.now().toUtc();
    await _habits.mutate((items) {
      final index = items.indexWhere((h) => h.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(deletedAt: now, updatedAt: now);
    });
    notifyListeners();
  }

  /// Toggle "done" for a habit on the given local day (defaults to today).
  Future<void> toggleOn(String habitId, {DateTime? day}) async {
    final key = dateKey(day ?? DateTime.now());
    final id = HabitLog.idFor(habitId, key);
    final now = DateTime.now().toUtc();
    await _logs.mutate((items) {
      final index = items.indexWhere((l) => l.id == id);
      if (index < 0) {
        items.add(HabitLog(
          id: id,
          habitId: habitId,
          date: key,
          done: true,
          createdAt: now,
          updatedAt: now,
        ));
        return;
      }
      final current = items[index];
      final nowDone = current.deleted || !current.done;
      items[index] = HabitLog(
        id: current.id,
        habitId: current.habitId,
        date: current.date,
        done: nowDone,
        createdAt: current.createdAt,
        updatedAt: now,
        deletedAt: nowDone ? null : now,
      );
    });
    notifyListeners();
  }
}
