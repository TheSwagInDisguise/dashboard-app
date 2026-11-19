import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daydeck/models/habit.dart';
import 'package:daydeck/models/watch.dart';
import 'package:daydeck/state/watch_store.dart';

int _epoch(DateTime date) =>
    epochDayOf(DateTime(date.year, date.month, date.day));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'strap fitting displaces the old strap, logs swaps, and updates today wear',
    () async {
      final store = WatchStore();
      await store.load();
      final watch = await store.addWatch(brand: 'Seiko', model: 'SKX');
      final first = await store.addStrap(
        name: 'black rubber',
        material: 'rubber',
        widthMm: 22,
      );
      final second = await store.addStrap(
        name: 'blue nato',
        material: 'nato',
        widthMm: 22,
      );
      final wear = await store.logTodaysWear(watch.id);

      expect(await store.fitStrap(first.id, watch.id), isTrue);
      expect(store.wearLogFor(wear.id)?.strapId, first.id);
      expect(await store.fitStrap(second.id, watch.id), isTrue);
      expect(store.strapOnWatch(watch.id)?.id, second.id);
      expect(store.straps.singleWhere((s) => s.id == first.id).watchId, isNull);
      expect(store.wearLogFor(wear.id)?.strapId, second.id);
      expect(store.strapSwaps, hasLength(3));
      expect(
        store.snapshotStraps().map((s) => Strap.fromJson(s.toJson()).name),
        contains('blue nato'),
      );
    },
  );

  test(
    'rotation suggestion favours the least recently worn eligible watch',
    () async {
      final store = WatchStore();
      await store.load();
      final worn = await store.addWatch(brand: 'A', model: 'worn');
      final fresh = await store.addWatch(brand: 'B', model: 'fresh');
      await store.addWearRaw(
        watchId: worn.id,
        day: _epoch(DateTime.now().subtract(const Duration(days: 1))),
      );
      expect(store.nextSuggestion?.id, fresh.id);
      expect(
        store.nextSuggestionReason(store.nextSuggestion!),
        'never worn yet',
      );
    },
  );

  test('service interval computes due date and a service entry can move it forward', () async {
    final store = WatchStore();
    await store.load();
    final today = DateTime.now();
    final oldPurchase = DateTime(today.year - 3, today.month, today.day);
    final watch = await store.addWatch(
      brand: 'Omega',
      model: 'test',
      serviceIntervalMonths: 12,
      purchaseDay: _epoch(oldPurchase),
    );
    expect(store.serviceIsDue(watch), isTrue);
    final nextDue = DateTime(today.year + 1, today.month, today.day);
    await store.logService(
      watchId: watch.id,
      date: today,
      description: 'full service',
      nextDue: nextDue,
    );
    expect(
      store.nextServiceDue(watch),
      DateTime(nextDue.year, nextDue.month, nextDue.day),
    );
    expect(store.serviceIsDue(watch), isFalse);
    expect(store.servicesFor(watch.id).single.description, 'full service');
  });
}
