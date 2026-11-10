import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/palettes.dart';

/// App-wide state. Loads everything from on-device storage at startup.
/// The GitHub token (when the user sets one later) is kept ONLY in secure
/// storage — never in shared preferences, never in code, never in logs.
class AppState extends ChangeNotifier {
  AppState._();

  SharedPreferences? _prefs;
  FlutterSecureStorage? _storage;

  DayDeckScheme _scheme = DayDeckScheme.modern; // dark-first default
  int _reminderMinutes = 19 * 60; // 19:00
  String _icalUrl = '';
  String? _githubToken;

  /// In-memory state for tests and as a last-resort fallback — nothing here
  /// throws, so the app always boots, even with no storage available.
  static AppState inMemory() => AppState._();

  static Future<AppState> load() async {
    final s = AppState._();

    try {
      s._prefs = await SharedPreferences.getInstance();
    } catch (_) {
      s._prefs = null; // non-fatal: keep defaults, persist nothing
    }
    try {
      s._storage = const FlutterSecureStorage();
    } catch (_) {
      s._storage = null;
    }

    final p = s._prefs;
    if (p != null) {
      try {
        final saved = p.getString('scheme');
        for (final candidate in DayDeckScheme.values) {
          if (candidate.name == saved) {
            s._scheme = candidate;
            break;
          }
        }
        s._reminderMinutes = p.getInt('reminder_minutes') ?? 19 * 60;
        s._icalUrl = p.getString('ical_url') ?? '';
      } catch (_) {
        // Corrupt prefs: fall back to defaults rather than crash.
      }
    }

    try {
      s._githubToken = await s._storage?.read(key: 'sync_github_token');
    } catch (_) {
      s._githubToken = null;
    }
    return s;
  }

  // ---- scheme ----------------------------------------------------------
  DayDeckScheme get scheme => _scheme;
  TerminalPalette get palette => paletteOf(_scheme);

  Future<void> setScheme(DayDeckScheme value) async {
    _scheme = value;
    notifyListeners();
    try {
      await _prefs?.setString('scheme', value.name);
    } catch (_) {}
  }

  // ---- evening reminder -------------------------------------------------
  int get reminderMinutes => _reminderMinutes;

  String get reminderLabel {
    final h = _reminderMinutes ~/ 60;
    final m = _reminderMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  Future<void> setReminderMinutes(int value) async {
    _reminderMinutes = value;
    notifyListeners();
    try {
      await _prefs?.setInt('reminder_minutes', value);
    } catch (_) {}
  }

  // ---- Google Calendar feed (view-only iCal) -----------------------------
  String get icalUrl => _icalUrl;

  Future<void> setIcalUrl(String value) async {
    final trimmed = value.trim();
    _icalUrl = trimmed;
    notifyListeners();
    try {
      await _prefs?.setString('ical_url', trimmed);
    } catch (_) {}
  }

  // ---- GitHub sync token (stored only on this device) -------------------
  bool get tokenConfigured => (_githubToken?.isNotEmpty ?? false);

  /// The raw token. Used ONLY by the sync engine to authenticate GitHub API
  /// calls over HTTPS. Never logged, never displayed, never synced.
  String? get syncToken => _githubToken;

  /// Returns false when the input is empty or secure storage is unavailable.
  Future<bool> saveToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _storage?.write(key: 'sync_github_token', value: trimmed);
    } catch (_) {
      return false;
    }
    _githubToken = trimmed;
    notifyListeners();
    return true;
  }

  Future<void> clearToken() async {
    try {
      await _storage?.delete(key: 'sync_github_token');
    } catch (_) {}
    _githubToken = null;
    notifyListeners();
  }
}
