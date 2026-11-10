import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daydeck/state/tasks_store.dart';
import 'package:daydeck/utils/dates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add, sort, toggle, delete, persist', () async {
    final store = TasksStore();
    await store.load();
    expect(store.openCount, 0);

    final alpha = await store.add(title: 'alpha', priority: 'P2');
    final bravo = await store.add(title: 'bravo', priority: 'P1', dueDate: todayKey());
    await store.add(title: 'charlie', priority: 'P3');

    // Sorted: due-first (bravo), then by priority among the undated.
    expect(store.openTasks.map((t) => t.title), ['bravo', 'alpha', 'charlie']);
    expect(store.openCount, 3);
    expect(store.dueTodayCount, 1);
    expect(store.overdueCount, 0);

    await store.toggleDone(bravo.id);
    expect(store.openCount, 2);
    expect(store.doneTasks.map((t) => t.title), ['bravo']);

    await store.deleteTask(alpha.id);
    expect(store.openTasks.map((t) => t.title), ['charlie']);

    // Persistence: a fresh instance reads the same on-device document.
    final restored = TasksStore();
    await restored.load();
    expect(restored.openTasks.map((t) => t.title), ['charlie']);
    expect(restored.doneTasks.map((t) => t.title), ['bravo']);
    expect(restored.openCount, 1);

    expect(await restored.clearCompleted(), 1);
    expect(restored.doneTasks, isEmpty);
  });

  test('overdue detection: due yesterday is overdue', () async {
    final store = TasksStore();
    await store.load();
    final yesterday = dateKey(DateTime.now().subtract(const Duration(days: 1)));
    await store.add(title: 'late task', dueDate: yesterday);
    expect(store.overdueCount, 1);
    expect(store.dueTodayCount, 0);
  });

  test('corrupt main document falls back to the on-disk backup', () async {
    final store = TasksStore();
    await store.load();
    await store.add(title: 'first');
    await store.add(title: 'second');

    // Sabotage the main document; the backup holds state after the first add.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks_json', '{ this is not json');

    final recovered = TasksStore();
    await recovered.load();
    expect(recovered.recoveryNotice, isNotNull);
    expect(recovered.openTasks.map((t) => t.title), ['first']);
  });

  test('invalid payload in a non-empty main stays null when no backup exists', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks_json', 'garbage{');
    final store = TasksStore();
    await store.load();
    expect(store.openCount, 0);
    // Nothing recovered, nothing crashed — the app still works.
  });
}
