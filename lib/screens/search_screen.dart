import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/calendar_feed.dart';
import '../data/ics.dart';
import '../models/event.dart';
import '../models/habit.dart';
import '../models/task.dart';
import '../state/app_state.dart';
import '../state/event_store.dart';
import '../state/habit_store.dart';
import '../state/tasks_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../utils/dates.dart';
import '../widgets/task_sheet.dart';

/// Opens the full-screen search across everything the app knows about:
/// tasks, local events, the cached Google Calendar feed and habits.
/// Read-only except for tasks (tap to edit) and habits (tap to toggle today).
Future<void> showDayDeckSearch(BuildContext context) {
  return showSearch<void>(
    context: context,
    delegate: _DayDeckSearchDelegate(),
  );
}

class _DayDeckSearchDelegate extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => 'search tasks, events, habits…';

  @override
  TextStyle? get searchFieldStyle => const TextStyle(fontSize: 16);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          tooltip: 'clear',
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'back',
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _resultsView(context);

  @override
  Widget buildSuggestions(BuildContext context) => _resultsView(context);

  Widget _resultsView(BuildContext context) {
    final store = context.watch<TasksStore>();
    final events = context.watch<EventStore>();
    final habits = context.watch<HabitStore>();
    final feed = context.watch<CalendarFeed>();
    final p = context.watch<AppState>().palette;

    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return _hint(context, p, 'type to search — tasks, events, calendar, habits');
    }

    final taskHits = store.openTasks
        .where((t) => t.title.toLowerCase().contains(q))
        .take(8)
        .toList();
    final doneHits = store.doneTasks
        .where((t) => t.title.toLowerCase().contains(q))
        .take(3)
        .toList();
    final localEvents = events.alive
        .where((e) => _eventMatch(e, q))
        .take(8)
        .toList();
    final gcalHits = feed.events
        .where((e) => _feedMatch(e, q))
        .take(8)
        .toList();
    final habitHits = habits.habits
        .where((h) => h.title.toLowerCase().contains(q))
        .take(8)
        .toList();

    final hasAnything = taskHits.isNotEmpty ||
        doneHits.isNotEmpty ||
        localEvents.isNotEmpty ||
        gcalHits.isNotEmpty ||
        habitHits.isNotEmpty;

    if (!hasAnything) {
      return _hint(context, p, 'nothing matches “$q”');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        if (taskHits.isNotEmpty || doneHits.isNotEmpty) ...[
          _section(context, p, 'TASKS · ${taskHits.length + doneHits.length}'),
          for (final t in taskHits) _TaskHit(palette: p, task: t),
          for (final t in doneHits) _TaskHit(palette: p, task: t, done: true),
          const SizedBox(height: 10),
        ],
        if (localEvents.isNotEmpty) ...[
          _section(context, p, 'EVENTS · ${localEvents.length}'),
          for (final e in localEvents) _LocalEventHit(palette: p, event: e),
          const SizedBox(height: 10),
        ],
        if (gcalHits.isNotEmpty) ...[
          _section(context, p, 'GOOGLE CALENDAR · ${gcalHits.length}'),
          for (final e in gcalHits) _GcalHit(palette: p, item: e),
          const SizedBox(height: 10),
        ],
        if (habitHits.isNotEmpty) ...[
          _section(context, p, 'HABITS · ${habitHits.length}'),
          for (final h in habitHits) _HabitHit(palette: p, habit: h),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  bool _eventMatch(Event e, String q) =>
      e.title.toLowerCase().contains(q) ||
      (e.location ?? '').toLowerCase().contains(q) ||
      (e.notes ?? '').toLowerCase().contains(q);

  bool _feedMatch(CalendarEventItem e, String q) =>
      e.title.toLowerCase().contains(q) ||
      (e.location ?? '').toLowerCase().contains(q) ||
      (e.notes ?? '').toLowerCase().contains(q);

  Widget _hint(BuildContext context, TerminalPalette p, String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: mono(context, size: 11, color: p.dim, letterSpacing: 0.4),
      ),
    );
  }

  Widget _section(BuildContext context, TerminalPalette p, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Text(title, style: mono(context, size: 9.5, color: p.dim, letterSpacing: 2)),
    );
  }
}

class _TaskHit extends StatelessWidget {
  const _TaskHit({required this.palette, required this.task, this.done = false});

  final TerminalPalette palette;
  final Task task;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return InkWell(
      onTap: () => showTaskSheet(context, initial: task),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Icon(done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                size: 16, color: done ? p.good : p.dim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: done ? p.dim : p.text,
                  fontSize: 13,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (task.dueDate != null) ...[
              const SizedBox(width: 8),
              Text(
                'due ${_shortDate(task.dueDate!)}',
                style: mono(context, size: 9, color: p.warn),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocalEventHit extends StatelessWidget {
  const _LocalEventHit({required this.palette, required this.event});

  final TerminalPalette palette;
  final Event event;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.event_note_outlined, size: 16, color: event.isShared ? p.accent2 : p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: TextStyle(color: p.text, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${event.isShared ? 'shared · ' : ''}${_fmtDateTime(context, event.start, event.allDay)}',
                  style: mono(context, size: 8.5, color: p.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GcalHit extends StatelessWidget {
  const _GcalHit({required this.palette, required this.item});

  final TerminalPalette palette;
  final CalendarEventItem item;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_outlined, size: 16, color: p.dim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: TextStyle(color: p.text, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  'google · read-only · ${_fmtDateTime(context, item.start, item.allDay)}',
                  style: mono(context, size: 8.5, color: p.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitHit extends StatelessWidget {
  const _HabitHit({required this.palette, required this.habit});

  final TerminalPalette palette;
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final store = context.watch<HabitStore>();
    final doneToday = store.doneToday(habit.id);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await store.toggleOn(habit.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(doneToday ? 'unchecked for today' : 'checked off today ✓')),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Icon(doneToday ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16, color: doneToday ? p.good : p.dim),
            const SizedBox(width: 10),
            Expanded(child: Text(habit.title, style: TextStyle(color: p.text, fontSize: 13))),
            Text(doneToday ? 'done today' : 'tap to check today',
                style: mono(context, size: 8.5, color: doneToday ? p.good : p.dim)),
          ],
        ),
      ),
    );
  }
}

String _shortDate(String key) {
  final d = parseDateKey(key);
  if (d == null) return key;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

String _fmtDateTime(BuildContext context, DateTime start, bool allDay) {
  // Local time, DD/MM/YYYY, 24h — matches the rest of the app.
  final local = start.toLocal();
  final base =
      '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  if (allDay) return '$base · all day';
  return '$base · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
