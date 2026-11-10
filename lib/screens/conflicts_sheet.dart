import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';

/// Review the losing versions parked by the sync engine (conflicts.json)
/// and restore any of them as brand-new items on this device. The parked
/// entries themselves stay untouched in the data repo.
Future<void> showConflictsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ConflictsSheet(),
  );
}

class _ConflictsSheet extends StatefulWidget {
  const _ConflictsSheet();

  @override
  State<_ConflictsSheet> createState() => _ConflictsSheetState();
}

class _ConflictsSheetState extends State<_ConflictsSheet> {
  List<Map<String, dynamic>>? _entries;
  String? _error;
  final Set<int> _restoring = {};
  final Set<int> _restored = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await context.read<SyncService>().fetchConflicts();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final entries = _entries;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: p.panel2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 42, height: 4, decoration: BoxDecoration(
                color: p.dim.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text('// SYNC CONFLICTS',
                        style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 2.2)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.refresh, color: p.dim, size: 20),
                      tooltip: 'reload',
                      onPressed: () {
                        setState(() {
                          _entries = null;
                          _error = null;
                        });
                        _load();
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: p.dim, size: 22),
                      tooltip: 'close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildBody(context, p, entries, controller),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    TerminalPalette p,
    List<Map<String, dynamic>>? entries,
    ScrollController controller,
  ) {
    if (_error != null) {
      return _centered(p, 'couldn’t read conflicts.json\n$_error');
    }
    if (entries == null) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }
    if (entries.isEmpty) {
      return _centered(p, '> conflicts.json is empty.\nnothing was ever lost — or it was, but nobody noticed.');
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      children: [
        Text(
          '${entries.length} parked losing version${entries.length == 1 ? '' : 's'} (newest first). '
          'RESTORE re-creates the item as a new one on this device.',
          style: mono(context, size: 9.5, color: p.dim),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < entries.length; i++) ...[
          _ConflictRow(
            palette: p,
            entry: entries[i],
            restoring: _restoring.contains(i),
            restored: _restored.contains(i),
            onRestore: () => _restore(i, entries[i]),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _restore(int index, Map<String, dynamic> entry) async {
    setState(() => _restoring.add(index));
    final ok = await context.read<SyncService>().restoreConflictAsNew(entry);
    if (!mounted) return;
    setState(() {
      _restoring.remove(index);
      if (ok) _restored.add(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'restored as a new ${_docLabel(entry['doc'])} item'
              : 'this entry can’t be restored (${_docLabel(entry['doc'])})',
        ),
      ),
    );
  }

  Widget _centered(TerminalPalette p, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.dim, fontSize: 12, height: 1.5),
        ),
      ),
    );
  }
}

String _docLabel(Object? doc) {
  switch (doc?.toString()) {
    case 'tasks.json':
      return 'task';
    case 'events.json':
      return 'event';
    case 'habits.json':
      return 'habit';
    case 'habit_logs.json':
      return 'habit log';
    default:
      return doc?.toString() ?? '?';
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.palette,
    required this.entry,
    required this.restoring,
    required this.restored,
    required this.onRestore,
  });

  final TerminalPalette palette;
  final Map<String, dynamic> entry;
  final bool restoring;
  final bool restored;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final item = entry['item'];
    final title = (item is Map ? item['title'] : null)?.toString() ??
        (entry['title']?.toString() ?? '(untitled)');
    final when = entry['when']?.toString() ?? '';
    final side = entry['side']?.toString() ?? '?';
    final doc = _docLabel(entry['doc']);
    final supported = ['task', 'event', 'habit'].contains(doc);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: restored ? p.good.withValues(alpha: 0.5) : p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  '$doc · $side-side lost · ${_fmtWhen(when)}',
                  style: mono(context, size: 8.5, color: p.dim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (restored)
            Icon(Icons.check_circle, color: p.good, size: 22)
          else if (supported)
            OutlinedButton(
              onPressed: restoring ? null : onRestore,
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 0),
              ),
              child: restoring
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                    )
                  : Text('RESTORE', style: mono(context, size: 9, weight: FontWeight.w700, letterSpacing: 1.5)),
            )
          else
            Tooltip(
              message: 'habit logs can’t be re-created — re-check the habit instead',
              child: Icon(Icons.info_outline, color: p.dim, size: 18),
            ),
        ],
      ),
    );
  }
}

String _fmtWhen(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
