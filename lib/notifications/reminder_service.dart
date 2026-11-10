import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily evening reminder: "did anything shared make it into Google
/// Calendar?" — a local-only notification, no network, no server.
/// No-op on web (browsers have no such channel from a PWA build).
class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const int _notificationId = 2030; // 20:30 — the default hour
  static const String _channelId = 'daydeck_evenings';
  static const String _channelName = 'Evening check';

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: androidSettings));

      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'A gentle evening nudge about shared events',
        importance: Importance.defaultImportance,
      ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+ (no-op elsewhere).
  Future<void> ensurePermission() async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Schedules (or re-schedules) the repeating evening check.
  Future<void> scheduleEveningCheck(int minutesOfDay) async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.cancel(_notificationId);

      final hour = minutesOfDay ~/ 60;
      final minute = minutesOfDay % 60;
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));

      await _plugin.zonedSchedule(
        _notificationId,
        'daydeck · evening check',
        'Any shared events still waiting to make it into Google Calendar?',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'A gentle evening nudge about shared events',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
