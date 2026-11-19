import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daydeck/models/watch.dart';
import 'package:daydeck/state/app_state.dart';
import 'package:daydeck/state/event_store.dart';
import 'package:daydeck/state/focus_store.dart';
import 'package:daydeck/state/habit_store.dart';
import 'package:daydeck/state/tasks_store.dart';
import 'package:daydeck/state/watch_store.dart';
import 'package:daydeck/sync/sync_service.dart';

class _Fixture {
  _Fixture(this.service, this.watches);
  final SyncService service;
  final WatchStore watches;
}

Future<_Fixture> _fixture() async {
  final tasks = TasksStore();
  final events = EventStore();
  final habits = HabitStore();
  final watches = WatchStore();
  final focus = FocusStore();
  await Future.wait([
    tasks.load(),
    events.load(),
    habits.load(),
    watches.load(),
    focus.load(),
  ]);
  return _Fixture(
    SyncService(
      tasksStore: tasks,
      eventStore: events,
      habitStore: habits,
      watchStore: watches,
      focusStore: focus,
      appState: AppState.inMemory(),
    ),
    watches,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'backup merge imports strap/service records and parks LWW conflicts',
    () async {
      final fixture = await _fixture();
      final store = fixture.watches;
      final old = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 2, 1);
      final local = Strap(
        id: 'same',
        name: 'leather',
        material: 'leather',
        createdAt: old,
        updatedAt: newer,
      );
      await store.replaceAllStraps([local]);
      final losingRemote = Strap(
        id: 'same',
        name: 'nato',
        material: 'nylon',
        createdAt: old,
        updatedAt: old,
      );
      final importedStrap = Strap(
        id: 'new',
        name: 'rubber',
        createdAt: old,
        updatedAt: old,
      );
      final swap = StrapSwap(
        id: 'swap-1',
        strapId: 'new',
        day: 20000,
        note: 'test fit',
        createdAt: old,
        updatedAt: old,
      );
      final serviceLog = WatchService(
        id: 'svc-1',
        watchId: 'w-1',
        day: 20000,
        description: 'overhaul',
        nextDueDay: 20500,
        createdAt: old,
        updatedAt: old,
      );

      final result = await fixture.service.mergeBackup({
        'app': 'daydeck',
        'schemaVersion': 3,
        'straps': [losingRemote.toJson(), importedStrap.toJson()],
        'strap_swaps': [swap.toJson()],
        'watch_services': [serviceLog.toJson()],
      });

      expect(result.records, 4);
      expect(result.conflicts, 1);
      expect(result.documents, 3);
      expect(
        store.straps.map((s) => s.name),
        containsAll(['leather', 'rubber']),
      );
      expect(store.straps.singleWhere((s) => s.id == 'same').name, 'leather');
      expect(store.strapSwaps.single.note, 'test fit');
      expect(store.servicesFor('w-1').single.description, 'overhaul');
      final parked = await fixture.service.fetchConflicts();
      expect(parked, hasLength(1));
      expect(await fixture.service.restoreConflictAsNew(parked.single), isTrue);
      expect(store.straps.map((s) => s.name), contains('nato'));
      expect(
        await fixture.service.restoreConflictAsNew({
          'doc': 'strap_swaps.json',
          'item': swap.toJson(),
        }),
        isTrue,
      );
      expect(
        await fixture.service.restoreConflictAsNew({
          'doc': 'watch_services.json',
          'item': serviceLog.toJson(),
        }),
        isTrue,
      );
      expect(store.strapSwaps, hasLength(2));
      expect(store.servicesFor('w-1'), hasLength(2));
    },
  );

  test(
    'older backup schemas do not erase documents they do not contain',
    () async {
      final fixture = await _fixture();
      await fixture.watches.addStrap(name: 'kept strap');
      final result = await fixture.service.mergeBackup({
        'schemaVersion': 2,
        'app': 'daydeck',
        'tasks': [],
      });
      expect(result.records, 0);
      expect(result.documents, 0);
      expect(fixture.watches.straps.single.name, 'kept strap');
    },
  );
}
