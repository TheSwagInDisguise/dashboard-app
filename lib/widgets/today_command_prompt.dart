import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/strength.dart';
import '../models/habit.dart';
import '../state/habit_store.dart';
import '../state/tasks_store.dart';
import '../state/watch_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import 'terminal_card.dart';

/// Small, local command line for common Today actions. Commands deliberately
/// operate through the existing stores so sync and tombstone semantics remain
/// identical to tapping the UI.
class TodayCommandPrompt extends StatefulWidget {
  const TodayCommandPrompt({super.key, required this.palette});

  final TerminalPalette palette;

  @override
  State<TodayCommandPrompt> createState() => _TodayCommandPromptState();
}

class _TodayCommandPromptState extends State<TodayCommandPrompt> {
  final _controller = TextEditingController();
  String _output = '';
  bool _busy = false;
  bool _ok = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final line = _controller.text.trim();
    if (line.isEmpty || _busy) return;
    setState(() => _busy = true);
    final habits = context.read<HabitStore>();
    final tasks = context.read<TasksStore>();
    final watches = context.read<WatchStore>();
    final words = line.split(RegExp(r'\s+'));
    final head = words.first.toLowerCase();
    final rest = line.substring(words.first.length).trim();
    var result = 'unknown command · type help';
    var success = false;

    try {
      if (head == 'help' || head == '?') {
        result = 'done <habit> · skip <habit> · late <habit> · shield <habit> · strength · task <text> · watch next · wear <watch>';
        success = true;
      } else if (head == 'task' ||
          (head == 'add' && rest.toLowerCase().startsWith('task '))) {
        final title = head == 'task' ? rest : rest.substring(5).trim();
        if (title.isEmpty) {
          result = 'usage: task <title>';
        } else {
          await tasks.add(title: title);
          result = 'task added · $title';
          success = true;
        }
      } else if (head == 'watch' && rest.toLowerCase() == 'next') {
        final watch = watches.nextSuggestion;
        result = watch == null
            ? 'no eligible watch · add one in WATCH'
            : 'watch next → ${watch.displayName} · ${watches.nextSuggestionReason(watch)}';
        success = watch != null;
      } else if (head == 'wear') {
        final q = rest.toLowerCase();
        final candidates = watches.collection.where((w) => w.displayName.toLowerCase() == q || w.displayName.toLowerCase().contains(q)).toList();
        if (candidates.length != 1) {
          result = 'watch not found or ambiguous · use its full name';
        } else {
          await watches.logTodaysWear(candidates.single.id);
          result = '[✓] ${candidates.single.displayName} logged on the wrist';
          success = true;
        }
      } else if (head == 'strength' || head == 'str') {
        final rows =
            habits.habits.map((h) => (h, habits.strengthOf(h))).toList()
              ..sort((a, b) => a.$2.score.compareTo(b.$2.score));
        result = rows.isEmpty
            ? 'no habits yet'
            : rows
                  .map(
                    (row) =>
                        '${row.$1.title}: ${Strength.label(row.$2)} ${Strength.sparkline(row.$2.history, cells: 5)}',
                  )
                  .join(' · ');
        success = rows.isNotEmpty;
      } else if (head == 'done' || head == 'check' || head == 'complete') {
        final habit = _findHabit(habits, rest);
        if (habit == null) {
          result = 'habit not found · use its name';
        } else {
          if (habit.negative) {
            await habits.logSlip(habit.id, slipped: false);
            result = '[✓] ${habit.title} · clean today';
          } else if (habits.isDoneToday(habit)) {
            result = '[✓] ${habit.title} already done today';
          } else {
            await habits.toggle(habit.id);
            result = '[✓] ${habit.title} logged today';
          }
          success = true;
        }
      } else if (head == 'skip') {
        final marker = rest.indexOf(' -- ');
        final habitRef = marker < 0 ? rest : rest.substring(0, marker);
        final reason = marker < 0
            ? 'deliberate skip'
            : rest.substring(marker + 4).trim();
        final habit = _findHabit(habits, habitRef.trim());
        if (habit == null) {
          result = 'habit not found · use its name';
        } else {
          await habits.skip(
            habit.id,
            reason.isEmpty ? 'deliberate skip' : reason,
          );
          result = '${habit.title} skipped · streak bridged';
          success = true;
        }
      } else if (head == 'late' || head == 'yesterday' || head == 'yday') {
        final habit = _findHabit(habits, rest);
        if (habit == null) {
          result = 'habit not found · use its name';
        } else {
          final day = habits.streakOf(habit).lateLogDay;
          if (day == null) {
            result = 'repair window closed or nothing to log';
          } else {
            await habits.toggle(habit.id, date: day);
            result = '[✓] ${habit.title} logged for ${day.day}/${day.month}';
            success = true;
          }
        }
      } else if (head == 'shield') {
        final habit = _findHabit(habits, rest);
        if (habit == null) {
          result = 'habit not found · use its name';
        } else {
          success = await habits.repairWithShield(habit.id);
          result = success
              ? 'streak repaired · shield spent'
              : 'no repairable gap or no shield available';
        }
      }
    } catch (error) {
      result = 'could not run command · ${error.runtimeType}';
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _output = result;
      _ok = success;
      _controller.clear();
    });
  }

  Habit? _findHabit(HabitStore store, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    final all = store.habits;
    for (final habit in all) {
      if (habit.title.toLowerCase() == q) return habit;
    }
    final matches = all
        .where((h) => h.title.toLowerCase().contains(q))
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return TerminalCard(
      palette: p,
      children: [
        Row(
          children: [
            Text(
              '>_',
              style: mono(
                context,
                size: 11,
                weight: FontWeight.w800,
                color: p.accent,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'COMMAND',
              style: mono(
                context,
                size: 8,
                weight: FontWeight.w700,
                color: p.dim,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                _controller.text = 'help';
                _run();
              },
              child: Text(
                'HELP',
                style: mono(context, size: 8, color: p.accent),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('today-command-input'),
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _run(),
                style: mono(context, size: 11, color: p.text),
                decoration: InputDecoration(
                  hintText: 'done read · task call dentist',
                  hintStyle: mono(context, size: 10, color: p.dim),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('today-command-run'),
              onPressed: _busy ? null : _run,
              tooltip: 'Run command',
              icon: Icon(Icons.arrow_forward, color: p.accent, size: 19),
            ),
          ],
        ),
        if (_output.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 2),
            child: Text(
              _output,
              style: mono(context, size: 9, color: _ok ? p.good : p.warn),
            ),
          ),
      ],
    );
  }
}
