import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/habit.dart' hide TimeOfDay;
import '../state/app_state.dart';
import '../state/habit_store.dart';
import '../state/json_doc_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';

/// Full editor for the v2 habit model. Existing records are edited in place so
/// their ids, history, XP, and sync identity remain stable.
class HabitEditorSheet extends StatefulWidget {
  const HabitEditorSheet({super.key, this.initial});
  final Habit? initial;

  @override
  State<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<HabitEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _unit;
  late final TextEditingController _minimum;
  late final TextEditingController _rampTo;
  late final TextEditingController _rampWeeks;
  late final TextEditingController _checklist;
  late final TextEditingController _notes;
  late final TextEditingController _focus;
  late final TextEditingController _break;
  late HabitType _type;
  late ScheduleType _schedule;
  late int _daysMask;
  late int _timesPerWeek;
  late int _monthDay;
  late bool _negative;
  late bool _checkIn;
  late bool _anchorRemind;
  late int _reminderMinutes;
  late String _timeOfDay;
  late String _area;
  String? _anchorId;
  bool _saving = false;

  bool get _editing => widget.initial != null;
  bool get _usesAmount =>
      _type == HabitType.counter || _type == HabitType.timer;

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    _name = TextEditingController(text: h?.name ?? '');
    _target = TextEditingController(text: '${h?.target ?? 1}');
    _unit = TextEditingController(text: h?.unit ?? '');
    _minimum = TextEditingController(
      text: h == null || h.minTarget == 0 ? '' : '${h.minTarget}',
    );
    _rampTo = TextEditingController(
      text: h == null || h.rampTo == 0 ? '' : '${h.rampTo}',
    );
    _rampWeeks = TextEditingController(
      text: h == null || h.rampWeeks == 0 ? '' : '${h.rampWeeks}',
    );
    _checklist = TextEditingController(text: h?.checklist ?? '');
    _notes = TextEditingController(text: h?.notes ?? '');
    _focus = TextEditingController(
      text: h == null || h.focusMinutes == 0 ? '' : '${h.focusMinutes}',
    );
    _break = TextEditingController(
      text: h == null || h.breakMinutes == 0 ? '' : '${h.breakMinutes}',
    );
    _type = h?.type ?? HabitType.checkbox;
    _schedule = h?.schedule ?? ScheduleType.daily;
    _daysMask = h?.daysMask ?? 127;
    _timesPerWeek = h?.timesPerWeek ?? 3;
    _monthDay = h?.monthDay ?? DateTime.now().day;
    _negative = h?.negative ?? false;
    _checkIn = h?.checkIn ?? false;
    _anchorRemind = h?.anchorRemind ?? false;
    _reminderMinutes = h?.reminderMinutes ?? -1;
    _timeOfDay = h?.timeOfDay ?? '';
    _area = h?.area ?? '';
    _anchorId = h?.anchorId;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _target,
      _unit,
      _minimum,
      _rampTo,
      _rampWeeks,
      _checklist,
      _notes,
      _focus,
      _break,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final target = int.tryParse(_target.text.trim()) ?? 0;
    final minTarget = int.tryParse(_minimum.text.trim()) ?? 0;
    final rampTo = int.tryParse(_rampTo.text.trim()) ?? 0;
    final rampWeeks = int.tryParse(_rampWeeks.text.trim()) ?? 0;
    final focusMinutes = int.tryParse(_focus.text.trim()) ?? 0;
    final breakMinutes = int.tryParse(_break.text.trim()) ?? 0;
    if (name.isEmpty) {
      _error('Give this habit a name first.');
      return;
    }
    if (_usesAmount && target < 1) {
      _error('Target must be at least 1.');
      return;
    }
    if (minTarget < 0 || (_usesAmount && minTarget > target && target > 0)) {
      _error('Minimum must be between 0 and the target.');
      return;
    }
    if ((_schedule == ScheduleType.specificDays ||
            _schedule == ScheduleType.biweekly) &&
        _daysMask == 0) {
      _error('Choose at least one scheduled weekday.');
      return;
    }
    if (rampWeeks < 0 || rampTo < 0) {
      _error('Ramp values cannot be negative.');
      return;
    }

    setState(() => _saving = true);
    final store = context.read<HabitStore>();
    final now = DateTime.now().toUtc();
    final old = widget.initial;
    final effectiveTarget = _usesAmount ? target : 1;
    if (old == null) {
      await store.addHabit(
        () => Habit(
          id: JsonDocStore.newId(),
          name: name,
          type: _type,
          target: effectiveTarget,
          unit: _usesAmount ? _unit.text.trim() : '',
          schedule: _schedule,
          daysMask: _daysMask,
          timesPerWeek: _timesPerWeek,
          monthDay: _monthDay,
          negative: _negative,
          reminderMinutes: _reminderMinutes,
          focusMinutes: focusMinutes,
          breakMinutes: breakMinutes,
          checkIn: _checkIn,
          checklist: _type == HabitType.checklist ? _checklist.text.trim() : '',
          timeOfDay: _timeOfDay,
          minTarget: _usesAmount ? minTarget : 0,
          rampTo: _usesAmount ? rampTo : 0,
          rampWeeks: _usesAmount ? rampWeeks : 0,
          rampStartDay: rampWeeks > 0 ? epochDayOf(DateTime.now()) : 0,
          anchorId: _anchorId,
          anchorRemind: _anchorRemind,
          area: _area,
          notes: _notes.text.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      await store.updateHabit(
        old.id,
        (h) => h.copyWith(
          name: name,
          type: _type,
          target: effectiveTarget,
          unit: _usesAmount ? _unit.text.trim() : '',
          schedule: _schedule,
          daysMask: _daysMask,
          timesPerWeek: _timesPerWeek,
          monthDay: _monthDay,
          negative: _negative,
          reminderMinutes: _reminderMinutes,
          focusMinutes: focusMinutes,
          breakMinutes: breakMinutes,
          checkIn: _checkIn,
          checklist: _type == HabitType.checklist ? _checklist.text.trim() : '',
          timeOfDay: _timeOfDay,
          minTarget: _usesAmount ? minTarget : 0,
          rampTo: _usesAmount ? rampTo : 0,
          rampWeeks: _usesAmount ? rampWeeks : 0,
          rampStartDay: rampWeeks > 0
              ? (h.rampWeeks > 0 ? h.rampStartDay : epochDayOf(DateTime.now()))
              : 0,
          anchorId: _anchorId,
          clearAnchorId: _anchorId == null,
          anchorRemind: _anchorRemind,
          area: _area,
          notes: _notes.text.trim(),
          updatedAt: now,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _error(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _delete() async {
    final habit = widget.initial;
    if (habit == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DELETE HABIT?'),
        content: Text(
          '“${habit.name}” and its history will be removed from synced devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<HabitStore>().deleteHabit(habit.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _setReminder() async {
    final initial = _reminderMinutes < 0
        ? const TimeOfDay(hour: 20, minute: 0)
        : TimeOfDay(
            hour: _reminderMinutes ~/ 60,
            minute: _reminderMinutes % 60,
          );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() => _reminderMinutes = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _pause({required bool resume}) async {
    final habit = widget.initial;
    if (habit == null) return;
    final until = resume ? null : DateTime.now().add(const Duration(days: 7));
    await context.read<HabitStore>().pauseHabit(habit.id, until);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final store = context.watch<HabitStore>();
    final habits = store.habits;
    final editingHabit = _editing
        ? habits.firstWhere(
            (h) => h.id == widget.initial!.id,
            orElse: () => widget.initial!,
          )
        : null;
    final anchors = habits.where((h) => h.id != widget.initial?.id).toList();
    final activePause =
        (editingHabit?.pausedUntil ?? 0) > epochDayOf(DateTime.now());
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        decoration: BoxDecoration(
          color: p.panel2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: p.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        _editing ? '// EDIT HABIT' : '// NEW HABIT',
                        style: mono(
                          context,
                          size: 13,
                          weight: FontWeight.w700,
                          color: p.accent,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: p.dim),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  _section(context, p, 'IDENTITY'),
                  TextField(
                    controller: _name,
                    autofocus: !_editing,
                    style: TextStyle(color: p.text),
                    decoration: const InputDecoration(
                      labelText: 'habit name',
                      hintText: 'e.g. read 10 pages',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<HabitType>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'tracking type',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: HabitType.checkbox,
                        child: Text('Checkbox'),
                      ),
                      DropdownMenuItem(
                        value: HabitType.counter,
                        child: Text('Counter'),
                      ),
                      DropdownMenuItem(
                        value: HabitType.timer,
                        child: Text('Timer'),
                      ),
                      DropdownMenuItem(
                        value: HabitType.checklist,
                        child: Text('Checklist'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _type = v);
                    },
                  ),
                  if (_usesAmount) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _target,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _type == HabitType.timer
                                  ? 'target minutes'
                                  : 'target count',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _unit,
                            decoration: const InputDecoration(
                              labelText: 'unit',
                              hintText: 'pages, km, reps',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _minimum,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'minimum to keep streak (optional)',
                        hintText: '0 = off',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _rampTo,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'ramp target (optional)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _rampWeeks,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'ramp length (weeks)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_type == HabitType.checklist) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _checklist,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'checklist items',
                        hintText: 'one item per line',
                      ),
                    ),
                  ],
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Avoid habit'),
                    subtitle: const Text(
                      'A scheduled day counts as kept unless you log a slip.',
                    ),
                    value: _negative,
                    onChanged: (v) => setState(() => _negative = v),
                  ),
                  _section(context, p, 'SCHEDULE'),
                  DropdownButtonFormField<ScheduleType>(
                    initialValue: _schedule,
                    decoration: const InputDecoration(labelText: 'cadence'),
                    items: const [
                      DropdownMenuItem(
                        value: ScheduleType.daily,
                        child: Text('Every day'),
                      ),
                      DropdownMenuItem(
                        value: ScheduleType.weekly,
                        child: Text('Weekly quota'),
                      ),
                      DropdownMenuItem(
                        value: ScheduleType.specificDays,
                        child: Text('Selected weekdays'),
                      ),
                      DropdownMenuItem(
                        value: ScheduleType.biweekly,
                        child: Text('Every other week'),
                      ),
                      DropdownMenuItem(
                        value: ScheduleType.monthly,
                        child: Text('Monthly'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      if (v != null) _schedule = v;
                    }),
                  ),
                  if (_schedule == ScheduleType.weekly) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _timesPerWeek,
                      decoration: const InputDecoration(
                        labelText: 'completions per week',
                      ),
                      items: [
                        for (var n = 1; n <= 7; n++)
                          DropdownMenuItem(value: n, child: Text('$n / week')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _timesPerWeek = v);
                      },
                    ),
                  ],
                  if (_schedule == ScheduleType.specificDays ||
                      _schedule == ScheduleType.biweekly) ...[
                    const SizedBox(height: 8),
                    Text(
                      'weekdays',
                      style: mono(
                        context,
                        size: 9,
                        color: p.dim,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        for (var i = 0; i < 7; i++)
                          ChoiceChip(
                            label: Text(
                              const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                            ),
                            selected: (_daysMask & (1 << i)) != 0,
                            onSelected: (v) => setState(
                              () => _daysMask = v
                                  ? _daysMask | (1 << i)
                                  : _daysMask & ~(1 << i),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (_schedule == ScheduleType.monthly) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _monthDay.clamp(1, 31),
                      decoration: const InputDecoration(
                        labelText: 'day of month (short months use final day)',
                      ),
                      items: [
                        for (var n = 1; n <= 31; n++)
                          DropdownMenuItem(
                            value: n,
                            child: Text('$n${_ordinal(n)}'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _monthDay = v);
                      },
                    ),
                  ],
                  _section(context, p, 'CUES & FOCUS'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reminder time'),
                    subtitle: Text(
                      _reminderMinutes < 0
                          ? 'Off'
                          : TimeOfDay(
                              hour: _reminderMinutes ~/ 60,
                              minute: _reminderMinutes % 60,
                            ).format(context),
                    ),
                    trailing: IconButton(
                      onPressed: _setReminder,
                      icon: const Icon(Icons.schedule),
                    ),
                    onTap: _setReminder,
                  ),
                  if (_reminderMinutes >= 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _reminderMinutes = -1),
                        child: const Text('TURN REMINDER OFF'),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: _timeOfDay.isEmpty ? '' : _timeOfDay,
                    decoration: const InputDecoration(labelText: 'day section'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Automatic')),
                      DropdownMenuItem(
                        value: 'morning',
                        child: Text('Morning'),
                      ),
                      DropdownMenuItem(
                        value: 'afternoon',
                        child: Text('Afternoon'),
                      ),
                      DropdownMenuItem(
                        value: 'evening',
                        child: Text('Evening'),
                      ),
                      DropdownMenuItem(value: 'any', child: Text('Anytime')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _timeOfDay = v);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Evening check-in'),
                    subtitle: const Text(
                      'Nudge if still unlogged at check-in.',
                    ),
                    value: _checkIn,
                    onChanged: (v) => setState(() => _checkIn = v),
                  ),
                  if (_type == HabitType.timer) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _focus,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'focus minutes',
                              hintText: 'app default',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _break,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'break minutes',
                              hintText: 'app default',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  _section(context, p, 'PERSONALIZATION'),
                  DropdownButtonFormField<String>(
                    initialValue: _area,
                    decoration: const InputDecoration(labelText: 'life area'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('None')),
                      DropdownMenuItem(value: 'body', child: Text('Body')),
                      DropdownMenuItem(value: 'mind', child: Text('Mind')),
                      DropdownMenuItem(value: 'work', child: Text('Work')),
                      DropdownMenuItem(value: 'people', child: Text('People')),
                      DropdownMenuItem(value: 'home', child: Text('Home')),
                      DropdownMenuItem(value: 'money', child: Text('Money')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _area = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: _anchorId,
                    decoration: const InputDecoration(
                      labelText: 'habit anchor (optional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      for (final h in anchors)
                        DropdownMenuItem<String?>(
                          value: h.id,
                          child: Text(h.name),
                        ),
                    ],
                    onChanged: (v) => setState(() => _anchorId = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remind me after anchor'),
                    value: _anchorRemind,
                    onChanged: _anchorId == null
                        ? null
                        : (v) => setState(() => _anchorRemind = v),
                  ),
                  TextField(
                    controller: _notes,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'notes'),
                  ),
                  if (_editing) ...[
                    _section(context, p, 'RECOVERY'),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            activePauseLabel(activePause, editingHabit!),
                            style: TextStyle(color: p.dim, fontSize: 11),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _pause(resume: activePause),
                          child: Text(activePause ? 'RESUME' : 'PAUSE 7 DAYS'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_editing)
                        TextButton(
                          onPressed: _delete,
                          child: Text('DELETE', style: TextStyle(color: p.bad)),
                        )
                      else
                        const Spacer(),
                      const Spacer(),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving
                              ? 'SAVING…'
                              : _editing
                              ? 'SAVE CHANGES'
                              : 'ADD HABIT',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String activePauseLabel(bool active, Habit habit) => active
      ? 'Paused until ${dateOfEpochDay(habit.pausedUntil).day}/${dateOfEpochDay(habit.pausedUntil).month}'
      : 'Habit is active';

  Widget _section(BuildContext context, TerminalPalette p, String label) =>
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          '// $label',
          style: mono(
            context,
            size: 9,
            weight: FontWeight.w800,
            color: p.accent,
            letterSpacing: 1.4,
          ),
        ),
      );

  String _ordinal(int day) {
    if (day >= 11 && day <= 13) return 'th';
    return switch (day % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
}

Future<void> showHabitEditorSheet(BuildContext context, {Habit? initial}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HabitEditorSheet(initial: initial),
    );
