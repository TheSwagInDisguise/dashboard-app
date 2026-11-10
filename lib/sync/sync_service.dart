import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import '../state/tasks_store.dart';
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

/// Keeps the on-device task document in sync with the user's PRIVATE GitHub
/// data repo as a single JSON file, using last-write-wins per item with a
/// full audit trail of losing versions in `conflicts.json` (plus an on-device
/// pending queue so a conflict is NEVER lost, even if the repo write fails).
///
/// Sync happens on app open, on resume, and debounced after local mutations.
/// No background service; nothing runs when the app isn't in the foreground.
class SyncService extends ChangeNotifier {
  SyncService({required TasksStore tasksStore, required AppState appState})
      : _store = tasksStore,
        _appState = appState {
    _store.addListener(_handleLocalMutation);
    _appState.addListener(_handleStateMutation);
    _lastSeenToken = appState.syncToken;
    if (_lastSeenToken == null) _status = SyncStatus.disabled;
  }

  static const String _repo = 'TheSwagInDisguise/dashboard-data';
  static const String _tasksPath = 'tasks.json';
  static const String _conflictsPath = 'conflicts.json';
  static const String _manifestPath = 'manifest.json';
  static const String _pendingKey = 'sync_conflicts_pending';
  static const String _schemaVersionKey = 'sync_schema_version';

  final TasksStore _store;
  final AppState _appState;

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

  /// One full sync pass. Concurrent calls coalesce into at most one extra run.
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

    final client = GitHubClient(token: token, repo: _repo);
    try {
      final success = await _syncTasksDocument(client);
      if (success) {
        await _flushPendingConflicts(client);
        await _ensureManifest(client);
        _status = SyncStatus.ok;
        _lastSyncedAt = DateTime.now();
        _lastError = null;
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

  Future<bool> _syncTasksDocument(GitHubClient client) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final remote = await client.getFile(_tasksPath);
      if (remote.status == SyncFileStatus.tokenInvalid) {
        _status = SyncStatus.tokenInvalid;
        notifyListeners();
        return false;
      }
      if (remote.status == SyncFileStatus.error) {
        _status = SyncStatus.error;
        _lastError = remote.error;
        notifyListeners();
        return false;
      }

      final List<Task> remoteItems = remote.exists ? _decodeItems(remote.content!) : <Task>[];
      final List<Task> localItems = _store.snapshotItems();
      final outcome = mergeTasks(localItems, remoteItems);

      // 1) apply merged result locally (skip the notify storm while applying)
      if (!itemsEqual(outcome.merged, localItems)) {
        _applyingRemote = true;
        try {
          await _store.replaceAll(outcome.merged);
        } finally {
          _applyingRemote = false;
        }
      }

      // 2) push the merged document back only if it differs from remote
      if (!itemsEqual(outcome.merged, remoteItems)) {
        final put = await client.putFile(
          _tasksPath,
          _encodeItems(outcome.merged),
          sha: remote.sha,
          message: 'daydeck: sync tasks ${DateTime.now().toUtc().toIso8601String()}',
        );
        if (put.status == SyncPutStatus.conflict) continue; // raced — re-read & re-merge
        if (put.status == SyncPutStatus.tokenInvalid) {
          _status = SyncStatus.tokenInvalid;
          notifyListeners();
          return false;
        }
        if (!put.succeeded) {
          _status = SyncStatus.error;
          _lastError = put.error;
          notifyListeners();
          return false;
        }
      }

      if (outcome.losers.isNotEmpty) await _recordConflicts(outcome.losers);
      return true;
    }

    _status = SyncStatus.error;
    _lastError = 'sync raced with another writer — try again';
    notifyListeners();
    return false;
  }

  // ================= conflicts.json =================

  Future<void> _recordConflicts(List<MergeLoser> losers) async {
    final pending = await _loadPendingConflicts();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final loser in losers) {
      pending.add({
        'when': now,
        'id': loser.item.id,
        'title': loser.item.title,
        'side': loser.side,
        'item': loser.item.toJson(),
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
      // Seed an empty conflicts.json once so the repo has the file.
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
      final key = jsonEncode([e['when'], e['id'], e['side']]);
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

  List<Task> _decodeItems(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map<String, dynamic> && decoded['items'] is List
          ? decoded['items'] as List
          : (decoded is List ? decoded : <dynamic>[]);
      return list
          .whereType<Map>()
          .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (_) {
      // A corrupt remote document must not break anything: treat it as empty,
      // keep local data, and let the next push rewrite it cleanly.
      return <Task>[];
    }
  }

  String _encodeItems(List<Task> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode({
      'schemaVersion': 1,
      'items': sorted.map((t) => t.toJson()).toList(),
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
      await prefs.setInt(_schemaVersionKey, 1);
    } catch (_) {}
  }
}
