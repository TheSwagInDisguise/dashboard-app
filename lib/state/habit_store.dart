// Habit store — the full PersonalTerminal habit engine on DayDeck's
// JSON-document sync (tombstone merge, no server). Habits, logs, routines,
// skip rules, shields and the XP ledger are six synced documents managed
// here behind one notifier.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/areas.dart';
import '../domain/challenges.dart';
import '../domain/progression.dart';
import '../domain/schedule.dart';
import '../domain/skip_rules.dart';
import '../domain/streak_engine.dart';
import '../domain/strength.dart';
import '../domain/targets.dart';
import '../models/habit.dart';
import '../utils/dates.dart';
import 'json_doc_store.dart';

class HabitStore extends ChangeNotifier {
  HabitStore()
      : _habits = JsonDocStore<Habit>(
          mainKey: 'habits_json',
          backupKey: 'habits_json_backup',
          fromJson: Habit.fromJson,
          toJson: (h) => h.toJson(),
          idOf: (h) => h.id,
        ),
        _logs = JsonDocStore<HabitLog>(
          mainKey: 'habit_logs_json',
          backupKey: 'habit_logs_json_backup',
          fromJson: HabitLog.fromJson,
          toJson: (l) => l.toJson(),
          idOf: (l) => l.id,
        ),
        _routines = JsonDocStore<Routine>(
          mainKey: 'routines_json',
          backupKey: 'routines_json_backup',
          fromJson: Routine.fromJson,
          toJson: (r) => r.toJson(),
          idOf: (r) => r.id,
        ),
        _skipRules = JsonDocStore<SkipRule>(
          mainKey: 'skip_rules_json',
          backupKey: 'skip_rules_json_backup',
          fromJson: SkipRule.fromJson,
          toJson: (r) => r.toJson(),
          idOf: (r) => r.id,
        ),
        _shields = JsonDocStore<ShieldUse>(
          mainKey: 'shield_uses_json',
          backupKey: 'shield_uses_json_backup',
          fromJson: ShieldUse.fromJson,
          toJson: (s) => s.toJson(),
          idOf: (s) => s.id,
        ),
        _xp = JsonDocStore<XpEvent>(
          mainKey: 'xp_events_json',
          backupKey: 'xp_events_json_backup',
          fromJson: XpEvent.fromJson,
          toJson: (x) => x.toJson(),
          idOf: (x) => x.id,
        );

  final JsonDocStore<Habit> _habits;
  final JsonDocStore<HabitLog> _logs;
  final JsonDocStore<Routine> _routines;
  final JsonDocStore<SkipRule> _skipRules;
  final JsonDocStore<ShieldUse> _shields;
  final JsonDocStore<XpEvent> _xp;

  String? get recoveryNotice =>
      _habits.recoveryNotice ??
      _logs.recoveryNotice ??
      _routines.recoveryNotice ??
      _skipRules.recoveryNotice ??
      _shields.recoveryNotice ??
      _xp.recoveryNotice;

  void clearRecoveryNotice() {
    _habits.clearRecoveryNotice();
    _logs.clearRecoveryNotice();
    _routines.clearRecoveryNotice();
    _skipRules.clearRecoveryNotice();
    _shields.clearRecoveryNotice();
    _xp.clearRecoveryNotice();
    notifyListeners();
  }

  Future<void> load() async {
    await _habits.load();
    await _logs.load();
    await _routines.load();
    await _skipRules.load();
    await _shields.load();
    await _xp.load();
    // Startup maintenance, mirroring PersonalTerminal's app-start behaviour:
    await settleNegativeHabits();
    await applySkipRules();
    await settleChallenges();
  }

  // ---- sync engine views ----
  List<Habit> snapshotHabits() => _habits.snapshotItems();
  List<HabitLog> snapshotLogs() => _logs.snapshotItems();
  List<Routine> snapshotRoutines() => _routines.snapshotItems();
  List<SkipRule> snapshotSkipRules() => _skipRules.snapshotItems();
  List<ShieldUse> snapshotShields() => _shields.snapshotItems();
  List<XpEvent> snapshotXp() => _xp.snapshotItems();

  Future<void> replaceAllHabits(List<Habit> items) async {
    await _habits.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllLogs(List<HabitLog> items) async {
    await _logs.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllRoutines(List<Routine> items) async {
    await _routines.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllSkipRules(List<SkipRule> items) async {
    await _skipRules.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllShields(List<ShieldUse> items) async {
    await _shields.replaceAll(items);
    notifyListeners();
  }

  Future<void> replaceAllXp(List<XpEvent> items) async {
    await _xp.replaceAll(items);
    notifyListeners();
  }

  // ================= queries ==============================================

  List<Habit> get habits {
    final list = _habits.items.where((h) => !h.deleted && !h.archived).toList()
      ..sort((a, b) {
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  List<Habit> get archivedHabits {
    final list = _habits.items.where((h) => !h.deleted && h.archived).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Habit? habitById(String id) {
    for (final h in _habits.items) {
      if (h.id == id && !h.deleted) return h;
    }
    return null;
  }

  List<Routine> get routines {
    final list = _routines.items.where((r) => !r.deleted).toList()
      ..sort((a, b) {
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  List<Habit> habitsInRoutine(String? routineId) =>
      habits.where((h) => h.routineId == routineId).toList();

  List<SkipRule> get skipRules =>
      _skipRules.items.where((r) => !r.deleted).toList();

  List<HabitLog> logsFor(String habitId) =>
      _logs.items.where((l) => !l.deleted && l.habitId == habitId).toList();

  HabitLog? logOn(String habitId, int day) {
    for (final l in _logs.items) {
      if (l.habitId == habitId && l.day == day && !l.deleted) return l;
    }
    return null;
  }

  bool doneOn(String habitId, String date) => doneOnEpoch(habitId, parseEpochDay(date));

  bool doneOnEpoch(String habitId, int day) => logOn(habitId, day)?.completed ?? false;

  /// Day-level completion for UI/XP purposes. Negative (avoid) habits are
  /// *kept* by default: they count as done unless a slip was logged.
  bool isDoneOn(Habit habit, int day) {
    if (habit.negative) return !_isSlipped(habit.id, day);
    return doneOnEpoch(habit.id, day);
  }

  bool isDoneToday(Habit habit, {DateTime? date}) =>
      isDoneOn(habit, epochDayOf(date ?? DateTime.now()));

  bool doneToday(String habitId) => doneOn(habitId, todayKey());

  bool skippedOn(String habitId, int day) => logOn(habitId, day)?.skipped ?? false;

  int weekCount(Habit habit, {DateTime? date}) {
    final d = date ?? DateTime.now();
    final start = epochDayOf(Schedule.weekStart(d));
    return logsFor(habit.id)
        .where((l) => l.completed && !l.skipped && l.day >= start && l.day <= start + 6)
        .length;
  }

  List<ShieldUse> get shieldUses => _shields.items.where((s) => !s.deleted).toList();

  List<ShieldUse> shieldsFor(String habitId) =>
      shieldUses.where((s) => s.habitId == habitId).toList();

  int get totalCompletions =>
      _logs.items.where((l) => !l.deleted && l.completed).length;

  int get shieldsUsed => shieldUses.length;

  int get shieldsAvailable =>
      Progression.shieldsAvailable(totalCompletions, shieldsUsed);

  List<XpEvent> get xpEvents {
    final list = _xp.items.where((x) => !x.deleted).toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return list;
  }

  int get totalXp => _xp.items.where((x) => !x.deleted).fold(0, (sum, x) => sum + x.amount);

  LevelProgress get levelProgress => Progression.progress(totalXp);

  /// Recent XP ledger entries, newest first.
  List<XpEvent> xpLog({int limit = 12}) => xpEvents.take(limit).toList();

  // ================= streaks & strength ==================================

  StreakInfo streakOf(Habit habit, {DateTime? today, int? hourNow}) => Streaks.compute(
        habit,
        logsFor(habit.id),
        shieldsFor(habit.id),
        today: today ?? DateTime.now(),
        hourNow: hourNow,
      );

  int currentStreak(Habit habit) => streakOf(habit).current;

  StrengthResult strengthOf(Habit habit, {DateTime? today}) {
    final shieldDays = shieldsFor(habit.id).map((s) => s.day).toSet();
    return Strength.compute(habit, logsFor(habit.id), today ?? DateTime.now(), shieldedDays: shieldDays);
  }

  List<bool> weekDots(Habit habit, {DateTime? date}) {
    final d = date ?? DateTime.now();
    final monday = Schedule.weekStart(d);
    return List<bool>.generate(7, (i) {
      final day = epochDayOf(monday.add(Duration(days: i)));
      return doneOnEpoch(habit.id, day);
    });
  }

  /// Old alias used by search/widget entry points.
  List<bool> thisWeekDots(Habit habit) => weekDots(habit);

  bool _isDueToday(Habit habit, DateTime today) {
    if (habit.isPausedOn(epochDayOf(today))) return false;
    if (habit.schedule == ScheduleType.weekly) {
      return weekCount(habit, date: today) < habit.timesPerWeek;
    }
    return Schedule.isDue(habit, today);
  }

  /// Habits expected today (not paused; weekly habits until quota met).
  List<Habit> dueToday({DateTime? date}) {
    final d = date ?? DateTime.now();
    return habits.where((h) => _isDueToday(h, d)).toList();
  }

  /// Habits due today that are completed today.
  int get doneTodayCount {
    final d = DateTime.now();
    return dueToday(date: d).where((h) => isDoneToday(h, date: d)).length;
  }

  bool isPerfectDay({DateTime? date}) {
    final d = date ?? DateTime.now();
    final due = dueToday(date: d);
    final epoch = epochDayOf(d);
    return due.isNotEmpty && due.every((h) => isDoneOn(h, epoch));
  }

  /// Completion rate per life area over the last [days] days ending today.
  List<AreaScore> areaBalance({int days = 30}) {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(Duration(days: days - 1));
    return Areas.balance(
      [for (final h in habits) (habit: h, logs: logsFor(h.id))],
      from,
      to,
    );
  }

  List<({Area area, int daysSince})> neglectedAreas({int days = 7}) =>
      Areas.neglected(
        [for (final h in habits) (habit: h, logs: logsFor(h.id))],
        DateTime.now(),
        days: days,
      );

  /// The anchor habit this one follows, if completed today (for stacking UX).
  bool anchorSatisfied(Habit habit) {
    final anchorId = habit.anchorId;
    if (anchorId == null) return true;
    return doneToday(anchorId);
  }

  Habit? anchorOf(Habit habit) => habit.anchorId == null ? null : habitById(habit.anchorId!);

  // ================= mutations: habits & routines ========================

  Future<Habit> addHabit(Habit Function() build) async {
    late Habit created;
    await _habits.mutate((items) {
      final maxPos = items.where((h) => !h.deleted).fold<int>(-1, (m, h) => math.max(m, h.position));
      created = build().copyWith(position: maxPos + 1);
      items.add(created);
    });
    notifyListeners();
    return created;
  }

  /// Convenience legacy-add used by conflicts restore & search.
  Future<Habit> addHabitRaw({required String title, String cadence = 'daily'}) async {
    final cadenceWeekly = cadence == 'weekly';
    final now = DateTime.now().toUtc();
    return addHabit(() => Habit(
          id: JsonDocStore.newId(),
          name: title.trim(),
          schedule: cadenceWeekly ? ScheduleType.weekly : ScheduleType.daily,
          timesPerWeek: cadenceWeekly ? 1 : 3,
          createdAt: now,
          updatedAt: now,
        ));
  }

  Future<void> updateHabit(String id, Habit Function(Habit) transform) async {
    final now = DateTime.now().toUtc();
    await _habits.mutate((items) {
      final index = items.indexWhere((h) => h.id == id);
      if (index < 0) return;
      items[index] = transform(items[index]).copyWith(updatedAt: now);
    });
    notifyListeners();
  }

  Future<void> setArchived(String id, bool archived) => updateHabit(id, (h) => h.copyWith(archived: archived));

  Future<void> deleteHabit(String id) async {
    final now = DateTime.now().toUtc();
    await _habits.mutate((items) {
      final index = items.indexWhere((h) => h.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(deletedAt: now, updatedAt: now);
    });
    await _logs.mutate((items) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].habitId == id && items[i].deletedAt == null) {
          items[i] = _tombLog(items[i], now);
        }
      }
    });
    await _shields.mutate((items) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].habitId == id && items[i].deletedAt == null) {
          items[i] = ShieldUse(
            id: items[i].id,
            habitId: items[i].habitId,
            day: items[i].day,
            usedAt: items[i].usedAt,
            createdAt: items[i].createdAt,
            updatedAt: now,
            deletedAt: now,
          );
        }
      }
    });
    notifyListeners();
  }

  Future<void> moveHabit(String id, int delta) async {
    final now = DateTime.now().toUtc();
    await _habits.mutate((items) {
      Habit? habit;
      for (final h in items) {
        if (h.id == id) {
          habit = h;
          break;
        }
      }
      if (habit == null) return;
      final routineId = habit.routineId;
      final siblings = items.where((h) => !h.deleted && h.routineId == routineId).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      final idx = siblings.indexWhere((h) => h.id == id);
      if (idx < 0) return;
      final target = (idx + delta).clamp(0, siblings.length - 1);
      if (idx == target) return;
      final reordered = List<Habit>.of(siblings);
      final item = reordered.removeAt(idx);
      reordered.insert(target, item);
      for (var i = 0; i < reordered.length; i++) {
        final h = reordered[i];
        final index = items.indexWhere((x) => x.id == h.id);
        if (index >= 0 && items[index].position != i) {
          items[index] = items[index].copyWith(position: i, updatedAt: now);
        }
      }
    });
    notifyListeners();
  }

  /// Pause until [until] (exclusive); null resumes now.
  Future<void> pauseHabit(String id, DateTime? until) async {
    final todayEpoch = epochDayOf(DateTime.now());
    final epoch = until == null ? 0 : epochDayOf(until);
    await updateHabit(id, (h) {
      if (epoch > todayEpoch) {
        return h.copyWith(pausedFrom: todayEpoch, pausedUntil: epoch);
      }
      return h.copyWith(pausedFrom: 0, pausedUntil: 0);
    });
  }

  Future<Routine> addRoutine({required String name, String icon = '>'}) async {
    final now = DateTime.now().toUtc();
    late Routine created;
    await _routines.mutate((items) {
      final maxPos = items.where((r) => !r.deleted).fold<int>(-1, (m, r) => math.max(m, r.position));
      created = Routine(
        id: JsonDocStore.newId(),
        name: name.trim(),
        icon: icon.trim().isEmpty ? '>' : icon.trim(),
        position: maxPos + 1,
        createdAt: now,
        updatedAt: now,
      );
      items.add(created);
    });
    notifyListeners();
    return created;
  }

  Future<void> renameRoutine(String id, String name, {String? icon}) async {
    final now = DateTime.now().toUtc();
    await _routines.mutate((items) {
      final index = items.indexWhere((r) => r.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(
        name: name.trim(),
        icon: icon?.trim().isEmpty ?? false ? items[index].icon : (icon?.trim() ?? items[index].icon),
        updatedAt: now,
      );
    });
    notifyListeners();
  }

  Future<void> deleteRoutine(String id) async {
    final now = DateTime.now().toUtc();
    await _routines.mutate((items) {
      final index = items.indexWhere((r) => r.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(deletedAt: now, updatedAt: now);
    });
    // Habits stay; they just fall back to the unsorted bucket.
    final habitIds = habits.where((h) => h.routineId == id).map((h) => h.id).toList();
    for (final habitId in habitIds) {
      await updateHabit(habitId, (h) => h.copyWith(clearRoutineId: true));
    }
    notifyListeners();
  }

  Future<SkipRule> addSkipRule(SkipRule rule) async {
    final now = DateTime.now().toUtc();
    late SkipRule created;
    await _skipRules.mutate((items) {
      created = SkipRule(
        id: JsonDocStore.newId(),
        name: rule.name.trim(),
        kind: rule.kind,
        fromDay: rule.fromDay,
        toDay: rule.toDay,
        weekdayMask: rule.weekdayMask,
        habitIds: rule.habitIds,
        enabled: rule.enabled,
        createdAt: now,
        updatedAt: now,
      );
      items.add(created);
    });
    notifyListeners();
    await applySkipRules();
    return created;
  }

  Future<void> updateSkipRule(String id, SkipRule Function(SkipRule) transform) async {
    final now = DateTime.now().toUtc();
    await _skipRules.mutate((items) {
      final index = items.indexWhere((r) => r.id == id);
      if (index < 0) return;
      items[index] = transform(items[index]).copyWith(updatedAt: now);
    });
    notifyListeners();
    await applySkipRules();
  }

  Future<void> deleteSkipRule(String id) async {
    final now = DateTime.now().toUtc();
    await _skipRules.mutate((items) {
      final index = items.indexWhere((r) => r.id == id);
      if (index < 0) return;
      items[index] = items[index].copyWith(deletedAt: now, updatedAt: now);
    });
    notifyListeners();
    await applySkipRules();
  }

  // ================= mutations: logging ==================================

  HabitLog _tombLog(HabitLog l, DateTime at) => HabitLog(
        id: l.id,
        habitId: l.habitId,
        day: l.day,
        value: l.value,
        completed: l.completed,
        skipped: l.skipped,
        skipReason: l.skipReason,
        note: l.note,
        mood: l.mood,
        items: l.items,
        ruleId: l.ruleId,
        createdAt: l.createdAt,
        updatedAt: at,
        deletedAt: at,
      );

  bool _isBare(HabitLog? l) =>
      l == null ||
      (l.note.isEmpty && l.mood == 0 && !l.skipped && l.ruleId == null);

  /// `habitId|yyyy-mm-dd` id is derived from the local day.
  HabitLog _makeLog({
    required String habitId,
    required int day,
    int value = 0,
    bool completed = false,
    bool skipped = false,
    String skipReason = '',
    String note = '',
    int mood = 0,
    int items = 0,
    String? ruleId,
    HabitLog? existing,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now().toUtc();
    return HabitLog(
      id: existing?.id ?? HabitLog.idFor(habitId, dateKeyOfEpochDay(day)),
      habitId: habitId,
      day: day,
      value: value,
      completed: completed,
      skipped: skipped,
      skipReason: skipReason,
      note: note,
      mood: mood,
      items: items,
      ruleId: ruleId,
      createdAt: existing?.createdAt ?? at,
      updatedAt: at,
    );
  }

  Future<void> toggle(String habitId, {DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null) return;
    final day = date ?? DateTime.now();
    final epoch = epochDayOf(day);
    if (habit.negative) return logSlip(habitId, slipped: !_isSlipped(habitId, epoch), date: day);

    final existing = logOn(habitId, epoch);
    final nowCompleted = !(existing?.completed ?? false);
    final value = nowCompleted ? Targets.target(habit, day) : 0;
    final items = habit.type == HabitType.checklist
        ? (nowCompleted ? _allItemsMask(habit) : 0)
        : existing?.items ?? 0;
    final wasPartial = existing != null && Targets.minimumReached(habit, existing.value, day);

    await _logs.mutate((itemsList) {
      final index = itemsList.indexWhere((l) => l.id == HabitLog.idFor(habitId, dateKeyOfEpochDay(epoch)));
      if (nowCompleted == false && _isBare(existing) && existing?.skipped == false) {
        // un-completing with nothing to keep → remove the row
        if (index >= 0) {
          itemsList[index] = _tombLog(itemsList[index], DateTime.now().toUtc());
        }
        return;
      }
      final log = _makeLog(
        habitId: habitId,
        day: epoch,
        value: value,
        completed: nowCompleted,
        skipped: false,
        note: existing?.note ?? '',
        mood: existing?.mood ?? 0,
        items: items,
        ruleId: existing?.ruleId,
        existing: existing,
      );
      if (index < 0) {
        itemsList.add(log);
      } else {
        itemsList[index] = log;
      }
    });
    await _afterChange(habit, epoch, existing?.completed == true, nowCompleted, day,
        wasPartial: wasPartial, isPartial: false);
    notifyListeners();
  }

  bool _isSlipped(String habitId, int epoch) {
    final l = logOn(habitId, epoch);
    return l != null && !l.completed && l.value > 0 && !l.skipped;
  }

  /// Avoid-habits: record (or clear) a slip. A slip forfeits the day's XP.
  Future<void> logSlip(String habitId, {required bool slipped, DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null) return;
    final day = date ?? DateTime.now();
    final epoch = epochDayOf(day);
    final existing = logOn(habitId, epoch);
    final wasCompleted = existing?.completed == true;

    await _logs.mutate((itemsList) {
      final id = HabitLog.idFor(habitId, dateKeyOfEpochDay(epoch));
      final index = itemsList.indexWhere((l) => l.id == id);
      if (slipped) {
        final log = _makeLog(
          habitId: habitId,
          day: epoch,
          value: 1,
          completed: false,
          note: existing?.note ?? '',
          mood: existing?.mood ?? 0,
          existing: existing,
        );
        if (index < 0) {
          itemsList.add(log);
        } else {
          itemsList[index] = log;
        }
        return;
      }
      if (existing == null) return;
      if (_isBare(existing) && !existing.skipped) {
        if (index >= 0) {
          itemsList[index] = _tombLog(itemsList[index], DateTime.now().toUtc());
        }
        return;
      }
      if (index >= 0) {
        itemsList[index] = _makeLog(
          habitId: habitId,
          day: epoch,
          value: 0,
          completed: false,
          skipped: existing.skipped,
          note: existing.note,
          mood: existing.mood,
          items: existing.items,
          ruleId: existing.ruleId,
          existing: existing,
        );
      }
    });
    await _afterChange(habit, epoch, wasCompleted, false, day);
    notifyListeners();
  }

  /// Checklist habits: tick / untick sub-item [index].
  Future<void> toggleItem(String habitId, int index, {DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null || habit.type != HabitType.checklist) return;
    final items = habit.checklistItems;
    if (index < 0 || index >= items.length) return;
    final day = date ?? DateTime.now();
    final epoch = epochDayOf(day);
    final existing = logOn(habitId, epoch);
    final wasCompleted = existing?.completed == true;
    final mask = (existing?.items ?? 0) ^ (1 << index);
    final ticked = _popCount(mask & _itemMaskFor(items.length));
    final completed = ticked >= items.length;

    await _logs.mutate((itemsList) {
      final id = HabitLog.idFor(habitId, dateKeyOfEpochDay(epoch));
      final i = itemsList.indexWhere((l) => l.id == id);
      if (ticked == 0 && existing != null && _isBare(existing) && !existing.skipped) {
        if (i >= 0) {
          itemsList[i] = _tombLog(itemsList[i], DateTime.now().toUtc());
        }
        return;
      }
      final log = _makeLog(
        habitId: habitId,
        day: epoch,
        value: ticked,
        completed: completed,
        skipped: false,
        note: existing?.note ?? '',
        mood: existing?.mood ?? 0,
        items: mask,
        ruleId: existing?.ruleId,
        existing: existing,
      );
      if (i < 0) {
        itemsList.add(log);
      } else {
        itemsList[i] = log;
      }
    });
    await _afterChange(habit, epoch, wasCompleted, completed, day);
    notifyListeners();
  }

  /// Increment/decrement a counter or add minutes to a timer habit.
  Future<void> addValue(String habitId, int delta, {DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null) return;
    final day = date ?? DateTime.now();
    final epoch = epochDayOf(day);
    final existing = logOn(habitId, epoch);
    final wasCompleted = existing?.completed == true;
    final wasPartial = existing != null && Targets.minimumReached(habit, existing.value, day);
    final newValue = math.max(0, (existing?.value ?? 0) + delta);
    final completed = newValue >= Targets.target(habit, day);
    final isPartial = Targets.minimumReached(habit, newValue, day);

    await _logs.mutate((itemsList) {
      final id = HabitLog.idFor(habitId, dateKeyOfEpochDay(epoch));
      final i = itemsList.indexWhere((l) => l.id == id);
      if (newValue == 0 && !completed && existing != null && _isBare(existing) && !existing.skipped) {
        if (i >= 0) {
          itemsList[i] = _tombLog(itemsList[i], DateTime.now().toUtc());
        }
        return;
      }
      final log = _makeLog(
        habitId: habitId,
        day: epoch,
        value: newValue,
        completed: completed,
        skipped: false,
        note: existing?.note ?? '',
        mood: existing?.mood ?? 0,
        items: existing?.items ?? 0,
        ruleId: existing?.ruleId,
        existing: existing,
      );
      if (i < 0) {
        itemsList.add(log);
      } else {
        itemsList[i] = log;
      }
    });
    await _afterChange(habit, epoch, wasCompleted, completed, day, wasPartial: wasPartial, isPartial: isPartial);
    notifyListeners();
  }

  /// Set an exact value (used by the edit sheet and `min read` flows).
  Future<void> setValue(String habitId, int value, {DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null) return;
    final day = date ?? DateTime.now();
    final epoch = epochDayOf(day);
    final existing = logOn(habitId, epoch);
    final wasCompleted = existing?.completed == true;
    final wasPartial = existing != null && Targets.minimumReached(habit, existing.value, day);
    final v = math.max(0, value);
    final completed = habit.type == HabitType.checkbox ? v > 0 : v >= Targets.target(habit, day);
    final isPartial = Targets.minimumReached(habit, v, day);

    await _logs.mutate((itemsList) {
      final id = HabitLog.idFor(habitId, dateKeyOfEpochDay(epoch));
      final i = itemsList.indexWhere((l) => l.id == id);
      if (v == 0 && existing != null && _isBare(existing) && !existing.skipped) {
        if (i >= 0) {
          itemsList[i] = _tombLog(itemsList[i], DateTime.now().toUtc());
        }
        return;
      }
      final log = _makeLog(
        habitId: habitId,
        day: epoch,
        value: v,
        completed: completed,
        skipped: false,
        note: existing?.note ?? '',
        mood: existing?.mood ?? 0,
        items: existing?.items ?? 0,
        ruleId: existing?.ruleId,
        existing: existing,
      );
      if (i < 0) {
        itemsList.add(log);
      } else {
        itemsList[i] = log;
      }
    });
    await _afterChange(habit, epoch, wasCompleted, completed, day, wasPartial: wasPartial, isPartial: isPartial);
    notifyListeners();
  }

  /// Minimum version: log exactly the minimum (`[~] min` button).
  Future<void> logMinimum(String habitId, {DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null || habit.minTarget <= 0) return;
    final day = date ?? DateTime.now();
    final existing = logOn(habitId, epochDayOf(day));
    if ((existing?.value ?? 0) >= habit.minTarget) return;
    await setValue(habitId, habit.minTarget, date: day);
  }

  /// Mark [date] as deliberately skipped (bridges the streak for free).
  Future<void> skip(String habitId, String reason, {DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null) return;
    final day = date ?? DateTime.now();
    final epoch = epochDayOf(day);
    final existing = logOn(habitId, epoch);
    final wasCompleted = existing?.completed == true;
    await _logs.mutate((itemsList) {
      final id = HabitLog.idFor(habitId, dateKeyOfEpochDay(epoch));
      final i = itemsList.indexWhere((l) => l.id == id);
      final log = _makeLog(
        habitId: habitId,
        day: epoch,
        value: 0,
        completed: false,
        skipped: true,
        skipReason: reason.trim(),
        note: existing?.note ?? '',
        mood: existing?.mood ?? 0,
        ruleId: existing?.ruleId,
        existing: existing,
      );
      if (i < 0) {
        itemsList.add(log);
      } else {
        itemsList[i] = log;
      }
    });
    await _afterChange(habit, epoch, wasCompleted, false, day);
    notifyListeners();
  }

  Future<void> unskip(String habitId, {DateTime? date}) async {
    final habit = habitById(habitId);
    if (habit == null) return;
    final day = date ?? DateTime.now();
    final epoch = epochDayOf(day);
    final existing = logOn(habitId, epoch);
    if (existing == null || !existing.skipped) return;
    await _logs.mutate((itemsList) {
      final i = itemsList.indexWhere((l) => l.id == existing.id);
      if (i < 0) return;
      if (existing.note.isEmpty && existing.mood == 0 && existing.ruleId == null) {
        itemsList[i] = _tombLog(itemsList[i], DateTime.now().toUtc());
        return;
      }
      itemsList[i] = _makeLog(
        habitId: habitId,
        day: epoch,
        value: 0,
        completed: false,
        skipped: false,
        note: existing.note,
        mood: existing.mood,
        ruleId: existing.ruleId,
        existing: existing,
      );
    });
    await _afterChange(habit, epoch, false, false, day);
    notifyListeners();
  }

  /// Attach a completion note and/or mood (1–5, 0 = none).
  Future<void> annotate(String habitId, DateTime date, {String? note, int? mood}) async {
    final epoch = epochDayOf(date);
    final existing = logOn(habitId, epoch);
    final updatedNote = note?.trim() ?? existing?.note ?? '';
    final updatedMood = mood?.clamp(0, 5) ?? existing?.mood ?? 0;
    await _logs.mutate((itemsList) {
      final id = HabitLog.idFor(habitId, dateKeyOfEpochDay(epoch));
      final i = itemsList.indexWhere((l) => l.id == id);
      if (updatedNote.isEmpty && updatedMood == 0 && existing == null) return;
      if (existing == null) {
        itemsList.add(_makeLog(
          habitId: habitId,
          day: epoch,
          value: 0,
          completed: false,
          note: updatedNote,
          mood: updatedMood,
        ));
        return;
      }
      if (existing.value == 0 && !existing.completed && !existing.skipped && updatedNote.isEmpty && updatedMood == 0) {
        if (i >= 0) {
          itemsList[i] = _tombLog(itemsList[i], DateTime.now().toUtc());
        }
        return;
      }
      if (i >= 0) {
        itemsList[i] = _makeLog(
          habitId: habitId,
          day: epoch,
          value: existing.value,
          completed: existing.completed,
          skipped: existing.skipped,
          skipReason: existing.skipReason,
          note: updatedNote,
          mood: updatedMood,
          items: existing.items,
          ruleId: existing.ruleId,
          existing: existing,
        );
      }
    });
    notifyListeners();
  }

  /// Repair the most recent missed scheduled day with a streak shield.
  /// Re-create a parked conflict's XP event as a brand-new ledger entry.
  Future<void> addXpRaw({required int day, required int amount, required String reason, String habitId = '0'}) async {
    final now = DateTime.now().toUtc();
    await _xp.mutate((items) => items.add(XpEvent(
          id: JsonDocStore.newId(),
          day: day,
          amount: amount,
          reason: reason,
          habitId: habitId,
          createdAt: now,
          updatedAt: now,
        )));
    notifyListeners();
  }

  /// Re-create a parked conflict's shield use as a brand-new marker.
  Future<void> addShieldUseRaw({required String habitId, required int day}) async {
    final now = DateTime.now().toUtc();
    await _shields.mutate((items) => items.add(ShieldUse(
          id: JsonDocStore.newId(),
          habitId: habitId,
          day: day,
          usedAt: now,
          createdAt: now,
          updatedAt: now,
        )));
    notifyListeners();
  }

  Future<bool> repairWithShield(String habitId) async {
    final habit = habitById(habitId);
    if (habit == null) return false;
    if (shieldsAvailable <= 0) return false;
    final info = streakOf(habit);
    final day = info.repairableDay;
    if (day == null) return false;
    final epoch = epochDayOf(day);
    final id = ShieldUse.idFor(habitId, epoch);
    final now = DateTime.now().toUtc();
    final exists = shieldUses.any((s) => s.id == id);
    if (exists) return false;
    await _shields.mutate((items) {
      items.add(ShieldUse(id: id, habitId: habitId, day: epoch, usedAt: now, createdAt: now, updatedAt: now));
    });
    notifyListeners();
    return true;
  }

  // ================= XP ledger ============================================

  Future<void> _awardOnce(String habitId, int day, String reason, int amount) async {
    final exists = _xp.items.any((x) => !x.deleted && x.habitId == habitId && x.day == day && x.reason == reason);
    if (exists) return;
    final now = DateTime.now().toUtc();
    await _xp.mutate((items) {
      items.add(XpEvent(
        id: JsonDocStore.newId(),
        day: day,
        amount: amount,
        reason: reason,
        habitId: habitId,
        createdAt: now,
        updatedAt: now,
      ));
    });
  }

  Future<void> _deleteXpFor(String habitId, int day, String reason) async {
    final now = DateTime.now().toUtc();
    await _xp.mutate((items) {
      for (var i = 0; i < items.length; i++) {
        final x = items[i];
        if (!x.deleted && x.habitId == habitId && x.day == day && x.reason == reason) {
          items[i] = XpEvent(
            id: x.id,
            day: x.day,
            amount: x.amount,
            reason: x.reason,
            habitId: x.habitId,
            createdAt: x.createdAt,
            updatedAt: now,
            deletedAt: now,
          );
        }
      }
    });
  }

  /// The shared post-change bookkeeping: XP add/remove for completion,
  /// minimum version, 7-day streak and the perfect-day bonus.
  Future<void> _afterChange(
    Habit habit,
    int epoch,
    bool wasCompleted,
    bool isCompleted,
    DateTime date, {
    bool wasPartial = false,
    bool isPartial = false,
  }) async {
    if (!wasCompleted && isCompleted) {
      await _deleteXpFor(habit.id, epoch, XpEvent.reasonMinimum);
      await _awardOnce(habit.id, epoch, XpEvent.reasonComplete, Progression.xpComplete);
      final streak = Streaks.compute(
        habit,
        logsFor(habit.id),
        shieldsFor(habit.id),
        today: date,
        hourNow: date.hour,
      );
      if (streak.current > 0 && streak.current % 7 == 0) {
        await _awardOnce(habit.id, epoch, XpEvent.reasonStreak, Progression.xpStreakWeek);
      }
    } else if (wasCompleted && !isCompleted) {
      await _deleteXpFor(habit.id, epoch, XpEvent.reasonComplete);
      await _deleteXpFor(habit.id, epoch, XpEvent.reasonStreak);
    }
    if (!isCompleted && isPartial && !wasPartial) {
      await _awardOnce(habit.id, epoch, XpEvent.reasonMinimum, Progression.xpMinimum);
    } else if (!isPartial && wasPartial && !isCompleted) {
      await _deleteXpFor(habit.id, epoch, XpEvent.reasonMinimum);
    }

    // Perfect-day bonus (habitId '0' = day-level event).
    final perfect = isPerfectDay(date: date);
    final hasPerfect = _xp.items.any((x) =>
        !x.deleted && x.habitId == '0' && x.day == epoch && x.reason == XpEvent.reasonPerfectDay);
    if (perfect && !hasPerfect) {
      await _awardOnce('0', epoch, XpEvent.reasonPerfectDay, Progression.xpPerfectDay);
    } else if (!perfect && hasPerfect) {
      await _deleteXpFor('0', epoch, XpEvent.reasonPerfectDay);
    }

    await settleChallenges(today: date);
  }

  // ================= maintenance passes ==================================

  /// Avoid-habits: close past scheduled days (up to [lookbackDays] back) that
  /// have no log as *kept* and earn their XP. Idempotent.
  Future<void> settleNegativeHabits({DateTime? today, int lookbackDays = 60}) async {
    final now = today ?? DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    var changed = false;
    for (final h in _habits.items.where((h) => !h.deleted && !h.archived && h.negative)) {
      final existing = {for (final l in logsFor(h.id)) l.day};
      final created = DateTime(h.createdAt.toLocal().year, h.createdAt.toLocal().month, h.createdAt.toLocal().day);
      var d = created.isAfter(today0.subtract(Duration(days: lookbackDays)))
          ? created
          : today0.subtract(Duration(days: lookbackDays));
      while (d.isBefore(today0)) {
        final e = epochDayOf(d);
        if (Schedule.isDue(h, d) && !existing.contains(e)) {
          final at = DateTime.now().toUtc();
          await _logs.mutate((items) {
            items.add(_makeLog(habitId: h.id, day: e, value: 0, completed: true, now: at));
          });
          await _awardOnce(h.id, e, XpEvent.reasonComplete, Progression.xpComplete);
          existing.add(e);
          changed = true;
        }
        d = d.add(const Duration(days: 1));
      }
    }
    if (changed) notifyListeners();
  }

  /// Streak insurance: auto-skip rules write logs tagged with the rule id;
  /// retract rule-skips whose rule no longer covers the day. Idempotent.
  Future<void> applySkipRules({DateTime? today, int pastDays = 14, int futureDays = 60}) async {
    final now = today ?? DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final rules = skipRules;
    final habits = this.habits;
    var changed = false;

    // 1) retract
    final ruleById = {for (final r in rules) r.id: r};
    for (final log in _logs.items.where((l) => !l.deleted && l.skipped && l.ruleId != null).toList()) {
      final rule = ruleById[log.ruleId];
      final habit = habitById(log.habitId);
      final still = rule != null &&
          habit != null &&
          SkipRules.matchesDay(rule, dateOfEpochDay(log.day)) &&
          SkipRules.appliesTo(rule, habit);
      if (still) continue;
      await _logs.mutate((items) {
        final i = items.indexWhere((l) => l.id == log.id);
        if (i < 0) return;
        if (log.note.isEmpty && log.mood == 0) {
          items[i] = _tombLog(items[i], DateTime.now().toUtc());
        } else {
          items[i] = _makeLog(
            habitId: log.habitId,
            day: log.day,
            value: 0,
            completed: false,
            skipped: false,
            skipReason: '',
            note: log.note,
            mood: log.mood,
            ruleId: null,
            existing: log,
          );
        }
      });
      changed = true;
    }

    // 2) apply
    if (rules.any((r) => r.enabled)) {
      for (final habit in habits) {
        if (habit.negative) continue;
        final existing = {for (final l in logsFor(habit.id)) l.day};
        var d = today0.subtract(const Duration(days: 14));
        final end = today0.add(Duration(days: futureDays));
        while (!d.isAfter(end)) {
          final e = epochDayOf(d);
          if (!existing.contains(e) && Schedule.isDue(habit, d)) {
            final rule = SkipRules.covering(rules, habit, d);
            if (rule != null) {
              final at = DateTime.now().toUtc();
              await _logs.mutate((items) {
                items.add(_makeLog(
                  habitId: habit.id,
                  day: e,
                  value: 0,
                  completed: false,
                  skipped: true,
                  skipReason: rule.name,
                  ruleId: rule.id,
                  now: at,
                ));
              });
              existing.add(e);
              changed = true;
            }
          }
          d = d.add(const Duration(days: 1));
        }
      }
    }
    if (changed) notifyListeners();
  }

  /// Settle expired challenges exactly once: half the scheduled days (rounded
  /// up) wins the stake. Returns the settlements written.
  Future<List<ChallengeSettlement>> settleChallenges({DateTime? today}) async {
    final now = today ?? DateTime.now();
    final settlements = <ChallengeSettlement>[];
    for (final h in _habits.items.where((h) => !h.deleted && !h.archived).toList()) {
      if (!Challenges.isSettling(h, now)) continue;
      final result = Challenges.tally(
        h,
        now,
        (epoch) => doneOnEpoch(h.id, epoch),
      );
      final needed = Challenges.threshold(result.scheduled);
      final success = result.done >= needed;
      var xp = 0;
      if (h.chStake > 0) {
        xp = success ? h.chStake * Progression.challengeXpWin : -h.chStake * Progression.challengeXpLose;
        final at = DateTime.now().toUtc();
        await _xp.mutate((items) {
          items.add(XpEvent(
            id: JsonDocStore.newId(),
            day: epochDayOf(now),
            amount: xp,
            reason: XpEvent.reasonChallenge,
            habitId: h.id,
            createdAt: at,
            updatedAt: at,
          ));
        });
      }
      await updateHabit(h.id, (cur) => cur.copyWith(chResolved: true));
      settlements.add(ChallengeSettlement(success: success, xp: xp, done: result.done, scheduled: result.scheduled));
    }
    return settlements;
  }

  // ================= bitmask helpers =======================================

  static int _itemMaskFor(int itemCount) =>
      itemCount >= 63 ? -1 : (1 << itemCount) - 1;

  int _allItemsMask(Habit habit) => _itemMaskFor(habit.checklistItems.length);

  static int _popCount(int mask) {
    var m = mask & _lowBits();
    var count = 0;
    while (m != 0) {
      m &= m - 1;
      count++;
    }
    return count;
  }

  static int _lowBits() => (1 << 62) - 1;
}

