import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daydeck/main.dart';
import 'package:daydeck/data/calendar_feed.dart';
import 'package:daydeck/state/app_state.dart';
import 'package:daydeck/state/event_store.dart';
import 'package:daydeck/state/habit_store.dart';
import 'package:daydeck/state/tasks_store.dart';
import 'package:daydeck/sync/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and renders the terminal-styled today view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.inMemory();
    final tasks = TasksStore();
    await tasks.load();
    final events = EventStore();
    await events.load();
    final habits = HabitStore();
    await habits.load();
    final feed = CalendarFeed(appState: appState, eventStore: events);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<TasksStore>.value(value: tasks),
          ChangeNotifierProvider<EventStore>.value(value: events),
          ChangeNotifierProvider<HabitStore>.value(value: habits),
          ChangeNotifierProvider<CalendarFeed>.value(value: feed),
          ChangeNotifierProvider<SyncService>.value(
            value: SyncService(
              tasksStore: tasks,
              eventStore: events,
              habitStore: habits,
              appState: appState,
            ),
          ),
        ],
        child: const DayDeckApp(),
      ),
    );
    await tester.pump();

    expect(find.text('day'), findsWidgets);
    expect(find.text('TODAY'), findsWidgets);
    expect(find.text('TASKS'), findsWidgets);
    expect(find.text('HABITS'), findsWidgets);
    expect(find.text('SETTINGS'), findsWidgets);
    expect(find.text('CALENDAR'), findsOneWidget);
    expect(find.textContaining('add your first habit'), findsOneWidget);
  });

  testWidgets('tasks added to the live store appear on the today view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tasks = TasksStore();
    await tasks.load();
    final appState = AppState.inMemory();
    final events = EventStore();
    await events.load();
    final habits = HabitStore();
    await habits.load();
    final feed = CalendarFeed(appState: appState, eventStore: events);
    await tasks.add(title: 'live store probe task');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<TasksStore>.value(value: tasks),
          ChangeNotifierProvider<EventStore>.value(value: events),
          ChangeNotifierProvider<HabitStore>.value(value: habits),
          ChangeNotifierProvider<CalendarFeed>.value(value: feed),
          ChangeNotifierProvider<SyncService>.value(
            value: SyncService(
              tasksStore: tasks,
              eventStore: events,
              habitStore: habits,
              appState: appState,
            ),
          ),
        ],
        child: const DayDeckApp(),
      ),
    );
    await tester.pump();

    expect(find.text('live store probe task'), findsWidgets);
  });

  testWidgets('switching to settings exposes scheme picker and token guide', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.inMemory();
    final tasks = TasksStore();
    await tasks.load();
    final events = EventStore();
    await events.load();
    final habits = HabitStore();
    await habits.load();
    final feed = CalendarFeed(appState: appState, eventStore: events);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<TasksStore>.value(value: tasks),
          ChangeNotifierProvider<EventStore>.value(value: events),
          ChangeNotifierProvider<HabitStore>.value(value: habits),
          ChangeNotifierProvider<CalendarFeed>.value(value: feed),
          ChangeNotifierProvider<SyncService>.value(
            value: SyncService(
              tasksStore: tasks,
              eventStore: events,
              habitStore: habits,
              appState: appState,
            ),
          ),
        ],
        child: const DayDeckApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('SETTINGS'));
    await tester.pump();

    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('modern'), findsOneWidget);
    expect(find.text('classic green'), findsOneWidget);
    expect(find.text('amber'), findsOneWidget);
    expect(find.textContaining('light'), findsOneWidget);
    expect(find.text('how to create your sync token'), findsOneWidget);
  });
}
