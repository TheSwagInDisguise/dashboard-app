import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';


import '../state/event_store.dart';
import '../state/focus_store.dart';
import '../state/habit_store.dart';
import '../state/tasks_store.dart';
import '../state/watch_store.dart';
import '../version.dart';
import '../sync/sync_service.dart';

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
    final focus = context.read<FocusStore>();
    final watches = context.read<WatchStore>();

    // schemaVersion 3 mirrors all syncable documents; watch photos are
    // device-local and deliberately not included.
    final payload = <String, dynamic>{
      'schemaVersion': 3,
      'app': 'daydeck',
      'appVersion': kAppVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'note': 'local backup — no tokens, no iCal URL, no calendar feed content, no photos',
      'tasks': tasks.snapshotItems().map((t) => t.toJson()).toList(),
      'events': events.snapshotItems().map((e) => e.toJson()).toList(),
      'habits': habits.snapshotHabits().map((h) => h.toJson()).toList(),
      'habit_logs': habits.snapshotLogs().map((l) => l.toJson()).toList(),
      'routines': habits.snapshotRoutines().map((r) => r.toJson()).toList(),
      'skip_rules': habits.snapshotSkipRules().map((r) => r.toJson()).toList(),
      'shield_uses': habits.snapshotShields().map((s) => s.toJson()).toList(),
      'xp_events': habits.snapshotXp().map((x) => x.toJson()).toList(),
      'watches': watches.snapshotWatches().map((w) => w.toJson()).toList(),
      'wear_logs': watches.snapshotWears().map((w) => w.toJson()).toList(),
      'straps': watches.snapshotStraps().map((s) => s.toJson()).toList(),
      'strap_swaps': watches.snapshotStrapSwaps().map((s) => s.toJson()).toList(),
      'watch_services': watches.snapshotServices().map((s) => s.toJson()).toList(),
      'focus_sessions': focus.snapshotSessions().map((s) => s.toJson()).toList(),
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

/// Select and safely merge a backup. This is intentionally non-destructive:
/// records are merged by id and update time; omitted documents are untouched,
/// and divergent versions are parked for the existing conflict-recovery UI.
Future<void> importJsonBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('The selected file is empty or unreadable.');
    }
    if (bytes.length > 50 * 1024 * 1024) {
      throw const FormatException(
        'Backup is larger than the 50 MB safety limit.',
      );
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('This is not a DayDeck JSON backup.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final app = payload['app']?.toString();
    if (app != null && app != 'daydeck') {
      throw const FormatException('This backup belongs to a different app.');
    }
    const keys = <String>[
      'tasks',
      'events',
      'habits',
      'habit_logs',
      'routines',
      'skip_rules',
      'shield_uses',
      'xp_events',
      'watches',
      'wear_logs',
      'straps',
      'strap_swaps',
      'watch_services',
      'focus_sessions',
    ];
    final present = keys.where((key) => payload[key] is List).toList();
    if (present.isEmpty) {
      throw const FormatException('No DayDeck data documents were found.');
    }
    final records = present.fold<int>(
      0,
      (sum, key) => sum + (payload[key] as List).length,
    );
    if (records == 0) {
      throw const FormatException('The backup contains no records to merge.');
    }
    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MERGE BACKUP?'),
        content: Text(
          '${file.name}\n\n$records records across ${present.length} data sections will be merged. Existing data is not erased. Conflicts are parked for review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('MERGE'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    final result = await context.read<SyncService>().mergeBackup(payload);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'backup merged · ${result.records} records · ${result.conflicts} conflict${result.conflicts == 1 ? '' : 's'} parked',
        ),
      ),
    );
  } on FormatException catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('backup not imported · ${e.message}')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('backup import failed · $e')),
      );
    }
  }
}

String _todayStamp() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
}
