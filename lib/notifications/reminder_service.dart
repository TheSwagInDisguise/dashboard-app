import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/habit.dart';
import '../models/task.dart';
import 'deep_links.dart';

/// Local notifications, no network, no server.
///
/// Three channels of nudge, all sharing one plugin:
///   1. Evening check (repeating daily, time chosen in Settings) — nags about
///      SHARED events waiting to make it into Google Calendar. Snoozeable.
///   2. Per-task reminders (one-shot, tied to a task's `reminderAt`).
/// No-op on web (browsers have no such channel from a PWA build).
class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// iOS notification categories: evening check offers SNOOZE inline.
  static final _darwinEveningCategory = DarwinNotificationCategory(
    'evening',
    actions: [
      DarwinNotificationAction.plain(
        'snooze30',
        'SNOOZE 30 MIN',
        options: {DarwinNotificationActionOption.foreground},
      ),
    ],
  );

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  static const int _eveningId = 2030; // 20:30 — the default hour
  static const int _snoozeId = 2031; // one-shot snooze from the evening check
  static const String _eveningChannelId = 'daydeck_evenings';
  static const String _taskChannelId = 'daydeck_tasks';
  static const String _eveningChannelName = 'Evening check';
  static const String _taskChannelName = 'Task reminders';
  static const String _taskSeqKey = 'task_reminder_seq';
  static const String _taskMapKey = 'task_reminder_map'; // taskId -> notifId
  static const String _taskWhenKey = 'task_reminder_when'; // taskId -> scheduled ISO (change detection)

  /// Top-level background handler — wired at init. Runs in a fresh isolate.
  @pragma('vm:entry-point')
  static Future<void> backgroundNotificationResponse(NotificationResponse response) async {
    try {
      if (response.actionId == 'snooze30') {
        await _scheduleSnoozeFromBackground();
        return;
      }
      DeepLinks.handle(response.payload);
    } catch (_) {}
  }

  static Future<void> _scheduleSnoozeFromBackground() async {
    try {
      tzdata.initializeTimeZones();
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
      final plugin = FlutterLocalNotificationsPlugin();
      const androidDetails = AndroidNotificationDetails(
        _eveningChannelId,
        _eveningChannelName,
        channelDescription: 'A gentle evening nudge about shared events',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      final scheduled = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 30));
      await plugin.zonedSchedule(
        _snoozeId,
        'daydeck · evening check (snoozed)',
        'Any shared events still waiting to make it into Google Calendar?',
        scheduled,
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(categoryIdentifier: 'evening'),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      final darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false, // permission requested explicitly in ensurePermission
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [_darwinEveningCategory],
      );
      await _plugin.initialize(
        InitializationSettings(android: androidSettings, iOS: darwinSettings),
        onDidReceiveNotificationResponse: (response) {
          if (response.actionId == 'snooze30') {
            unawaited(_snoozeEveningCheck());
            return;
          }
          DeepLinks.handle(response.payload);
        },
        onDidReceiveBackgroundNotificationResponse: ReminderService.backgroundNotificationResponse,
      );

      final android = _isAndroid
          ? _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          : null;
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _eveningChannelId,
        _eveningChannelName,
        description: 'A gentle evening nudge about shared events',
        importance: Importance.defaultImportance,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _taskChannelId,
        _taskChannelName,
        description: 'One-off nudges for tasks you asked to be reminded about',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _focusChannelId,
        _focusChannelName,
        description: 'Focus session finished',
        importance: Importance.defaultImportance,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _habitChannelId,
        _habitChannelName,
        description: 'Your habits at the time you asked for them',
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
      if (_isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return;
      }
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Schedules (or re-schedules) the repeating evening check. Tap = SHARED
  /// queue; SNOOZE action = one-off nudge 30 minutes later. [checkInHabits]
  /// lists unlogged check-in habits whose names are appended to the body.
  Future<void> scheduleEveningCheck(int minutesOfDay, {List<String> checkInHabits = const []}) async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.cancel(_eveningId);

      final hour = minutesOfDay ~/ 60;
      final minute = minutesOfDay % 60;
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));

      final pending = checkInHabits.take(3).map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
      final suffix = pending.isEmpty
          ? ''
          : '\nday not closed: ${pending.join(', ')}${checkInHabits.length > 3 ? '…' : ''}';

      await _plugin.zonedSchedule(
        _eveningId,
        'daydeck · evening check',
        'Any shared events still waiting to make it into Google Calendar?${suffix.isEmpty ? '' : suffix}',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _eveningChannelId,
            _eveningChannelName,
            channelDescription: 'A gentle evening nudge about shared events',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction('snooze30', '30 MIN', cancelNotification: true),
            ],
          ),
          iOS: DarwinNotificationDetails(categoryIdentifier: 'evening'),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'shared_queue',
      );
    } catch (_) {}
  }

  Future<void> _snoozeEveningCheck() async {
    if (!_ready) return;
    try {
      final scheduled = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 30));
      await _plugin.zonedSchedule(
        _snoozeId,
        'daydeck · evening check (snoozed)',
        'Any shared events still waiting to make it into Google Calendar?',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _eveningChannelId,
            _eveningChannelName,
            channelDescription: 'A gentle evening nudge about shared events',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(categoryIdentifier: 'evening'),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'shared_queue',
      );
    } catch (_) {}
  }

  // ---------------- focus (pomodoro) ----------------

  static const int _focusDoneId = 2040;
  static const String _focusChannelId = 'daydeck_focus';
  static const String _focusChannelName = 'Focus sessions';
  static const String _habitChannelId = 'daydeck_habits';
  static const String _habitChannelName = 'Habit reminders';
  static const int _habitSeqStart = 6000;
  static const int _anchorSeqStart = 7000;
  static const int _anchorWrap = 90; // 7000..7090 anchor-nudge id ring
  static const String _habitMapKey = 'habit_reminder_map'; // habitId -> notifId
  static const String _habitAtKey = 'habit_reminder_at'; // habitId -> minutesOfDay
  static const String _habitSeqKey = 'habit_reminder_seq';

  /// Schedule a one-shot "focus is done" notification at [when]. Any previous
  /// focus notification is replaced. iOS gets the same plain local notification
  /// (no DND / Live Activity integration).
  Future<void> scheduleFocusDone(DateTime when, {required String habitName}) async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.cancel(_focusDoneId);
      final at = tz.TZDateTime.from(when.toLocal(), tz.local);
      if (!at.isAfter(tz.TZDateTime.now(tz.local))) return;

      await _plugin.zonedSchedule(
        _focusDoneId,
        'daydeck · focus done',
        habitName.isEmpty ? 'time’s up — take the break.' : 'done with $habitName — take the break.',
        at,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _focusChannelId,
            _focusChannelName,
            channelDescription: 'Focus session finished',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'focus',
      );
    } catch (_) {}
  }

  Future<void> cancelFocusDone() async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.cancel(_focusDoneId);
    } catch (_) {}
  }

  // ---------------- per-habit reminders ----------------

  /// Reconciles scheduled daily reminders with the habit list (reminderMinutes
  /// >= 0). Called on every habit-store change; cheap when nothing moved.
  Future<void> syncHabitReminders(List<Habit> habits) async {
    if (kIsWeb || !_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _readIntMap(prefs.getString(_habitMapKey));
      final at = _readIntMap(prefs.getString(_habitAtKey));

      final desired = <String, int>{};
      for (final h in habits) {
        if (h.deleted || h.archived) continue;
        if (h.reminderMinutes >= 0) desired[h.id] = h.reminderMinutes;
      }

      // Cancel reminders for habits that no longer want one.
      for (final entry in {...map}.entries) {
        if (!desired.containsKey(entry.key)) {
          await _plugin.cancel(entry.value);
          map.remove(entry.key);
          at.remove(entry.key);
        }
      }

      var seq = prefs.getInt(_habitSeqKey) ?? _habitSeqStart;
      var nameById = <String, String>{for (final h in habits) h.id: h.name};
      for (final entry in desired.entries) {
        if (at[entry.key] == entry.value && map.containsKey(entry.key)) continue; // unchanged
        var notifId = map[entry.key];
        if (notifId == null) {
          notifId = seq;
          seq += 1;
          map[entry.key] = notifId;
        }
        await _plugin.cancel(notifId);
        final hour = entry.value ~/ 60;
        final minute = entry.value % 60;
        final nowTz = tz.TZDateTime.now(tz.local);
        var scheduled = tz.TZDateTime(tz.local, nowTz.year, nowTz.month, nowTz.day, hour, minute);
        if (!scheduled.isAfter(nowTz)) scheduled = scheduled.add(const Duration(days: 1));

        await _plugin.zonedSchedule(
          notifId,
          'daydeck · habit',
          _truncate(nameById[entry.key] ?? 'habit', 90),
          scheduled,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _habitChannelId,
              _habitChannelName,
              channelDescription: 'Your habits at the time you asked for them',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'habits',
        );
        at[entry.key] = entry.value;
      }

      await prefs.setInt(_habitSeqKey, seq);
      await prefs.setString(_habitMapKey, jsonEncode(map));
      await prefs.setString(_habitAtKey, jsonEncode(at));
    } catch (_) {}
  }

  /// One-shot nudge fired when a habit's anchor completes today
  /// ("meditate done → journal?"). Uses a rotating id ring.
  Future<void> showAnchorNudge(String habitName) async {
    if (kIsWeb || !_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seq = prefs.getInt('anchor_nudge_seq') ?? 0;
      final id = _anchorSeqStart + (seq % _anchorWrap);
      await prefs.setInt('anchor_nudge_seq', seq + 1);
      await _plugin.zonedSchedule(
        id,
        'daydeck · stacked habit',
        'anchor done — ${_truncate(habitName, 80)} is up next',
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 2)),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _habitChannelId,
            _habitChannelName,
            channelDescription: 'Your habits at the time you asked for them',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'habits',
      );
    } catch (_) {}
  }

  // ---------------- per-task reminders ----------------

  /// Reconciles scheduled notifications with the open-task snapshot:
  /// schedules what's new or changed, cancels what's done/deleted/rescheduled.
  /// Cheap enough to call on every store change.
  Future<void> syncTaskReminders(List<Task> tasks) async {
    if (kIsWeb || !_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _readIntMap(prefs.getString(_taskMapKey));
      final when = _readStrMap(prefs.getString(_taskWhenKey));

      final desired = <String, DateTime>{};
      for (final t in tasks) {
        if (t.deleted || t.done || t.reminderAt == null) continue;
        if (t.reminderAt!.isAfter(DateTime.now().toUtc())) desired[t.id] = t.reminderAt!;
      }

      // Cancel reminders for tasks that no longer want one.
      for (final entry in {...map}.entries) {
        final taskId = entry.key;
        if (!desired.containsKey(taskId)) {
          await _plugin.cancel(entry.value);
          map.remove(taskId);
          when.remove(taskId);
        }
      }

      var seq = prefs.getInt(_taskSeqKey) ?? 5000;
      for (final entry in desired.entries) {
        final iso = entry.value.toUtc().toIso8601String();
        if (when[entry.key] == iso && map.containsKey(entry.key)) continue; // unchanged
        var notifId = map[entry.key];
        if (notifId == null) {
          notifId = seq;
          seq += 1;
          map[entry.key] = notifId;
        }
        await _plugin.cancel(notifId);
        final tzTime = tz.TZDateTime.from(entry.value.toUtc(), tz.local);
        await _plugin.zonedSchedule(
          notifId,
          'daydeck · task reminder',
          _truncate((tasks.firstWhere((t) => t.id == entry.key)).title, 90),
          tzTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _taskChannelId,
              _taskChannelName,
              channelDescription: 'One-off nudges for tasks you asked to be reminded about',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'task:${entry.key}',
        );
        when[entry.key] = iso;
      }

      await prefs.setInt(_taskSeqKey, seq);
      await prefs.setString(_taskMapKey, jsonEncode(map));
      await prefs.setString(_taskWhenKey, jsonEncode(when));
    } catch (_) {}
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static Map<String, int> _readIntMap(String? raw) {
    try {
      if (raw == null || raw.isEmpty) return <String, int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return <String, int>{};
    }
  }

  static Map<String, String> _readStrMap(String? raw) {
    try {
      if (raw == null || raw.isEmpty) return <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
