import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import '../utils/dates.dart';

/// Local, offline-first task store.
///
/// A single JSON document in shared_preferences (atomic), with the previous
/// good copy kept as an automatic backup. If the main document is missing or
/// corrupt, the backup is transparently restored and [recoveryNotice] is set
/// so the UI can tell the user what happened. Nothing is ever silently lost.
///
/// Persistence layer is deliberately thin — Phase 3 swaps the backing store
/// for the private GitHub data repo with last-write-wins merge.
class TasksStore extends ChangeNotifier {
  TasksStore();

  static const String _kMainKey = 'tasks_json';
  static const String _kBackupKey = 'tasks_json_backup';
  static const int _kSchemaVersion = 1;

  SharedPreferences? _prefs;
  final List<Task> _items = [];
  bool _loaded = false;

  /// Set when the main store was unreadable and the backup was used.
  String? recoveryNotice;

  bool get loaded => _loaded;

  // ---------------- load ----------------

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null; // no storage available — run in-memory, persist nothing
      _loaded = true;
      return;
    }

    final raw = _prefs!.getString(_kMainKey);
    var items = _tryParse(raw);

    if (items == null && raw != null && raw.isNotEmpty) {
      // Main document corrupt — fall back to the previous good copy.
      final backupRaw = _prefs!.getString(_kBackupKey);
      final backup = _tryParse(backupRaw);
      if (backup != null) {
        items = backup;
        recoveryNotice = 'tasks were restored from the on-device backup';
      }
    }

    _items
      ..clear()
      ..addAll(items ?? const <Task>[]);
    _loaded = true;
    notifyListeners();
  }

  List<Task>? _tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final List<dynamic>? list = decoded is Map<String, dynamic> && decoded['items'] is List
          ? decoded['items'] as List
          : (decoded is List ? decoded : null);
      if (list == null) return null;
      return list
          .whereType<Map>()
          .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  // ---------------- queries ----------------

  List<Task> get _alive => _items.where((t) => !t.deleted).toList();

  /// Open tasks, best-first: earlier due dates first, then priority (P1 > P2
  /// > P3), then most recently created.
  List<Task> get openTasks {
    final list = _alive.where((t) => !t.done).toList()..sort(_compareOpen);
    return list;
  }

  List<Task> get doneTasks {
    final list = _alive.where((t) => t.done).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  int get openCount => _alive.where((t) => !t.done).length;

  int get overdueCount {
    final today = todayKey();
    return _alive.where((t) => !t.done && t.dueDate != null && t.dueDate!.compareTo(today) < 0).length;
  }

  int get dueTodayCount {
    final today = todayKey();
    return _alive.where((t) => !t.done && t.dueDate == today).length;
  }

  static int _compareOpen(Task a, Task b) {
    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    if (ad != null && bd == null) return -1;
    if (ad == null && bd != null) return 1;
    final p = a.priority.compareTo(b.priority); // 'P1' < 'P2' < 'P3'
    if (p != 0) return p;
    return b.createdAt.compareTo(a.createdAt);
  }

  /// Read-only view of every item (including tombstones) for the sync engine.
  List<Task> snapshotItems() => List<Task>.unmodifiable(_items);

  /// Replaces the whole document — used by the sync engine after a merge.
  /// Persists with the same rotate-then-write atomicity and notifies listeners.
  Future<void> replaceAll(List<Task> items) async {
    _items
      ..clear()
      ..addAll(items);
    await _persist();
    notifyListeners();
  }

  Task? byId(String id) {
    for (final t in _items) {
      if (t.id == id && !t.deleted) return t;
    }
    return null;
  }

  void clearRecoveryNotice() {
    recoveryNotice = null;
    notifyListeners();
  }

  // ---------------- mutations ----------------

  Future<Task> add({required String title, String priority = 'P2', String? dueDate}) async {
    final trimmed = title.trim();
    final now = DateTime.now().toUtc();
    final task = Task(
      id: _newId(),
      title: trimmed,
      priority: _sanitisePriority(priority),
      dueDate: dueDate,
      createdAt: now,
      updatedAt: now,
    );
    _items.add(task);
    await _persist();
    notifyListeners();
    return task;
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? priority,
    String? dueDate,
    bool clearDueDate = false,
  }) async {
    final index = _items.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final current = _items[index];
    _items[index] = current.copyWith(
      title: title?.trim(),
      priority: priority == null ? null : _sanitisePriority(priority),
      dueDate: dueDate,
      clearDueDate: clearDueDate,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> toggleDone(String id) async {
    final index = _items.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final current = _items[index];
    _items[index] = current.copyWith(
      done: !current.done,
      updatedAt: DateTime.now().toUtc(),
    );
    await _persist();
    notifyListeners();
  }

  /// Soft delete (tombstone) — Phase 3 sync propagates deletions.
  Future<void> deleteTask(String id) async {
    final index = _items.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final now = DateTime.now().toUtc();
    _items[index] = _items[index].copyWith(deletedAt: now, updatedAt: now);
    await _persist();
    notifyListeners();
  }

  /// Tombstones every completed task. Returns how many were cleared.
  Future<int> clearCompleted() async {
    final now = DateTime.now().toUtc();
    var count = 0;
    for (var i = 0; i < _items.length; i++) {
      final t = _items[i];
      if (!t.deleted && t.done) {
        _items[i] = t.copyWith(deletedAt: now, updatedAt: now);
        count++;
      }
    }
    if (count > 0) {
      await _persist();
      notifyListeners();
    }
    return count;
  }

  // ---------------- persistence ----------------

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      // Rotate main -> backup first, then write the new main document.
      final previous = prefs.getString(_kMainKey);
      if (previous != null && previous.isNotEmpty) {
        await prefs.setString(_kBackupKey, previous);
      }
      final payload = jsonEncode(<String, dynamic>{
        'schemaVersion': _kSchemaVersion,
        'items': _items.map((t) => t.toJson()).toList(),
      });
      await prefs.setString(_kMainKey, payload);
      recoveryNotice = null;
    } catch (_) {
      // Nothing to do — data stays in memory; user keeps using the app.
    }
  }

  String _newId() {
    final random = Random();
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = random.nextInt(1 << 32).toRadixString(36);
    return '$stamp-$salt';
  }

  String _sanitisePriority(String value) {
    final v = value.trim().toUpperCase();
    return (v == 'P1' || v == 'P2' || v == 'P3') ? v : 'P2';
  }
}
