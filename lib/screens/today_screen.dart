import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/calendar_feed.dart';
import '../models/event.dart';
import '../models/habit.dart';
import '../state/app_state.dart';
import '../state/event_store.dart';
import '../state/habit_store.dart';
import '../state/tasks_store.dart';
import '../sync/sync_service.dart';
import '../widgets/event_sheet.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import 'search_screen.dart';
import '../notifications/deep_links.dart';
import '../version.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/section_header.dart';
import '../widgets/task_row.dart';
import '../widgets/task_sheet.dart';
import '../widgets/terminal_card.dart';
import '../widgets/terminal_chip.dart';

/// The terminal-styled "Today" dashboard.
/// Everything is live: tasks, habits, local events and the read-only
/// Google Calendar feed (via Settings → CALENDAR).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final store = context.watch<TasksStore>();
    final events = context.watch<EventStore>();
    final habits = context.watch<HabitStore>();
    final feed = context.watch<CalendarFeed>();
    final p = app.palette;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final week = ((dayOfYear + DateTime(now.year, 1, 1).weekday - 2) / 7).floor() + 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusStrip(palette: p, count: store.openCount),
          const _SharedQueueDeepLinkHandler(),
          const SizedBox(height: 10),
          _HeaderRow(
            palette: p,
            onSearch: () => showDayDeckSearch(context),
            dateLine:
                '${_weekdays[now.weekday - 1]} ${now.day.toString().padLeft(2, '0')} ${_months[now.month - 1]} ${now.year}',
            metaLine: 'week ${week.clamp(1, 53)} · day $dayOfYear',
          ),
          const SizedBox(height: 6),
          _WeekStrip(palette: p, habits: context.watch<HabitStore>(), tasks: store),
          const SizedBox(height: 12),

          // ---------- two-pane on fold / tablet / wide screens ----------
          if (MediaQuery.sizeOf(context).width >= 700)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                                // ---------- CALENDAR (live) ----------
                                SectionHeader(palette: p, title: 'CALENDAR', trailing: _calendarTrailing(feed)),
                                const SizedBox(height: 8),
                                TerminalCard(
                                  palette: p,
                                  children: _buildCalendarRows(context, p, events, feed, now),
                                ),
                                if (_calendarNotes(feed).isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  for (final note in _calendarNotes(feed))
                                    Text('· $note', style: mono(context, size: 8.5, color: p.dim)),
                                ],
                                const SizedBox(height: 14),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                                // ---------- TASKS (live) ----------
                                SectionHeader(palette: p, title: 'TASKS', trailing: '${store.openCount} open'),
                                const SizedBox(height: 8),
                                TerminalCard(
                                  palette: p,
                                  children: [
                                    if (store.openTasks.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Text(
                                          '> no open tasks — slate clear.',
                                          textAlign: TextAlign.center,
                                          style: mono(context, size: 11, color: p.dim),
                                        ),
                                      )
                                    else ...[
                                      for (final task in store.openTasks.take(4)) ...[
                                        if (task != store.openTasks.take(4).first) TerminalCardRule(palette: p),
                                        TaskRow(
                                          palette: p,
                                          task: task,
                                          onToggle: () => store.toggleDone(task.id),
                                          onOpen: () => showTaskSheet(context, initial: task),
                                        ),
                                      ],
                                      if (store.openTasks.length > 4)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            '+ ${store.openTasks.length - 4} more in TASKS →',
                                            textAlign: TextAlign.center,
                                            style: mono(context, size: 9.5, color: p.dim),
                                          ),
                                        ),
                                    ],
                                    const SizedBox(height: 6),
                                    _AddTaskGhostRow(palette: p),
                                  ],
                                ),
                                const SizedBox(height: 14),
                      const SizedBox(height: 14),
                                // ---------- HABITS (live) ----------
                                SectionHeader(
                                  palette: p,
                                  title: 'HABITS',
                                  trailing: habits.habits.isEmpty ? 'none yet' : '${habits.habits.where((h) => habits.doneToday(h.id)).length}/${habits.habits.length} today',
                                ),
                                const SizedBox(height: 8),
                                TerminalCard(
                                  palette: p,
                                  children: habits.habits.isEmpty
                                      ? [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            child: Column(
                                              children: [
                                                Text(
                                                  '> no habits yet — streaks start with one tiny daily thing.',
                                                  textAlign: TextAlign.center,
                                                  style: mono(context, size: 10.5, color: p.dim),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'add your first habit in the HABITS tab →',
                                                  textAlign: TextAlign.center,
                                                  style: mono(context, size: 10.5, weight: FontWeight.w600, color: p.accent),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ]
                                      : [
                                          for (final habit in habits.habits.take(4)) ...[
                                            if (habit != habits.habits.take(4).first) TerminalCardRule(palette: p),
                                            _HabitRow(
                                              palette: p,
                                              habit: habit,
                                              doneToday: habits.doneToday(habit.id),
                                              streak: habits.currentStreak(habit),
                                              onToggle: () => habits.toggleOn(habit.id),
                                            ),
                                          ],
                                          if (habits.habits.length > 4)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Text(
                                                '+ ${habits.habits.length - 4} more in HABITS →',
                                                textAlign: TextAlign.center,
                                                style: mono(context, size: 9.5, color: p.dim),
                                              ),
                                            ),
                                        ],
                                ),
                    ],
                  ),
                ),
              ],
            )
          else ...[
          // ---------- CALENDAR (live) ----------
          SectionHeader(palette: p, title: 'CALENDAR', trailing: _calendarTrailing(feed)),
          const SizedBox(height: 8),
          TerminalCard(
            palette: p,
            children: _buildCalendarRows(context, p, events, feed, now),
          ),
          if (_calendarNotes(feed).isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final note in _calendarNotes(feed))
              Text('· $note', style: mono(context, size: 8.5, color: p.dim)),
          ],
          const SizedBox(height: 14),
          // ---------- TASKS (live) ----------
          SectionHeader(palette: p, title: 'TASKS', trailing: '${store.openCount} open'),
          const SizedBox(height: 8),
          TerminalCard(
            palette: p,
            children: [
              if (store.openTasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '> no open tasks — slate clear.',
                    textAlign: TextAlign.center,
                    style: mono(context, size: 11, color: p.dim),
                  ),
                )
              else ...[
                for (final task in store.openTasks.take(4)) ...[
                  if (task != store.openTasks.take(4).first) TerminalCardRule(palette: p),
                  TaskRow(
                    palette: p,
                    task: task,
                    onToggle: () => store.toggleDone(task.id),
                    onOpen: () => showTaskSheet(context, initial: task),
                  ),
                ],
                if (store.openTasks.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+ ${store.openTasks.length - 4} more in TASKS →',
                      textAlign: TextAlign.center,
                      style: mono(context, size: 9.5, color: p.dim),
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              _AddTaskGhostRow(palette: p),
            ],
          ),
          const SizedBox(height: 14),
          // ---------- HABITS (live) ----------
          SectionHeader(
            palette: p,
            title: 'HABITS',
            trailing: habits.habits.isEmpty ? 'none yet' : '${habits.habits.where((h) => habits.doneToday(h.id)).length}/${habits.habits.length} today',
          ),
          const SizedBox(height: 8),
          TerminalCard(
            palette: p,
            children: habits.habits.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          Text(
                            '> no habits yet — streaks start with one tiny daily thing.',
                            textAlign: TextAlign.center,
                            style: mono(context, size: 10.5, color: p.dim),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'add your first habit in the HABITS tab →',
                            textAlign: TextAlign.center,
                            style: mono(context, size: 10.5, weight: FontWeight.w600, color: p.accent),
                          ),
                        ],
                      ),
                    ),
                  ]
                : [
                    for (final habit in habits.habits.take(4)) ...[
                      if (habit != habits.habits.take(4).first) TerminalCardRule(palette: p),
                      _HabitRow(
                        palette: p,
                        habit: habit,
                        doneToday: habits.doneToday(habit.id),
                        streak: habits.currentStreak(habit),
                        onToggle: () => habits.toggleOn(habit.id),
                      ),
                    ],
                    if (habits.habits.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '+ ${habits.habits.length - 4} more in HABITS →',
                          textAlign: TextAlign.center,
                          style: mono(context, size: 9.5, color: p.dim),
                        ),
                      ),
                  ],
          ),
          ],
          const SizedBox(height: 12),

          Text(
            'everything here is live · calendar is read-only from Google',
            textAlign: TextAlign.center,
            style: mono(context, size: 9, color: p.dim.withValues(alpha: 0.75), letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}


// ---------- calendar helpers ----------

String _calendarTrailing(CalendarFeed feed) {
  switch (feed.status) {
    case CalendarStatus.disabled:
      return 'not connected';
    case CalendarStatus.fetching:
      return 'refreshing…';
    case CalendarStatus.error:
      return 'offline';
    case CalendarStatus.ok:
      final t = feed.lastFetched;
      if (t == null) return 'ok';
      return '⇡ ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

List<String> _calendarNotes(CalendarFeed feed) {
  final notes = [...feed.notes];
  if (feed.status == CalendarStatus.error && feed.lastError != null) {
    notes.insert(0, feed.lastError!);
  }
  return notes;
}

List<Widget> _buildCalendarRows(BuildContext context, TerminalPalette p, EventStore eventStore, CalendarFeed feed, DateTime now) {
  final gcalToday = feed.events.where((e) => _isSameDay(e.start.toLocal(), now)).toList();
  final localToday = eventStore.forDay(now);
  final pendingShared = eventStore.sharedPending();
  final hiddenShared = pendingShared.where((e) => !_isSameDay(e.start.toLocal(), now)).toList();

  final rows = <Widget>[];

  void gap() {
    if (rows.isNotEmpty) rows.add(TerminalCardRule(palette: p));
  }

  if (gcalToday.isEmpty && localToday.isEmpty) {
    final message = switch (feed.status) {
      CalendarStatus.disabled => '> no calendar connected yet — Settings → CALENDAR holds the 2-minute guide.',
      CalendarStatus.fetching => '> asking Google for today’s schedule…',
      CalendarStatus.error => '> couldn’t reach your calendar — showing what we know.',
      CalendarStatus.ok => '> nothing scheduled today — go touch grass.',
    };
    rows.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: mono(context, size: 10.5, color: p.dim),
      ),
    ));
  } else {
    for (final event in gcalToday) {
      gap();
      rows.add(_TimelineRow(
        palette: p,
        timeLabel: _timeRange(event.start.toLocal(), event.end.toLocal(), event.allDay),
        title: event.title,
        caption: event.allDay ? 'all day · google calendar' : 'google calendar${event.location != null ? ' · ${event.location}' : ''}',
        chip: TerminalChip(label: 'GCAL', color: p.accent),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('from Google Calendar — edit it there, not here')),
        ),
      ));
    }
    for (final event in localToday) {
      gap();
      rows.add(_LocalEventRow(
        palette: p,
        event: event,
        onEdit: () => showEventSheet(context, initial: event),
      ));
    }
  }

  // Shared queue — pending shared events parked on other days.
  if (hiddenShared.isNotEmpty) {
    gap();
    rows.add(_SharedQueueRow(palette: p, pending: hiddenShared, eventStore: eventStore));
  }

  // Add + refresh affordances.
  gap();
  rows.add(_AddEventRow(palette: p, onTap: () => showEventSheet(context)));
  gap();
  rows.add(_RefreshCalendarRow(palette: p, onTap: () => context.read<CalendarFeed>().refresh()));

  return rows;
}

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _timeRange(DateTime start, DateTime end, bool allDay) {
  if (allDay) return 'ALL-DAY';
  String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return '${hm(start)}–${hm(end)}';
}

// ===========================================================================


class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.palette, required this.count});

  final TerminalPalette palette;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SyncIndicator(palette: palette),
          _LiveClock(palette: palette),
          Text('v$kAppVersion', style: mono(context, size: 10, color: palette.dim)),
        ],
      ),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final (color, label, tip) = switch (sync.status) {
      SyncStatus.disabled => (palette.dim, 'local · no sync', 'no token set — everything stays on this device'),
      SyncStatus.idle => (palette.accent, '⇡ pending…', 'waiting for first sync'),
      SyncStatus.syncing => (palette.accent, '⇡ syncing…', 'talking to GitHub'),
      SyncStatus.ok => (palette.good, '⇡ ${_fmt(sync.lastSyncedAt)}', 'synced with dashboard-data — you are good'),
      SyncStatus.tokenInvalid => (palette.bad, '⚠ sync paused', 'GitHub rejected your token — Settings → SYNC'),
      SyncStatus.error => (palette.warn, '⇡ offline', 'could not reach GitHub — will retry automatically'),
    };

    return InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip))),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            Text('●', style: mono(context, size: 10, color: color)),
            const SizedBox(width: 6),
            Text(label, style: mono(context, size: 10, color: color)),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime? time) {
    if (time == null) return 'synced';
    final t = time.toLocal();
    return 'synced ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _LiveClock extends StatefulWidget {
  const _LiveClock({required this.palette});

  final TerminalPalette palette;

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    return Text(label, style: mono(context, size: 11, weight: FontWeight.w600, color: widget.palette.text));
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.palette, required this.dateLine, required this.metaLine, required this.onSearch});

  final TerminalPalette palette;
  final String dateLine;
  final String metaLine;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('day', style: mono(context, size: 24, weight: FontWeight.w700, color: palette.text, letterSpacing: 3)),
            Text('deck', style: mono(context, size: 24, weight: FontWeight.w700, color: palette.accent, letterSpacing: 3)),
            const SizedBox(width: 7),
            BlinkingCursor(color: palette.accent),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(dateLine, style: mono(context, size: 11, weight: FontWeight.w600, color: palette.accent2)),
                const SizedBox(height: 2),
                Text(metaLine, style: mono(context, size: 10, color: palette.dim)),
              ],
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: Icon(Icons.search, color: palette.dim, size: 20),
              tooltip: 'search',
              onPressed: onSearch,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            ),
          ],
        ),
      ],
    );
  }
}

/// One dim line: this week's habit hit rate + tasks completed in the last 7 days.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.palette, required this.habits, required this.tasks});

  final TerminalPalette palette;
  final HabitStore habits;
  final TasksStore tasks;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final dailyHabits = habits.habits.where((h) => h.cadence == 'daily').toList();
    int habitChecks = 0;
    for (final h in dailyHabits) {
      habitChecks += habits.thisWeekDots(h).where((d) => d).length;
    }
    final habitPct = dailyHabits.isEmpty ? null : (habitChecks * 100 / (7 * dailyHabits.length)).round();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final doneThisWeek = tasks.doneTasks.where((t) => t.updatedAt.isAfter(weekAgo)).length;

    final parts = <String>[];
    if (habitPct != null) parts.add('habits $habitPct%');
    parts.add('$doneThisWeek task${doneThisWeek == 1 ? '' : 's'} done');

    return Center(
      child: Text(
        'this week · ${parts.join(' · ')}',
        style: mono(context, size: 9, color: p.dim.withValues(alpha: 0.85), letterSpacing: 0.5),
      ),
    );
  }
}

// ---------- calendar ----------

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.palette,
    required this.timeLabel,
    required this.title,
    required this.chip,
    this.caption,
    this.onTap,
    this.trailing,
  });

  final TerminalPalette palette;
  final String timeLabel;
  final String title;
  final String? caption;
  final TerminalChip chip;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              timeLabel,
              style: mono(context, size: 10.5, weight: FontWeight.w600, color: palette.accent),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: palette.text, fontSize: 12.5, height: 1.35)),
                if (caption != null && caption!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: mono(context, size: 9, color: palette.dim)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          ?trailing,
          const SizedBox(width: 4),
          Padding(padding: const EdgeInsets.only(top: 1), child: chip),
        ],
      ),
    );
  }
}

class _LocalEventRow extends StatelessWidget {
  const _LocalEventRow({required this.palette, required this.event, required this.onEdit});

  final TerminalPalette palette;
  final Event event;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final timeLabel = _timeRange(event.start.toLocal(), event.end.toLocal(), event.allDay);
    final captionParts = <String>[
      'local · you added it in the app',
      if (event.location != null && event.location!.isNotEmpty) event.location!,
    ];
    final shared = event.isShared;

    return _TimelineRow(
      palette: palette,
      timeLabel: timeLabel,
      title: event.title,
      caption: captionParts.join(' · '),
      chip: TerminalChip(
        label: shared ? 'SHARED ⧗' : 'LOCAL',
        color: shared ? palette.warn : palette.dim,
      ),
      onTap: onEdit,
      trailing: shared
          ? IconButton(
              icon: Icon(Icons.check_circle_outline, size: 21, color: palette.warn),
              tooltip: 'mark: it’s in Google Calendar',
              onPressed: () async {
                final store = context.read<EventStore>();
                await store.toggleDone(event.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('marked — it’s in Google Calendar ✓')),
                  );
                }
              },
            )
          : null,
    );
  }
}

/// One-line nudge for shared events parked on other days. Tap to mark them
/// all done, or long-press to open the sheet for each.
class _SharedQueueRow extends StatelessWidget {
  const _SharedQueueRow({required this.palette, required this.pending, required this.eventStore});

  final TerminalPalette palette;
  final List<Event> pending;
  final EventStore eventStore;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showSharedQueueDialog(context, pending, eventStore),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Text('⧗', style: mono(context, size: 11, color: palette.warn)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'SHARED QUEUE · ${pending.length} not yet in Google Calendar',
              style: mono(context, size: 9.5, weight: FontWeight.w600, color: palette.warn, letterSpacing: 0.6),
            ),
          ),
          Text('tap →', style: mono(context, size: 9, color: palette.dim)),
        ],
      ),
    );
  }
}

class _AddEventRow extends StatelessWidget {
  const _AddEventRow({required this.palette, required this.onTap});

  final TerminalPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 3, top: 2, bottom: 2),
        child: Row(
          children: [
            Text('+', style: mono(context, size: 12, weight: FontWeight.w700, color: palette.accent)),
            const SizedBox(width: 9),
            Text('add event…', style: mono(context, size: 11, color: palette.dim)),
          ],
        ),
      ),
    );
  }
}

class _RefreshCalendarRow extends StatelessWidget {
  const _RefreshCalendarRow({required this.palette, required this.onTap});

  final TerminalPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<CalendarFeed>();
    final label = switch (feed.status) {
      CalendarStatus.fetching => 'refreshing the calendar…',
      CalendarStatus.error => 'tap to retry the calendar',
      _ => 'tap to refresh the calendar',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: feed.status == CalendarStatus.fetching ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 3, top: 2, bottom: 2),
        child: Row(
          children: [
            Icon(Icons.refresh, size: 12, color: palette.dim),
            const SizedBox(width: 9),
            Text(label, style: mono(context, size: 9.5, color: palette.dim)),
          ],
        ),
      ),
    );
  }
}

// ---------- habits ----------

class _HabitRow extends StatelessWidget {
  const _HabitRow({
    required this.palette,
    required this.habit,
    required this.doneToday,
    required this.streak,
    required this.onToggle,
  });

  final TerminalPalette palette;
  final Habit habit;
  final bool doneToday;
  final int streak;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(
            doneToday ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 21,
            color: doneToday ? palette.good : palette.dim,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              habit.title,
              style: TextStyle(
                color: doneToday ? palette.dim : palette.text,
                fontSize: 12.5,
                decoration: doneToday ? TextDecoration.lineThrough : null,
                decorationColor: palette.dim,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$streak',
            style: mono(context, size: 15, weight: FontWeight.w700, color: streak > 0 ? palette.good : palette.dim),
          ),
          const SizedBox(width: 4),
          Text(
            habit.cadence == 'weekly' ? 'WK' : 'DAY',
            style: mono(context, size: 7.5, color: palette.dim, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

class _AddTaskGhostRow extends StatelessWidget {
  const _AddTaskGhostRow({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showTaskSheet(context),
      child: Padding(
        padding: const EdgeInsets.only(left: 3, top: 2, bottom: 2),
        child: Row(
          children: [
            Text('+', style: mono(context, size: 12, weight: FontWeight.w700, color: palette.accent)),
            const SizedBox(width: 9),
            Text('add task…', style: mono(context, size: 11, color: palette.dim)),
          ],
        ),
      ),
    );
  }
}


/// Tap-to-open dialog listing SHARED events parked on other days.
/// Used by the queue row and by the evening notification deep link.
Future<void> showSharedQueueDialog(BuildContext context, List<Event> pending, EventStore eventStore) {
  final p = context.read<AppState>().palette;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('SHARED QUEUE · ${pending.length}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final event in pending)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${event.title}  ·  ${event.start.toLocal().day.toString().padLeft(2, '0')}/${event.start.toLocal().month.toString().padLeft(2, '0')}',
                        style: TextStyle(color: p.text, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await eventStore.toggleDone(event.id);
                        if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                      },
                      child: Text('IN GCAL ✓', style: mono(ctx, size: 9.5, weight: FontWeight.w700, color: p.good)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'anything marked here (or spotted in the Google feed automatically) disappears from your day.',
              style: TextStyle(color: p.dim, fontSize: 9.5, height: 1.5),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('close'))],
    ),
  );
}

/// Fires the SHARED QUEUE dialog when a deep link asks for it (evening
/// notification tap). Invisible; lives inside the Today screen.
class _SharedQueueDeepLinkHandler extends StatefulWidget {
  const _SharedQueueDeepLinkHandler();

  @override
  State<_SharedQueueDeepLinkHandler> createState() => _SharedQueueDeepLinkHandlerState();
}

class _SharedQueueDeepLinkHandlerState extends State<_SharedQueueDeepLinkHandler> {
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _seen = DeepLinks.sharedQueueRequests.value;
    DeepLinks.sharedQueueRequests.addListener(_maybeOpen);
    if (_seen > 0) _maybeOpen(); // requested before this screen mounted
  }

  @override
  void dispose() {
    DeepLinks.sharedQueueRequests.removeListener(_maybeOpen);
    super.dispose();
  }

  void _maybeOpen() {
    final requested = DeepLinks.sharedQueueRequests.value;
    if (requested == _seen) return;
    _seen = requested;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<EventStore>();
      final now = DateTime.now();
      final pending = store
          .sharedPending()
          .where((e) => !_isSameDay(e.start.toLocal(), now))
          .toList();
      if (pending.isNotEmpty) {
        unawaited(showSharedQueueDialog(context, pending, store));
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
