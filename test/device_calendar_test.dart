import 'package:flutter_test/flutter_test.dart';

import 'package:daydeck/data/device_calendar.dart';
import 'package:daydeck/data/ics.dart';

DateTime _t(int y, int mo, int d, int h, int mi) => DateTime(y, mo, d, h, mi);

CalendarEventItem _ev(String title, DateTime start, {bool allDay = false, String? location}) =>
    CalendarEventItem(
      uid: 'test:$title:${start.millisecondsSinceEpoch}',
      title: title,
      start: start,
      end: start.add(const Duration(hours: 1)),
      allDay: allDay,
      location: location,
    );

void main() {
  test('same Google event via iCal and device collapses to one; device copy wins', () {
    final start = _t(2026, 11, 10, 14, 0);
    final ical = _ev('Team standup', start, location: 'room 2');
    final device = _ev('Team standup', start, location: 'room 2');
    final merged = mergeCalendarSources([ical], [device]);
    expect(merged.length, 1);
    expect(merged.first.uid, device.uid);
  });

  test('title punctuation/skew and 10-minute bucket tolerate feed drift', () {
    final ical = _ev('Team  standup!', _t(2026, 11, 10, 14, 4));
    final device = _ev('team standup', _t(2026, 11, 10, 14, 7));
    final merged = mergeCalendarSources([ical], [device]);
    expect(merged.length, 1);
    expect(merged.first.title, 'team standup');
  });

  test('different days or very different times both survive', () {
    final a = _ev('standup', _t(2026, 11, 10, 14, 0));
    final b = _ev('standup', _t(2026, 11, 11, 14, 0));
    final c = _ev('standup', _t(2026, 11, 10, 18, 0));
    expect(mergeCalendarSources([a, c], [b]).length, 3);
  });

  test('all-day events dedupe per day, sorted before timed', () {
    final ical = _ev('rego renewal', _t(2026, 11, 11, 0, 0), allDay: true);
    final device = _ev('rego renewal', _t(2026, 11, 11, 0, 0), allDay: true);
    final timed = _ev('gym', _t(2026, 11, 11, 7, 0));
    final merged = mergeCalendarSources([timed, ical], [device]);
    expect(merged.length, 2);
    expect(merged.first.allDay, isTrue);
    expect(merged.last.title, 'gym');
  });
}
