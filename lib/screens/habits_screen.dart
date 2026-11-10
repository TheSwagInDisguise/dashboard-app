import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/habit.dart';
import '../state/app_state.dart';
import '../state/habit_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../widgets/terminal_card.dart';
import '../widgets/terminal_chip.dart';

/// Habits — a short daily checklist with streaks. Synced like everything
/// else; no demo data; starts empty.
class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final store = context.watch<HabitStore>();
    final habits = store.habits;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Text(
              '// HABITS',
              style: mono(context, size: 24, weight: FontWeight.w700, color: p.accent, letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'small things, done daily',
              style: mono(context, size: 9.5, color: p.dim, letterSpacing: 2.4),
            ),
          ),
          const SizedBox(height: 18),

          SectionHeader(palette: p, title: 'YOUR HABITS', trailing: habits.isEmpty ? 'empty' : '${habits.where((h) => store.doneToday(h.id)).length}/${habits.length} today'),
          const SizedBox(height: 8),
          if (habits.isEmpty)
            TerminalCard(
              palette: p,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 6, 14),
                  child: Column(
                    children: [
                      Text('// nothing here yet', style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 2)),
                      const SizedBox(height: 10),
                      Text(
                        'Pick one tiny thing you can do most days —\n'
                        '“read 10 pages”, “walk 15 min”, “no sugar after 8”.\n'
                        'That’s the whole system.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.dim, fontSize: 12, height: 1.65),
                      ),
                      const SizedBox(height: 14),
                      _AddHabitButton(palette: p, label: 'ADD YOUR FIRST HABIT'),
                    ],
                  ),
                ),
              ],
            )
          else
            TerminalCard(
              palette: p,
              children: [
                for (final habit in habits) ...[
                  if (habit != habits.first) TerminalCardRule(palette: p),
                  _HabitCardRow(
                    palette: p,
                    habit: habit,
                    doneToday: store.doneToday(habit.id),
                    streak: store.currentStreak(habit),
                    weekDots: store.thisWeekDots(habit),
                    onToggle: () => store.toggleOn(habit.id),
                    onEdit: () => _showHabitSheet(context, initial: habit),
                  ),
                ],
                const SizedBox(height: 6),
                _AddHabitButton(palette: p, label: '+ ADD HABIT', small: true),
              ],
            ),
          const SizedBox(height: 12),
          Text(
            'tap a habit to check it off for today · ⋯ to rename or delete\n'
            'streaks reset if you miss a day (daily) or a week (weekly)',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.dim, fontSize: 10.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================

class _HabitCardRow extends StatelessWidget {
  const _HabitCardRow({
    required this.palette,
    required this.habit,
    required this.doneToday,
    required this.streak,
    required this.weekDots,
    required this.onToggle,
    required this.onEdit,
  });

  final TerminalPalette palette;
  final Habit habit;
  final bool doneToday;
  final int streak;
  final List<bool> weekDots; // Mon..Sun
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              doneToday ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 23,
              color: doneToday ? palette.good : palette.dim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
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
                      const SizedBox(width: 6),
                      TerminalChip(label: habit.cadence == 'weekly' ? 'WK' : 'DLY', color: palette.dim),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Text(
                            weekDots[i] ? '●' : '○',
                            style: mono(context, size: 10, color: weekDots[i] ? palette.good : palette.border),
                          ),
                        ),
                      const SizedBox(width: 2),
                      Text('M T W T F S S', style: mono(context, size: 6.5, color: palette.dim, letterSpacing: 1.1)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$streak',
                  style: mono(context, size: 17, weight: FontWeight.w700, color: streak > 0 ? palette.good : palette.dim),
                ),
                Text(
                  habit.cadence == 'weekly' ? 'WK STREAK' : 'DAY STREAK',
                  style: mono(context, size: 6, color: palette.dim, letterSpacing: 1.1),
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: palette.dim),
              color: palette.panel2,
              onSelected: (value) {
                if (value == 'edit') onEdit();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('rename / change cadence')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddHabitButton extends StatelessWidget {
  const _AddHabitButton({required this.palette, required this.label, this.small = false});

  final TerminalPalette palette;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: () => _showHabitSheet(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: small ? 6 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('+', style: mono(context, size: small ? 12 : 14, weight: FontWeight.w700, color: palette.accent)),
              const SizedBox(width: 8),
              Text(
                label,
                style: mono(context, size: small ? 10 : 11, weight: FontWeight.w700, color: palette.accent, letterSpacing: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showHabitSheet(BuildContext context, {Habit? initial}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HabitSheet(initial: initial),
  );
}

class _HabitSheet extends StatefulWidget {
  const _HabitSheet({this.initial});

  final Habit? initial;

  @override
  State<_HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends State<_HabitSheet> {
  late final TextEditingController _title;
  late String _cadence;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title ?? '');
    _cadence = widget.initial?.cadence ?? 'daily';
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('give it a name first')));
      return;
    }
    setState(() => _saving = true);
    final store = context.read<HabitStore>();
    if (_isEdit) {
      await store.updateHabit(widget.initial!.id, title: title, cadence: _cadence);
    } else {
      await store.addHabit(title: title, cadence: _cadence);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DELETE HABIT?'),
        content: Text('“${widget.initial!.title}” and its streak history will be removed. '
            'This cannot be undone once it syncs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('DELETE', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<HabitStore>().deleteHabit(widget.initial!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.panel2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: p.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      _isEdit ? '// EDIT HABIT' : '// NEW HABIT',
                      style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 2.4),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: p.dim, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'close',
                    ),
                  ],
                ),
                TextField(
                  controller: _title,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  style: TextStyle(color: p.text, fontSize: 15),
                  decoration: const InputDecoration(
                    labelText: 'habit',
                    hintText: 'e.g. read 10 pages',
                  ),
                ),
                const SizedBox(height: 12),
                Text('cadence', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final value in ['daily', 'weekly']) ...[
                      _CadenceOption(
                        palette: p,
                        label: value.toUpperCase(),
                        caption: value == 'daily' ? 'streak per day' : 'streak per week',
                        selected: _cadence == value,
                        onTap: () => setState(() => _cadence = value),
                      ),
                      if (value != 'weekly') const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_isEdit) ...[
                      TextButton(
                        onPressed: _delete,
                        child: Text('DELETE', style: mono(context, size: 11, weight: FontWeight.w700, color: p.bad, letterSpacing: 1.6)),
                      ),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    Material(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _saving ? null : _save,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                          child: Text(
                            _saving ? 'SAVING…' : (_isEdit ? 'SAVE CHANGES' : 'ADD HABIT'),
                            style: mono(context, size: 11, weight: FontWeight.w700, color: p.bg, letterSpacing: 1.6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CadenceOption extends StatelessWidget {
  const _CadenceOption({
    required this.palette,
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final TerminalPalette palette;
  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.14) : p.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? p.accent : p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mono(context, size: 10.5, weight: FontWeight.w700, color: selected ? p.accent : p.dim, letterSpacing: 1.4)),
              const SizedBox(height: 2),
              Text(caption, style: TextStyle(color: p.dim, fontSize: 9.5, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}
