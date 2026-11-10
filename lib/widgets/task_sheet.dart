import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import '../state/tasks_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../utils/dates.dart';

/// Opens the terminal-styled task sheet. Pass [initial] to edit an existing
/// task; omit it to create a new one.
Future<void> showTaskSheet(BuildContext context, {Task? initial}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TaskSheet(initial: initial),
  );
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({this.initial});

  final Task? initial;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final TextEditingController _title;
  late String _priority;
  String? _dueDate;
  bool _remind = false;
  TimeOfDay _remindTime = const TimeOfDay(hour: 9, minute: 0);
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title ?? '');
    _priority = widget.initial?.priority ?? 'P2';
    _dueDate = widget.initial?.dueDate;
    final reminder = widget.initial?.reminderAt;
    if (reminder != null) {
      final local = reminder.toLocal();
      _remind = true;
      _remindTime = TimeOfDay(hour: local.hour, minute: local.minute);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = parseDateKey(_dueDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'due date',
      cancelText: 'cancel',
      confirmText: 'set',
    );
    if (picked != null) setState(() => _dueDate = dateKey(picked));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _snack('give it a title first');
      return;
    }
    // Reminder = due date at the chosen local time, converted to UTC.
    DateTime? reminderUtc;
    final due = parseDateKey(_dueDate);
    if (_remind && due != null) {
      reminderUtc = DateTime(due.year, due.month, due.day, _remindTime.hour, _remindTime.minute).toUtc();
    }
    setState(() => _saving = true);
    final store = context.read<TasksStore>();
    if (_isEdit) {
      await store.updateTask(
        widget.initial!.id,
        title: title,
        priority: _priority,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        reminderAt: reminderUtc,
        clearReminder: _remind == false,
      );
    } else {
      await store.add(title: title, priority: _priority, dueDate: _dueDate, reminderAt: reminderUtc);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DELETE TASK?'),
        content: Text('“${widget.initial!.title}” will be removed on this device. '
            'This cannot be undone once it syncs (Phase 3).'),
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
      await context.read<TasksStore>().deleteTask(widget.initial!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<AppState>().palette;
    final p = palette;

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
                      _isEdit ? '// EDIT TASK' : '// NEW TASK',
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
                    labelText: 'task',
                    hintText: 'e.g. renew car rego',
                  ),
                ),
                const SizedBox(height: 12),

                // ---- priority ----
                Text('priority', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final value in ['P1', 'P2', 'P3']) ...[
                      _PriorityOption(
                        palette: p,
                        value: value,
                        selected: _priority == value,
                        onTap: () => setState(() => _priority = value),
                      ),
                      if (value != 'P3') const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // ---- due date ----
                Text('due', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DueOption(palette: p, label: 'none', selected: _dueDate == null, onTap: () => setState(() { _dueDate = null; _remind = false; })),
                    _DueOption(
                      palette: p,
                      label: 'today',
                      selected: _dueDate == todayKey(),
                      onTap: () => setState(() => _dueDate = todayKey()),
                    ),
                    _DueOption(
                      palette: p,
                      label: 'tomorrow',
                      selected: _dueDate == dateKey(DateTime.now().add(const Duration(days: 1))),
                      onTap: () => setState(() => _dueDate = dateKey(DateTime.now().add(const Duration(days: 1)))),
                    ),
                    _DueOption(
                      palette: p,
                      label: 'pick…',
                      selected: _dueDate != null && _dueDate != todayKey() &&
                          _dueDate != dateKey(DateTime.now().add(const Duration(days: 1))),
                      onTap: _pickDate,
                    ),
                  ],
                ),
                if (_dueDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'due ${parseDateKey(_dueDate)!.day.toString().padLeft(2, '0')}/${parseDateKey(_dueDate)!.month.toString().padLeft(2, '0')}'
                    '/${parseDateKey(_dueDate)!.year}  (${describeDue(_dueDate).label})',
                    style: mono(context, size: 10, color: p.accent),
                  ),
                ],
                const SizedBox(height: 12),

                // ---- reminder ----
                Text('reminder', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                if (_dueDate == null)
                  Text('set a due date first', style: mono(context, size: 9, color: p.dim))
                else
                  Row(
                    children: [
                      Switch(
                        value: _remind,
                        activeThumbColor: p.accent,
                        onChanged: (v) => setState(() => _remind = v),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _remind ? 'remind me at' : 'no reminder',
                          style: TextStyle(color: p.text, fontSize: 12),
                        ),
                      ),
                      if (_remind)
                        OutlinedButton(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _remindTime,
                              helpText: 'reminder time',
                            );
                            if (picked != null) setState(() => _remindTime = picked);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.accent,
                            side: BorderSide(color: p.accent.withValues(alpha: 0.6)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          child: Text(
                            '${_remindTime.hour.toString().padLeft(2, '0')}:${_remindTime.minute.toString().padLeft(2, '0')}',
                            style: mono(context, size: 12, weight: FontWeight.w700, letterSpacing: 1.5),
                          ),
                        ),
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
                    _SheetButton(
                      palette: p,
                      label: _saving ? 'SAVING…' : (_isEdit ? 'SAVE CHANGES' : 'ADD TASK'),
                      onTap: _saving ? null : _save,
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

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({
    required this.palette,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final TerminalPalette palette;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  Color get _color => switch (value) {
        'P1' => palette.bad,
        'P2' => palette.warn,
        _ => palette.dim,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : palette.border, width: selected ? 1.6 : 1),
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
        ),
        child: Text(
          value,
          style: mono(context, size: 12, weight: FontWeight.w700, color: selected ? color : palette.dim, letterSpacing: 1.4),
        ),
      ),
    );
  }
}

class _DueOption extends StatelessWidget {
  const _DueOption({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TerminalPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? p.accent : p.border, width: selected ? 1.6 : 1),
          color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          label,
          style: mono(context, size: 11, weight: FontWeight.w600, color: selected ? p.accent : p.dim),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.palette, required this.label, required this.onTap});

  final TerminalPalette palette;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: p.accent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              label,
              style: mono(context, size: 12, weight: FontWeight.w700, color: p.bg, letterSpacing: 1.8),
            ),
          ),
        ),
      ),
    );
  }
}
