import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../home_widget_bridge.dart';
import '../notifications/deep_links.dart';
import '../state/app_state.dart';
import '../state/tasks_store.dart';
import '../theme/app_theme.dart';
import '../theme/palettes.dart';
import '../sync/sync_service.dart';
import '../widgets/scanlines.dart';
import '../widgets/task_sheet.dart';
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

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _index = 0;
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _pausedAt;

  static const _channel = MethodChannel('daydeck/input');

  static const _tabs = [
    (icon: Icons.today_outlined, label: 'TODAY'),
    (icon: Icons.checklist_rounded, label: 'TASKS'),
    (icon: Icons.repeat_rounded, label: 'HABITS'),
    (icon: Icons.settings_outlined, label: 'SETTINGS'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeepLinks.tasksRequests.addListener(_onTasksDeepLink);
    DeepLinks.sharedQueueRequests.addListener(_onSharedQueueDeepLink);
    _channel.setMethodCallHandler(_onNativeCall);
    final store = context.read<TasksStore>();
    store.addListener(_onTasksStoreChanged);
    final appState = context.read<AppState>();
    _locked = appState.appLockEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_fetchInitialInput());
      unawaited(updateDayDeckWidget(context.read<TasksStore>()));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeepLinks.tasksRequests.removeListener(_onTasksDeepLink);
    DeepLinks.sharedQueueRequests.removeListener(_onSharedQueueDeepLink);
    _channel.setMethodCallHandler(null);
    try {
      context.read<TasksStore>().removeListener(_onTasksStoreChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _pausedAt == null ? Duration.zero : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      final enabled = context.read<AppState>().appLockEnabled;
      if (enabled && !_locked && away > const Duration(seconds: 30)) {
        setState(() => _locked = true);
        unawaited(_authenticate());
      }
    }
  }

  // ---------------- biometric lock ----------------

  Future<void> _authenticate() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final auth = LocalAuthentication();
      bool canAuth;
      try {
        canAuth = await auth.isDeviceSupported();
      } catch (_) {
        canAuth = false;
      }
      if (!canAuth) {
        // No biometrics / device credential set up — never trap the user.
        if (mounted) setState(() => _locked = false);
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'unlock daydeck',
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // Stay locked; the unlock button retries.
    } finally {
      _authenticating = false;
    }
  }

  // ---------------- native input (share / tile / shortcuts) ----------------

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'nativeInput') _routeInput(call.arguments);
    return null;
  }

  Future<void> _fetchInitialInput() async {
    try {
      final input = await _channel.invokeMethod<dynamic>('getInitialInput');
      _routeInput(input);
    } catch (_) {}
  }

  void _routeInput(dynamic input) {
    if (!mounted || input is! Map) return;
    switch (input['type']?.toString()) {
      case 'share':
        _handleShare(input['text']);
      case 'add_task':
        _goTasksAndAdd();
      case 'sync_now':
        _syncNow();
      case 'open_today':
        setState(() => _index = 0);
    }
  }

  Future<void> _handleShare(dynamic text) async {
    final raw = (text ?? '').toString().trim();
    if (raw.isEmpty) return;
    final title = raw.length > 500 ? raw.substring(0, 500) : raw;
    await context.read<TasksStore>().add(title: title, priority: 'P2');
    if (!mounted) return;
    setState(() => _index = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('captured from share sheet as a task')),
    );
  }

  void _goTasksAndAdd() {
    setState(() => _index = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showTaskSheet(context));
    });
  }

  Future<void> _syncNow() async {
    await context.read<SyncService>().syncNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('syncing…')),
    );
  }

  // ---------------- deep links from notifications ----------------

  void _onTasksDeepLink() {
    if (mounted) setState(() => _index = 1);
  }

  void _onSharedQueueDeepLink() {
    if (mounted) setState(() => _index = 0);
  }

  // ---------------- home-screen widget ----------------

  void _onTasksStoreChanged() {
    unawaited(updateDayDeckWidget(context.read<TasksStore>()));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<AppState>().palette;
    final sync = context.watch<SyncService>();

    if (_locked) {
      return _LockScreen(palette: palette, onUnlock: _authenticate);
    }

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


/// Full-screen gate shown when biometric app lock is enabled and not yet
/// authenticated this session/resume. Only rendered on Android; the web
/// build never enables it.
class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.palette, required this.onUnlock});

  final TerminalPalette palette;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 54, color: p.accent),
            const SizedBox(height: 18),
            Text(
              'daydeck · locked',
              style: mono(context, size: 13, weight: FontWeight.w700, color: p.accent, letterSpacing: 3),
            ),
            const SizedBox(height: 6),
            Text(
              'biometrics required to see your day',
              style: TextStyle(color: p.dim, fontSize: 11),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onUnlock,
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent.withValues(alpha: 0.65)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              ),
              icon: const Icon(Icons.fingerprint),
              label: Text('UNLOCK', style: mono(context, size: 11, weight: FontWeight.w700, letterSpacing: 2.4)),
            ),
          ],
        ),
      ),
    );
  }
}
