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
      ),
      _straps = JsonDocStore<Strap>(
        mainKey: 'straps_json',
        backupKey: 'straps_json_backup',
        fromJson: Strap.fromJson,
        toJson: (x) => x.toJson(),
        idOf: (x) => x.id,
      ),
      _swaps = JsonDocStore<StrapSwap>(
        mainKey: 'strap_swaps_json',
        backupKey: 'strap_swaps_json_backup',
        fromJson: StrapSwap.fromJson,
        toJson: (x) => x.toJson(),
        idOf: (x) => x.id,
      ),
      _services = JsonDocStore<WatchService>(
        mainKey: 'watch_services_json',
        backupKey: 'watch_services_json_backup',
        fromJson: WatchService.fromJson,
        toJson: (x) => x.toJson(),
        idOf: (x) => x.id,
      );

  final JsonDocStore<Watch> _watches;
  final JsonDocStore<WearLog> _wears;
  final JsonDocStore<Strap> _straps;
  final JsonDocStore<StrapSwap> _swaps;
  final JsonDocStore<WatchService> _services;

  String? get recoveryNotice =>
      _watches.recoveryNotice ??
      _wears.recoveryNotice ??
      _straps.recoveryNotice ??
      _swaps.recoveryNotice ??
      _services.recoveryNotice;

  Future<void> load() async {
    await _watches.load();
    await _wears.load();
    await _straps.load();
    await _swaps.load();
    await _services.load();
  }

  // ---- sync engine views ----
  List<Watch> snapshotWatches() => _watches.snapshotItems();
  List<WearLog> snapshotWears() => _wears.snapshotItems();
  List<Strap> snapshotStraps() => _straps.snapshotItems();
  List<StrapSwap> snapshotStrapSwaps() => _swaps.snapshotItems();
  List<WatchService> snapshotServices() => _services.snapshotItems();

  Future<void> replaceAllWatches(List<Watch> items) async {
    await _watches.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllWears(List<WearLog> items) async {
    await _wears.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllStraps(List<Strap> items) async {
    await _straps.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllStrapSwaps(List<StrapSwap> items) async {
    await _swaps.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllServices(List<WatchService> items) async {
    await _services.replaceAll(items);
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

  List<Strap> get straps =>
      _straps.items.where((x) => !x.deleted).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  List<StrapSwap> get strapSwaps =>
      _swaps.items.where((x) => !x.deleted).toList()
        ..sort((a, b) => b.day.compareTo(a.day));
  List<WatchService> get services =>
      _services.items.where((x) => !x.deleted).toList()
        ..sort((a, b) => b.day.compareTo(a.day));
  List<WatchService> servicesFor(String watchId) =>
      services.where((x) => x.watchId == watchId).toList();
  List<StrapSwap> swapsFor(String strapId) =>
      strapSwaps.where((x) => x.strapId == strapId).toList();
  Strap? strapOnWatch(String watchId) {
    for (final strap in straps) {
      if (strap.watchId == watchId) return strap;
    }
    return null;
  }

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

  Watch? get nextSuggestion {
    final candidates = collection
        .where((w) => w.status != Watch.statusRepair)
        .toList();
    if (candidates.isEmpty) return null;
    var maxWears = 1;
    for (final watch in candidates) {
      final count = wearCount(watch.id);
      if (count > maxWears) maxWears = count;
    }
    candidates.sort(
      (a, b) =>
          _rotationScore(b, maxWears).compareTo(_rotationScore(a, maxWears)),
    );
    return candidates.first;
  }

  double _rotationScore(Watch watch, int maxWears) {
    final since = daysSinceWorn(watch.id) ?? 365;
    final underworn = (1 - wearCount(watch.id) / maxWears) * 10;
    return since.clamp(0, 365) + underworn + (since <= 1 ? -50 : 0);
  }

  String nextSuggestionReason(Watch watch) {
    final since = daysSinceWorn(watch.id);
    if (since == null) return 'never worn yet';
    if (since >= 30) return 'neglected for $since days';
    return 'last worn $since days ago · ${wearCount(watch.id)} wears total';
  }

  DateTime? nextServiceDue(Watch watch) {
    if (watch.serviceIntervalMonths <= 0) return null;
    final logs =
        servicesFor(watch.id).where((s) => s.kind == 'service').toList()
          ..sort((a, b) => b.day.compareTo(a.day));
    final last = logs.firstOrNull;
    if (last?.nextDueDay != null) return dateOfEpochDay(last!.nextDueDay!);
    final baseDay =
        last?.day ?? watch.purchaseDay ?? epochDayOf(watch.createdAt.toLocal());
    final base = dateOfEpochDay(baseDay);
    final month = base.month - 1 + watch.serviceIntervalMonths;
    final year = base.year + month ~/ 12;
    final m = month % 12 + 1;
    final day = base.day.clamp(1, DateTime(year, m + 1, 0).day);
    return DateTime(year, m, day);
  }

  bool serviceIsDue(Watch watch, {DateTime? date}) {
    final due = nextServiceDue(watch);
    final today = date ?? DateTime.now();
    return due != null &&
        !DateTime(
          due.year,
          due.month,
          due.day,
        ).isAfter(DateTime(today.year, today.month, today.day));
  }

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
    int serviceIntervalMonths = 0,
    int? purchaseDay,
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
      serviceIntervalMonths: serviceIntervalMonths,
      purchaseDay: purchaseDay,
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
  Future<WearLog> addWearRaw({
    required String watchId,
    required int day,
    String note = '',
  }) async {
    final now = DateTime.now().toUtc();
    final wear = WearLog(
      id: JsonDocStore.newId(),
      watchId: watchId,
      day: day,
      note: note.trim(),
      strapId: strapOnWatch(watchId)?.id,
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
    final existing = wearLogs
        .where((w) => w.watchId == watchId && w.day == today)
        .toList();
    if (existing.isNotEmpty) return existing.first;
    final now = DateTime.now().toUtc();
    final wear = WearLog(
      id: JsonDocStore.newId(),
      watchId: watchId,
      day: today,
      note: note.trim(),
      strapId: strapOnWatch(watchId)?.id,
      createdAt: now,
      updatedAt: now,
    );
    await _wears.mutate((items) => items.add(wear));
    notifyListeners();
    return wear;
  }

  Future<Strap> addStrap({
    required String name,
    String material = '',
    String color = '',
    int? widthMm,
    String notes = '',
  }) async {
    final now = DateTime.now().toUtc();
    final strap = Strap(
      id: JsonDocStore.newId(),
      name: name.trim(),
      material: material.trim(),
      color: color.trim(),
      widthMm: widthMm,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _straps.mutate((items) => items.add(strap));
    notifyListeners();
    return strap;
  }

  Future<bool> fitStrap(
    String strapId,
    String? watchId, {
    String note = '',
    DateTime? date,
  }) async {
    final strap = straps.where((s) => s.id == strapId).firstOrNull;
    if (strap == null || strap.watchId == watchId) return false;
    if (watchId != null && !collection.any((w) => w.id == watchId)) {
      return false;
    }
    final day = epochDayOf(date ?? DateTime.now());
    final now = DateTime.now().toUtc();
    if (watchId != null) {
      for (final current in straps.where(
        (s) => s.watchId == watchId && s.id != strapId,
      )) {
        await _straps.mutate((items) {
          final i = items.indexWhere((x) => x.id == current.id);
          if (i >= 0) {
            items[i] = current.copyWith(clearWatchId: true, updatedAt: now);
          }
        });
        await _swaps.mutate(
          (items) => items.add(
            StrapSwap(
              id: JsonDocStore.newId(),
              strapId: current.id,
              day: day,
              note: 'replaced by ${strap.name}',
              createdAt: now,
              updatedAt: now,
            ),
          ),
        );
      }
    }
    await _straps.mutate((items) {
      final i = items.indexWhere((x) => x.id == strapId);
      if (i >= 0) {
        items[i] = strap.copyWith(
          watchId: watchId,
          clearWatchId: watchId == null,
          updatedAt: now,
        );
      }
    });
    await _swaps.mutate(
      (items) => items.add(
        StrapSwap(
          id: JsonDocStore.newId(),
          strapId: strapId,
          watchId: watchId,
          day: day,
          note: note.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    if (watchId != null) {
      final existing = wearLogs
          .where((w) => w.watchId == watchId && w.day == day)
          .firstOrNull;
      if (existing != null) {
        await _wears.mutate((items) {
          final i = items.indexWhere((x) => x.id == existing.id);
          if (i >= 0) {
            items[i] = WearLog(
              id: existing.id,
              watchId: existing.watchId,
              day: existing.day,
              note: existing.note,
              strapId: strapId,
              createdAt: existing.createdAt,
              updatedAt: now,
            );
          }
        });
      }
    }
    notifyListeners();
    return true;
  }

  Future<WatchService> logService({
    required String watchId,
    required DateTime date,
    String kind = 'service',
    String description = '',
    double? cost,
    String currency = '',
    DateTime? nextDue,
  }) async {
    final now = DateTime.now().toUtc();
    final log = WatchService(
      id: JsonDocStore.newId(),
      watchId: watchId,
      day: epochDayOf(date),
      kind: kind,
      description: description.trim(),
      cost: cost,
      currency: currency,
      nextDueDay: nextDue == null ? null : epochDayOf(nextDue),
      createdAt: now,
      updatedAt: now,
    );
    await _services.mutate((items) => items.add(log));
    notifyListeners();
    return log;
  }

  Future<void> addStrapRaw({
    required String name,
    String material = '',
    String color = '',
    int? widthMm,
    String? watchId,
    String notes = '',
  }) async {
    final now = DateTime.now().toUtc();
    await _straps.mutate(
      (items) => items.add(
        Strap(
          id: JsonDocStore.newId(),
          name: name,
          material: material,
          color: color,
          widthMm: widthMm,
          watchId: watchId,
          notes: notes,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> addStrapSwapRaw({
    required String strapId,
    String? watchId,
    required int day,
    String note = '',
  }) async {
    final now = DateTime.now().toUtc();
    await _swaps.mutate(
      (items) => items.add(
        StrapSwap(
          id: JsonDocStore.newId(),
          strapId: strapId,
          watchId: watchId,
          day: day,
          note: note,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> addServiceRaw({
    required String watchId,
    required int day,
    String kind = 'service',
    String description = '',
    double? cost,
    String currency = '',
    int? nextDueDay,
  }) async {
    final now = DateTime.now().toUtc();
    await _services.mutate(
      (items) => items.add(
        WatchService(
          id: JsonDocStore.newId(),
          watchId: watchId,
          day: day,
          kind: kind,
          description: description,
          cost: cost,
          currency: currency,
          nextDueDay: nextDueDay,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    notifyListeners();
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
