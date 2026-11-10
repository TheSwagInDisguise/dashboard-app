import 'dart:convert';

import '../models/task.dart';

/// Pure merge logic for the sync engine — last-write-wins per item with a
/// deterministic tiebreak, and every losing version collected so nothing is
/// silently discarded. No I/O in this file; fully unit-testable.

/// A version of an item that lost the LWW contest.
class MergeLoser {
  const MergeLoser({required this.item, required this.side});

  final Task item;

  /// Which side lost: 'local' or 'remote'.
  final String side;

  Map<String, dynamic> toJson() => {'side': side, 'item': item.toJson()};
}

class MergeOutcome {
  const MergeOutcome({required this.merged, required this.losers});

  /// The merged item set (union by id), sorted by id for canonical output.
  final List<Task> merged;

  /// Losing versions that differ semantically — park these in conflicts.json.
  final List<MergeLoser> losers;
}

/// Canonical, stable JSON for a list of items — used for change detection.
String canonicalItems(List<Task> items) {
  final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
  return jsonEncode(sorted.map((t) => t.toJson()).toList());
}

bool itemsEqual(List<Task> a, List<Task> b) => canonicalItems(a) == canonicalItems(b);

MergeOutcome mergeTasks(List<Task> local, List<Task> remote) {
  final byId = <String, Task>{for (final t in local) t.id: t};
  final losers = <MergeLoser>[];

  for (final remoteItem in remote) {
    final localItem = byId[remoteItem.id];
    if (localItem == null) {
      byId[remoteItem.id] = remoteItem;
      continue;
    }
    if (!_semanticallyDifferent(localItem, remoteItem)) {
      byId[remoteItem.id] = _newer(localItem, remoteItem);
      continue;
    }
    final winner = _newer(localItem, remoteItem);
    final localWon = identical(winner, localItem);
    losers.add(MergeLoser(item: localWon ? remoteItem : localItem, side: localWon ? 'remote' : 'local'));
    byId[remoteItem.id] = winner;
  }

  final merged = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  return MergeOutcome(merged: merged, losers: losers);
}

/// Winner: strictly by updatedAt; identical timestamps fall back to a stable
/// canonical comparison so both devices pick the same item.
Task _newer(Task a, Task b) {
  if (a.updatedAt.isAfter(b.updatedAt)) return a;
  if (b.updatedAt.isAfter(a.updatedAt)) return b;
  final cmp = jsonEncode(a.toJson()).compareTo(jsonEncode(b.toJson()));
  return cmp >= 0 ? a : b;
}

bool _semanticallyDifferent(Task a, Task b) =>
    a.title != b.title ||
    a.done != b.done ||
    a.priority != b.priority ||
    a.dueDate != b.dueDate ||
    a.deleted != b.deleted;
