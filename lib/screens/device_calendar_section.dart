import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/calendar_feed.dart';
import '../data/device_calendar.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';

/// GOOGLE CALENDAR · DEVICE — reads calendars *synced onto this phone*
/// (Android only). The reliable path for a private shared calendar:
/// your phone already syncs it, so the app just asks for read access.
/// Nothing is uploaded; events never leave the device.
class DeviceCalendarSection extends StatefulWidget {
  const DeviceCalendarSection({super.key, required this.palette});

  final TerminalPalette palette;

  @override
  State<DeviceCalendarSection> createState() => _DeviceCalendarSectionState();
}

class _DeviceCalendarSectionState extends State<DeviceCalendarSection> {
  bool _permKnown = false;
  bool _permGranted = false;
  bool _busy = false;

  TerminalPalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await DeviceCalendarReader.checkPermission();
    if (!mounted) return;
    setState(() {
      _permGranted = granted;
      _permKnown = true;
    });
  }

  Future<void> _toggle(bool on) async {
    final app = context.read<AppState>();
    final feed = context.read<CalendarFeed>();
    if (on) {
      // User gesture — the right moment for the system permission dialog.
      final granted = await DeviceCalendarReader.requestPermission();
      if (!mounted) return;
      setState(() {
        _permGranted = granted;
        _permKnown = true;
      });
      await app.setDeviceCalendarEnabled(true);
      if (mounted) await feed.refresh();
      if (!granted && mounted) {
        _snack('permission denied — enable “calendar” for daydeck in Android settings');
      }
    } else {
      await app.setDeviceCalendarEnabled(false);
      if (mounted) await feed.refresh();
    }
  }

  Future<void> _grant() async {
    final feed = context.read<CalendarFeed>();
    final granted = await DeviceCalendarReader.requestPermission();
    if (!mounted) return;
    setState(() {
      _permGranted = granted;
      _permKnown = true;
    });
    if (granted) await feed.refresh();
  }

  Future<void> _choose() async {
    final app = context.read<AppState>();
    final feed = context.read<CalendarFeed>();
    setState(() => _busy = true);
    List<DeviceCalendarInfo> calendars;
    try {
      calendars = await DeviceCalendarReader.listCalendars();
    } catch (e) {
      if (mounted) _snack('couldn’t list calendars: ${e.toString().replaceFirst('Exception: ', '')}');
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (_) => _CalendarPickerDialog(
        palette: p,
        calendars: calendars,
        initialSelection: app.deviceCalendarIds.toSet(),
      ),
    );
    if (saved == null) return;
    await app.setDeviceCalendarIds(saved);
    if (mounted) await feed.refresh();
    if (mounted) _snack(saved.isEmpty ? 'all synced calendars selected' : 'calendar selection saved');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink(); // web keeps the GitHub Action path; see GOOGLE CALENDAR above
    }
    final p = this.p;
    final app = context.watch<AppState>();
    final enabled = app.deviceCalendarEnabled;
    final selectedCount = app.deviceCalendarIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(palette: p, title: 'DEVICE CALENDAR', trailing: 'android'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.phone_android, size: 20, color: p.dim),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'read calendars synced to this phone',
                          style: TextStyle(color: p.text, fontSize: 13, height: 1.35),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'for private shared calendars with no secret iCal link',
                          style: mono(context, size: 8.5, color: p.dim),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    activeThumbColor: p.accent,
                    onChanged: _busy ? null : _toggle,
                  ),
                ],
              ),
              if (enabled) ...[
                const SizedBox(height: 10),
                if (!_permKnown)
                  Text('checking permission…', style: mono(context, size: 9, color: p.dim))
                else if (!_permGranted) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'calendar permission needed — the app can only read what the phone syncs',
                          style: TextStyle(color: p.warn, fontSize: 10.5, height: 1.45),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _SmallButton(palette: p, label: 'GRANT', onTap: _grant),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedCount == 0
                              ? 'reading every calendar synced to this phone'
                              : 'reading $selectedCount of the phone’s calendars',
                          style: mono(context, size: 9, color: p.dim),
                        ),
                      ),
                      _SmallButton(
                        palette: p,
                        label: _busy ? '…' : 'CHOOSE',
                        onTap: _busy ? () {} : _choose,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'tip · shared calendar not on this phone yet? open Google Calendar → ☰ → '
                  'settings → your account → make sure the shared calendar is ticked, then come back and pull-to-refresh',
                  style: mono(context, size: 8, color: p.dim).copyWith(height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.palette, required this.label, required this.onTap});

  final TerminalPalette palette;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.accent,
        side: BorderSide(color: palette.accent.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
      child: Text(label, style: mono(context, size: 9.5, weight: FontWeight.w700, letterSpacing: 1.6)),
    );
  }
}

class _CalendarPickerDialog extends StatefulWidget {
  const _CalendarPickerDialog({
    required this.palette,
    required this.calendars,
    required this.initialSelection,
  });

  final TerminalPalette palette;
  final List<DeviceCalendarInfo> calendars;

  /// Empty = all calendars selected.
  final Set<String> initialSelection;

  @override
  State<_CalendarPickerDialog> createState() => _CalendarPickerDialogState();
}

class _CalendarPickerDialogState extends State<_CalendarPickerDialog> {
  late Set<String> _selected;

  bool get _allSelected => _selected.length == widget.calendars.length;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection.isEmpty
        ? widget.calendars.map((c) => c.id).toSet()
        : widget.initialSelection;
  }

  void _save() {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('pick at least one calendar, or turn the toggle off')),
      );
      return;
    }
    // Storing every id == "all": collapse to empty so the feed's default matches.
    Navigator.of(context).pop(_allSelected ? <String>[] : _selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return AlertDialog(
      backgroundColor: p.panel,
      title: Text('calendars on this phone',
          style: mono(context, size: 11, weight: FontWeight.w700, color: p.accent, letterSpacing: 1.8)),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.calendars.isEmpty
            ? Text(
                'no calendars visible to this phone. open Google Calendar once, tick the calendar under your account, then retry.',
                style: TextStyle(color: p.dim, fontSize: 11, height: 1.5),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final cal in widget.calendars)
                    CheckboxListTile(
                      value: _selected.contains(cal.id),
                      activeColor: p.accent,
                      dense: true,
                      side: BorderSide(color: p.dim),
                      title: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(color: Color(cal.color | 0xFF000000), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cal.name,
                              style: TextStyle(color: p.text, fontSize: 12, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${cal.account}${cal.syncEnabled ? '' : ' · not syncing to this phone'}',
                        style: mono(context, size: 8, color: p.dim),
                      ),
                      onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(cal.id);
                            } else {
                              _selected.remove(cal.id);
                            }
                          }),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: mono(context, size: 10, color: p.dim, letterSpacing: 1.5)),
        ),
        TextButton(
          onPressed: _save,
          child: Text('SAVE', style: mono(context, size: 10, weight: FontWeight.w700, color: p.accent, letterSpacing: 1.5)),
        ),
      ],
    );
  }
}
