import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/habit.dart' show epochDayOf, dateOfEpochDay;
import '../models/watch.dart';
import '../state/app_state.dart';
import '../state/watch_photo_store.dart';
import '../state/watch_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../widgets/watch_accessories.dart';
import '../widgets/terminal_card.dart';
import '../widgets/terminal_chip.dart';

/// The rotation — a wear tracker for the collection. Metadata (which watch,
/// when) syncs like everything else; the photos never leave this device.
class WatchScreen extends StatelessWidget {
  const WatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final store = context.watch<WatchStore>();
    final collection = store.collection;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Text(
              '// WATCHES',
              style: mono(context, size: 24, weight: FontWeight.w700, color: p.accent, letterSpacing: 6),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'the rotation · every wristshot logged',
              style: mono(context, size: 9.5, color: p.dim, letterSpacing: 2.4),
            ),
          ),
          const SizedBox(height: 18),
          if (collection.isEmpty && store.watches.isEmpty)
            _EmptyWatchState(palette: p)
          else ...[
            WatchNextCard(palette: p),
            const SizedBox(height: 10),
            ServiceDueList(palette: p),
            const SizedBox(height: 10),
            StrapLibrary(palette: p),
            const SizedBox(height: 14),
            _WearTodayCard(palette: p),
            const SizedBox(height: 14),
            _StatsStrip(palette: p),
            const SizedBox(height: 14),
            SectionHeader(palette: p, title: 'THE VAULT', trailing: 'least worn first'),
            const SizedBox(height: 8),
            _VaultList(palette: p),
            const SizedBox(height: 14),
            SectionHeader(palette: p, title: 'COLLECTION', trailing: '${store.watches.where((w) => !w.deleted && !w.archived).length}'),
            const SizedBox(height: 8),
            _CollectionList(palette: p),
          ],
          const SizedBox(height: 12),
          _AddWatchButton(palette: p, onTap: () => _showWatchSheet(context)),
        ],
      ),
    );
  }
}

/// One-tap "I wore X today" for the collection.
class _WearTodayCard extends StatelessWidget {
  const _WearTodayCard({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final store = context.watch<WatchStore>();
    final collection = store.collection;
    final todayWears = store.wearLogs.where((w) => w.day == epochDayOf(DateTime.now())).toList();
    final wornIds = todayWears.map((w) => w.watchId).toSet();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: p.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TODAY', style: mono(context, size: 10, weight: FontWeight.w800, color: p.accent, letterSpacing: 2)),
              const SizedBox(width: 8),
              Text(
                wornIds.isEmpty ? 'nothing on the wrist yet' : '${wornIds.length} on the wrist',
                style: mono(context, size: 9.5, color: p.dim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (collection.isEmpty)
            Text('add a watch below to start the rotation', style: TextStyle(color: p.dim, fontSize: 10.5))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final watch in collection)
                  _WearChip(
                    palette: p,
                    watch: watch,
                    worn: wornIds.contains(watch.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WearChip extends StatelessWidget {
  const _WearChip({required this.palette, required this.watch, required this.worn});

  final TerminalPalette palette;
  final Watch watch;
  final bool worn;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return InkWell(
      onTap: () => _logWear(context, watch),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 92,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          color: worn ? p.accent.withValues(alpha: 0.15) : p.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: worn ? p.accent : p.border),
        ),
        child: Column(
          children: [
            _WatchAvatar(watch: watch, size: 46, fontSize: 12),
            const SizedBox(height: 5),
            Text(
              watch.displayName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: worn ? p.accent : p.text, fontSize: 8.5, height: 1.25, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              worn ? 'ON WRIST ✓' : 'WORE IT',
              style: mono(context, size: 7, weight: FontWeight.w800, color: worn ? p.accent : p.dim, letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _logWear(BuildContext context, Watch watch) async {
  final store = context.read<WatchStore>();
  final photos = context.read<WatchPhotoStore>();
  final wear = await store.logTodaysWear(watch.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 4),
      content: Text('${watch.displayName} on the wrist today'),
      action: SnackBarAction(
        label: 'WRIST SHOT',
        onPressed: () => _pickPhoto(context, (path) => photos.setWristShot(wear.id, path)),
      ),
    ),
  );
}

/// Avatar: profile photo if set locally, otherwise initials.
class _WatchAvatar extends StatelessWidget {
  const _WatchAvatar({required this.watch, required this.size, this.fontSize = 15});

  final Watch watch;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final photos = context.watch<WatchPhotoStore>();
    final rel = photos.relativeForWatch(watch.id);
    return FutureBuilder<String?>(
      future: photos.absoluteFor(rel),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initials(p),
            ),
          );
        }
        return _initials(p);
      },
    );
  }

  Widget _initials(TerminalPalette p) {
    final letters = watch.displayName.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent.withValues(alpha: 0.16), border: Border.all(color: p.accent.withValues(alpha: 0.5))),
      child: Text(
        letters.isEmpty ? '?' : letters,
        style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: fontSize, fontWeight: FontWeight.w800, color: p.accent),
      ),
    );
  }
}

/// Quick stats: wears logged, most/least worn.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final store = context.watch<WatchStore>();
    final most = store.mostWorn;
    final least = store.leastWorn;

    Widget cell(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: mono(context, size: 15, weight: FontWeight.w800, color: p.accent), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(label, style: mono(context, size: 7.5, color: p.dim, letterSpacing: 1.2)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          cell('${store.totalWears}', 'TOTAL WEARS'),
          Container(width: 1, height: 30, color: p.border),
          cell(most == null ? '—' : '${store.wearCount(most.id)}× ${most.displayName}', 'MOST WORN'),
          Container(width: 1, height: 30, color: p.border),
          cell(least == null ? '—' : '${store.wearCount(least.id)}× ${least.displayName}', 'LEAST WORN'),
        ],
      ),
    );
  }
}

/// The vault: collection watches by days-since-worn, neglected first.
class _VaultList extends StatelessWidget {
  const _VaultList({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final store = context.watch<WatchStore>();
    final vault = store.vault;
    final epoch = epochDayOf(DateTime.now());

    return TerminalCard(
      palette: p,
      children: [
        for (final watch in vault) ...[
          if (watch != vault.first) TerminalCardRule(palette: p),
          _VaultRow(palette: p, watch: watch, todayEpoch: epoch),
        ],
      ],
    );
  }
}

class _VaultRow extends StatelessWidget {
  const _VaultRow({required this.palette, required this.watch, required this.todayEpoch});

  final TerminalPalette palette;
  final Watch watch;
  final int todayEpoch;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final store = context.watch<WatchStore>();
    final wears = store.wearsOf(watch.id);
    final days = wears.isEmpty ? null : todayEpoch - wears.first.day;
    final neglected = days == null || days >= 30;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _WatchAvatar(watch: watch, size: 38, fontSize: 10.5),
      title: Text(watch.displayName, style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        days == null ? 'never worn' : '${days == 0 ? 'on wrist today' : '${days}d since last worn'} · ${wears.length}× total',
        style: mono(context, size: 8.5, color: neglected ? p.warn : p.dim),
      ),
      trailing: InkWell(
        onTap: () => _logWear(context, watch),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border), color: p.panel2),
          child: Text('WORE\nIT', textAlign: TextAlign.center, style: mono(context, size: 7, weight: FontWeight.w800, color: p.accent).copyWith(height: 1.15)),
        ),
      ),
      onTap: () => _showWatchDetail(context, watch),
    );
  }
}

/// Full list incl. status filter; tap for detail.
class _CollectionList extends StatefulWidget {
  const _CollectionList({required this.palette});

  final TerminalPalette palette;

  @override
  State<_CollectionList> createState() => _CollectionListState();
}

class _CollectionListState extends State<_CollectionList> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final store = context.watch<WatchStore>();
    final visible = store.watches.where((w) {
      if (w.deleted || w.archived) return false;
      return switch (_filter) {
        'all' => true,
        'owned' => w.status == Watch.statusOwned,
        'repair' => w.status == Watch.statusRepair,
        'wishlist' => w.status == Watch.statusWishlist,
        'sold' => w.status == Watch.statusSold,
        _ => true,
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in const ['all', 'owned', 'repair', 'wishlist', 'sold'])
              _StatusFilterChip(palette: p, label: f.toUpperCase(), selected: _filter == f, onTap: () => setState(() => _filter = f)),
          ],
        ),
        const SizedBox(height: 8),
        TerminalCard(
          palette: p,
          children: [
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('nothing here — add a watch →', textAlign: TextAlign.center, style: mono(context, size: 10, color: p.dim)),
              )
            else
              for (final watch in visible) ...[
                if (watch != visible.first) TerminalCardRule(palette: p),
                _CollectionRow(palette: p, watch: watch),
              ],
          ],
        ),
      ],
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({required this.palette, required this.label, required this.selected, required this.onTap});

  final TerminalPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? p.accent : p.border),
          color: selected ? p.accent.withValues(alpha: 0.14) : null,
        ),
        child: Text(label, style: mono(context, size: 8, weight: FontWeight.w700, color: selected ? p.accent : p.dim, letterSpacing: 1.2)),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.palette, required this.watch});

  final TerminalPalette palette;
  final Watch watch;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final store = context.watch<WatchStore>();
    final count = store.wearCount(watch.id);
    final maxCount = store.collection.map((w) => store.wearCount(w.id)).fold<int>(0, (a, b) => a > b ? a : b);
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _WatchAvatar(watch: watch, size: 38, fontSize: 10.5),
      title: Row(
        children: [
          Expanded(
            child: Text(watch.displayName, style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (watch.status != Watch.statusOwned)
            TerminalChip(label: watch.status.toUpperCase(), color: watch.status == Watch.statusSold ? p.dim : p.warn),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: fraction,
                  backgroundColor: p.border,
                  valueColor: AlwaysStoppedAnimation(p.accent),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$count×', style: mono(context, size: 9, color: p.dim)),
          ],
        ),
      ),
      trailing: IconButton(
        tooltip: 'add or change watch photo',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.add_a_photo_outlined, color: p.accent, size: 19),
        onPressed: () => _pickPhoto(
          context,
          (path) => context.read<WatchPhotoStore>().setProfilePhoto(watch.id, path),
        ),
      ),
      onTap: () => _showWatchDetail(context, watch),
    );
  }
}

class _EmptyWatchState extends StatelessWidget {
  const _EmptyWatchState({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return TerminalCard(
      palette: p,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 18, 6, 18),
          child: Column(
            children: [
              Text('// the box is empty', style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 2)),
              const SizedBox(height: 10),
              Text(
                'Add the watch on your wrist.\nTap “wore it” each day it goes on — daydeck keeps the rotation honest.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.dim, fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddWatchButton extends StatelessWidget {
  const _AddWatchButton({required this.palette, required this.onTap});

  final TerminalPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: p.accent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
          child: Text('+ ADD WATCH', textAlign: TextAlign.center,
              style: mono(context, size: 11, weight: FontWeight.w700, color: p.bg, letterSpacing: 1.8)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- photo pick

Future<void> _pickPhoto(BuildContext context, Future<bool> Function(String path) ingest) async {
  final p = context.read<AppState>().palette;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: p.panel2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('// WRIST / PROFILE PHOTO', style: mono(ctx, size: 11, weight: FontWeight.w700, color: p.accent, letterSpacing: 2)),
            const SizedBox(height: 4),
            Text('stored on this device only — never uploaded, never synced',
                style: TextStyle(color: p.dim, fontSize: 9.5)),
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: p.text),
              title: Text('camera', style: TextStyle(color: p.text)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: p.text),
              title: Text('photo library', style: TextStyle(color: p.text)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return;
  try {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;
    final ok = await ingest(picked.path);
    if (context.mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('could not save that photo')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('photo picker unavailable here')));
    }
  }
}

// ---------------------------------------------------------------- detail sheet

void _showWatchDetail(BuildContext context, Watch watch) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WatchDetailSheet(watchId: watch.id),
  );
}

class _WatchDetailSheet extends StatelessWidget {
  const _WatchDetailSheet({required this.watchId});

  final String watchId;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final store = context.watch<WatchStore>();
    final photos = context.watch<WatchPhotoStore>();
    Watch? found;
    for (final w in store.watches) {
      if (w.id == watchId) {
        found = w;
        break;
      }
    }
    if (found == null) {
      return const SizedBox.shrink();
    }
    final watch = found;
    final wears = store.wearsOf(watch.id);
    final firstWear = wears.isEmpty ? null : wears.last.day;
    final rel = photos.relativeForWatch(watch.id);
    WearLog? todayWear;
    for (final w in wears) {
      if (w.day == epochDayOf(DateTime.now())) {
        todayWear = w;
        break;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: BoxDecoration(
          color: p.panel2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: p.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('// ${watch.displayName.toUpperCase()}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 1.6)),
                    ),
                    IconButton(icon: Icon(Icons.close, color: p.dim), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Center(
                  child: GestureDetector(
                    onTap: () => _pickPhoto(context, (path) => photos.setProfilePhoto(watch.id, path)),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        _DetailPhoto(watch: watch, rel: rel, size: 170),
                        Container(
                          decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.edit, size: 14, color: p.accent),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (rel != null)
                  Center(
                    child: TextButton(
                      onPressed: () => photos.clearProfilePhoto(watch.id),
                      child: Text('remove photo', style: mono(context, size: 9, color: p.dim)),
                    ),
                  ),
                const SizedBox(height: 8),
                _WatchSpec(palette: p, label: 'movement', value: watch.movement.isEmpty ? '—' : watch.movement),
                _WatchSpec(palette: p, label: 'reference', value: watch.reference.isEmpty ? '—' : watch.reference),
                _WatchSpec(
                  palette: p,
                  label: 'case',
                  value: watch.caseSizeMm == null ? '—' : '${watch.caseSizeMm!.toStringAsFixed(watch.caseSizeMm! % 1 == 0 ? 0 : 1)} mm',
                ),
                _WatchSpec(palette: p, label: 'status', value: watch.status.toUpperCase()),
                if (watch.notes.isNotEmpty) Text(watch.notes, style: TextStyle(color: p.dim, fontSize: 11, height: 1.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () async {
                            await context.read<WatchStore>().logTodaysWear(watch.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('on the wrist today · ${watch.displayName}')));
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
                            child: Text(
                              todayWear == null ? 'WORE IT TODAY' : 'ON WRIST TODAY ✓',
                              textAlign: TextAlign.center,
                              style: mono(context, size: 10, weight: FontWeight.w800, color: p.bg, letterSpacing: 1.4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('// WEAR LOG · ${wears.length}', style: mono(context, size: 9.5, weight: FontWeight.w700, color: p.dim, letterSpacing: 1.6)),
                const SizedBox(height: 4),
                if (wears.isEmpty)
                  Text('no wears logged yet — every tap above counts.', style: TextStyle(color: p.dim, fontSize: 10.5))
                else
                  for (final wear in wears.take(30))
                    _WearRow(palette: p, wear: wear, watchId: watch.id),
                if (firstWear != null) ...[
                  const SizedBox(height: 8),
                  Text('in the rotation since ${_ddmmyyyy(dateOfEpochDay(firstWear))}',
                      style: mono(context, size: 9, color: p.dim)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showWatchSheet(context, initial: watch);
                      },
                      child: Text('EDIT', style: mono(context, size: 10, weight: FontWeight.w700, color: p.dim, letterSpacing: 1.6)),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final store = context.read<WatchStore>();
                        final photos = context.read<WatchPhotoStore>();
                        final wearIds = wears.map((w) => w.id).toList();
                        await store.deleteWatch(watch.id);
                        await photos.removeAllForWatch(watch.id, wearIds);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text('DELETE', style: mono(context, size: 10, weight: FontWeight.w700, color: p.bad, letterSpacing: 1.6)),
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

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _DetailPhoto extends StatelessWidget {
  const _DetailPhoto({required this.watch, required this.rel, required this.size});

  final Watch watch;
  final String? rel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;
    final photos = context.watch<WatchPhotoStore>();
    return FutureBuilder<String?>(
      future: photos.absoluteFor(rel),
      builder: (context, snapshot) {
        final path = snapshot.data;
        final shape = BorderRadius.circular(16);
        if (path == null) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: shape, color: p.panel, border: Border.all(color: p.border)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.watch_outlined, size: 44, color: p.dim),
                const SizedBox(height: 6),
                Text('no photo yet', style: mono(context, size: 8.5, color: p.dim, letterSpacing: 1.2)),
                Text('tap to add one', style: mono(context, size: 8.5, color: p.accent)),
              ],
            ),
          );
        }
        return ClipRRect(
          borderRadius: shape,
          child: Image.file(File(path), width: size, height: size, fit: BoxFit.cover),
        );
      },
    );
  }
}

class _WatchSpec extends StatelessWidget {
  const _WatchSpec({required this.palette, required this.label, required this.value});

  final TerminalPalette palette;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label.toUpperCase(), style: mono(context, size: 8, color: p.dim, letterSpacing: 1.4)),
          ),
          Expanded(child: Text(value, style: TextStyle(color: p.text, fontSize: 11.5))),
        ],
      ),
    );
  }
}

class _WearRow extends StatelessWidget {
  const _WearRow({required this.palette, required this.wear, required this.watchId});

  final TerminalPalette palette;
  final WearLog wear;
  final String watchId;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final photos = context.watch<WatchPhotoStore>();
    final rel = photos.relativeForWear(wear.id);
    final d = dateOfEpochDay(wear.day);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(_ddmmyyyy(d), style: mono(context, size: 9, color: p.dim)),
          ),
          FutureBuilder<String?>(
            future: photos.absoluteFor(rel),
            builder: (context, snapshot) {
              final path = snapshot.data;
              if (path != null) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(path), width: 30, height: 30, fit: BoxFit.cover),
                );
              }
              return InkWell(
                onTap: () => _pickPhoto(context, (p2) => photos.setWristShot(wear.id, p2)),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: p.border)),
                  child: Icon(Icons.add_a_photo_outlined, size: 14, color: p.dim),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(wear.note.isEmpty ? '—' : wear.note, style: TextStyle(color: p.dim, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: p.dim),
            tooltip: 'remove this wear',
            onPressed: () => context.read<WatchStore>().removeWear(wear.id),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- add/edit sheet

void _showWatchSheet(BuildContext context, {Watch? initial}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WatchSheet(initial: initial),
  );
}

class _WatchSheet extends StatefulWidget {
  const _WatchSheet({this.initial});

  final Watch? initial;

  @override
  State<_WatchSheet> createState() => _WatchSheetState();
}

class _WatchSheetState extends State<_WatchSheet> {
  late final TextEditingController _name;
  late final TextEditingController _nick;
  late final TextEditingController _brand;
  late final TextEditingController _movement;
  late final TextEditingController _ref;
  late final TextEditingController _case;
  late final TextEditingController _notes;

  late String _status;
  bool _saving = false;

  static const _statusOptions = [Watch.statusOwned, Watch.statusRepair, Watch.statusWishlist, Watch.statusSold];

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    _name = TextEditingController(text: h?.model ?? '');
    _nick = TextEditingController(text: h?.nickname ?? '');
    _brand = TextEditingController(text: h?.brand ?? '');
    _movement = TextEditingController(text: h?.movement ?? '');
    _ref = TextEditingController(text: h?.reference ?? '');
    _case = TextEditingController(text: h?.caseSizeMm == null ? '' : '${h!.caseSizeMm}');
    _notes = TextEditingController(text: h?.notes ?? '');
    _status = h?.status ?? Watch.statusOwned;
  }

  @override
  void dispose() {
    for (final c in [_name, _nick, _brand, _movement, _ref, _case, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('give the watch a name first')));
      return;
    }
    setState(() => _saving = true);
    final store = context.read<WatchStore>();
    final caseMm = double.tryParse(_case.text.trim());
    if (widget.initial != null) {
      await store.updateWatch(widget.initial!.copyWith(
            brand: _brand.text.trim(),
            model: name,
            nickname: _nick.text.trim(),
            movement: _movement.text.trim(),
            reference: _ref.text.trim(),
            caseSizeMm: caseMm,
            clearCaseSizeMm: caseMm == null,
            status: _status,
            notes: _notes.text.trim(),
          ));
    } else {
      await store.addWatch(
            brand: _brand.text.trim(),
            model: name,
            nickname: _nick.text.trim(),
            movement: _movement.text.trim(),
            reference: _ref.text.trim(),
            caseSizeMm: caseMm,
            status: _status,
            notes: _notes.text.trim(),
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().palette;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: p.panel2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: p.border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(widget.initial != null ? '// EDIT WATCH' : '// ADD WATCH',
                        style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 2.4)),
                    const Spacer(),
                    IconButton(icon: Icon(Icons.close, color: p.dim), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                TextField(
                  controller: _name,
                  autofocus: widget.initial == null,
                  style: TextStyle(color: p.text),
                  decoration: const InputDecoration(labelText: 'model', hintText: 'e.g. SKX007'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nick,
                  style: TextStyle(color: p.text),
                  decoration: const InputDecoration(labelText: 'nickname (optional)', hintText: 'the “diver”'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _brand,
                        style: TextStyle(color: p.text),
                        decoration: const InputDecoration(labelText: 'brand'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _movement,
                        style: TextStyle(color: p.text),
                        decoration: const InputDecoration(labelText: 'movement', hintText: 'automatic'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ref,
                        style: TextStyle(color: p.text),
                        decoration: const InputDecoration(labelText: 'reference'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 84,
                      child: TextField(
                        controller: _case,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: p.text),
                        decoration: const InputDecoration(labelText: 'case mm'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _WatchLabel(palette: p, text: 'STATUS'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in _statusOptions)
                      ChoiceChip(
                        label: Text(s.toUpperCase()),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  style: TextStyle(color: p.text, fontSize: 12),
                  decoration: const InputDecoration(labelText: 'notes'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.initial != null)
                      TextButton(
                        onPressed: () async {
                          final store = context.read<WatchStore>();
                          await store.archiveWatch(widget.initial!.id, !widget.initial!.archived);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Text(widget.initial!.archived ? 'UNARCHIVE' : 'ARCHIVE',
                            style: mono(context, size: 10, weight: FontWeight.w700, color: p.dim, letterSpacing: 1.6)),
                      ),
                    const Spacer(),
                    Material(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _saving ? null : _save,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                          child: Text(_saving ? 'SAVING…' : 'SAVE',
                              style: mono(context, size: 11, weight: FontWeight.w700, color: p.bg, letterSpacing: 1.6)),
                        ),
                      ),
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

class _WatchLabel extends StatelessWidget {
  const _WatchLabel({required this.palette, required this.text});

  final TerminalPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: mono(context, size: 8.5, color: palette.dim, letterSpacing: 1.6));
}
