import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../models/focus_session.dart';
import '../models/habit.dart';
import '../models/task.dart';
import '../models/watch.dart';
import '../state/app_state.dart';
import '../state/event_store.dart';
import '../state/focus_store.dart';
import '../state/habit_store.dart';
import '../state/tasks_store.dart';
import '../state/watch_store.dart';
import 'github_client.dart';
import 'merger.dart';

enum SyncStatus {
  /// No token configured — everything stays local.
  disabled,

  /// Token present, nothing synced yet (first run pending).
  idle,

  /// A sync pass is running.
  syncing,

  /// Last sync pass succeeded.
  ok,

  /// GitHub rejected the token (expired / revoked / wrong scope). Fixable by
  /// pasting a fresh token in Settings — the app keeps working locally.
  tokenInvalid,

  /// Network or server-side failure. Transient; data is safe locally.
  error,
}

/// One synced JSON document in the private dashboard-data repo.
/// Everything the engine needs, parameterised — so tasks, events, habits and
/// habit logs all flow through the *same* merge logic.
class _Doc<T> {
  _Doc({
    required this.path,
    required this.displayName,
    required this.snapshot,
    required this.apply,
    required this.fromJson,
    required this.toJson,
    required this.semanticallyDifferent,
    required this.updatedAtOf,
    required this.createdAtOf,
    required this.idOf,
    required this.titleOf,
  });

  final String path;
  final String displayName;
  final List<T> Function() snapshot;
  final Future<void> Function(List<T>) apply;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;
  final bool Function(T a, T b) semanticallyDifferent;
  final DateTime Function(T) updatedAtOf;
  final DateTime Function(T) createdAtOf;
  final String Function(T) idOf;
  final String Function(T) titleOf;
}

/// Keeps on-device documents in sync with the user's PRIVATE GitHub data
/// repo as JSON files, using last-write-wins per item with a full audit
/// trail of losing versions in conflicts.json (plus an on-device pending
/// queue so a conflict is NEVER lost, even if the repo write fails).
///
/// Sync happens on app open, on resume (via the UI), and debounced after
/// local mutations. No background service; nothing runs when the app isn't
/// in the foreground.
class SyncService extends ChangeNotifier {
  SyncService({
    required TasksStore tasksStore,
    required EventStore eventStore,
    required HabitStore habitStore,
    required WatchStore watchStore,
    required FocusStore focusStore,
    required AppState appState,
  })  : _tasks = tasksStore,
        _events = eventStore,
        _habits = habitStore,
        _watches = watchStore,
        _focus = focusStore,
        _appState = appState {
    _docs = <_Doc<dynamic>>[
      _Doc<Task>(
        path: 'tasks.json',
        displayName: 'tasks',
        snapshot: tasksStore.snapshotItems,
        apply: tasksStore.replaceAll,
        fromJson: Task.fromJson,
        toJson: (t) => t.toJson(),
        semanticallyDifferent: _taskDiff,
        updatedAtOf: (t) => t.updatedAt,
        createdAtOf: (t) => t.createdAt,
        idOf: (t) => t.id,
        titleOf: (t) => t.title,
      ),
      _Doc<Event>(
        path: 'events.json',
        displayName: 'events',
        snapshot: eventStore.snapshotItems,
        apply: eventStore.replaceAll,
        fromJson: Event.fromJson,
        toJson: (e) => e.toJson(),
        semanticallyDifferent: eventSemanticallyDifferent,
        updatedAtOf: (e) => e.updatedAt,
        createdAtOf: (e) => e.createdAt,
        idOf: (e) => e.id,
        titleOf: (e) => e.title,
      ),
      _Doc<Habit>(
        path: 'habits.json',
        displayName: 'habits',
        snapshot: habitStore.snapshotHabits,
        apply: habitStore.replaceAllHabits,
        fromJson: Habit.fromJson,
        toJson: (h) => h.toJson(),
        semanticallyDifferent: habitSemanticallyDifferent,
        updatedAtOf: (h) => h.updatedAt,
        createdAtOf: (h) => h.createdAt,
        idOf: (h) => h.id,
        titleOf: (h) => h.title,
      ),
      _Doc<HabitLog>(
        path: 'habit_logs.json',
        displayName: 'habit check-ins',
        snapshot: habitStore.snapshotLogs,
        apply: habitStore.replaceAllLogs,
        fromJson: HabitLog.fromJson,
        toJson: (l) => l.toJson(),
        semanticallyDifferent: habitLogSemanticallyDifferent,
        updatedAtOf: (l) => l.updatedAt,
        createdAtOf: (l) => l.createdAt,
        idOf: (l) => l.id,
        titleOf: (l) => 'check-in on ${l.date}',
      ),
      _Doc<Routine>(
        path: 'routines.json',
        displayName: 'routines',
        snapshot: habitStore.snapshotRoutines,
        apply: habitStore.replaceAllRoutines,
        fromJson: Routine.fromJson,
        toJson: (r) => r.toJson(),
        semanticallyDifferent: routineSemanticallyDifferent,
        updatedAtOf: (r) => r.updatedAt,
        createdAtOf: (r) => r.createdAt,
        idOf: (r) => r.id,
        titleOf: (r) => r.name,
      ),
      _Doc<SkipRule>(
        path: 'skip_rules.json',
        displayName: 'skip rules',
        snapshot: habitStore.snapshotSkipRules,
        apply: habitStore.replaceAllSkipRules,
        fromJson: SkipRule.fromJson,
        toJson: (r) => r.toJson(),
        semanticallyDifferent: skipRuleSemanticallyDifferent,
        updatedAtOf: (r) => r.updatedAt,
        createdAtOf: (r) => r.createdAt,
        idOf: (r) => r.id,
        titleOf: (r) => r.name,
      ),
      _Doc<ShieldUse>(
        path: 'shield_uses.json',
        displayName: 'streak shields',
        snapshot: habitStore.snapshotShields,
        apply: habitStore.replaceAllShields,
        fromJson: ShieldUse.fromJson,
        toJson: (x) => x.toJson(),
        semanticallyDifferent: shieldUseSemanticallyDifferent,
        updatedAtOf: (x) => x.updatedAt,
        createdAtOf: (x) => x.createdAt,
        idOf: (x) => x.id,
        titleOf: (x) => 'shield on ${x.day}',
      ),
      _Doc<XpEvent>(
        path: 'xp_events.json',
        displayName: 'xp ledger',
        snapshot: habitStore.snapshotXp,
        apply: habitStore.replaceAllXp,
        fromJson: XpEvent.fromJson,
        toJson: (x) => x.toJson(),
        semanticallyDifferent: xpEventSemanticallyDifferent,
        updatedAtOf: (x) => x.updatedAt,
        createdAtOf: (x) => x.createdAt,
        idOf: (x) => x.id,
        titleOf: (x) => '${x.amount} xp · ${x.reason}',
      ),
      _Doc<Watch>(
        path: 'watches.json',
        displayName: 'watches',
        snapshot: watchStore.snapshotWatches,
        apply: watchStore.replaceAllWatches,
        fromJson: Watch.fromJson,
        toJson: (w) => w.toJson(),
        semanticallyDifferent: watchSemanticallyDifferent,
        updatedAtOf: (w) => w.updatedAt,
        createdAtOf: (w) => w.createdAt,
        idOf: (w) => w.id,
        titleOf: (w) => w.displayName,
      ),
      _Doc<WearLog>(
        path: 'wear_logs.json',
        displayName: 'watch wears',
        snapshot: watchStore.snapshotWears,
        apply: watchStore.replaceAllWears,
        fromJson: WearLog.fromJson,
        toJson: (w) => w.toJson(),
        semanticallyDifferent: wearLogSemanticallyDifferent,
        updatedAtOf: (w) => w.updatedAt,
        createdAtOf: (w) => w.createdAt,
        idOf: (w) => w.id,
        titleOf: (w) => 'wear on ${w.toJson()['date']}',
      ),
      _Doc<FocusSession>(
        path: 'focus_sessions.json',
        displayName: 'focus sessions',
        snapshot: focusStore.snapshotSessions,
        apply: focusStore.replaceAllSessions,
        fromJson: FocusSession.fromJson,
        toJson: (s) => s.toJson(),
        semanticallyDifferent: focusSessionSemanticallyDifferent,
        updatedAtOf: (s) => s.updatedAt,
        createdAtOf: (s) => s.createdAt,
        idOf: (s) => s.id,
        titleOf: (s) => '${s.minutes} min ${s.kind}',
      ),
    ];

    _tasks.addListener(_handleLocalMutation);
    _events.addListener(_handleLocalMutation);
    _habits.addListener(_handleLocalMutation);
    _watches.addListener(_handleLocalMutation);
    _focus.addListener(_handleLocalMutation);
    _appState.addListener(_handleStateMutation);
    _lastSeenToken = appState.syncToken;
    if (_lastSeenToken == null) _status = SyncStatus.disabled;
  }

  static const String _repo = 'TheSwagInDisguise/dashboard-data';
  static const String _conflictsPath = 'conflicts.json';
  static const String _manifestPath = 'manifest.json';
  static const String _pendingKey = 'sync_conflicts_pending';

  final TasksStore _tasks;
  final EventStore _events;
  final HabitStore _habits;
  final WatchStore _watches;
  final FocusStore _focus;
  final AppState _appState;

  late final List<_Doc<dynamic>> _docs;

  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncedAt;
  String? _lastError;
  bool _running = false;
  bool _pendingRun = false;
  bool _applyingRemote = false;
  int _debounceTag = 0;
  String? _lastSeenToken;

  SyncStatus get status => _status;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get lastError => _lastError;
  bool get isEnabled => _appState.syncToken?.isNotEmpty ?? false;

  // ================= triggers =================

  void _handleLocalMutation() {
    if (_running || _applyingRemote) return;
    _schedule(const Duration(seconds: 4));
  }

  void _handleStateMutation() {
    final token = _appState.syncToken;
    if (token != _lastSeenToken) {
      _lastSeenToken = token;
      if (token == null || token.isEmpty) {
        _status = SyncStatus.disabled;
        notifyListeners();
      } else {
        _schedule(const Duration(milliseconds: 600));
      }
    }
  }

  void _schedule(Duration delay) {
    final tag = ++_debounceTag;
    Future.delayed(delay, () {
      if (tag == _debounceTag) unawaited(syncNow());
    });
  }

  // ================= sync engine =================

  /// One full sync pass over every document. Concurrent calls coalesce into
  /// at most one extra run.
  Future<void> syncNow() async {
    if (_running) {
      _pendingRun = true;
      return;
    }
    final token = _appState.syncToken;
    if (token == null || token.isEmpty) {
      if (_status != SyncStatus.disabled) {
        _status = SyncStatus.disabled;
        notifyListeners();
      }
      return;
    }

    _running = true;
    _status = SyncStatus.syncing;
    notifyListeners();

    final passStart = DateTime.now().toUtc();
    final client = GitHubClient(token: token, repo: _repo);
    var tokenRejected = false;
    var anyError = false;

    try {
      for (final doc in _docs) {
        final result = await _syncDocument<dynamic>(client, doc, passStart);
        switch (result) {
          case SyncStatus.tokenInvalid:
            tokenRejected = true;
          case SyncStatus.error:
            anyError = true;
          case _:
            break;
        }
        if (tokenRejected) break; // no point asking GitHub anything else
      }

      if (tokenRejected) {
        _status = SyncStatus.tokenInvalid;
      } else {
        await _flushPendingConflicts(client);
        await _ensureManifest(client);
        if (anyError) {
          _status = SyncStatus.error;
        } else {
          _status = SyncStatus.ok;
          _lastSyncedAt = DateTime.now();
          _lastError = null;
        }
      }
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = 'unexpected: $e';
    } finally {
      client.close();
      _running = false;
      notifyListeners();
      if (_pendingRun) {
        _pendingRun = false;
        unawaited(syncNow());
      }
    }
  }

  Future<SyncStatus> _syncDocument<T>(GitHubClient client, _Doc<T> doc, DateTime passStart) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final remote = await client.getFile(doc.path);
      if (remote.status == SyncFileStatus.tokenInvalid) return SyncStatus.tokenInvalid;
      if (remote.status == SyncFileStatus.error) {
        _lastError = '${doc.displayName}: ${remote.error}';
        return SyncStatus.error;
      }

      final List<T> remoteItems = remote.exists ? _decodeItems(remote.content!, doc) : <T>[];
      final List<T> localItems = doc.snapshot();
      final outcome = mergeLww<T>(
        localItems,
        remoteItems,
        idOf: doc.idOf,
        updatedAtOf: doc.updatedAtOf,
        semanticallyDifferent: doc.semanticallyDifferent,
        canonicalOf: (t) => jsonEncode(doc.toJson(t)),
      );

      // Overlay anything that changed locally while this pass was running —
      // it wins outright so we never clobber a fresh edit.
      final mergedById = <String, T>{for (final item in outcome.merged) doc.idOf(item): item};
      for (final localItem in doc.snapshot()) {
        if (doc.updatedAtOf(localItem).isAfter(passStart)) {
          mergedById[doc.idOf(localItem)] = localItem;
        }
      }
      final mergedNow = mergedById.values.toList()..sort((a, b) => doc.idOf(a).compareTo(doc.idOf(b)));

      // Apply locally only if it actually differs (skip notify storms).
      if (!itemsEqualOf(mergedNow, localItems, doc.toJson, doc.idOf)) {
        _applyingRemote = true;
        try {
          await doc.apply(mergedNow);
        } finally {
          _applyingRemote = false;
        }
      }

      // Push only if the repo's copy differs.
      if (!itemsEqualOf(mergedNow, remoteItems, doc.toJson, doc.idOf)) {
        final put = await client.putFile(
          doc.path,
          _encodeItems(mergedNow, doc),
          sha: remote.sha,
          message: 'daydeck: sync ${doc.path} ${DateTime.now().toUtc().toIso8601String()}',
        );
        if (put.status == SyncPutStatus.conflict) continue; // raced — re-read & re-merge
        if (put.status == SyncPutStatus.tokenInvalid) return SyncStatus.tokenInvalid;
        if (!put.succeeded) {
          _lastError = '${doc.displayName}: ${put.error}';
          return SyncStatus.error;
        }
      }

      if (outcome.losers.isNotEmpty) {
        await _recordConflicts(outcome.losers, doc);
      }
      return SyncStatus.ok;
    }

    _lastError = 'sync raced with another writer on ${doc.displayName} — try again';
    return SyncStatus.error;
  }

  static bool _taskDiff(Task a, Task b) =>
      a.title != b.title ||
      a.done != b.done ||
      a.priority != b.priority ||
      a.dueDate != b.dueDate ||
      a.deleted != b.deleted;

  // ================= conflicts.json =================

  /// Public: everything parked in conflicts.json (local pending + remote).
  /// Used by Settings → SYNC CONFLICTS. Best-effort: no token → just the
  /// local pending queue; parse failures → whatever decodes cleanly.
  Future<List<Map<String, dynamic>>> fetchConflicts() async {
    final pending = await _loadPendingConflicts();
    final token = _appState.syncToken;
    if (token == null || token.isEmpty) return pending;
    try {
      final client = GitHubClient(token: token, repo: _repo);
      final remote = await client.getFile(_conflictsPath);
      if (!remote.exists || remote.content == null) return pending;
      final remoteEntries = _decodeConflicts(remote.content!);
      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      for (final e in [...remoteEntries, ...pending]) {
        final key = jsonEncode([e['when'], e['doc'], e['id'], e['side']]);
        if (seen.add(key)) merged.add(e);
      }
      merged.sort((a, b) => (b['when'] ?? '').toString().compareTo((a['when'] ?? '').toString()));
      return merged;
    } catch (_) {
      return pending;
    }
  }

  /// Public: re-create a parked LOSING version as a brand-new item on this
  /// device. Supported docs: tasks.json / events.json / habits.json.
  /// Returns false if the entry can't be restored (unsupported doc or the
  /// payload is unusable).
  Future<bool> restoreConflictAsNew(Map<String, dynamic> conflict) async {
    try {
      final item = conflict['item'];
      if (item is! Map) return false;
      final map = Map<String, dynamic>.from(item);
      switch (conflict['doc']?.toString()) {
        case 'tasks.json':
          await _tasks.add(
            title: (map['title'] ?? '').toString(),
            priority: (map['priority'] ?? 'P2').toString(),
            dueDate: map['due']?.toString(),
          );
          return true;
        case 'events.json':
          final start = DateTime.tryParse(map['start']?.toString() ?? '');
          final end = DateTime.tryParse(map['end']?.toString() ?? '');
          if (start == null || end == null) return false;
          await _events.add(
            title: (map['title'] ?? '').toString(),
            start: start,
            end: end,
            allDay: map['allDay'] == true,
            visibility: map['visibility']?.toString() ?? 'private',
            notes: map['notes']?.toString(),
            location: map['location']?.toString(),
          );
          return true;
        case 'habits.json':
          final title = (map['name'] ?? map['title'] ?? '').toString().trim();
          if (title.isEmpty) return false;
          await _habits.addHabitRaw(
            title: title,
            cadence: (map['cadence'] ?? (map['schedule'] == 'weekly' ? 'weekly' : 'daily')).toString(),
          );
          return true;
        case 'routines.json':
          final name = (map['name'] ?? '').toString().trim();
          if (name.isEmpty) return false;
          await _habits.addRoutine(name: name, icon: (map['icon'] ?? '>').toString());
          return true;
        case 'skip_rules.json':
          final name = (map['name'] ?? '').toString().trim();
          if (name.isEmpty) return false;
          final now = DateTime.now().toUtc();
          await _habits.addSkipRule(SkipRule(
            id: 'conflict', // addSkipRule re-ids
            name: name,
            kind: (map['kind'] ?? SkipRule.kindRange).toString(),
            fromDay: (map['fromDay'] as num?)?.toInt(),
            toDay: (map['toDay'] as num?)?.toInt(),
            weekdayMask: (map['weekdayMask'] as num?)?.toInt() ?? 0,
            habitIds: (map['habitIds'] ?? '').toString(),
            enabled: map['enabled'] != false,
            createdAt: now,
            updatedAt: now,
          ));
          return true;
        case 'shield_uses.json':
          final habitId = map['habitId']?.toString() ?? '';
          final day = (map['day'] as num?)?.toInt();
          if (habitId.isEmpty || day == null) return false;
          await _habits.addShieldUseRaw(habitId: habitId, day: day);
          return true;
        case 'xp_events.json':
          final day = (map['day'] as num?)?.toInt();
          final amount = (map['amount'] as num?)?.toInt() ?? 0;
          if (day == null || amount == 0) return false;
          await _habits.addXpRaw(
            day: day,
            amount: amount,
            reason: (map['reason'] ?? 'complete').toString(),
            habitId: (map['habitId'] ?? '0').toString(),
          );
          return true;
        case 'watches.json':
          final model = (map['model'] ?? '').toString().trim();
          if (model.isEmpty) return false;
          await _watches.addWatch(
            brand: (map['brand'] ?? '').toString(),
            model: model,
            nickname: (map['nickname'] ?? '').toString(),
            reference: (map['reference'] ?? '').toString(),
            movement: (map['movement'] ?? '').toString(),
            caseSizeMm: (map['caseSizeMm'] as num?)?.toDouble(),
            color: (map['color'] ?? 'cyan').toString(),
            status: (map['status'] ?? Watch.statusOwned).toString(),
            notes: (map['notes'] ?? '').toString(),
          );
          return true;
        case 'wear_logs.json':
          final watchId = map['watchId']?.toString() ?? '';
          final day = (map['day'] as num?)?.toInt();
          if (watchId.isEmpty || day == null) return false;
          await _watches.addWearRaw(watchId: watchId, day: day, note: (map['note'] ?? '').toString());
          return true;
        case 'focus_sessions.json':
          final minutes = (map['minutes'] as num?)?.toInt() ?? 0;
          final startedAt = (map['startedAt'] as num?)?.toInt();
          final endedAt = (map['endedAt'] as num?)?.toInt();
          if (minutes < 1 || startedAt == null || endedAt == null) return false;
          await _focus.recordSession(
            habitId: (map['habitId'] ?? '0').toString(),
            startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: true),
            endedAt: DateTime.fromMillisecondsSinceEpoch(endedAt, isUtc: true),
            minutes: minutes,
            kind: (map['kind'] ?? FocusSession.kindFocus).toString(),
            completed: map['completed'] != false,
          );
          return true;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _recordConflicts<T>(List<MergeLoser<T>> losers, _Doc<T> doc) async {
    final pending = await _loadPendingConflicts();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final loser in losers) {
      pending.add({
        'when': now,
        'doc': doc.path,
        'id': doc.idOf(loser.item),
        'title': doc.titleOf(loser.item),
        'side': loser.side,
        'item': doc.toJson(loser.item),
      });
    }
    await _savePendingConflicts(pending);
  }

  Future<void> _flushPendingConflicts(GitHubClient client) async {
    final pending = await _loadPendingConflicts();

    final remote = await client.getFile(_conflictsPath);
    if (remote.status == SyncFileStatus.tokenInvalid || remote.status == SyncFileStatus.error) {
      // Keep everything pending; retry next sync. Nothing is lost.
      return;
    }

    final List<Map<String, dynamic>> remoteEntries = remote.exists ? _decodeConflicts(remote.content!) : <Map<String, dynamic>>[];

    if (pending.isEmpty) {
      if (!remote.exists) {
        await client.putFile(
          _conflictsPath,
          jsonEncode({'schemaVersion': 1, 'conflicts': <Map<String, dynamic>>[]}),
          message: 'daydeck: seed conflicts.json',
        );
      }
      return;
    }

    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final e in [...remoteEntries, ...pending]) {
      final key = jsonEncode([e['when'], e['doc'], e['id'], e['side']]);
      if (seen.add(key)) merged.add(e);
    }
    final capped = merged.length > 200 ? merged.sublist(merged.length - 200) : merged;

    final put = await client.putFile(
      _conflictsPath,
      jsonEncode({'schemaVersion': 1, 'conflicts': capped}),
      sha: remote.sha,
      message: 'daydeck: park ${pending.length} sync conflict${pending.length == 1 ? '' : 's'}',
    );

    if (put.succeeded) {
      await _savePendingConflicts(<Map<String, dynamic>>[]);
    }
    // On failure: pending stays in shared_preferences and is retried next sync.
  }

  // ================= manifest.json =================

  Future<void> _ensureManifest(GitHubClient client) async {
    try {
      final manifest = await client.getFile(_manifestPath);
      if (manifest.exists || manifest.status != SyncFileStatus.notFound) return;
      await client.putFile(
        _manifestPath,
        jsonEncode({
          'schemaVersion': 1,
          'app': 'daydeck',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
        message: 'daydeck: create manifest.json',
      );
    } catch (_) {
      // Non-fatal — manifest only carries schemaVersion for future migrations.
    }
  }

  // ================= codec helpers =================

  List<T> _decodeItems<T>(String raw, _Doc<T> doc) {
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map<String, dynamic> && decoded['items'] is List
          ? decoded['items'] as List
          : (decoded is List ? decoded : <dynamic>[]);
      return list
          .whereType<Map>()
          .map((e) => doc.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => doc.idOf(t).isNotEmpty)
          .toList();
    } catch (_) {
      // A corrupt remote document must not break anything: treat it as empty,
      // keep local data, and let the next push rewrite it cleanly.
      return <T>[];
    }
  }

  String _encodeItems<T>(List<T> items, _Doc<T> doc) {
    final sorted = [...items]..sort((a, b) => doc.idOf(a).compareTo(doc.idOf(b)));
    return jsonEncode({
      'schemaVersion': 1,
      'items': sorted.map(doc.toJson).toList(),
    });
  }

  List<Map<String, dynamic>> _decodeConflicts(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map<String, dynamic> && decoded['conflicts'] is List ? decoded['conflicts'] as List : <dynamic>[];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadPendingConflicts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _savePendingConflicts(List<Map<String, dynamic>> conflicts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (conflicts.isEmpty) {
        await prefs.remove(_pendingKey);
        return;
      }
      // Cap the local queue; oldest beyond 500 are dropped (remote caps at 200).
      final capped = conflicts.length > 500 ? conflicts.sublist(conflicts.length - 500) : conflicts;
      await prefs.setString(_pendingKey, jsonEncode(capped));
    } catch (_) {}
  }
}
