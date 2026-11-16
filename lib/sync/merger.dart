import 'dart:convert';

import '../models/event.dart';
import '../models/focus_session.dart';
import '../models/habit.dart';
import '../models/task.dart';
import '../models/watch.dart';

/// Pure merge logic for the sync engine — last-write-wins per item with a
/// deterministic tiebreak, and every losing version collected so nothing is
/// silently discarded. No I/O in this file; fully unit-testable.
///
/// Generic over the item type; Task-specific wrappers are at the bottom and
/// keep the Phase 3 API (mergeTasks/itemsEqual/canonicalItems) intact.

/// A version of an item that lost the LWW contest.
class MergeLoser<T> {
  const MergeLoser({required this.item, required this.side});

  final T item;

  /// Which side lost: 'local' or 'remote'.
  final String side;
}

class MergeOutcome<T> {
  const MergeOutcome({required this.merged, required this.losers});

  /// The merged item set (union by id), sorted by id for canonical output.
  final List<T> merged;

  /// Losing versions that differ semantically — park these in conflicts.json.
  final List<MergeLoser<T>> losers;
}

/// Stable, canonical JSON for a list — used for change detection.
String canonicalItemsOf<T>(List<T> items, Map<String, dynamic> Function(T) toJson, String Function(T) idOf) {
  final sorted = [...items]..sort((a, b) => idOf(a).compareTo(idOf(b)));
  return jsonEncode(sorted.map(toJson).toList());
}

bool itemsEqualOf<T>(List<T> a, List<T> b, Map<String, dynamic> Function(T) toJson, String Function(T) idOf) =>
    canonicalItemsOf(a, toJson, idOf) == canonicalItemsOf(b, toJson, idOf);

MergeOutcome<T> mergeLww<T>(
  List<T> local,
  List<T> remote, {
  required String Function(T) idOf,
  required DateTime Function(T) updatedAtOf,
  required bool Function(T a, T b) semanticallyDifferent,
  required String Function(T) canonicalOf,
}) {
  final byId = <String, T>{for (final t in local) idOf(t): t};
  final losers = <MergeLoser<T>>[];

  for (final remoteItem in remote) {
    final id = idOf(remoteItem);
    final localItem = byId[id];
    if (localItem == null) {
      byId[id] = remoteItem;
      continue;
    }
    if (!semanticallyDifferent(localItem, remoteItem)) {
      byId[id] = _newerOf(localItem, remoteItem, updatedAtOf, canonicalOf);
      continue;
    }
    final winner = _newerOf(localItem, remoteItem, updatedAtOf, canonicalOf);
    final localWon = identical(winner, localItem);
    losers.add(MergeLoser<T>(item: localWon ? remoteItem : localItem, side: localWon ? 'remote' : 'local'));
    byId[id] = winner;
  }

  final merged = byId.values.toList()..sort((a, b) => idOf(a).compareTo(idOf(b)));
  return MergeOutcome<T>(merged: merged, losers: losers);
}

/// Winner: strictly by updatedAt; identical timestamps fall back to a stable
/// canonical comparison so both devices pick the same item.
T _newerOf<T>(
  T a,
  T b,
  DateTime Function(T) updatedAtOf,
  String Function(T) canonicalOf,
) {
  final aTime = updatedAtOf(a);
  final bTime = updatedAtOf(b);
  if (aTime.isAfter(bTime)) return a;
  if (bTime.isAfter(aTime)) return b;
  return canonicalOf(a).compareTo(canonicalOf(b)) >= 0 ? a : b;
}

// ---------------- Task wrappers (Phase 3 API kept intact) ----------------

MergeOutcome<Task> mergeTasks(List<Task> local, List<Task> remote) => mergeLww<Task>(
      local,
      remote,
      idOf: (t) => t.id,
      updatedAtOf: (t) => t.updatedAt,
      semanticallyDifferent: _semanticallyDifferent,
      canonicalOf: (t) => jsonEncode(t.toJson()),
    );

String canonicalItems(List<Task> items) =>
    canonicalItemsOf(items, (t) => t.toJson(), (t) => t.id);

bool itemsEqual(List<Task> a, List<Task> b) => itemsEqualOf(a, b, (t) => t.toJson(), (t) => t.id);

bool _semanticallyDifferent(Task a, Task b) =>
    a.title != b.title ||
    a.done != b.done ||
    a.priority != b.priority ||
    a.dueDate != b.dueDate ||
    a.deleted != b.deleted;

// ---------------- Event / Habit / HabitLog diff rules ----------------

bool eventSemanticallyDifferent(Event a, Event b) {
  return a.title != b.title ||
      a.notes != b.notes ||
      a.location != b.location ||
      a.start != b.start ||
      a.end != b.end ||
      a.allDay != b.allDay ||
      a.visibility != b.visibility ||
      a.done != b.done ||
      a.deleted != b.deleted;
}

bool habitSemanticallyDifferent(Habit a, Habit b) {
  // Compare the canonical sync payload (photo-free by construction).
  Map<String, dynamic> flat(Habit h) {
    final m = Map<String, dynamic>.from(h.toJson())..remove('createdAt')..remove('updatedAt');
    return m;
  }

  return jsonEncode(flat(a)) != jsonEncode(flat(b));
}

bool habitLogSemanticallyDifferent(HabitLog a, HabitLog b) {
  final ja = a.toJson()..remove('createdAt')..remove('updatedAt')..remove('date');
  final jb = b.toJson()..remove('createdAt')..remove('updatedAt')..remove('date');
  return jsonEncode(ja) != jsonEncode(jb);
}

bool routineSemanticallyDifferent(Routine a, Routine b) =>
    a.name != b.name || a.icon != b.icon || a.position != b.position || a.deleted != b.deleted;

bool skipRuleSemanticallyDifferent(SkipRule a, SkipRule b) =>
    a.name != b.name ||
    a.kind != b.kind ||
    a.fromDay != b.fromDay ||
    a.toDay != b.toDay ||
    a.weekdayMask != b.weekdayMask ||
    a.habitIds != b.habitIds ||
    a.enabled != b.enabled ||
    a.deleted != b.deleted;

bool shieldUseSemanticallyDifferent(ShieldUse a, ShieldUse b) =>
    a.habitId != b.habitId || a.day != b.day || a.deleted != b.deleted;

bool xpEventSemanticallyDifferent(XpEvent a, XpEvent b) =>
    a.day != b.day || a.amount != b.amount || a.reason != b.reason || a.habitId != b.habitId || a.deleted != b.deleted;

bool focusSessionSemanticallyDifferent(FocusSession a, FocusSession b) =>
    a.habitId != b.habitId ||
    a.day != b.day ||
    a.startedAt != b.startedAt ||
    a.endedAt != b.endedAt ||
    a.minutes != b.minutes ||
    a.kind != b.kind ||
    a.completed != b.completed ||
    a.deleted != b.deleted;

bool watchSemanticallyDifferent(Watch a, Watch b) =>
    a.brand != b.brand ||
    a.model != b.model ||
    a.nickname != b.nickname ||
    a.reference != b.reference ||
    a.movement != b.movement ||
    a.caseSizeMm != b.caseSizeMm ||
    a.color != b.color ||
    a.notes != b.notes ||
    a.status != b.status ||
    a.archived != b.archived ||
    a.deleted != b.deleted;

bool wearLogSemanticallyDifferent(WearLog a, WearLog b) =>
    a.watchId != b.watchId || a.day != b.day || a.note != b.note || a.deleted != b.deleted;
