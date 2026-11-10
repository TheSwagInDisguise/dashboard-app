import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted settings; AppState.load() never throws, so the app
  // always boots — even with no storage available.
  final state = await AppState.load();

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
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
