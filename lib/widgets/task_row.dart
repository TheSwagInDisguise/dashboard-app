import 'package:flutter/material.dart';

import '../models/task.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../utils/dates.dart';
import 'terminal_chip.dart';

/// One task row: `[x]` checkbox on the left, title + meta on the right.
/// Tapping the checkbox toggles completion; tapping the body opens the editor.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.palette,
    required this.task,
    required this.onToggle,
    required this.onOpen,
  });

  final TerminalPalette palette;
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  Color _priorityColor() => switch (task.priority) {
        'P1' => palette.bad,
        'P2' => palette.warn,
        _ => palette.dim,
      };

  Color _dueColor(DueStatus status) => switch (status) {
        DueStatus.overdue => palette.bad,
        DueStatus.today => palette.warn,
        DueStatus.tomorrow => palette.accent,
        _ => palette.dim,
      };

  @override
  Widget build(BuildContext context) {
    final due = describeDue(task.dueDate);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // checkbox — real 44px touch target
        InkResponse(
          onTap: onToggle,
          radius: 22,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              button: true,
              label: task.done ? 'mark not done' : 'mark done',
              child: Text(
                task.done ? '[x]' : '[ ]',
                style: mono(
                  context,
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: task.done ? palette.good : palette.accent,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
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
                  if (due.label.isNotEmpty || !task.done) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (due.label.isNotEmpty)
                          Text(due.label, style: mono(context, size: 9, color: _dueColor(due.status))),
                        if (due.label.isNotEmpty) const SizedBox(width: 8),
                        TerminalChip(label: task.priority, color: _priorityColor()),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
