// Static sample content for screens whose real data lands later
// (calendar in Phase 4, habits in Phase 6). Tasks are already live —
// see lib/state/tasks_store.dart.
//
// The sample rows intentionally include one "shared, pending sync" event so
// the queue behaviour is visible in previews.

enum DemoEventSource { gcal, sharedPending, local }

class DemoEvent {
  const DemoEvent({
    required this.start,
    required this.end,
    required this.title,
    required this.source,
    this.caption,
  });

  final String start;
  final String end;
  final String title;
  final DemoEventSource source;
  final String? caption;
}

const List<DemoEvent> kDemoEvents = [
  DemoEvent(
    start: '09:30',
    end: '10:00',
    title: 'Weekly standup',
    source: DemoEventSource.gcal,
    caption: 'google calendar',
  ),
  DemoEvent(
    start: '12:15',
    end: '12:45',
    title: 'Lunch with Sam',
    source: DemoEventSource.gcal,
    caption: 'google calendar',
  ),
  DemoEvent(
    start: '17:30',
    end: '18:30',
    title: "Dinner — Nonna's",
    source: DemoEventSource.sharedPending,
    caption: 'queued for Google Calendar — not sent yet',
  ),
  DemoEvent(
    start: '20:00',
    end: '20:30',
    title: 'Read before bed',
    source: DemoEventSource.local,
    caption: 'private — stays in the app',
  ),
];

class DemoHabit {
  const DemoHabit({
    required this.name,
    required this.week,
    required this.streak,
  });

  final String name;

  /// Last 7 days, Monday first. true = done.
  final List<bool> week;
  final int streak;
}

const List<DemoHabit> kDemoHabits = [
  DemoHabit(name: 'Move 20 min', week: [true, true, true, true, true, false, false], streak: 34),
  DemoHabit(name: 'Read 10 min', week: [true, true, true, true, false, true, false], streak: 5),
  DemoHabit(name: 'No sugar after 8pm', week: [true, true, true, true, true, true, true], streak: 12),
];
