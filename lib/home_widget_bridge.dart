import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'state/tasks_store.dart';

/// Pushes the glance-state into the Android home-screen widget.
/// Keys match DayDeckWidgetReceiver.kt — keep them in sync.
/// No-op on web (browsers have no home-screen widget).
Future<void> updateDayDeckWidget(TasksStore store) async {
  if (kIsWeb) return;
  try {
    final open = store.openTasks;
    final lines = open.take(4).map((t) {
      final due = t.dueDate != null ? ' · due ${_shortDue(t.dueDate!)}' : '';
      return '· ${_truncate(t.title, 46)}$due';
    }).join('\n');

    await HomeWidget.saveWidgetData<String>('open_count', '${store.openCount}');
    await HomeWidget.saveWidgetData<String>(
      'agenda',
      lines.isEmpty ? 'slate clear — nothing open' : lines,
    );
    await HomeWidget.saveWidgetData<String>(
      'footer',
      'daydeck · updated ${_stamp()}',
    );
    await HomeWidget.updateWidget(androidName: 'DayDeckWidgetReceiver');
  } catch (_) {}
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';

String _shortDue(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return key;
  return '${parts[2]}/${parts[1]}';
}

String _stamp() {
  final now = DateTime.now();
  return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}
