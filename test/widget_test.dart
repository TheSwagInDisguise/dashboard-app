import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daydeck/main.dart';
import 'package:daydeck/state/app_state.dart';
import 'package:daydeck/state/tasks_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and renders the terminal-styled today view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.inMemory();
    final tasks = TasksStore();
    await tasks.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<TasksStore>.value(value: tasks),
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
    expect(find.text('Move 20 min'), findsOneWidget);
  });

  testWidgets('tasks added to the live store appear on the today view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tasks = TasksStore();
    await tasks.load();
    await tasks.add(title: 'live store probe task');

    final appState = AppState.inMemory();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<TasksStore>.value(value: tasks),
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<TasksStore>.value(value: tasks),
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
