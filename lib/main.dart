import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/tasks_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted state; neither loader throws, so the app always boots —
  // even with no storage available.
  final appState = await AppState.load();
  final tasksStore = TasksStore();
  await tasksStore.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<TasksStore>.value(value: tasksStore),
      ],
      child: const DayDeckApp(),
    ),
  );
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
