import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';


import '../state/event_store.dart';
import '../state/habit_store.dart';
import '../state/tasks_store.dart';
import '../version.dart';

/// One-tap disaster recovery: everything the app owns, as a single JSON
/// file, through the system share sheet (Save to Drive, email, Signal —
/// wherever the owner wants it). Never includes the GitHub token or the
/// iCal URL — those never leave secure storage.
Future<void> exportJsonBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final tasks = context.read<TasksStore>();
    final events = context.read<EventStore>();
    final habits = context.read<HabitStore>();

    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'app': 'daydeck',
      'appVersion': kAppVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'note': 'local backup — no tokens, no iCal URL, no calendar feed content',
      'tasks': tasks.snapshotItems().map((t) => t.toJson()).toList(),
      'events': events.snapshotItems().map((e) => e.toJson()).toList(),
      'habits': habits.snapshotHabits().map((h) => h.toJson()).toList(),
      'habit_logs': habits.snapshotLogs().map((l) => l.toJson()).toList(),
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);

    if (kIsWeb) {
      await SharePlus.instance.share(ShareParams(
        text: encoded,
        subject: 'daydeck backup ${_todayStamp()}',
      ));
      return;
    }

    final dir = await getTemporaryDirectory();
    final stamp = _todayStamp();
    final file = File('${dir.path}/daydeck-backup-$stamp.json');
    await file.writeAsString(encoded, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'daydeck backup $stamp',
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('export failed: $e')));
  }
}

String _todayStamp() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
}
