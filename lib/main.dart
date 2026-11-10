import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/calendar_feed.dart';
import 'notifications/reminder_service.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/event_store.dart';
import 'state/habit_store.dart';
import 'state/tasks_store.dart';
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
  final feed = CalendarFeed(appState: appState, eventStore: eventStore);
  await feed.loadCache();

  final sync = SyncService(
    tasksStore: tasksStore,
    eventStore: eventStore,
    habitStore: habitStore,
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
  var lastReminderMinutes = appState.reminderMinutes;
  appState.addListener(() {
    final minutes = appState.reminderMinutes;
    if (minutes != lastReminderMinutes) {
      lastReminderMinutes = minutes;
      unawaited(reminder.scheduleEveningCheck(minutes));
    }
  });
  unawaited(reminder.scheduleEveningCheck(lastReminderMinutes));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<TasksStore>.value(value: tasksStore),
        ChangeNotifierProvider<EventStore>.value(value: eventStore),
        ChangeNotifierProvider<HabitStore>.value(value: habitStore),
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
