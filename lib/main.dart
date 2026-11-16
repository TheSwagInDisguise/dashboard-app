import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/calendar_feed.dart';
import 'notifications/reminder_service.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/event_store.dart';
import 'state/focus_store.dart';
import 'state/habit_store.dart';
import 'state/pomodoro_timer.dart';
import 'state/tasks_store.dart';
import 'state/watch_photo_store.dart';
import 'state/watch_store.dart';
import 'models/habit.dart' show epochDayOf;
import 'sync/sync_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted state; neither loader throws, so the app always boots —
  // even with no storage available.
  final appState = await AppState.load();
  final tasksStore = TasksStore();
  await tasksStore.load();
  final eventStore = EventStore();
  await eventStore.load();
  final habitStore = HabitStore();
  await habitStore.load();
  final watchStore = WatchStore();
  await watchStore.load();
  final watchPhotos = WatchPhotoStore();
  await watchPhotos.load();
  final focusStore = FocusStore();
  await focusStore.load();
  final feed = CalendarFeed(appState: appState, eventStore: eventStore);
  await feed.loadCache();

  final sync = SyncService(
    tasksStore: tasksStore,
    eventStore: eventStore,
    habitStore: habitStore,
    watchStore: watchStore,
    focusStore: focusStore,
    appState: appState,
  );

  // Local notifications (evening check + per-task reminders; web = silent no-op).
  final reminder = ReminderService();
  await reminder.init();
  unawaited(reminder.ensurePermission());
  unawaited(reminder.syncTaskReminders(tasksStore.snapshotItems()));
  tasksStore.addListener(() {
    unawaited(reminder.syncTaskReminders(tasksStore.snapshotItems()));
  });

  final pomodoro = PomodoroTimer(
    focusStore: focusStore,
    habitStore: habitStore,
    appState: appState,
    reminders: reminder,
  );

  List<String> pendingCheckIns() {
    return habitStore.habits
        .where((h) => h.checkIn && !habitStore.isDoneToday(h) && !habitStore.skippedOn(h.id, epochDayOf(DateTime.now())))
        .map((h) => h.name)
        .toList();
  }

  unawaited(reminder.syncHabitReminders(habitStore.snapshotHabits()));
  var lastDoneToday = <String>{};
  habitStore.addListener(() {
    unawaited(reminder.syncHabitReminders(habitStore.snapshotHabits()));
    final doneNow = habitStore.habits.where(habitStore.isDoneToday).map((h) => h.id).toSet();
    for (final h in habitStore.habits) {
      final anchorId = h.anchorId;
      if (anchorId != null &&
          h.anchorRemind &&
          !doneNow.contains(h.id) &&
          doneNow.contains(anchorId) &&
          !lastDoneToday.contains(anchorId)) {
        // The habit this one is stacked on just completed — nudge.
        unawaited(reminder.showAnchorNudge(h.name));
      }
    }
    lastDoneToday = doneNow;
    unawaited(reminder.scheduleEveningCheck(appState.reminderMinutes, checkInHabits: pendingCheckIns()));
  });
  var lastReminderMinutes = appState.reminderMinutes;
  appState.addListener(() {
    final minutes = appState.reminderMinutes;
    if (minutes != lastReminderMinutes) {
      lastReminderMinutes = minutes;
      unawaited(reminder.scheduleEveningCheck(minutes, checkInHabits: pendingCheckIns()));
    }
  });
  unawaited(reminder.scheduleEveningCheck(lastReminderMinutes, checkInHabits: pendingCheckIns()));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<TasksStore>.value(value: tasksStore),
        ChangeNotifierProvider<EventStore>.value(value: eventStore),
        ChangeNotifierProvider<HabitStore>.value(value: habitStore),
        ChangeNotifierProvider<WatchStore>.value(value: watchStore),
        ChangeNotifierProvider<WatchPhotoStore>.value(value: watchPhotos),
        ChangeNotifierProvider<FocusStore>.value(value: focusStore),
        ChangeNotifierProvider<PomodoroTimer>.value(value: pomodoro),
        ChangeNotifierProvider<CalendarFeed>.value(value: feed),
        ChangeNotifierProvider<SyncService>.value(value: sync),
      ],
      child: const DayDeckApp(),
    ),
  );

  // Kick off background sync + calendar refresh after the first frame —
  // never blocks the UI. Feed also refreshes on app resume.
  feed.startLifecycleRefresh();
  unawaited(sync.syncNow());
  unawaited(feed.refresh());
}

class DayDeckApp extends StatelessWidget {
  const DayDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<AppState>().palette;
    final theme = buildDayDeckTheme(palette);

    return MaterialApp(
      title: 'DayDeck',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: palette.isLight ? ThemeMode.light : ThemeMode.dark,
      home: const Shell(),
    );
  }
}
