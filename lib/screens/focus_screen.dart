import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/focus_session.dart';
import '../models/habit.dart';
import '../state/app_state.dart';
import '../state/focus_store.dart';
import '../state/habit_store.dart';
import '../state/pomodoro_timer.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../widgets/terminal_card.dart';

/// FOCUS — the cockpit for the pomodoro/stopwatch. Countdown focus phases
/// auto-schedule a break, credit minutes to the bound habit on finish and
/// (Android, when enabled) hold DND for the phase.
class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final timer = context.watch<PomodoroTimer>();
    final store = context.watch<FocusStore>();
    final habitStore = context.watch<HabitStore>();
    final phase = timer.phase;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Text(
              '// FOCUS',
              style: mono(context, size: 24, weight: FontWeight.w700, color: p.accent, letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'deep work, one phase at a time',
              style: mono(context, size: 9.5, color: p.dim, letterSpacing: 2.4),
            ),
          ),
          const SizedBox(height: 20),
          if (phase == PomPhase.idle) _IdlePane(palette: p) else _ActivePane(palette: p, timer: timer),
          const SizedBox(height: 18),
          _TodaySummary(palette: p, store: store),
          const SizedBox(height: 14),
          SectionHeader(palette: p, title: 'HEATMAP', trailing: 'last 26 weeks'),
          const SizedBox(height: 8),
          _FocusHeatmap(palette: p, store: store),
          const SizedBox(height: 14),
          SectionHeader(
            palette: p,
            title: 'RECENT SESSIONS',
            trailing: '${store.totalSessions} total · ${store.totalFocusMinutes}m',
          ),
          const SizedBox(height: 8),
          _RecentSessions(palette: p, store: store, habitStore: habitStore),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- idle pane

class _IdlePane extends StatelessWidget {
  const _IdlePane({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final app = context.watch<AppState>();
    final habits = context.watch<HabitStore>();
    final timer = context.read<PomodoroTimer>();
    final timerHabits = habits.habits.where((h) => h.type == HabitType.timer).toList();
    final focusMinutes = app.focusDefaultMinutes;
    final breakMinutes = app.breakDefaultMinutes;

    return TerminalCard(
      palette: p,
      children: [
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PhaseDigits(palette: p, label: 'FOCUS', value: focusMinutes),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text('→', style: mono(context, size: 22, color: p.dim)),
            ),
            _PhaseDigits(palette: p, label: 'BREAK', value: breakMinutes),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('defaults — change them in SETTINGS → FOCUS',
              style: mono(context, size: 8, color: p.dim, letterSpacing: 1)),
        ),
        const SizedBox(height: 10),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.bolt_outlined, color: p.accent),
          title: Text('free session', style: TextStyle(color: p.text, fontSize: 12)),
          subtitle: Text('$focusMinutes min countdown · then a $breakMinutes min break',
              style: TextStyle(color: p.dim, fontSize: 10)),
          trailing: Icon(Icons.play_arrow, color: p.accent),
          onTap: () => timer.startFocus(),
        ),
        TerminalCardRule(palette: p),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.timer_outlined, color: p.accent),
          title: Text('stopwatch', style: TextStyle(color: p.text, fontSize: 12)),
          subtitle: Text('counts up until you stop · credits the bound habit', style: TextStyle(color: p.dim, fontSize: 10)),
          trailing: Icon(Icons.play_arrow, color: p.accent),
          onTap: () => timer.startFocus(stopwatch: true),
        ),
        if (timerHabits.isNotEmpty) ...[
          TerminalCardRule(palette: p),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text('// TIMER HABITS', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
          ),
          for (final h in timerHabits)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.repeat, color: p.accent),
              title: Text(h.name, style: TextStyle(color: p.text, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${h.focusMinutes > 0 ? h.focusMinutes : focusMinutes}m focus · target ${h.target}m',
                style: TextStyle(color: p.dim, fontSize: 10),
              ),
              trailing: Icon(Icons.play_arrow, color: p.accent),
              onTap: () => timer.startFocus(habit: h),
            ),
        ],
        const SizedBox(height: 2),
      ],
    );
  }
}

class _PhaseDigits extends StatelessWidget {
  const _PhaseDigits({required this.palette, required this.label, required this.value});

  final TerminalPalette palette;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      children: [
        Text(
          value.toString().padLeft(2, '0'),
          style: mono(context, size: 38, weight: FontWeight.w700, color: p.text),
        ),
        Text(label, style: mono(context, size: 8.5, color: p.dim, letterSpacing: 2.4)),
      ],
    );
  }
}

// ---------------------------------------------------------------- active pane

class _ActivePane extends StatelessWidget {
  const _ActivePane({required this.palette, required this.timer});

  final TerminalPalette palette;
  final PomodoroTimer timer;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final isBreak = timer.inBreak;
    final color = isBreak ? p.accent2 : p.accent;
    final phaseLabel = isBreak ? 'BREAK' : (timer.isStopwatch ? 'STOPWATCH' : 'FOCUS');
    return TerminalCard(
      palette: p,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: timer.running ? p.good : p.dim),
            ),
            const SizedBox(width: 6),
            Text('$phaseLabel SESSION', style: mono(context, size: 10, weight: FontWeight.w700, color: color, letterSpacing: 2.2)),
            if (timer.habitName.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(timer.habitName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.dim, fontSize: 11)),
              ),
            ] else
              const Spacer(),
            if (timer.running)
              Text('live', style: mono(context, size: 8.5, color: p.good, letterSpacing: 1.4))
            else
              Text('paused', style: mono(context, size: 8.5, color: p.warn, letterSpacing: 1.4)),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: _CountdownText(color: color),
        ),
        if (!timer.isStopwatch && !isBreak) ...[
          Center(
            child: Text(
              'finishes ${_formatClock(DateTime.now().add(timer.display))} · tap to pause/resume',
              style: mono(context, size: 8.5, color: p.dim),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundControl(
              palette: p,
              icon: timer.running ? Icons.pause : Icons.play_arrow,
              label: timer.running ? 'PAUSE' : 'RESUME',
              onTap: timer.running ? timer.pause : timer.resume,
            ),
            const SizedBox(width: 14),
            _RoundControl(
              palette: p,
              icon: Icons.skip_next,
              label: 'SKIP',
              onTap: () => unawaited(timer.skip()),
            ),
            const SizedBox(width: 14),
            _RoundControl(
              palette: p,
              icon: Icons.stop,
              label: 'STOP',
              danger: true,
              onTap: () => unawaited(timer.stop()),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatClock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Repaints itself every second — the parent watches the timer but this
/// guarantees smooth second changes without leaking timers.
class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.color});

  final Color color;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = context.watch<PomodoroTimer>();
    var remaining = timer.display;
    if (remaining.isNegative) remaining = Duration.zero;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final text = hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
    return Text(
      text,
      style: mono(context, size: 54, weight: FontWeight.w700, color: widget.color).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final TerminalPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final color = danger ? p.bad : p.text;
    return Column(
      children: [
        Material(
          color: p.panel2,
          shape: CircleBorder(side: BorderSide(color: danger ? p.bad.withValues(alpha: 0.55) : p.border)),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: color, size: 22),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: mono(context, size: 8, color: danger ? p.bad : p.dim, letterSpacing: 1.6)),
      ],
    );
  }
}

// ------------------------------------------------------------------ summary

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.palette, required this.store});

  final TerminalPalette palette;
  final FocusStore store;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final week = store.totalMinutesSince(DateTime.now().subtract(const Duration(days: 6)));

    Widget cell(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: mono(context, size: 16, weight: FontWeight.w800, color: p.accent)),
              const SizedBox(height: 2),
              Text(label, style: mono(context, size: 7.5, color: p.dim, letterSpacing: 1.4)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          cell('${store.todaySessions}', 'SESSIONS TODAY'),
          Container(width: 1, height: 30, color: p.border),
          cell('${store.todayMinutes}m', 'MINUTES TODAY'),
          Container(width: 1, height: 30, color: p.border),
          cell('${week}m', 'THIS WEEK'),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- heatmap

class _FocusHeatmap extends StatelessWidget {
  const _FocusHeatmap({required this.palette, required this.store});

  final TerminalPalette palette;
  final FocusStore store;

  static const _weeks = 26;
  static const _days = _weeks * 7;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final minutes = store.minutesByDay(days: _days);
    final maxMin = minutes.values.fold<int>(0, (a, b) => math.max(a, b));
    final now = DateTime.now();
    // End on Saturday so the last column is a full week.
    final end = now.add(Duration(days: DateTime.saturday - now.weekday));
    final start = end.subtract(const Duration(days: _days - 1));

    Color cellColor(int min) {
      if (min <= 0) return p.panel2;
      final t = maxMin <= 0 ? 0.0 : min / maxMin;
      if (t < 0.25) return p.accent.withValues(alpha: 0.22);
      if (t < 0.5) return p.accent.withValues(alpha: 0.38);
      if (t < 0.75) return p.accent.withValues(alpha: 0.62);
      return p.accent;
    }

    return TerminalCard(
      palette: p,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var w = 0; w < _weeks; w++)
                Padding(
                  padding: EdgeInsets.only(right: w == _weeks - 1 ? 0 : 3),
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Builder(
                          builder: (context) {
                            final day = start.add(Duration(days: w * 7 + d));
                            final epoch = epochDayOf(day);
                            final min = minutes[epoch] ?? 0;
                            final isFuture = day.isAfter(now);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Tooltip(
                                message: isFuture
                                    ? ''
                                    : '${day.day}/${day.month}/${day.year} · ${min}m',
                                child: Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: isFuture ? Colors.transparent : cellColor(min),
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(color: p.border.withValues(alpha: 0.6), width: 0.5),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('less', style: mono(context, size: 8, color: p.dim)),
            const SizedBox(width: 6),
            for (final alpha in const [0.0, 0.22, 0.38, 0.62, 1.0])
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: alpha == 0.0 ? p.panel2 : p.accent.withValues(alpha: alpha),
                    border: Border.all(color: p.border.withValues(alpha: 0.6), width: 0.5),
                  ),
                ),
              ),
            Text('more', style: mono(context, size: 8, color: p.dim)),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ recent list

class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.palette, required this.store, required this.habitStore});

  final TerminalPalette palette;
  final FocusStore store;
  final HabitStore habitStore;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final recent = store.sessions.take(12).toList();

    return TerminalCard(
      palette: p,
      children: [
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'no sessions yet — hit START on a free session above',
              textAlign: TextAlign.center,
              style: mono(context, size: 10, color: p.dim),
            ),
          )
        else
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) TerminalCardRule(palette: p),
            _SessionRow(palette: p, session: recent[i], habitStore: habitStore, onDelete: () => store.deleteSession(recent[i].id)),
          ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.palette, required this.session, required this.habitStore, required this.onDelete});

  final TerminalPalette palette;
  final FocusSession session;
  final HabitStore habitStore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final habit = session.habitId == '0' ? null : habitStore.habitById(session.habitId);
    final d = DateTime.fromMillisecondsSinceEpoch(session.startedAt, isUtc: true).toLocal();
    final label = session.kind == 'stopwatch' ? 'STOPWATCH' : 'FOCUS';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        session.kind == 'stopwatch' ? Icons.timer_outlined : Icons.center_focus_strong_outlined,
        color: session.completed ? p.good : p.warn,
        size: 20,
      ),
      title: Row(
        children: [
          Text('${session.minutes}m', style: mono(context, size: 12, weight: FontWeight.w800, color: p.text)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              habit?.name ?? 'free session',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.dim, fontSize: 11),
            ),
          ),
          if (!session.completed)
            Text('PARTIAL', style: mono(context, size: 7, color: p.warn, letterSpacing: 1.2)),
        ],
      ),
      subtitle: Text(
        '$label · ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
        style: mono(context, size: 8.5, color: p.dim),
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 15, color: p.dim),
        tooltip: 'remove session',
        onPressed: onDelete,
      ),
    );
  }
}
