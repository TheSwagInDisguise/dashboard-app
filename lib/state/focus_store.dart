// Focus-session store — pomodoro / stopwatch history. Synced like every
// other document; minutes feed the session heatmap and per-habit history.

import 'package:flutter/foundation.dart';

import '../models/focus_session.dart';
import '../models/habit.dart' show epochDayOf;
import 'json_doc_store.dart';

class FocusStore extends ChangeNotifier {
  FocusStore()
      : _sessions = JsonDocStore<FocusSession>(
          mainKey: 'focus_sessions_json',
          backupKey: 'focus_sessions_json_backup',
          fromJson: FocusSession.fromJson,
          toJson: (s) => s.toJson(),
          idOf: (s) => s.id,
        );

  final JsonDocStore<FocusSession> _sessions;

  String? get recoveryNotice => _sessions.recoveryNotice;

  Future<void> load() => _sessions.load();

  List<FocusSession> snapshotSessions() => _sessions.snapshotItems();

  Future<void> replaceAllSessions(List<FocusSession> items) async {
    await _sessions.replaceAll(items);
    notifyListeners();
  }

  List<FocusSession> get sessions {
    final list = _sessions.items.where((s) => !s.deleted).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  List<FocusSession> sessionsOnDay(int epochDay) =>
      sessions.where((s) => s.day == epochDay).toList();

  int sessionsOnDate(DateTime date) => sessionsOnDay(epochDayOf(date)).length;

  int get todaySessions => sessionsOnDate(DateTime.now());

  int get todayMinutes {
    final today = epochDayOf(DateTime.now());
    return sessionsOnDay(today).fold(0, (sum, s) => sum + s.minutes);
  }

  int totalMinutesSince(DateTime from) {
    final floor = epochDayOf(from);
    return sessions.where((s) => s.day >= floor).fold(0, (sum, s) => sum + s.minutes);
  }

  int get totalFocusMinutes => sessions.fold(0, (sum, s) => sum + s.minutes);

  int get totalSessions => sessions.length;

  /// epoch day → minutes, for the heatmap (last [days] days).
  Map<int, int> minutesByDay({int days = 365}) {
    final cutoff = epochDayOf(DateTime.now().subtract(Duration(days: days - 1)));
    final map = <int, int>{};
    for (final s in sessions) {
      if (s.day >= cutoff) {
        map[s.day] = (map[s.day] ?? 0) + s.minutes;
      }
    }
    return map;
  }

  /// epoch day → session count, for the heatmap count view.
  Map<int, int> sessionsByDay({int days = 365}) {
    final cutoff = epochDayOf(DateTime.now().subtract(Duration(days: days - 1)));
    final map = <int, int>{};
    for (final s in sessions) {
      if (s.day >= cutoff) {
        map[s.day] = (map[s.day] ?? 0) + 1;
      }
    }
    return map;
  }

  List<FocusSession> sessionsForHabit(String habitId, {int limit = 50}) =>
      sessions.where((s) => s.habitId == habitId).take(limit).toList();

  int minutesForHabit(String habitId) =>
      sessions.where((s) => s.habitId == habitId).fold(0, (sum, s) => sum + s.minutes);

  Future<FocusSession?> recordSession({
    required String habitId,
    required DateTime startedAt,
    required DateTime endedAt,
    required int minutes,
    required String kind,
    bool completed = true,
  }) async {
    if (minutes <= 0) return null;
    final now = DateTime.now().toUtc();
    final day = epochDayOf(startedAt);
    final session = FocusSession(
      id: JsonDocStore.newId(),
      habitId: habitId,
      day: day,
      startedAt: startedAt.toUtc().millisecondsSinceEpoch,
      endedAt: endedAt.toUtc().millisecondsSinceEpoch,
      minutes: minutes,
      kind: kind,
      completed: completed,
      createdAt: now,
      updatedAt: now,
    );
    await _sessions.mutate((items) => items.add(session));
    notifyListeners();
    return session;
  }

  Future<void> deleteSession(String id) async {
    final now = DateTime.now().toUtc();
    await _sessions.mutate((items) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].id == id && !items[i].deleted) {
          final s = items[i];
          items[i] = FocusSession(
            id: s.id,
            habitId: s.habitId,
            day: s.day,
            startedAt: s.startedAt,
            endedAt: s.endedAt,
            minutes: s.minutes,
            kind: s.kind,
            completed: s.completed,
            createdAt: s.createdAt,
            updatedAt: now,
            deletedAt: now,
          );
        }
      }
    });
    notifyListeners();
  }
}
