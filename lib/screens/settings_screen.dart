import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../widgets/section_header.dart';
import '../version.dart';

const String _kRepoUrl = 'https://github.com/TheSwagInDisguise/dashboard-app';
const String _kReleasesUrl = 'https://github.com/TheSwagInDisguise/dashboard-app/releases';
const String _kTokensUrl = 'https://github.com/settings/personal-access-tokens';

/// Settings — appearance, sync (GitHub), reminders, calendar feed and about.
/// The GitHub sync token is only ever held in secure device storage; this
/// screen never logs it and this app contains no secrets.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _tokenController;
  late final TextEditingController _icalController;
  bool _obscureToken = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _tokenController = TextEditingController();
    _icalController = TextEditingController(text: app.icalUrl);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _icalController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _snack('could not open the browser — paste this URL:\n$url');
      }
    } catch (_) {
      if (mounted) _snack('could not open the browser — paste this URL:\n$url');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pasteToken() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _snack('clipboard is empty');
      return;
    }
    setState(() => _tokenController.text = text);
    _snack('pasted ${text.length} characters — tap SAVE');
  }

  Future<void> _saveToken(AppState app) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _snack('nothing to save — paste a token first');
      return;
    }
    if (!token.startsWith('github_pat_')) {
      _snack(
        'that does not look like a fine-grained GitHub token (starts with "github_pat_"). Not saved.',
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await app.saveToken(token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _tokenController.clear(); // don't keep it floating in the field
    });
    _snack(ok ? 'token stored — it never leaves this device' : 'secure storage unavailable — token not saved');
  }

  Future<void> _clearToken(AppState app) async {
    await app.clearToken();
    if (mounted) _snack('token removed from this device');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.palette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 22),
      children: [
        const SizedBox(height: 6),
        Center(
          child: Text(
            '// SETTINGS',
            style: mono(context, size: 22, weight: FontWeight.w700, color: p.accent, letterSpacing: 5),
          ),
        ),
        const SizedBox(height: 16),

        // ============ APPEARANCE ============
        SectionHeader(palette: p, title: 'APPEARANCE'),
        const SizedBox(height: 8),
        for (final entry in kPalettes.entries) ...[
          _SchemeTile(
            paletteOfOption: entry.value,
            selected: entry.key == app.scheme,
            activeScheme: app.scheme,
            onTap: () => app.setScheme(entry.key),
            accent: p.accent,
            textColor: p.text,
            dimColor: p.dim,
            borderColor: p.border,
            panelColor: p.panel,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),

        // ============ SYNC (GitHub) ============
        SectionHeader(
          palette: p,
          title: 'SYNC',
          trailing: app.tokenConfigured ? 'token set' : 'not set',
        ),
        const SizedBox(height: 8),
        _Panel(
          palette: p,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('●', style: mono(context, size: 11, color: app.tokenConfigured ? p.good : p.warn)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.tokenConfigured
                          ? 'token stored on this device — sync arrives in Phase 3'
                          : 'no token yet — the app keeps everything local for now',
                      style: TextStyle(color: p.text, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Shared data lives in your private GitHub repo “dashboard-data” as JSON files. '
                'The app talks to it through the GitHub API — no server, ever.',
                style: TextStyle(color: p.dim, fontSize: 11, height: 1.5),
              ),
              const SizedBox(height: 10),
              _SyncGuide(palette: p, onOpenUrl: _openUrl),
              const SizedBox(height: 10),
              TextField(
                controller: _tokenController,
                obscureText: _obscureToken,
                autocorrect: false,
                enableSuggestions: false,
                style: mono(context, size: 12, color: p.text),
                decoration: InputDecoration(
                  labelText: 'token (github_pat_…)',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _obscureToken ? 'show' : 'hide',
                        icon: Icon(_obscureToken ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                        onPressed: () => setState(() => _obscureToken = !_obscureToken),
                      ),
                      IconButton(
                        tooltip: 'paste',
                        icon: const Icon(Icons.content_paste_go, size: 20),
                        onPressed: _pasteToken,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _TerminalButton(
                    palette: p,
                    label: _busy ? 'SAVING…' : 'SAVE TOKEN',
                    primary: true,
                    onTap: _busy ? null : () => _saveToken(app),
                  ),
                  if (app.tokenConfigured)
                    _TerminalButton(
                      palette: p,
                      label: 'REMOVE',
                      danger: true,
                      onTap: () => _clearToken(app),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'stored only in this device’s secure storage · never in code, never synced,\n'
                'never shown again — remove it below to wipe it completely',
                style: mono(context, size: 9, color: p.bad.withValues(alpha: 0.85), letterSpacing: 0.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ============ EVENING REMINDER ============
        SectionHeader(palette: p, title: 'EVENING REMINDER', trailing: 'phase 5'),
        const SizedBox(height: 8),
        _Panel(
          palette: p,
          child: Row(
            children: [
              Icon(Icons.notifications_none_outlined, color: p.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('pending shared events', style: TextStyle(color: p.text, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      'notifies you each evening with a one-tap link to add them to Google Calendar',
                      style: TextStyle(color: p.dim, fontSize: 10.5, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Text(app.reminderLabel, style: mono(context, size: 16, weight: FontWeight.w700, color: p.accent)),
                  const SizedBox(height: 4),
                  _TerminalButton(
                    palette: p,
                    label: 'CHANGE',
                    small: true,
                    onTap: () async {
                      final current = TimeOfDay(hour: app.reminderMinutes ~/ 60, minute: app.reminderMinutes % 60);
                      final picked = await showTimePicker(context: context, initialTime: current);
                      if (picked != null) {
                        await app.setReminderMinutes(picked.hour * 60 + picked.minute);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ============ CALENDAR (iCal) ============
        SectionHeader(palette: p, title: 'GOOGLE CALENDAR', trailing: 'view-only'),
        const SizedBox(height: 8),
        _Panel(
          palette: p,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Read-only, via your calendar’s secret iCal address — the app never signs in to Google '
                'and never writes to your calendar on its own.',
                style: TextStyle(color: p.text, fontSize: 11.5, height: 1.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _icalController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                style: mono(context, size: 10.5, color: p.text),
                decoration: const InputDecoration(
                  labelText: 'secret address in iCal format',
                  hintText: 'https://calendar.google.com/calendar/ical/…/basic.ics',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TerminalButton(
                    palette: p,
                    label: 'SAVE URL',
                    onTap: () async {
                      await app.setIcalUrl(_icalController.text);
                      if (context.mounted) _snack('iCal URL saved');
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Google refreshes the feed itself — changes can take a few hours.',
                      style: TextStyle(color: p.dim, fontSize: 9.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ============ ABOUT ============
        SectionHeader(palette: p, title: 'ABOUT'),
        const SizedBox(height: 8),
        _Panel(
          palette: p,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AboutRow(palette: p, label: 'version', value: '$kAppVersion+1'),
              _AboutRow(palette: p, label: 'code', value: 'TheSwagInDisguise/dashboard-app', onTap: () => _openUrl(_kRepoUrl)),
              _AboutRow(palette: p, label: 'releases', value: 'installable APK builds', onTap: () => _openUrl(_kReleasesUrl)),
              _AboutRow(palette: p, label: 'data', value: 'private repo dashboard-data'),
              _AboutRow(palette: p, label: 'font', value: 'JetBrains Mono · SIL OFL'),
              const SizedBox(height: 6),
              Text(
                'no personal data, tokens or calendar content are stored in the code, the APK or the web build.',
                style: mono(context, size: 9, color: p.dim, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({required this.palette, required this.child});

  final TerminalPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

class _SchemeTile extends StatelessWidget {
  const _SchemeTile({
    required this.paletteOfOption,
    required this.selected,
    required this.activeScheme,
    required this.onTap,
    required this.accent,
    required this.textColor,
    required this.dimColor,
    required this.borderColor,
    required this.panelColor,
  });

  final TerminalPalette paletteOfOption;
  final bool selected;
  final DayDeckScheme activeScheme;
  final VoidCallback onTap;
  final Color accent;
  final Color textColor;
  final Color dimColor;
  final Color borderColor;
  final Color panelColor;

  @override
  Widget build(BuildContext context) {
    final option = paletteOfOption;
    final isModern = option.scheme == DayDeckScheme.modern;

    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : panelColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? accent : borderColor),
          ),
          child: Row(
            children: [
              // colour dot — modern shows a two-tone gradient
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isModern ? null : option.accent,
                  gradient: isModern
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF22D3EE), Color(0xFFE879F9)],
                        )
                      : null,
                  border: Border.all(color: option.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label + (option.scheme == DayDeckScheme.light ? '  ·  fallback' : ''),
                      style: mono(
                        context,
                        size: 12,
                        weight: FontWeight.w700,
                        color: selected ? accent : textColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(option.descriptor, style: TextStyle(color: dimColor, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                selected ? '[*]' : '[ ]',
                style: mono(context, size: 14, weight: FontWeight.w700, color: selected ? accent : dimColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalButton extends StatelessWidget {
  const _TerminalButton({
    required this.palette,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
    this.small = false,
  });

  final TerminalPalette palette;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final fg = danger
        ? palette.bad
        : primary
            ? palette.bg
            : palette.accent;
    final bg = primary ? palette.accent : Colors.transparent;

    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 7 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: danger ? palette.bad : palette.accent),
            ),
            child: Text(
              label,
              style: mono(
                context,
                size: small ? 10 : 11,
                weight: FontWeight.w700,
                color: fg,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The built-in, plain-language guide for creating the app’s sync token —
/// shipped inside the app itself so the instructions travel with it.
class _SyncGuide extends StatelessWidget {
  const _SyncGuide({required this.palette, required this.onOpenUrl});

  final TerminalPalette palette;
  final Future<void> Function(String url) onOpenUrl;

  static const _steps = [
    '1  Open github.com in a browser and sign in.',
    '2  Click your avatar (top right) → Settings.',
    '3  Left sidebar, bottom: Developer settings → Personal access tokens → Fine-grained tokens.',
    '4  “Generate new token”. Name: “daydeck-app”.  Pick the longest expiry you are comfortable with.',
    '5  Repository access → “Only select repositories” → tick dashboard-data (only that one).',
    '6  Repository permissions → “Contents: Read and write”. Leave everything else untouched (Metadata stays Read-only).',
    '7  “Generate token” — copy the github_pat_… value NOW (it is shown once). Paste it here and tap SAVE TOKEN.',
  ];

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ExpansionTile(
      title: Text(
        'how to create your sync token',
        style: mono(context, size: 11.5, weight: FontWeight.w600, color: p.accent, letterSpacing: 0.8),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        for (final step in _steps) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              step,
              style: TextStyle(color: p.text, fontSize: 11.5, height: 1.55),
            ),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _TerminalButton(
            palette: p,
            label: 'OPEN GITHUB → FINE-GRAINED TOKENS',
            small: true,
            onTap: () => onOpenUrl(_kTokensUrl),
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          _kTokensUrl,
          style: mono(context, size: 9, color: p.dim),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.palette, required this.label, required this.value, this.onTap});

  final TerminalPalette palette;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: mono(context, size: 10, color: palette.dim, letterSpacing: 0.8)),
        ),
        Expanded(
          child: Text(value, style: mono(context, size: 10, color: onTap != null ? palette.accent : palette.text)),
        ),
        if (onTap != null) Icon(Icons.open_in_new, size: 13, color: palette.accent),
      ],
    );

    if (onTap == null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: content);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: content),
    );
  }
}
