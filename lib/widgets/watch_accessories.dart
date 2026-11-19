import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/habit.dart' show dateOfEpochDay;
import '../models/watch.dart';
import '../state/watch_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import 'section_header.dart';
import 'terminal_card.dart';

class WatchNextCard extends StatelessWidget {
  const WatchNextCard({super.key, required this.palette});
  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WatchStore>();
    final watch = store.nextSuggestion;
    return TerminalCard(
      palette: palette,
      children: [
        Row(
          children: [
            Text(
              'WATCH NEXT',
              style: mono(
                context,
                size: 9,
                weight: FontWeight.w800,
                color: palette.accent,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            Text(
              'rotation pick',
              style: mono(context, size: 8, color: palette.dim),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (watch == null)
          Text(
            'add an owned watch to start a rotation',
            style: mono(context, size: 9, color: palette.dim),
          )
        else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      watch.displayName,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      store.nextSuggestionReason(watch),
                      style: mono(context, size: 8, color: palette.dim),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                key: const ValueKey('watch-next-log'),
                onPressed: () => store.logTodaysWear(watch.id),
                icon: Icon(
                  Icons.watch_outlined,
                  size: 15,
                  color: palette.accent,
                ),
                label: Text(
                  'WEAR',
                  style: mono(
                    context,
                    size: 8,
                    weight: FontWeight.w800,
                    color: palette.accent,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class ServiceDueList extends StatelessWidget {
  const ServiceDueList({super.key, required this.palette});
  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WatchStore>();
    final tracked = store.collection
        .map((w) => (watch: w, due: store.nextServiceDue(w)))
        .where((x) => x.due != null)
        .toList();
    if (tracked.isEmpty) return const SizedBox.shrink();
    final today = DateTime.now();
    final due = tracked
        .where(
          (x) => !DateTime(
            x.due!.year,
            x.due!.month,
            x.due!.day,
          ).isAfter(DateTime(today.year, today.month, today.day)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          palette: palette,
          title: 'SERVICE WATCH',
          trailing: due.isEmpty ? 'all clear' : '${due.length} due',
        ),
        const SizedBox(height: 6),
        for (final item in due.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: palette.bad.withValues(alpha: .08),
                border: Border.all(color: palette.bad.withValues(alpha: .4)),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  Icon(Icons.build_outlined, size: 13, color: palette.bad),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${item.watch.displayName} · due ${_date(item.due!)}',
                      style: mono(
                        context,
                        size: 8,
                        weight: FontWeight.w700,
                        color: palette.bad,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        showWatchServiceDialog(context, item.watch),
                    child: Text(
                      'LOG',
                      style: mono(context, size: 8, color: palette.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class StrapLibrary extends StatelessWidget {
  const StrapLibrary({super.key, required this.palette});
  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WatchStore>();
    final watches = store.collection;
    final straps = store.straps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          palette: palette,
          title: 'STRAP LIBRARY',
          trailing: '${straps.length}',
        ),
        const SizedBox(height: 7),
        TerminalCard(
          palette: palette,
          children: [
            if (straps.isEmpty)
              Text(
                'no straps logged yet',
                style: mono(context, size: 9, color: palette.dim),
              )
            else
              for (var i = 0; i < straps.length; i++) ...[
                if (i > 0) TerminalCardRule(palette: palette),
                _StrapRow(palette: palette, strap: straps[i]),
              ],
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('add-strap-button'),
                onPressed: () => _addStrap(context),
                icon: Icon(Icons.add, size: 15, color: palette.accent),
                label: Text(
                  'ADD STRAP',
                  style: mono(
                    context,
                    size: 8,
                    weight: FontWeight.w800,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
            if (watches.isEmpty)
              Text(
                'add a watch before fitting straps',
                style: mono(context, size: 8, color: palette.dim),
              ),
          ],
        ),
      ],
    );
  }
}

class _StrapRow extends StatelessWidget {
  const _StrapRow({required this.palette, required this.strap});
  final TerminalPalette palette;
  final Strap strap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WatchStore>();
    final watch = strap.watchId == null
        ? null
        : store.watches.where((w) => w.id == strap.watchId).firstOrNull;
    final swaps = store.swapsFor(strap.id);
    final latest = swaps.isEmpty ? null : swaps.first;
    final fittedDays = watch == null || latest == null
        ? null
        : (DateTime.now().difference(dateOfEpochDay(latest.day)).inDays).clamp(
            0,
            9999,
          );
    final where = watch == null
        ? 'IN DRAWER'
        : 'ON ${watch.displayName.toUpperCase()}${fittedDays == null ? '' : ' · ${fittedDays}D'}';
    final meta = [
      strap.material,
      strap.color,
      strap.widthMm == null ? '' : '${strap.widthMm}mm',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return Row(
      children: [
        Icon(
          Icons.watch,
          size: 15,
          color: watch == null ? palette.dim : palette.accent,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strap.name,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                meta.isEmpty ? where : '$meta · $where',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: mono(context, size: 7.5, color: palette.dim),
              ),
              for (final swap in swaps.take(3))
                Text(
                  '${_date(dateOfEpochDay(swap.day))} → ${swap.watchId == null ? 'drawer' : store.watches.where((w) => w.id == swap.watchId).firstOrNull?.displayName ?? 'watch'}${swap.note.isEmpty ? '' : ' · ${swap.note}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 7, color: palette.dim),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'fit or move strap',
          key: ValueKey('fit-strap-${strap.id}'),
          onPressed: () => _chooseFit(context, strap),
          icon: Icon(Icons.swap_horiz, size: 18, color: palette.accent),
        ),
      ],
    );
  }
}

Future<void> _addStrap(BuildContext context) async {
  final name = TextEditingController();
  final material = TextEditingController();
  final color = TextEditingController();
  final width = TextEditingController();
  final p = context.read<WatchStore>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ADD STRAP'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'name'),
            ),
            TextField(
              controller: material,
              decoration: const InputDecoration(labelText: 'material'),
            ),
            TextField(
              controller: color,
              decoration: const InputDecoration(labelText: 'colour'),
            ),
            TextField(
              controller: width,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'lug width mm'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('SAVE'),
        ),
      ],
    ),
  );
  if (ok == true && name.text.trim().isNotEmpty) {
    await p.addStrap(
      name: name.text,
      material: material.text,
      color: color.text,
      widthMm: int.tryParse(width.text),
    );
  }
  name.dispose();
  material.dispose();
  color.dispose();
  width.dispose();
}

Future<void> _chooseFit(BuildContext context, Strap strap) async {
  final store = context.read<WatchStore>();
  final watches = store.collection;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('FIT ${strap.name.toUpperCase()}'),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('IN THE DRAWER'),
              leading: const Icon(Icons.inventory_2_outlined),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final watch in watches)
              ListTile(
                title: Text(watch.displayName),
                leading: const Icon(Icons.watch_outlined),
                onTap: () => Navigator.pop(ctx, watch.id),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('CANCEL'),
        ),
      ],
    ),
  );
  if (result != null) {
    await store.fitStrap(strap.id, result.isEmpty ? null : result);
  }
}

Future<void> showWatchServiceDialog(BuildContext context, Watch watch) async {
  final description = TextEditingController();
  final store = context.read<WatchStore>();
  final save = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('LOG SERVICE · ${watch.displayName}'),
      content: TextField(
        controller: description,
        decoration: const InputDecoration(labelText: 'work done / notes'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('LOG TODAY'),
        ),
      ],
    ),
  );
  if (save == true) {
    await store.logService(
      watchId: watch.id,
      date: DateTime.now(),
      description: description.text,
    );
  }
  description.dispose();
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
