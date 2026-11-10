import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
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

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
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
        ),
      ),
    );
  }
}
