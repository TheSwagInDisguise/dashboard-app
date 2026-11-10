import 'package:flutter_test/flutter_test.dart';

import 'package:daydeck/models/task.dart';
import 'package:daydeck/sync/merger.dart';

Task mk(
  String id, {
  String title = 'task',
  bool done = false,
  String priority = 'P2',
  String? due,
  DateTime? updated,
  DateTime? deleted,
}) {
  final stamp = updated ?? DateTime.utc(2026, 11, 1);
  return Task(
    id: id,
    title: title,
    done: done,
    priority: priority,
    dueDate: due,
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: deleted,
  );
}

void main() {
  group('mergeTasks', () {
    test('union of disjoint items from both sides', () {
      final outcome = mergeTasks(
        [mk('a'), mk('b')],
        [mk('c')],
      );
      expect(outcome.merged.map((t) => t.id), ['a', 'b', 'c']);
      expect(outcome.losers, isEmpty);
    });

    test('newer remote version wins; local loser is parked with side=local', () {
      final day2 = DateTime.utc(2026, 11, 2);
      final day3 = DateTime.utc(2026, 11, 3);
      final outcome = mergeTasks(
        [mk('t1', title: 'local edit', updated: day2)],
        [mk('t1', title: 'remote edit', updated: day3)],
      );
      expect(outcome.merged.single.title, 'remote edit');
      expect(outcome.losers, hasLength(1));
      expect(outcome.losers.single.side, 'local');
      expect(outcome.losers.single.item.title, 'local edit');
    });

    test('newer local version wins; remote loser is parked with side=remote', () {
      final day2 = DateTime.utc(2026, 11, 2);
      final day3 = DateTime.utc(2026, 11, 3);
      final outcome = mergeTasks(
        [mk('t1', title: 'local edit', updated: day3)],
        [mk('t1', title: 'remote edit', updated: day2)],
      );
      expect(outcome.merged.single.title, 'local edit');
      expect(outcome.losers.single.side, 'remote');
    });

    test('identical timestamps merge deterministically regardless of argument order', () {
      final stamp = DateTime.utc(2026, 11, 5);
      final x = mk('t1', title: 'apple', updated: stamp);
      final y = mk('t1', title: 'zebra', updated: stamp);
      final first = mergeTasks([x], [y]).merged.single;
      final second = mergeTasks([y], [x]).merged.single;
      expect(first.title, second.title);
    });

    test('newer tombstone outvotes an older live edit', () {
      final day1 = DateTime.utc(2026, 11, 1);
      final day2 = DateTime.utc(2026, 11, 2);
      final outcome = mergeTasks(
        [mk('t1', done: true, updated: day1)],
        [mk('t1', updated: day2, deleted: day2)],
      );
      expect(outcome.merged.single.deleted, isTrue);
      expect(outcome.losers.single.side, 'local');
    });

    test('newer live edit outvotes an older tombstone', () {
      final day1 = DateTime.utc(2026, 11, 1);
      final day2 = DateTime.utc(2026, 11, 2);
      final outcome = mergeTasks(
        [mk('t1', title: 'revived', updated: day2)],
        [mk('t1', updated: day1, deleted: day1)],
      );
      expect(outcome.merged.single.deleted, isFalse);
      expect(outcome.merged.single.title, 'revived');
    });

    test('identical documents merge without losers', () {
      final stamp = DateTime.utc(2026, 11, 5);
      final outcome = mergeTasks(
        [mk('a', updated: stamp), mk('b', updated: stamp)],
        [mk('b', updated: stamp), mk('a', updated: stamp)],
      );
      expect(outcome.losers, isEmpty);
      expect(outcome.merged.map((t) => t.id), ['a', 'b']);
    });

    test('itemsEqual ignores list order', () {
      final stamp = DateTime.utc(2026, 11, 5);
      expect(
        itemsEqual([mk('a', updated: stamp), mk('b', updated: stamp)],
            [mk('b', updated: stamp), mk('a', updated: stamp)]),
        isTrue,
      );
    });
  });
}
