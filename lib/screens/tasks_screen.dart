import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/tasks_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../widgets/task_row.dart';
import '../widgets/task_sheet.dart';
import '../widgets/terminal_card.dart';

/// The real task list — local, offline-first. Add, edit, complete or delete;
/// synced to the private GitHub data repo like everything else.
///
/// Wide screens (fold inner display): open tasks on the left, done on the
/// right — instead of one very long column.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  Future<void> _confirmClearDone(BuildContext context, TasksStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CLEAR DONE TASKS?'),
        content: const Text('All completed tasks will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CLEAR', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final count = await store.clearCompleted();
      if (context.mounted && count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('cleared $count completed task${count == 1 ? '' : 's'}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final store = context.watch<TasksStore>();
    final openTasks = store.openTasks;
    final doneTasks = store.doneTasks;
    final wide = MediaQuery.sizeOf(context).width >= 700;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '// TASKS',
          style: mono(context, size: 22, weight: FontWeight.w700, color: p.accent, letterSpacing: 5),
        ),
        const Spacer(),
        if (doneTasks.isNotEmpty)
          InkWell(
            onTap: () => _confirmClearDone(context, store),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                '[ clear done ]',
                style: mono(context, size: 10, weight: FontWeight.w600, color: p.bad, letterSpacing: 0.6),
              ),
            ),
          ),
      ],
    );

    final stats = Row(
      children: [
        Text('${store.openCount} open', style: mono(context, size: 10, color: p.dim)),
        Text(' · ', style: mono(context, size: 10, color: p.dim)),
        Text(
          '${store.dueTodayCount} due today',
          style: mono(context, size: 10, color: store.dueTodayCount > 0 ? p.warn : p.dim),
        ),
        Text(' · ', style: mono(context, size: 10, color: p.dim)),
        Text(
          '${store.overdueCount} overdue',
          style: mono(context, size: 10, color: store.overdueCount > 0 ? p.bad : p.dim),
        ),
      ],
    );

    final openBlock = [
      if (openTasks.isEmpty) ...[
        const SizedBox(height: 26),
        Text('> slate clear.', style: mono(context, size: 15, weight: FontWeight.w600, color: p.accent), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('no open tasks — the day is yours', style: TextStyle(color: p.dim, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 18),
      ] else
        TerminalCard(
          palette: p,
          children: [
            for (var i = 0; i < openTasks.length; i++) ...[
              if (i > 0) TerminalCardRule(palette: p),
              TaskRow(
                palette: p,
                task: openTasks[i],
                onToggle: () => store.toggleDone(openTasks[i].id),
                onOpen: () => showTaskSheet(context, initial: openTasks[i]),
              ),
            ],
          ],
        ),
      const SizedBox(height: 12),
      _AddTaskButton(palette: p),
    ];

    final doneBlock = [
      SectionHeader(palette: p, title: 'DONE · ${doneTasks.length}', trailing: 'tap to revive'),
      const SizedBox(height: 8),
      if (doneTasks.isEmpty)
        TerminalCard(
          palette: p,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '> nothing completed yet.',
                textAlign: TextAlign.center,
                style: mono(context, size: 10.5, color: p.dim),
              ),
            ),
          ],
        )
      else
        TerminalCard(
          palette: p,
          children: [
            for (var i = 0; i < doneTasks.length; i++) ...[
              if (i > 0) TerminalCardRule(palette: p),
              TaskRow(
                palette: p,
                task: doneTasks[i],
                onToggle: () => store.toggleDone(doneTasks[i].id),
                onOpen: () => showTaskSheet(context, initial: doneTasks[i]),
              ),
            ],
          ],
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      children: [
        if (store.recoveryNotice != null)
          _RecoveryBanner(
            palette: p,
            message: store.recoveryNotice!,
            onDismiss: store.clearRecoveryNotice,
          ),
        const SizedBox(height: 6),
        header,
        const SizedBox(height: 4),
        stats,
        const SizedBox(height: 14),
        if (!wide) ...[
          ...openBlock,
          if (doneTasks.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...doneBlock,
          ],
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: openBlock),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 6,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: doneBlock),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          'stored locally · synced to your private GitHub repo',
          textAlign: TextAlign.center,
          style: mono(context, size: 9, color: p.dim.withValues(alpha: 0.75), letterSpacing: 0.6),
        ),
      ],
    );
  }
}

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({required this.palette, required this.message, required this.onDismiss});

  final TerminalPalette palette;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.warn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.warn.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: palette.warn, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: palette.warn, fontSize: 11.5, height: 1.4))),
          IconButton(icon: Icon(Icons.close, size: 18, color: palette.dim), onPressed: onDismiss),
        ],
      ),
    );
  }
}

class _AddTaskButton extends StatelessWidget {
  const _AddTaskButton({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showTaskSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('+  ADD TASK', style: mono(context, size: 12, weight: FontWeight.w700, color: p.accent, letterSpacing: 2.4)),
            const SizedBox(width: 10),
            Text('↵', style: mono(context, size: 12, color: p.dim)),
          ],
        ),
      ),
    );
  }
}
