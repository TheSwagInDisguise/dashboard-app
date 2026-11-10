import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/demo_data.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/section_header.dart';
import '../widgets/terminal_chip.dart';

/// The terminal-styled "Today" dashboard. Phase 1 ships it with clearly
/// labelled sample data; Phases 2–6 wire in real tasks, calendar and sync.
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
    final p = app.palette;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final week = ((dayOfYear + DateTime(now.year, 1, 1).weekday - 2) / 7).floor() + 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusStrip(palette: p),
          const SizedBox(height: 10),
          _HeaderRow(
            palette: p,
            dateLine:
                '${_weekdays[now.weekday - 1]} ${now.day.toString().padLeft(2, '0')} ${_months[now.month - 1]} ${now.year}',
            metaLine: 'week ${week.clamp(1, 53)} · day $dayOfYear',
          ),
          const SizedBox(height: 14),

          // ---------- CALENDAR ----------
          SectionHeader(palette: p, title: 'CALENDAR', trailing: 'sample'),
          const SizedBox(height: 8),
          _Card(
            palette: p,
            children: [
              for (final event in kDemoEvents) ...[
                if (event != kDemoEvents.first) _Rule(palette: p),
                _EventRow(palette: p, event: event),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // ---------- TASKS ----------
          SectionHeader(palette: p, title: 'TASKS', trailing: '3 open · 1 done'),
          const SizedBox(height: 8),
          _Card(
            palette: p,
            children: [
              for (final task in kDemoTasks) ...[
                if (task != kDemoTasks.first) _Rule(palette: p),
                _TaskRow(palette: p, task: task),
              ],
              const SizedBox(height: 2),
              _AddTaskGhostRow(palette: p),
            ],
          ),
          const SizedBox(height: 14),

          // ---------- HABITS ----------
          SectionHeader(palette: p, title: 'HABITS', trailing: 'today'),
          const SizedBox(height: 8),
          _Card(
            palette: p,
            children: [
              for (final habit in kDemoHabits) ...[
                if (habit != kDemoHabits.first) _Rule(palette: p),
                _HabitRow(palette: p, habit: habit),
              ],
            ],
          ),
          const SizedBox(height: 12),

          Text(
            'sample data — tasks, calendar & sync land in Phases 2–6',
            textAlign: TextAlign.center,
            style: mono(context, size: 9, color: p.dim.withValues(alpha: 0.75), letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.palette});

  final TerminalPalette palette;

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
          Row(
            children: [
              Text('●', style: mono(context, size: 10, color: palette.good)),
              const SizedBox(width: 6),
              Text('local-first', style: mono(context, size: 10, color: palette.dim)),
            ],
          ),
          _LiveClock(palette: palette),
          Text('v0.1.0', style: mono(context, size: 10, color: palette.dim)),
        ],
      ),
    );
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
  const _HeaderRow({required this.palette, required this.dateLine, required this.metaLine});

  final TerminalPalette palette;
  final String dateLine;
  final String metaLine;

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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dateLine, style: mono(context, size: 11, weight: FontWeight.w600, color: palette.accent2)),
            const SizedBox(height: 2),
            Text(metaLine, style: mono(context, size: 10, color: palette.dim)),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.palette, required this.children});

  final TerminalPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) => Divider(color: palette.border, height: 14);
}

// ---------- calendar ----------

class _EventRow extends StatelessWidget {
  const _EventRow({required this.palette, required this.event});

  final TerminalPalette palette;
  final DemoEvent event;

  @override
  Widget build(BuildContext context) {
    final chip = switch (event.source) {
      DemoEventSource.gcal => TerminalChip(label: 'GCAL', color: palette.accent),
      DemoEventSource.sharedPending => TerminalChip(label: 'SHARED ⧗', color: palette.warn),
      DemoEventSource.local => TerminalChip(label: 'LOCAL', color: palette.dim),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            '${event.start}–${event.end}',
            style: mono(context, size: 10.5, weight: FontWeight.w600, color: palette.accent),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: TextStyle(color: palette.text, fontSize: 12.5, height: 1.35)),
              if (event.caption != null) ...[
                const SizedBox(height: 2),
                Text(event.caption!, style: mono(context, size: 9, color: palette.dim)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(padding: const EdgeInsets.only(top: 1), child: chip),
      ],
    );
  }
}

// ---------- tasks ----------

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.palette, required this.task});

  final TerminalPalette palette;
  final DemoTask task;

  Color _priorityColor() => switch (task.priority) {
        'P1' => palette.bad,
        'P2' => palette.warn,
        _ => palette.dim,
      };

  Color _dueColor() => switch (task.dueKind) {
        DemoDueKind.overdue => palette.bad,
        DemoDueKind.today => palette.warn,
        DemoDueKind.done => palette.dim,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.done ? '[x]' : '[ ]',
          style: mono(
            context,
            size: 13,
            weight: FontWeight.w700,
            color: task.done ? palette.good : palette.accent,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                style: TextStyle(
                  color: task.done ? palette.dim : palette.text,
                  fontSize: 12.5,
                  height: 1.35,
                  decoration: task.done ? TextDecoration.lineThrough : null,
                  decorationColor: palette.dim,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(task.dueLabel, style: mono(context, size: 9, color: _dueColor())),
                  const SizedBox(width: 8),
                  TerminalChip(label: task.priority, color: _priorityColor()),
                ],
              ),
            ],
          ),
        ),
      ],
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
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('tasks arrive in Phase 2 — local & offline')),
        );
      },
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

// ---------- habits ----------

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.palette, required this.habit});

  final TerminalPalette palette;
  final DemoHabit habit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(habit.name, style: TextStyle(color: palette.text, fontSize: 12.5)),
        ),
        // 7-day completion dots, Monday first
        Row(
          children: [
            for (final done in habit.week)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Text(
                  done ? '●' : '○',
                  style: mono(context, size: 10, color: done ? palette.good : palette.border),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${habit.streak}',
              style: mono(context, size: 15, weight: FontWeight.w700, color: palette.good),
            ),
            Text(
              'DAY STREAK',
              style: mono(context, size: 6.5, color: palette.dim, letterSpacing: 1.1),
            ),
          ],
        ),
      ],
    );
  }
}
