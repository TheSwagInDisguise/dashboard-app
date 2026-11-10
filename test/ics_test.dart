import 'package:flutter_test/flutter_test.dart';

import 'package:daydeck/data/ics.dart';

const _ics = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Test//EN
BEGIN:VEVENT
UID:uid-standup
DTSTAMP:20261101T000000Z
DTSTART:20261109T093000
DTEND:20261109T100000
SUMMARY:Weekly standup
LOCATION:Room 4
END:VEVENT
BEGIN:VEVENT
UID:uid-allday
DTSTART;VALUE=DATE:20261120
SUMMARY:Public holiday
END:VEVENT
BEGIN:VEVENT
UID:uid-folded
DTSTART:20261110T120000
SUMMARY:A very long event title that the feed
  happens to fold across two physical lines
END:VEVENT
BEGIN:VEVENT
UID:uid-zulu
DTSTART:20261112T010000Z
DTEND:20261112T020000Z
SUMMARY:Zulu time event
END:VEVENT
BEGIN:VEVENT
UID:uid-cancelled
DTSTART:20261113T090000
SUMMARY:Cancelled standup
STATUS:CANCELLED
END:VEVENT
END:VCALENDAR
''';

const _recurring = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:uid-daily
DTSTART:20261109T090000
DTEND:20261109T091500
SUMMARY:Daily thing
RRULE:FREQ=DAILY;COUNT=3
END:VEVENT
BEGIN:VEVENT
UID:uid-weekly
DTSTART:20261109T090000
DTEND:20261109T091500
SUMMARY:Weekly thing
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4
END:VEVENT
BEGIN:VEVENT
UID:uid-exdate
DTSTART:20261109T090000
DTEND:20261109T091500
SUMMARY:Skip me sometimes
RRULE:FREQ=DAILY;COUNT=3
EXDATE:20261110T090000
END:VEVENT
BEGIN:VEVENT
UID:uid-override
DTSTART:20261109T090000
DTEND:20261109T091500
SUMMARY:Regular instance
RRULE:FREQ=DAILY;COUNT=3
END:VEVENT
BEGIN:VEVENT
UID:uid-override
RECURRENCE-ID:20261110T090000
DTSTART:20261110T140000
DTEND:20261110T150000
SUMMARY:Special Tuesday
END:VEVENT
BEGIN:VEVENT
UID:uid-monthly
DTSTART:20261115T100000
DTEND:20261115T110000
SUMMARY:Monthly thing
RRULE:FREQ=MONTHLY;COUNT=3
END:VEVENT
END:VCALENDAR
''';

void main() {
  final windowStart = DateTime(2026, 11, 1);
  final windowEnd = DateTime(2027, 1, 31);

  test('parses timed, all-day, folded and UTC events', () {
    final events = expandEvents(parseIcs(_ics), windowStart, windowEnd).events;
    final byUid = {for (final e in events) e.uid: e};

    expect(byUid['uid-standup']!.title, 'Weekly standup');
    expect(byUid['uid-standup']!.location, 'Room 4');
    expect(byUid['uid-standup']!.start, DateTime(2026, 11, 9, 9, 30));
    expect(byUid['uid-standup']!.allDay, isFalse);

    expect(byUid['uid-allday']!.allDay, isTrue);
    expect(byUid['uid-allday']!.start.day, 20);

    expect(byUid['uid-folded']!.title,
        'A very long event title that the feed happens to fold across two physical lines');

    // 20261112T010000Z in UTC — must round-trip to the exact same instant.
    expect(byUid['uid-zulu']!.start.toUtc(), DateTime.utc(2026, 11, 12, 1, 0));

    expect(events.any((e) => e.uid == 'uid-cancelled'), isFalse);
  });

  test('DAILY with COUNT expands the exact number of occurrences', () {
    final events = expandEvents(parseIcs(_recurring), windowStart, windowEnd).events;
    final daily = events.where((e) => e.uid == 'uid-daily').toList();
    expect(daily, hasLength(3));
    expect(daily.map((e) => e.start.day), [9, 10, 11]);
  });

  test('WEEKLY with BYDAY only lands on the chosen weekdays', () {
    final events = expandEvents(parseIcs(_recurring), windowStart, windowEnd).events;
    final weekly = events.where((e) => e.uid == 'uid-weekly').toList();
    expect(weekly.map((e) => '${e.start.year}-${e.start.month}-${e.start.day}'),
        ['2026-11-9', '2026-11-11', '2026-11-16', '2026-11-18']);
  });

  test('EXDATE removes exactly one occurrence', () {
    final events = expandEvents(parseIcs(_recurring), windowStart, windowEnd).events;
    final ex = events.where((e) => e.uid == 'uid-exdate').toList();
    expect(ex.map((e) => e.start.day), [9, 11]);
  });

  test('RECURRENCE-ID overrides a single instance', () {
    final events = expandEvents(parseIcs(_recurring), windowStart, windowEnd).events;
    final override = events.where((e) => e.uid == 'uid-override').toList()..sort((a, b) => a.start.compareTo(b.start));
    expect(override.map((e) => e.title), ['Regular instance', 'Special Tuesday', 'Regular instance']);
    expect(override[1].start.hour, 14); // moved to 14:00
  });

  test('MONTHLY keeps the day-of-month across months', () {
    final events = expandEvents(parseIcs(_recurring), windowStart, windowEnd).events;
    final monthly = events.where((e) => e.uid == 'uid-monthly').toList();
    expect(monthly.map((e) => '${e.start.year}-${e.start.month}-${e.start.day}'),
        ['2026-11-15', '2026-12-15', '2027-1-15']);
  });

  test('window bounds are respected', () {
    final events = expandEvents(
      parseIcs(_recurring),
      DateTime(2026, 11, 10),
      DateTime(2026, 11, 12),
    ).events;
    final daily = events.where((e) => e.uid == 'uid-daily').toList();
    // Only the 10th and 11th inside the window.
    expect(daily.map((e) => e.start.day), [10, 11]);
  });
}
