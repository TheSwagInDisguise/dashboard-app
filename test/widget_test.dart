import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daydeck/state/app_state.dart';
import 'package:daydeck/state/event_store.dart';
import 'package:daydeck/state/focus_store.dart';
import 'package:daydeck/state/habit_store.dart';
import 'package:daydeck/state/pomodoro_timer.dart';
import 'package:daydeck/notifications/reminder_service.dart';
import 'package:daydeck/state/tasks_store.dart';
import 'package:daydeck/state/watch_photo_store.dart';
import 'package:daydeck/state/watch_store.dart';
import 'package:daydeck/sync/sync_service.dart';
import 'package:daydeck/main.dart';
import 'package:daydeck/data/calendar_feed.dart';

Future<void> _pumpApp(
  WidgetTester tester, {
  required TasksStore tasks,
}) async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState.inMemory();
  final events = EventStore();
  await events.load();
  final habits = HabitStore();
  await habits.load();
  final watches = WatchStore();
  await watches.load();
  final watchPhotos = WatchPhotoStore();
  await watchPhotos.load();
  final focus = FocusStore();
  await focus.load();
  final feed = CalendarFeed(appState: appState, eventStore: events);
  final sync = SyncService(tasksStore: tasks, eventStore: events, habitStore: habits,
      watchStore: watches, focusStore: focus, appState: appState);
  final pomodoro = PomodoroTimer(focusStore: focus, habitStore: habits, appState: appState, reminders: ReminderService());

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<TasksStore>.value(value: tasks),
        ChangeNotifierProvider<EventStore>.value(value: events),
        ChangeNotifierProvider<HabitStore>.value(value: habits),
        ChangeNotifierProvider<WatchStore>.value(value: watches),
        ChangeNotifierProvider<WatchPhotoStore>.value(value: watchPhotos),
        ChangeNotifierProvider<FocusStore>.value(value: focus),
        ChangeNotifierProvider<PomodoroTimer>.value(value: pomodoro),
        ChangeNotifierProvider<CalendarFeed>.value(value: feed),
        ChangeNotifierProvider<SyncService>.value(value: sync),
      ],
      child: const DayDeckApp(),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and renders the terminal-styled today view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tasks = TasksStore();
    await tasks.load();

    await _pumpApp(tester, tasks: tasks);

    expect(find.text('TODAY'), findsWidgets);
    expect(find.text('TASKS'), findsWidgets);
    expect(find.text('HABITS'), findsWidgets);
    expect(find.text('WATCH'), findsWidgets);
    expect(find.text('FOCUS'), findsWidgets);
    expect(find.text('PROFILE'), findsWidgets);
    expect(find.text('SETTINGS'), findsNothing);
    expect(find.text('CALENDAR'), findsOneWidget);
    expect(find.textContaining('add your first habit'), findsOneWidget);
  });

  testWidgets('tasks added to the live store appear on the today view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tasks = TasksStore();
    await tasks.load();
    await tasks.add(title: 'live store probe task');

    await _pumpApp(tester, tasks: tasks);

    expect(find.text('live store probe task'), findsWidgets);
  });

  testWidgets('settings are reachable inside profile and expose theme picker and sync guide', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tasks = TasksStore();
    await tasks.load();

    await _pumpApp(tester, tasks: tasks);

    await tester.tap(find.text('PROFILE').last);
    await tester.pump();
    await tester.tap(find.text('PREFERENCES & SYNC'));
    await tester.pump();

    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('modern'), findsOneWidget);
    expect(find.text('classic green'), findsOneWidget);
    expect(find.text('amber'), findsOneWidget);
    expect(find.textContaining('light'), findsOneWidget);
    expect(find.text('how to create your sync token'), findsOneWidget);
  });
}
