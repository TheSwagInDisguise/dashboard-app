// Pomodoro / stopwatch controller — the countdown state machine behind the
// FOCUS tab and habit timers.
//
// Countdown focus phases record a session when they finish; breaks follow
// automatically. Stopwatch mode counts up until stopped. On Android the
// device is put in DND (priority mode: none) for the duration of a focus
// phase when Settings → Focus → "silence notifications during focus" is on.
// iOS has no DND control — it gets a plain local notification at phase end.
//
// The controller keeps state in memory only (a running timer does not
// survive a process kill) and re-syncs phase completion when the app is
// resumed.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/habit.dart' show Habit;
import '../models/focus_session.dart';
import '../notifications/reminder_service.dart';
import 'app_state.dart';
import 'focus_store.dart';
import 'habit_store.dart';

enum PomPhase { idle, focus, breakPhase }
enum PomKind { focus, stopwatch }

class PomodoroTimer extends ChangeNotifier {
  PomodoroTimer({
    required this.focusStore,
    required this.habitStore,
    required this.appState,
    required this.reminders,
  });

  final FocusStore focusStore;
  final HabitStore habitStore;
  final AppState appState;
  final ReminderService reminders;

  static const _dnd = MethodChannel('daydeck/dnd');

  PomPhase _phase = PomPhase.idle;
  PomKind _kind = PomKind.focus;
  bool _running = false;
  bool _stopwatch = false;

  /// End time for countdown phases (null for stopwatch / idle / paused).
  DateTime? _endsAt;

  /// Remaining at the moment of pause (or the configured length on start).
  Duration _remaining = Duration.zero;

  /// Elapsed at pause for the stopwatch (and when phase started, basis).
  Duration _elapsed = Duration.zero;

  /// When the current focus/stopwatch session started.
  DateTime? _sessionStart;

  /// Whole minutes configured for the *current* countdown focus phase.
  int _sessionMinutes = 0;

  /// Habit bound to the session; '0' = free session.
  String _habitId = '0';
  String _habitName = '';

  int _breakMinutes = 0;

  Timer? _ticker;

  PomPhase get phase => _phase;
  PomKind get kind => _kind;
  bool get running => _running;
  bool get isStopwatch => _stopwatch;
  String get habitName => _habitName;
  String get habitId => _habitId;
  bool get inFocus => _phase == PomPhase.focus;
  bool get inBreak => _phase == PomPhase.breakPhase;
  bool get active => _phase != PomPhase.idle;

  /// Remaining for countdown phases; elapsed for stopwatch.
  Duration get display => _stopwatch
      ? _elapsed + (_running && _sessionStart != null ? DateTime.now().difference(_resumeAnchor) : Duration.zero)
      : _remaining;

  DateTime _resumeAnchor = DateTime.now();

  int get configuredFocusMinutes {
    final habit = _habitId == '0' ? null : habitStore.habitById(_habitId);
    final perHabit = habit?.focusMinutes ?? 0;
    return perHabit > 0 ? perHabit : appState.focusDefaultMinutes;
  }

  /// Per-habit break override; falls back to the global default.
  int _breakFor(Habit? habit) {
    final perHabit = habit?.breakMinutes ?? 0;
    return perHabit > 0 ? perHabit : appState.breakDefaultMinutes;
  }

  // ------------------------------------------------------------ start ----

  /// Start (or restart) a focus phase bound to [habit] (or a free session).
  void startFocus({Habit? habit, bool stopwatch = false}) {
    _teardownTicker();
    final focusMinutes = habit == null
        ? appState.focusDefaultMinutes
        : (habit.focusMinutes > 0 ? habit.focusMinutes : appState.focusDefaultMinutes);
    _habitId = habit?.id ?? '0';
    _habitName = habit?.name ?? '';
    _breakMinutes = _breakFor(habit);
    _sessionMinutes = focusMinutes;
    _sessionStart = DateTime.now();
    _kind = stopwatch ? PomKind.stopwatch : PomKind.focus;
    _stopwatch = stopwatch;
    _phase = PomPhase.focus;
    _running = true;
    _elapsed = Duration.zero;
    _remaining = Duration(minutes: focusMinutes);
    _resumeAnchor = DateTime.now();
    _endsAt = stopwatch ? null : DateTime.now().add(_remaining);
    if (!stopwatch) {
      unawaited(reminders.scheduleFocusDone(_endsAt!, habitName: _habitName));
    }
    unawaited(_setDnd(true));
    _startTicker();
    notifyListeners();
  }

  /// Start the break after a focus phase completes (or manually).
  void startBreak() {
    _teardownTicker();
    _phase = PomPhase.breakPhase;
    _kind = PomKind.focus;
    _stopwatch = false;
    _sessionStart = DateTime.now();
    _remaining = Duration(minutes: _breakMinutes <= 0 ? appState.breakDefaultMinutes : _breakMinutes);
    _endsAt = DateTime.now().add(_remaining);
    _running = true;
    unawaited(reminders.scheduleFocusDone(_endsAt!, habitName: ''));
    _startTicker();
    notifyListeners();
  }

  // ------------------------------------------------------------ controls ----

  void pause() {
    if (!_running || _phase == PomPhase.idle) return;
    _running = false;
    if (_stopwatch) {
      _elapsed += DateTime.now().difference(_resumeAnchor);
    } else {
      _remaining = _endsAt != null ? _endsAt!.difference(DateTime.now()) : _remaining;
      if (_remaining.isNegative) _remaining = Duration.zero;
    }
    unawaited(reminders.cancelFocusDone());
    _teardownTicker();
    notifyListeners();
  }

  void resume() {
    if (_running || _phase == PomPhase.idle) return;
    _running = true;
    _resumeAnchor = DateTime.now();
    if (!_stopwatch) {
      _endsAt = DateTime.now().add(_remaining);
      unawaited(reminders.scheduleFocusDone(_endsAt!, habitName: _habitName));
    }
    _startTicker();
    notifyListeners();
  }

  /// Finish the current phase early. A focus phase that lasted ≥1 minute is
  /// recorded with completed=false; breaks are simply discarded.
  Future<void> skip() async {
    if (_phase == PomPhase.idle) return;
    await _finishPhase(early: true);
  }

  /// Stop the whole session (break included). Partial focus time ≥1 minute is
  /// recorded with completed=false.
  Future<void> stop({bool record = true}) async {
    if (_phase == PomPhase.idle) return;
    await _finishPhase(early: true, stopAfter: true, record: record);
  }

  /// Called when the app returns to the foreground: complete a phase whose
  /// end passed while we were away.
  void appResumed() {
    if (!_running || _stopwatch || _phase == PomPhase.idle) return;
    _tick();
  }

  // ------------------------------------------------------------ internals ----

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _teardownTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    if (!_running) return;
    if (_stopwatch) {
      // elapsed is derived from the anchor; just repaint.
      notifyListeners();
      return;
    }
    final remaining = _endsAt!.difference(DateTime.now());
    if (remaining.isNegative || remaining.inSeconds <= 0) {
      unawaited(_finishPhase(early: false));
      return;
    }
    _remaining = remaining;
    notifyListeners();
  }

  Future<void> _finishPhase({required bool early, bool stopAfter = false, bool record = true}) async {
    _teardownTicker();
    unawaited(reminders.cancelFocusDone());
    await _setDnd(false);

    if (_phase == PomPhase.focus && record) {
      final now = DateTime.now();
      final started = _sessionStart ?? now;
      final int minutes;
      if (_stopwatch) {
        minutes = DateTime.now().difference(_resumeAnchor).inMinutes + _elapsed.inMinutes;
      } else if (early) {
        minutes = started == now
            ? 0
            : ((_sessionMinutes) - _remaining.inMinutes).clamp(0, _sessionMinutes);
      } else {
        minutes = _sessionMinutes;
      }
      final completed = !early && !_stopwatch;
      if (minutes >= 1) {
        final session = await focusStore.recordSession(
          habitId: _habitId,
          startedAt: started,
          endedAt: now,
          minutes: minutes,
          kind: _stopwatch ? FocusSession.kindStopwatch : FocusSession.kindFocus,
          completed: completed,
        );
        if (session != null && _habitId != '0') {
          // Credit the minutes to the bound habit (timer habits ride on this).
          await habitStore.addValue(_habitId, minutes);
        }
      }
    }

    if (_phase == PomPhase.focus && !stopAfter && !early && _breakMinutes > 0) {
      // Natural end of a countdown focus → go straight into the break.
      startBreak();
      return;
    }

    if (_phase == PomPhase.focus && !stopAfter && !early && _breakMinutes <= 0) {
      // No break configured: rest at idle.
      _resetToIdle();
      return;
    }

    _resetToIdle();
  }

  void _resetToIdle() {
    _phase = PomPhase.idle;
    _running = false;
    _stopwatch = false;
    _endsAt = null;
    _remaining = Duration.zero;
    _elapsed = Duration.zero;
    _sessionStart = null;
    _habitId = '0';
    _habitName = '';
    notifyListeners();
  }

  Future<void> _setDnd(bool enable) async {
    if (kIsWeb || !Platform.isAndroid) return; // iOS: no DND control — plain notifications only
    if (enable && !appState.dndDuringFocus) return;
    try {
      await _dnd.invokeMethod<bool>(enable ? 'enable' : 'disable');
    } catch (_) {
      // Permission not granted or method unavailable — never block the session.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
