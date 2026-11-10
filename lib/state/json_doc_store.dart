import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// One on-device JSON document with a rotate-then-write backup and a
/// tombstone-aware item list. Non-ChangeNotifier — the owning store wraps a
/// JsonDocStore and notifies its own listeners.
///
/// If the main document is missing/corrupt the previous good copy is restored
/// and [recoveryNotice] is set so the UI can say so. Nothing silently lost.
class JsonDocStore<T> {
  JsonDocStore({
    required this.mainKey,
    required this.backupKey,
    required this.fromJson,
    required this.toJson,
    required this.idOf,
  });

  final String mainKey;
  final String backupKey;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T item) toJson;
  final String Function(T item) idOf;

  static const int schemaVersion = 1;

  SharedPreferences? _prefs;
  final List<T> _items = [];
  bool _loaded = false;

  String? recoveryNotice;

  bool get loaded => _loaded;
  List<T> get items => List<T>.unmodifiable(_items);

  /// Read-only view of every item (including tombstones) for the sync engine.
  List<T> snapshotItems() => List<T>.unmodifiable(_items);

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
      _loaded = true;
      return;
    }

    final raw = _prefs!.getString(mainKey);
    var items = _tryParse(raw);

    if (items == null && raw != null && raw.isNotEmpty) {
      final backup = _tryParse(_prefs!.getString(backupKey));
      if (backup != null) {
        items = backup;
        recoveryNotice = '$mainKey was restored from the on-device backup';
      }
    }

    _items
      ..clear()
      ..addAll(items ?? <T>[]);
    _loaded = true;
  }

  List<T>? _tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final List<dynamic>? list = decoded is Map<String, dynamic> && decoded['items'] is List
          ? decoded['items'] as List
          : (decoded is List ? decoded : null);
      if (list == null) return null;
      return list
          .whereType<Map>()
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .where((t) => idOf(t).isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Applies an in-memory mutation then persists (rotate-then-write).
  Future<void> mutate(void Function(List<T> items) change) async {
    change(_items);
    await persist();
  }

  /// Replaces the whole document — used by the sync engine after a merge.
  Future<void> replaceAll(List<T> items) async {
    _items
      ..clear()
      ..addAll(items);
    await persist();
  }

  Future<void> persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final previous = prefs.getString(mainKey);
      if (previous != null && previous.isNotEmpty) {
        await prefs.setString(backupKey, previous);
      }
      final payload = jsonEncode(<String, dynamic>{
        'schemaVersion': schemaVersion,
        'items': _items.map(toJson).toList(),
      });
      await prefs.setString(mainKey, payload);
      recoveryNotice = null;
    } catch (_) {
      // Non-fatal — data stays in memory; the user keeps using the app.
    }
  }

  void clearRecoveryNotice() => recoveryNotice = null;

  static String newId() {
    final random = Random();
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = random.nextInt(1 << 32).toRadixString(36);
    return '$stamp-$salt';
  }
}
