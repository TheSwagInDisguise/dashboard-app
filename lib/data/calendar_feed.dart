import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';
import '../state/event_store.dart';
import '../sync/github_client.dart';
import 'device_calendar.dart';
import 'ics.dart';

/// Where the user-facing events come from:
///   Android / desktop: direct fetch of the secret iCal URL (CORS-free),
///        plus the calendars synced onto the phone (Android only) — the
///        reliable path for a *private shared* calendar with no secret link.
///   Web: the `calendar.json` mirror in the private dashboard-data repo,
///        refreshed hourly by a GitHub Action from the same secret URL
///        (browsers can't read Google's feed cross-origin). Read via the
///        Contents API using the user's sync token.
enum CalendarStatus { disabled, fetching, ok, error }

/// Fetches Google Calendar events (view-only) and caches the last good copy.
/// Also performs the "shared → seen in feed → auto-done" hand-off.
class CalendarFeed extends ChangeNotifier with WidgetsBindingObserver {
  CalendarFeed({required this._appState, required this._eventStore});

  static const String _cacheKey = 'calendar_cache_json';

  final AppState _appState;
  final EventStore _eventStore;

  CalendarStatus _status = CalendarStatus.disabled;
  List<CalendarEventItem> _events = [];
  List<String> _notes = [];
  DateTime? _lastFetched;
  String? _lastError;
  bool _observing = false;

  CalendarStatus get status => _status;
  List<CalendarEventItem> get events => List.unmodifiable(_events);
  List<String> get notes => List.unmodifiable(_notes);
  DateTime? get lastFetched => _lastFetched;
  String? get lastError => _lastError;

  bool get isConfigured =>
      kIsWeb ? (_appState.syncToken?.isNotEmpty ?? false) : (_appState.icalUrl.isNotEmpty || _appState.deviceCalendarEnabled);

  /// Restore the cached snapshot so the UI has content offline.
  Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) {
        _updateStatusForConfig();
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _events = (decoded['events'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => CalendarEventItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final fetched = DateTime.tryParse(decoded['fetchedAt']?.toString() ?? '');
      _lastFetched = fetched?.toLocal();
      _status = CalendarStatus.ok;
    } catch (_) {
      _status = CalendarStatus.disabled;
    }
    notifyListeners();
  }

  /// Poll on resume too (app open while the phone was in a pocket).
  void startLifecycleRefresh() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    _status = CalendarStatus.fetching;
    _lastError = null;
    notifyListeners();

    try {
      if (kIsWeb) {
        await _refreshWeb();
      } else {
        await _refreshNative();
      }
      _status = CalendarStatus.ok;
      _lastFetched = DateTime.now();
      _lastError = null;
      await _persistCache();
    } catch (e) {
      _status = CalendarStatus.error;
      _lastError = _friendlyError(e);
    }
    notifyListeners();
    await _autoCloseSharedEvents();
  }

  Future<void> _refreshNative() async {
    final icalEvents = <CalendarEventItem>[];
    final deviceEvents = <CalendarEventItem>[];
    final notes = <String>[];

    // ---- iCal (secret address) — optional now that device calendar exists ----
    final url = _appState.icalUrl.trim();
    String? icalError;
    if (url.isNotEmpty) {
      try {
        final uri = Uri.tryParse(url);
        if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
          icalError = 'that doesn’t look like a valid iCal URL';
        } else {
          final response = await http
              .get(uri, headers: const {'Accept': 'text/calendar, text/plain, */*'})
              .timeout(const Duration(seconds: 25));
          if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
            icalError = 'Google refused the feed — is the secret address still valid? (Settings → CALENDAR → guide)';
          } else if (response.statusCode != 200) {
            icalError = 'calendar fetch failed (HTTP ${response.statusCode})';
          } else {
            final raw = parseIcs(response.body);
            final now = DateTime.now();
            final result = expandEvents(
              raw,
              DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
              DateTime(now.year, now.month, now.day).add(const Duration(days: 31)),
            );
            icalEvents.addAll(result.events);
            notes.addAll(result.skippedRules);
          }
        }
      } catch (e) {
        icalError = _friendlyError(e);
      }
    }

    // ---- On-device calendars (Android) — incl. private shared ones ----------
    if (_appState.deviceCalendarEnabled) {
      try {
        final granted = await DeviceCalendarReader.checkPermission();
        if (granted) {
          final now = DateTime.now();
          final events = await DeviceCalendarReader.listEvents(
            begin: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
            end: DateTime(now.year, now.month, now.day).add(const Duration(days: 31)),
            includeCalendarIds: _appState.deviceCalendarIds.toSet(),
          );
          deviceEvents.addAll(events);
        } else {
          notes.add('device calendar: permission not granted — grant it in Settings → GOOGLE CALENDAR');
        }
      } catch (e) {
        notes.add('device calendar: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }

    if (icalError != null && deviceEvents.isNotEmpty) notes.insert(0, 'iCal: $icalError');
    _events = mergeCalendarSources(icalEvents, deviceEvents);
    _notes = notes;

    final attempted = url.isNotEmpty || _appState.deviceCalendarEnabled;
    if (!attempted) {
      _status = CalendarStatus.disabled;
      return;
    }
    if (_events.isNotEmpty) {
      _status = CalendarStatus.ok;
    } else if (icalError != null) {
      // Old behaviour: configured-but-unreachable feed surfaces as an error.
      throw _FeedException(icalError);
    } else {
      // Only the device path was configured and it produced nothing —
      // the reason (permission missing, etc.) is in the notes.
      _status = CalendarStatus.ok;
    }
  }

  Future<void> _refreshWeb() async {
    final token = _appState.syncToken;
    if (token == null || token.isEmpty) {
      _status = CalendarStatus.disabled;
      _lastError = 'web calendar is read via the hourly GitHub Action — add the ICAL_URL secret (Settings → CALENDAR → guide), and keep your sync token set';
      _events = [];
      return;
    }
    final client = GitHubClient(token: token, repo: 'TheSwagInDisguise/dashboard-data');
    try {
      final file = await client.getFile('calendar.json');
      if (file.status == SyncFileStatus.notFound) {
        _events = [];
        _notes = const ['calendar.json not found yet — the Action creates it on its next hourly run (or run it manually from the Actions tab)'];
        return;
      }
      if (file.status == SyncFileStatus.tokenInvalid) {
        throw const _FeedException('GitHub rejected your token — Settings → SYNC');
      }
      if (!file.exists) {
        throw _FeedException(file.error ?? 'could not read calendar.json');
      }
      final decoded = jsonDecode(file.content!) as Map<String, dynamic>;
      _events = (decoded['events'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => CalendarEventItem.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.allDay == b.allDay ? a.start.compareTo(b.start) : (a.allDay ? -1 : 1));
      _notes = const [];
    } finally {
      client.close();
    }
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'fetchedAt': DateTime.now().toUtc().toIso8601String(),
          'events': _events.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  /// SHARED local event found in the Google feed → flip done (auto-hide).
  Future<void> _autoCloseSharedEvents() async {
    try {
      final pending = _eventStore.sharedPending();
      if (pending.isEmpty || _events.isEmpty) return;
      for (final local in pending) {
        final match = _events.any((g) => _sameEvent(g, local.title, local.start, local.allDay));
        if (match) await _eventStore.toggleDone(local.id);
      }
    } catch (_) {
      // Never let the auto-close convenience break the calendar itself.
    }
  }

  static bool _sameEvent(CalendarEventItem gcal, String localTitle, DateTime localStart, bool localAllDay) {
    if (gcal.title.trim().toLowerCase() != localTitle.trim().toLowerCase()) return false;
    if (localAllDay) {
      final a = gcal.start.toLocal(), b = localStart.toLocal();
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }
    return gcal.start.difference(localStart.toUtc()).abs() <= const Duration(minutes: 30) ||
        gcal.start.difference(localStart).abs() <= const Duration(minutes: 30);
  }

  void _updateStatusForConfig() {
    if (!isConfigured) _status = CalendarStatus.disabled;
  }

  String _friendlyError(Object e) {
    if (e is _FeedException) return e.message;
    final text = e.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('Network is unreachable')) {
      return 'no internet connection';
    }
    if (text.contains('TimeoutException')) return 'the calendar server took too long to answer';
    return text.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _FeedException implements Exception {
  const _FeedException(this.message);
  final String message;
}
