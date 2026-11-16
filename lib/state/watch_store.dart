// Watch-wear tracker store — the collection, wear logs and the
// days-since-worn vault. Synced like everything else EXCEPT photos, which
// live device-local (see watch_photo_store.dart).

import 'package:flutter/foundation.dart';

import '../models/habit.dart' show epochDayOf, dateOfEpochDay;
import '../models/watch.dart';
import 'json_doc_store.dart';

class WatchStore extends ChangeNotifier {
  WatchStore()
      : _watches = JsonDocStore<Watch>(
          mainKey: 'watches_json',
          backupKey: 'watches_json_backup',
          fromJson: Watch.fromJson,
          toJson: (w) => w.toJson(),
          idOf: (w) => w.id,
        ),
        _wears = JsonDocStore<WearLog>(
          mainKey: 'wear_logs_json',
          backupKey: 'wear_logs_json_backup',
          fromJson: WearLog.fromJson,
          toJson: (w) => w.toJson(),
          idOf: (w) => w.id,
        );

  final JsonDocStore<Watch> _watches;
  final JsonDocStore<WearLog> _wears;

  String? get recoveryNotice => _watches.recoveryNotice ?? _wears.recoveryNotice;

  Future<void> load() async {
    await _watches.load();
    await _wears.load();
  }

  // ---- sync engine views ----
  List<Watch> snapshotWatches() => _watches.snapshotItems();
  List<WearLog> snapshotWears() => _wears.snapshotItems();

  Future<void> replaceAllWatches(List<Watch> items) async {
    await _watches.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllWears(List<WearLog> items) async {
    await _wears.replaceAll(items);
    notifyListeners();
  }

  // ---- queries -----------------------------------------------------------

  List<Watch> get watches {
    final list = _watches.items.where((w) => !w.deleted).toList()
      ..sort((a, b) {
        final byCreated = a.createdAt.compareTo(b.createdAt);
        return byCreated;
      });
    return list;
  }

  List<Watch> get collection => watches.where((w) => w.owned).toList();

  List<WearLog> get wearLogs {
    final list = _wears.items.where((w) => !w.deleted).toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return list;
  }

  WearLog? wearLogFor(String id) {
    for (final w in _wears.items) {
      if (w.id == id) return w.deleted ? null : w;
    }
    return null;
  }

  List<WearLog> wearsOf(String watchId) =>
      wearLogs.where((w) => w.watchId == watchId).toList();

  int wearCount(String watchId) => wearsOf(watchId).length;

  int? daysSinceWorn(String watchId, {DateTime? now}) {
    final wears = wearsOf(watchId);
    if (wears.isEmpty) return null;
    final last = wears.first.day; // wearLogs sorted newest first
    return epochDayOf(now ?? DateTime.now()) - last;
  }

  /// The vault: collection watches sorted by longest time since worn
  /// (unworn ones first — they need the wrist most).
  List<Watch> get vault {
    final list = List<Watch>.of(collection);
    final epoch = epochDayOf(DateTime.now());
    int rank(Watch w) {
      final wears = wearsOf(w.id);
      if (wears.isEmpty) return 1 << 30;
      return epoch - wears.first.day;
    }

    list.sort((a, b) => rank(b).compareTo(rank(a)));
    return list;
  }

  /// Most-worn / least-worn within the collection (by wear count).
  Watch? get mostWorn {
    Watch? best;
    var bestCount = -1;
    for (final w in collection) {
      final c = wearCount(w.id);
      if (c > bestCount) {
        bestCount = c;
        best = w;
      }
    }
    return bestCount > 0 ? best : null;
  }

  Watch? get leastWorn {
    Watch? worst;
    var worstCount = 1 << 30;
    for (final w in collection) {
      final c = wearCount(w.id);
      if (c < worstCount) {
        worstCount = c;
        worst = w;
      }
    }
    return worst;
  }

  int get totalWears => wearLogs.length;

  /// Wear for today, if any.
  WearLog? get todayWear {
    final today = epochDayOf(DateTime.now());
    for (final w in wearLogs) {
      if (w.day == today) return w;
    }
    return null;
  }

  int get todayWearCount =>
      wearLogs.where((w) => w.day == epochDayOf(DateTime.now())).length;

  // ---- mutations ---------------------------------------------------------

  Future<Watch> addWatch({
    required String brand,
    required String model,
    String nickname = '',
    String reference = '',
    String movement = '',
    double? caseSizeMm,
    String color = 'cyan',
    String status = Watch.statusOwned,
    String notes = '',
  }) async {
    final now = DateTime.now().toUtc();
    final watch = Watch(
      id: JsonDocStore.newId(),
      brand: brand.trim(),
      model: model.trim(),
      nickname: nickname.trim(),
      reference: reference.trim(),
      movement: movement.trim(),
      caseSizeMm: caseSizeMm,
      color: color,
      status: status,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _watches.mutate((items) => items.add(watch));
    notifyListeners();
    return watch;
  }

  Future<void> updateWatch(Watch updated) async {
    final now = DateTime.now().toUtc();
    await _watches.mutate((items) {
      final index = items.indexWhere((w) => w.id == updated.id);
      if (index < 0) return;
      items[index] = updated.copyWith(updatedAt: now);
    });
    notifyListeners();
  }

  Future<void> archiveWatch(String id, bool archived) async {
    final now = DateTime.now().toUtc();
    await _watches.mutate((items) {
      final index = items.indexWhere((w) => w.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(archived: archived, updatedAt: now);
    });
    notifyListeners();
  }

  Future<void> deleteWatch(String id) async {
    final now = DateTime.now().toUtc();
    await _watches.mutate((items) {
      final index = items.indexWhere((w) => w.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(deletedAt: now, updatedAt: now);
    });
    // Wear logs go with it.
    await _wears.mutate((items) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].watchId == id && !items[i].deleted) {
          items[i] = WearLog(
            id: items[i].id,
            watchId: items[i].watchId,
            day: items[i].day,
            note: items[i].note,
            createdAt: items[i].createdAt,
            updatedAt: now,
            deletedAt: now,
          );
        }
      }
    });
    notifyListeners();
  }

  /// Re-create a parked conflict's wear log as a brand-new entry (any day).
  Future<WearLog> addWearRaw({required String watchId, required int day, String note = ''}) async {
    final now = DateTime.now().toUtc();
    final wear = WearLog(
      id: JsonDocStore.newId(),
      watchId: watchId,
      day: day,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _wears.mutate((items) => items.add(wear));
    notifyListeners();
    return wear;
  }

  /// One-tap "log today's wear". Returns the wear log id (existing one for
  /// today when already logged, new otherwise).
  Future<WearLog> logTodaysWear(String watchId, {String note = ''}) async {
    final today = epochDayOf(DateTime.now());
    final existing = wearLogs.where((w) => w.watchId == watchId && w.day == today).toList();
    if (existing.isNotEmpty) return existing.first;
    final now = DateTime.now().toUtc();
    final wear = WearLog(
      id: JsonDocStore.newId(),
      watchId: watchId,
      day: today,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _wears.mutate((items) => items.add(wear));
    notifyListeners();
    return wear;
  }

  Future<void> removeWear(String wearLogId) async {
    final now = DateTime.now().toUtc();
    await _wears.mutate((items) {
      for (var i = 0; i < items.length; i++) {
        final w = items[i];
        if (w.id == wearLogId && !w.deleted) {
          items[i] = WearLog(
            id: w.id,
            watchId: w.watchId,
            day: w.day,
            note: w.note,
            createdAt: w.createdAt,
            updatedAt: now,
            deletedAt: now,
          );
        }
      }
    });
    notifyListeners();
  }
}

/// Absolute date of a wear log day, for display.
DateTime wearDay(WearLog log) => dateOfEpochDay(log.day);
