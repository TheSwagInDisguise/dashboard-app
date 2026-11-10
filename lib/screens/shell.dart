import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../sync/sync_service.dart';
import '../widgets/scanlines.dart';
import 'habits_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';
import 'today_screen.dart';

/// App shell: holds the current tab, paints the CRT scanline overlay and the
/// terminal-style bottom navigation. Content is capped at a comfortable
/// reading width on larger screens (web / tablets).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

/// Persistent warning shown whenever GitHub has rejected the sync token.
/// Everything in the app keeps working locally; tapping jumps to Settings.
class _TokenExpiredBanner extends StatelessWidget {
  const _TokenExpiredBanner({required this.palette, required this.onFix});

  final TerminalPalette palette;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.bad.withValues(alpha: 0.14),
      child: InkWell(
        onTap: onFix,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.bad.withValues(alpha: 0.6))),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: palette.bad, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'sync paused — GitHub rejected your token (expired or revoked?)',
                  style: TextStyle(color: palette.bad, fontSize: 11, height: 1.35),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'FIX →',
                style: TextStyle(
                  color: palette.bad,
                  fontFamily: 'JetBrainsMono',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Width at/above which fold/tablet layouts kick in (Fold 5 cover ≈ 360,
/// inner ≈ 800+; phones sit below 700).
const double _kWideBreakpoint = 700;

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _tabs = [
    (icon: Icons.today_outlined, label: 'TODAY'),
    (icon: Icons.checklist_rounded, label: 'TASKS'),
    (icon: Icons.repeat_rounded, label: 'HABITS'),
    (icon: Icons.settings_outlined, label: 'SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<AppState>().palette;
    final sync = context.watch<SyncService>();

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (sync.status == SyncStatus.tokenInvalid)
              _TokenExpiredBanner(palette: palette, onFix: () => setState(() => _index = 3)),
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width >= _kWideBreakpoint ? 1180 : 640,
                      ),
                      child: IndexedStack(
                        index: _index,
                        children: const [
                          TodayScreen(),
                          TasksScreen(),
                          HabitsScreen(),
                          SettingsScreen(),
                        ],
                      ),
                    ),
                  ),
                  Scanlines(alpha: palette.scanlineAlpha),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _TerminalTabBar(
        palette: palette,
        tabs: _tabs,
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _TerminalTabBar extends StatelessWidget {
  const _TerminalTabBar({
    required this.palette,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final TerminalPalette palette;
  final List<({IconData icon, String label})> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.panel2,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // On fold/tablet widths, keep the tab cluster centred instead of
              // stretching the tabs across the whole inner display. Padding is
              // used (not Center) so the bar's height stays intrinsic.
              const maxCluster = 640.0;
              final spare = (constraints.maxWidth - maxCluster) / 2;
              final inset = spare > 0 ? spare : 0.0;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: Row(
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      Expanded(
                        child: InkWell(
                          onTap: () => onChanged(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: i == index ? palette.accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tabs[i].icon,
                                  size: 20,
                                  color: i == index ? palette.accent : palette.dim,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  tabs[i].label,
                                  style: mono(
                                    context,
                                    size: 9,
                                    weight: FontWeight.w600,
                                    color: i == index ? palette.accent : palette.dim,
                                    letterSpacing: 2.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
