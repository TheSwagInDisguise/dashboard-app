// Local-only watch photo store.
//
// Watch profile photos and per-wear wrist shots are kept ON-DEVICE ONLY —
// they are never serialized into any synced document and never uploaded to
// the GitHub repo. This store maps entity ids → relative file paths inside
// the app documents directory; the bytes live under watch_photos/.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchPhotoStore extends ChangeNotifier {
  static const _prefsKey = 'watch_photos_local_json';
  static const _dirName = 'watch_photos';

  SharedPreferences? _prefs;
  final Map<String, String> _paths = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _paths
            ..clear()
            ..addAll(decoded.map((k, v) => MapEntry(k.toString(), v.toString())));
        }
      }
    } catch (_) {
      // Non-fatal — photos simply show as missing this run.
    }
    _loaded = true;
  }

  // ---- keys ----

  static String watchKey(String watchId) => 'watch:$watchId';
  static String wearKey(String wearLogId) => 'wear:$wearLogId';

  String? relativeForWatch(String watchId) => _paths[watchKey(watchId)];
  String? relativeForWear(String wearLogId) => _paths[wearKey(wearLogId)];

  /// Absolute path for a relative path previously stored; null if the file
  /// is missing (e.g. synced from another device — photos don't travel).
  Future<String?> absoluteFor(String? relative) async {
    if (relative == null || relative.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_dirName/${relative.split('/').last}');
      return await file.exists() ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Copy [sourcePath] into the photo directory and associate it with [key].
  Future<String?> _ingest(String key, String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${dir.path}/$_dirName');
      if (!await photoDir.exists()) await photoDir.create(recursive: true);
      final ext = _extensionOf(sourcePath);
      final name = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}$ext';
      await File(sourcePath).copy('${photoDir.path}/$name');
      _paths[key] = name;
      await _persist();
      notifyListeners();
      return name;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setProfilePhoto(String watchId, String sourcePath) async =>
      (await _ingest(watchKey(watchId), sourcePath)) != null;

  Future<bool> setWristShot(String wearLogId, String sourcePath) async =>
      (await _ingest(wearKey(wearLogId), sourcePath)) != null;

  Future<void> clearProfilePhoto(String watchId) => _removeKey(watchKey(watchId));
  Future<void> clearWristShot(String wearLogId) => _removeKey(wearKey(wearLogId));

  Future<void> _removeKey(String key) async {
    final rel = _paths.remove(key);
    if (rel != null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_dirName/$rel');
        if (await file.exists()) await file.delete();
      } catch (_) {}
      await _persist();
      notifyListeners();
    }
  }

  /// Deletes every photo attached to a watch: its profile photo and every
  /// wrist shot on [wearLogIds]. Called when a watch is deleted.
  Future<void> removeAllForWatch(String watchId, List<String> wearLogIds) async {
    await _removeKey(watchKey(watchId));
    for (final id in wearLogIds) {
      await _removeKey(wearKey(id));
    }
  }

  Future<void> _persist() async {
    try {
      await _prefs?.setString(_prefsKey, jsonEncode(_paths));
    } catch (_) {}
  }

  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = name.substring(dot).toLowerCase();
    const ok = {'.jpg', '.jpeg', '.png', '.heic', '.webp'};
    return ok.contains(ext) ? ext : '.jpg';
  }
}
