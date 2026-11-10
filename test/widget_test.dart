import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:daydeck/main.dart';
import 'package:daydeck/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots and renders the terminal-styled today view', (tester) async {
    final state = AppState.inMemory();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const DayDeckApp(),
      ),
    );
    await tester.pump();

    // Header wordmark and navigation render.
    expect(find.text('day'), findsWidgets);
    expect(find.text('TODAY'), findsWidgets);
    expect(find.text('TASKS'), findsWidgets);
    expect(find.text('HABITS'), findsWidgets);
    expect(find.text('SETTINGS'), findsWidgets);

    // Sample data is visible and labelled as such.
    expect(find.text('CALENDAR'), findsOneWidget);
    expect(find.text('Buy oat milk'), findsOneWidget);
    expect(find.text('Move 20 min'), findsOneWidget);
  });

  testWidgets('switching to settings exposes scheme picker and token guide', (tester) async {
    final state = AppState.inMemory();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
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
