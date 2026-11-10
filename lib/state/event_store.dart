import 'package:flutter/foundation.dart';

import '../models/event.dart';
import 'json_doc_store.dart';

/// Local calendar event store. Offline-first; the sync engine merges this
/// document with the private GitHub data repo like the tasks document.
class EventStore extends ChangeNotifier {
  EventStore()
      : _doc = JsonDocStore<Event>(
          mainKey: 'events_json',
          backupKey: 'events_json_backup',
          fromJson: Event.fromJson,
          toJson: (e) => e.toJson(),
          idOf: (e) => e.id,
        );

  final JsonDocStore<Event> _doc;

  String? get recoveryNotice => _doc.recoveryNotice;
  void clearRecoveryNotice() {
    _doc.clearRecoveryNotice();
    notifyListeners();
  }

  Future<void> load() => _doc.load();

  /// Read-only view of every item (including tombstones) for the sync engine.
  List<Event> snapshotItems() => _doc.snapshotItems();

  /// Replaces the whole document — used by the sync engine after a merge.
  Future<void> replaceAll(List<Event> items) async {
    await _doc.replaceAll(items);
    notifyListeners();
  }

  List<Event> get alive => _doc.items.where((e) => !e.deleted).toList();

  /// Events overlapping the given local day (all-day included), all-day first,
  /// then by start time. Done SHARED events are filtered out (auto-hide).
  List<Event> forDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final list = alive.where((e) {
      if (e.done && e.isShared) return false;
      final localStart = e.start.toLocal();
      final localEnd = e.end.toLocal();
      if (e.allDay) {
        final d = DateTime(localStart.year, localStart.month, localStart.day);
        return !d.isBefore(dayStart) && d.isBefore(dayEnd);
      }
      return localEnd.isAfter(dayStart) && localStart.isBefore(dayEnd);
    }).toList()
      ..sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.start.compareTo(b.start);
      });
    return list;
  }

  /// SHARED events not yet marked on-calendar — the checklist the evening
  /// reminder nags about.
  List<Event> sharedPending() {
    final list = alive.where((e) => e.isShared && !e.done).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  int get sharedPendingCount => sharedPending().length;

  Event? byId(String id) {
    for (final e in _doc.items) {
      if (e.id == id && !e.deleted) return e;
    }
    return null;
  }

  Future<Event> add({
    required String title,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String visibility = 'private',
    String? location,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    final event = Event(
      id: JsonDocStore.newId(),
      title: title.trim(),
      notes: _clean(notes),
      location: _clean(location),
      start: start.toUtc(),
      end: end.toUtc(),
      allDay: allDay,
      visibility: visibility == 'shared' ? 'shared' : 'private',
      createdAt: now,
      updatedAt: now,
    );
    await _doc.mutate((items) => items.add(event));
    notifyListeners();
    return event;
  }

  Future<void> updateEvent(
    String id, {
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? visibility,
    String? location,
    String? notes,
    bool clearLocation = false,
    bool clearNotes = false,
  }) async {
    final now = DateTime.now().toUtc();
    await _doc.mutate((items) {
      final index = items.indexWhere((e) => e.id == id);
      if (index < 0) return;
      final current = items[index];
      items[index] = current.copyWith(
        title: title?.trim(),
        start: start?.toUtc(),
        end: end?.toUtc(),
        allDay: allDay,
        visibility: visibility == null ? null : (visibility == 'shared' ? 'shared' : 'private'),
        location: location,
        notes: notes,
        clearLocation: clearLocation,
        clearNotes: clearNotes,
        updatedAt: now,
      );
    });
    notifyListeners();
  }

  /// Mark/unmark done — for SHARED events this hides them from Today.
  Future<void> toggleDone(String id) async {
    final now = DateTime.now().toUtc();
    await _doc.mutate((items) {
      final index = items.indexWhere((e) => e.id == id);
      if (index < 0) return;
      final current = items[index];
      items[index] = current.copyWith(done: !current.done, updatedAt: now);
    });
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    final now = DateTime.now().toUtc();
    await _doc.mutate((items) {
      final index = items.indexWhere((e) => e.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(deletedAt: now, updatedAt: now);
    });
    notifyListeners();
  }

  String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
