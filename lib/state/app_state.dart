import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/palettes.dart';

/// App-wide state. Loads everything from on-device storage at startup.
/// The GitHub token and the secret iCal address are kept ONLY in secure
/// storage — never in shared preferences, never in code, never in logs.
class AppState extends ChangeNotifier {
  AppState._();

  SharedPreferences? _prefs;
  FlutterSecureStorage? _storage;

  DayDeckScheme _scheme = DayDeckScheme.modern; // dark-first default
  int _reminderMinutes = 20 * 60 + 30; // 20:30 (owner default)
  String _icalUrl = '';
  bool _deviceCalendarEnabled = true; // Android reads phone-synced calendars (incl. shared)
  Set<String> _deviceCalendarIds = const {}; // empty = all calendars on the phone
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
        var storedReminder = p.getInt('reminder_minutes') ?? 20 * 60 + 30;
        if (storedReminder == 19 * 60) {
          // Owner moved the evening check 19:00 → 20:30 (2026-11-10).
          storedReminder = 20 * 60 + 30;
          try { await p.setInt('reminder_minutes', storedReminder); } catch (_) {}
        }
        s._reminderMinutes = storedReminder;
        s._icalUrl = p.getString('ical_url') ?? ''; // migrated to secure storage below
        s._deviceCalendarEnabled = p.getBool('device_calendar_enabled') ?? true;
        s._deviceCalendarIds = (p.getStringList('device_calendar_ids') ?? const <String>[]).toSet();
      } catch (_) {
        // Corrupt prefs: fall back to defaults rather than crash.
      }
    }

    try {
      s._githubToken = await s._storage?.read(key: 'sync_github_token');
    } catch (_) {
      s._githubToken = null;
    }

    // Secret iCal address: prefer secure storage; migrate any prefs copy over.
    try {
      final secure = await s._storage?.read(key: 'ical_url');
      if (secure != null && secure.isNotEmpty) {
        s._icalUrl = secure;
      } else if (s._icalUrl.isNotEmpty) {
        final legacy = s._icalUrl;
        await s._storage?.write(key: 'ical_url', value: legacy);
        await s._prefs?.remove('ical_url');
      }
    } catch (_) {
      // Keep whatever we had (possibly the prefs copy) — never lose it.
    }
    return s;
  }

  // ---- app lock --------------------------------------------------------
  /// Optional biometric gate on app open / resume (Android only).
  bool get appLockEnabled => _prefs?.getBool('app_lock') ?? false;

  Future<void> setAppLockEnabled(bool value) async {
    try {
      await _prefs?.setBool('app_lock', value);
    } catch (_) {}
    notifyListeners();
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
      if (trimmed.isEmpty) {
        await _storage?.delete(key: 'ical_url');
      } else {
        await _storage?.write(key: 'ical_url', value: trimmed);
      }
      await _prefs?.remove('ical_url'); // it never lives in plain prefs now
    } catch (_) {
      // Secure storage unavailable — keep in memory for this session only.
    }
  }

  // ---- Device calendar (Android only; reads phone-synced calendars) ------
  // Per-device by design: calendar ids differ between handsets, so the
  // selection is kept in local prefs and never synced.
  bool get deviceCalendarEnabled => _deviceCalendarEnabled;
  List<String> get deviceCalendarIds => List.unmodifiable(_deviceCalendarIds);

  Future<void> setDeviceCalendarEnabled(bool value) async {
    _deviceCalendarEnabled = value;
    notifyListeners();
    try {
      await _prefs?.setBool('device_calendar_enabled', value);
    } catch (_) {}
  }

  /// Empty list = every synced calendar on this phone.
  Future<void> setDeviceCalendarIds(List<String> ids) async {
    _deviceCalendarIds = ids.toSet();
    notifyListeners();
    try {
      await _prefs?.setStringList('device_calendar_ids', ids);
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
