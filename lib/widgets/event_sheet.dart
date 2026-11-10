import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/event.dart';
import '../state/app_state.dart';
import '../state/event_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';

/// Opens the terminal-styled event sheet. Pass [initial] to edit; omit to create.
Future<void> showEventSheet(BuildContext context, {Event? initial, DateTime? defaultStart}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EventSheet(initial: initial, defaultStart: defaultStart),
  );
}

class _EventSheet extends StatefulWidget {
  const _EventSheet({this.initial, this.defaultStart});

  final Event? initial;
  final DateTime? defaultStart;

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _notes;
  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
  late String _visibility;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final base = initial?.start.toLocal() ?? widget.defaultStart ?? DateTime.now();
    _title = TextEditingController(text: initial?.title ?? '');
    _location = TextEditingController(text: initial?.location ?? '');
    _notes = TextEditingController(text: initial?.notes ?? '');
    _start = base;
    _end = initial?.end.toLocal() ?? base.add(const Duration(hours: 1));
    _allDay = initial?.allDay ?? false;
    _visibility = initial?.visibility ?? 'private';
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      helpText: isStart ? 'starts on' : 'ends on',
      cancelText: 'cancel',
      confirmText: 'set',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        final duration = _end.difference(_start);
        _start = _allDay
            ? DateTime(picked.year, picked.month, picked.day)
            : DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
        _end = _start.add(duration);
      } else {
        _end = _allDay
            ? DateTime(picked.year, picked.month, picked.day)
            : DateTime(picked.year, picked.month, picked.day, _end.hour, _end.minute);
        if (_end.isBefore(_start)) _end = _start;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = TimeOfDay.fromDateTime(isStart ? _start : _end);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        final duration = _end.difference(_start);
        _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
        _end = _start.add(duration);
      } else {
        _end = DateTime(_end.year, _end.month, _end.day, picked.hour, picked.minute);
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _snack('give it a title first');
      return;
    }
    setState(() => _saving = true);
    final store = context.read<EventStore>();
    final startUtc = _start.toUtc();
    final endUtc = _end.toUtc();
    final location = _location.text.trim();
    final notes = _notes.text.trim();
    if (_isEdit) {
      await store.updateEvent(
        widget.initial!.id,
        title: title,
        start: startUtc,
        end: endUtc,
        allDay: _allDay,
        visibility: _visibility,
        location: location,
        notes: notes,
        clearLocation: location.isEmpty,
        clearNotes: notes.isEmpty,
      );
    } else {
      await store.add(
        title: title,
        start: startUtc,
        end: endUtc,
        allDay: _allDay,
        visibility: _visibility,
        location: location,
        notes: notes,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DELETE EVENT?'),
        content: Text('“${widget.initial!.title}” will be removed on this device. '
            'It stays recoverable via sync history if it already synced.'),
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
      await context.read<EventStore>().deleteEvent(widget.initial!.id);
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
                      _isEdit ? '// EDIT EVENT' : '// NEW EVENT',
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
                    labelText: 'event',
                    hintText: 'e.g. dinner at Nonna’s',
                  ),
                ),
                const SizedBox(height: 12),

                // ---- all-day toggle ----
                Row(
                  children: [
                    Text('all-day', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                    const Spacer(),
                    Switch(
                      value: _allDay,
                      activeThumbColor: p.accent,
                      onChanged: (v) => setState(() => _allDay = v),
                    ),
                  ],
                ),

                // ---- start / end ----
                Text('start', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SheetChip(
                      palette: p,
                      label: '${_start.day.toString().padLeft(2, '0')}/${_start.month.toString().padLeft(2, '0')}/${_start.year}',
                      onTap: () => _pickDate(isStart: true),
                    ),
                    if (!_allDay)
                      _SheetChip(
                        palette: p,
                        label: '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}',
                        onTap: () => _pickTime(isStart: true),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('end', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SheetChip(
                      palette: p,
                      label: '${_end.day.toString().padLeft(2, '0')}/${_end.month.toString().padLeft(2, '0')}/${_end.year}',
                      onTap: () => _pickDate(isStart: false),
                    ),
                    if (!_allDay)
                      _SheetChip(
                        palette: p,
                        label: '${_end.hour.toString().padLeft(2, '0')}:${_end.minute.toString().padLeft(2, '0')}',
                        onTap: () => _pickTime(isStart: false),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // ---- visibility ----
                Text('visibility', style: mono(context, size: 9.5, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _VisibilityOption(
                      palette: p,
                      label: 'PRIVATE',
                      caption: 'stays in the app',
                      selected: _visibility == 'private',
                      onTap: () => setState(() => _visibility = 'private'),
                    ),
                    const SizedBox(width: 8),
                    _VisibilityOption(
                      palette: p,
                      label: 'SHARED',
                      caption: 'I’ll add it to Google Calendar',
                      selected: _visibility == 'shared',
                      onTap: () => setState(() => _visibility = 'shared'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _location,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: p.text, fontSize: 13.5),
                  decoration: const InputDecoration(
                    labelText: 'where (optional)',
                    hintText: 'e.g. Nonna’s place',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  style: TextStyle(color: p.text, fontSize: 13.5),
                  decoration: const InputDecoration(
                    labelText: 'notes (optional)',
                    hintText: 'anything worth remembering',
                  ),
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
                      label: _saving ? 'SAVING…' : (_isEdit ? 'SAVE CHANGES' : 'ADD EVENT'),
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

class _SheetChip extends StatelessWidget {
  const _SheetChip({required this.palette, required this.label, required this.onTap});

  final TerminalPalette palette;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_calendar_outlined, size: 14, color: p.accent),
            const SizedBox(width: 7),
            Text(label, style: mono(context, size: 11, weight: FontWeight.w600, color: p.text)),
          ],
        ),
      ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
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
              Text(
                label,
                style: mono(context, size: 10.5, weight: FontWeight.w700, color: selected ? p.accent : p.dim, letterSpacing: 1.4),
              ),
              const SizedBox(height: 2),
              Text(caption, style: TextStyle(color: p.dim, fontSize: 9.5, height: 1.35)),
            ],
          ),
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
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: p.accent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
            child: Text(
              label,
              style: mono(context, size: 11, weight: FontWeight.w700, color: p.bg, letterSpacing: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}
