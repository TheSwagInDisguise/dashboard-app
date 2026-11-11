import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ics.dart';

/// Read-only access to the calendars synced onto this Android device via
/// `android.provider.CalendarContract` — the one reliable source for a
/// *private shared* calendar that the owner won't hand an iCal secret for.
/// Everything happens on-device; nothing leaves the phone.
///
/// Web is a no-op by design: browsers can't see the device calendar.
class DeviceCalendarInfo {
  const DeviceCalendarInfo({
    required this.id,
    required this.name,
    required this.account,
    required this.color,
    required this.syncEnabled,
  });

  final String id;
  final String name;
  final String account;
  final int color;
  final bool syncEnabled;

  static DeviceCalendarInfo fromJson(Map<Object?, Object?> json) => DeviceCalendarInfo(
        id: json['id']?.toString() ?? '',
        name: (json['name']?.toString() ?? '').trim().isEmpty ? '(unnamed calendar)' : json['name'] as String,
        account: json['account']?.toString() ?? '',
        color: (json['color'] as num?)?.toInt() ?? 0,
        syncEnabled: json['syncEnabled'] == true,
      );
}

class DeviceCalendarReader {
  static const MethodChannel _channel = MethodChannel('daydeck/devicecal');

  /// True on Android (where CalendarContract exists) and false everywhere else.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<bool> checkPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('checkCalendarPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestCalendarPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// All calendars known to the device (including ones not syncing).
  static Future<List<DeviceCalendarInfo>> listCalendars() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('listCalendars');
    return (raw ?? const [])
        .whereType<Map>()
        .map((m) => DeviceCalendarInfo.fromJson(m.cast<Object?, Object?>()))
        .toList();
  }

  /// Instances overlapping [begin, end], already expanded by the OS.
  /// [includeCalendarIds] empty = every calendar; otherwise only the chosen ones.
  static Future<List<CalendarEventItem>> listEvents({
    required DateTime begin,
    required DateTime end,
    Set<String> includeCalendarIds = const {},
  }) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>(
      'listEvents',
      {
        'beginMs': begin.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
      },
    );
    final items = <CalendarEventItem>[];
    for (final entry in raw ?? const <Object?>[]) {
      if (entry is! Map) continue;
      final calId = entry['calendarId']?.toString() ?? '';
      if (includeCalendarIds.isNotEmpty && !includeCalendarIds.contains(calId)) continue;
      final allDay = entry['allDay'] == true;
      final beginMs = (entry['begin'] as num?)?.toInt();
      final endMs = (entry['end'] as num?)?.toInt();
      if (beginMs == null || endMs == null) continue;
      final eventId = entry['eventId']?.toString() ?? beginMs.toString();
      items.add(CalendarEventItem(
        uid: 'dev:$calId:$eventId:$beginMs',
        title: (entry['title']?.toString() ?? '').trim().isEmpty ? '(no title)' : entry['title'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(beginMs),
        end: DateTime.fromMillisecondsSinceEpoch(endMs),
        allDay: allDay,
        location: entry['location']?.toString(),
        notes: entry['notes']?.toString(),
      ));
    }
    items.sort((a, b) => a.allDay == b.allDay
        ? a.start.compareTo(b.start)
        : (a.allDay ? -1 : 1));
    return items;
  }
}

/// Merge iCal-feed events and device-synced events, dropping duplicates.
/// The same Google event can reach us both ways; the device copy wins
/// (it reflects the shared calendar after edits immediately).
/// Both lists stay sorted: all-day first, then by start time.
List<CalendarEventItem> mergeCalendarSources(
  List<CalendarEventItem> ical,
  List<CalendarEventItem> device,
) {
  final merged = <CalendarEventItem>[...device];
  final deviceKeys = device.map(_dedupeKey).toSet();
  for (final event in ical) {
    if (deviceKeys.contains(_dedupeKey(event))) continue;
    merged.add(event);
  }
  merged.sort((a, b) => a.allDay == b.allDay
      ? a.start.compareTo(b.start)
      : (a.allDay ? -1 : 1));
  return merged;
}

String _normalizeTitle(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Title + day + start-of-slot unique key. Timed events round to a 10-minute
/// bucket so tiny feed/device clock skews still collapse onto one key.
String _dedupeKey(CalendarEventItem e) {
  final local = e.start.toLocal();
  final day = '${local.year}-${local.month}-${local.day}';
  if (e.allDay) return 'a|$day|${_normalizeTitle(e.title)}';
  final slot = local.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute ~/ 10;
  return 't|$day|$slot|${_normalizeTitle(e.title)}';
}
