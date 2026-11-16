// Habit domain models, sync-ready (updatedAt + tombstones).
//
// Ports the PersonalTerminal habit model (Kotlin/Room) to Dart: four habit
// types (checkbox/counter/timer/checklist), five schedules, avoid-habits,
// routines, streak shields, XP events, ramps, anchors, challenges and life
// areas. Habit ids and habit-log keys are stable strings so both devices
// build the same ids and merge cleanly.
//
// Legacy formats from DayDeck v0.10.x are migrated transparently on read:
//   Habit    {title, cadence: daily|weekly}  → name, DAILY / WEEKLY timesPerWeek 1
//   HabitLog {date: 'yyyy-mm-dd', done}      → day (epoch day), completed
// Logged history is preserved.

enum HabitType { checkbox, counter, timer, checklist }
enum ScheduleType { daily, weekly, specificDays, biweekly, monthly }
enum TimeOfDay { morning, afternoon, evening, any }

HabitType habitTypeFromString(String? v) => HabitType.values.firstWhere(
      (e) => e.name == v?.toLowerCase(),
      orElse: () => HabitType.checkbox,
    );

ScheduleType scheduleFromString(String? v, {String? legacyCadence}) {
  if (v != null) {
    for (final e in ScheduleType.values) {
      if (e.name == v.toLowerCase()) return e;
    }
  }
  // legacy cadence: 'weekly' meant "≥1 log a week" — keep that meaning.
  if (legacyCadence == 'weekly') return ScheduleType.weekly;
  return ScheduleType.daily;
}

TimeOfDay timeOfDayFromString(String? v) => TimeOfDay.values.firstWhere(
      (e) => e.name == v?.toLowerCase(),
      orElse: () => TimeOfDay.any,
    );

/// Minutes-of-day → section (morning < 12:00 ≤ afternoon < 17:00 ≤ evening).
TimeOfDay timeOfDayAt(int minuteOfDay) {
  if (minuteOfDay < 12 * 60) return TimeOfDay.morning;
  if (minuteOfDay < 17 * 60) return TimeOfDay.afternoon;
  return TimeOfDay.evening;
}

String timeOfDayLabel(TimeOfDay t) => switch (t) {
      TimeOfDay.morning => 'morning',
      TimeOfDay.afternoon => 'afternoon',
      TimeOfDay.evening => 'evening',
      TimeOfDay.any => 'anytime',
    };

/// Epoch day (days since 1970-01-01, local-time zone independent).
int epochDayOf(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  return local.difference(DateTime(1970, 1, 1)).inDays;
}

/// Local midnight for an epoch day.
DateTime dateOfEpochDay(int day) =>
    DateTime(1970, 1, 1).add(Duration(days: day));

String dateKeyOfEpochDay(int day) {
  final d = dateOfEpochDay(day);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

int parseEpochDay(String? v) {
  if (v == null) return 0;
  final d = DateTime.tryParse(v);
  return d == null ? 0 : epochDayOf(d);
}

class Habit {
  Habit({
    required this.id,
    required this.name,
    this.type = HabitType.checkbox,
    this.target = 1,
    this.unit = '',
    this.schedule = ScheduleType.daily,
    this.daysMask = 127,
    this.timesPerWeek = 3,
    this.monthDay = 0,
    this.routineId,
    this.color = 'green',
    this.position = 0,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.notes = '',
    this.negative = false,
    this.reminderMinutes = -1,
    this.focusMinutes = 0,
    this.breakMinutes = 0,
    this.checkIn = false,
    this.checklist = '',
    this.timeOfDay = '',
    this.pausedFrom = 0,
    this.pausedUntil = 0,
    this.minTarget = 0,
    this.rampTo = 0,
    this.rampWeeks = 0,
    this.rampStartDay = 0,
    this.anchorId,
    this.anchorRemind = false,
    this.area = '',
    this.chStart = 0,
    this.chEnd = 0,
    this.chStake = 0,
    this.chResolved = false,
  });

  final String id;
  final String name;
  final HabitType type;

  /// Counter: target count. Timer: target minutes. Checkbox: 1.
  final int target;
  final String unit;
  final ScheduleType schedule;

  /// Bitmask Mon=1, Tue=2, … Sun=64 (SPECIFIC_DAYS / BIWEEKLY).
  final int daysMask;

  /// WEEKLY schedule: completions required per week.
  final int timesPerWeek;

  /// MONTHLY schedule: day of month 1–31 (0 = none).
  final int monthDay;
  final String? routineId;
  final String color;
  final int position;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String notes;

  /// Avoid-habit ("no sugar"): each scheduled day is kept unless a slip is logged.
  final bool negative;

  /// Minutes after local midnight; -1 = no reminder.
  final int reminderMinutes;

  /// Timer habits: per-habit focus / break length in minutes (0 = global default).
  final int focusMinutes;
  final int breakMinutes;

  /// Evening check-in nudge if the habit is still unlogged at check-in time.
  final bool checkIn;

  /// Checklist sub-items, newline separated.
  final String checklist;

  /// '' | morning | afternoon | evening | any
  final String timeOfDay;

  /// Pause window [pausedFrom, pausedUntil) (epoch days), 0 = not paused.
  final int pausedFrom;
  final int pausedUntil;

  /// Minimum version (counter/timer): reaching this keeps the streak as a partial day.
  final int minTarget;

  /// Ramp: target grows linearly from [target] to [rampTo] over [rampWeeks] from [rampStartDay].
  final int rampTo;
  final int rampWeeks;
  final int rampStartDay;

  /// Habit stacking: id of the anchor habit; null = none.
  final String? anchorId;
  final bool anchorRemind;

  /// Life area (body/mind/work/people/home/money); '' = none.
  final String area;

  /// Challenge window [chStart, chEnd] (inclusive epoch days); 0 = no challenge.
  final int chStart;
  final int chEnd;
  final int chStake;
  final bool chResolved;

  bool get deleted => deletedAt != null;

  List<String> get checklistItems => type != HabitType.checklist
      ? const []
      : checklist.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  bool isPausedOn(int epochDay) =>
      pausedUntil > 0 && epochDay >= pausedFrom && epochDay < pausedUntil;

  TimeOfDay get section {
    if (timeOfDay.isNotEmpty) return timeOfDayFromString(timeOfDay);
    if (reminderMinutes >= 0) return timeOfDayAt(reminderMinutes);
    return TimeOfDay.any;
  }

  /// Backwards-compatible title alias (DayDeck ≤0.10 called it title).
  String get title => name;

  Habit copyWith({
    String? name,
    HabitType? type,
    int? target,
    String? unit,
    ScheduleType? schedule,
    int? daysMask,
    int? timesPerWeek,
    int? monthDay,
    String? routineId,
    bool clearRoutineId = false,
    String? color,
    int? position,
    bool? archived,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? notes,
    bool? negative,
    int? reminderMinutes,
    int? focusMinutes,
    int? breakMinutes,
    bool? checkIn,
    String? checklist,
    String? timeOfDay,
    int? pausedFrom,
    int? pausedUntil,
    int? minTarget,
    int? rampTo,
    int? rampWeeks,
    int? rampStartDay,
    String? anchorId,
    bool clearAnchorId = false,
    bool? anchorRemind,
    String? area,
    int? chStart,
    int? chEnd,
    int? chStake,
    bool? chResolved,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      target: target ?? this.target,
      unit: unit ?? this.unit,
      schedule: schedule ?? this.schedule,
      daysMask: daysMask ?? this.daysMask,
      timesPerWeek: timesPerWeek ?? this.timesPerWeek,
      monthDay: monthDay ?? this.monthDay,
      routineId: clearRoutineId ? null : (routineId ?? this.routineId),
      color: color ?? this.color,
      position: position ?? this.position,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      notes: notes ?? this.notes,
      negative: negative ?? this.negative,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      focusMinutes: focusMinutes ?? this.focusMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      checkIn: checkIn ?? this.checkIn,
      checklist: checklist ?? this.checklist,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      pausedFrom: pausedFrom ?? this.pausedFrom,
      pausedUntil: pausedUntil ?? this.pausedUntil,
      minTarget: minTarget ?? this.minTarget,
      rampTo: rampTo ?? this.rampTo,
      rampWeeks: rampWeeks ?? this.rampWeeks,
      rampStartDay: rampStartDay ?? this.rampStartDay,
      anchorId: clearAnchorId ? null : (anchorId ?? this.anchorId),
      anchorRemind: anchorRemind ?? this.anchorRemind,
      area: area ?? this.area,
      chStart: chStart ?? this.chStart,
      chEnd: chEnd ?? this.chEnd,
      chStake: chStake ?? this.chStake,
      chResolved: chResolved ?? this.chResolved,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'target': target,
        'unit': unit,
        'schedule': schedule.name,
        'daysMask': daysMask,
        'timesPerWeek': timesPerWeek,
        'monthDay': monthDay,
        'routineId': routineId,
        'color': color,
        'position': position,
        'archived': archived,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
        'notes': notes,
        'negative': negative,
        'reminderMinutes': reminderMinutes,
        'focusMinutes': focusMinutes,
        'breakMinutes': breakMinutes,
        'checkIn': checkIn,
        'checklist': checklist,
        'timeOfDay': timeOfDay,
        'pausedFrom': pausedFrom,
        'pausedUntil': pausedUntil,
        'minTarget': minTarget,
        'rampTo': rampTo,
        'rampWeeks': rampWeeks,
        'rampStartDay': rampStartDay,
        'anchorId': anchorId,
        'anchorRemind': anchorRemind,
        'area': area,
        'chStart': chStart,
        'chEnd': chEnd,
        'chStake': chStake,
        'chResolved': chResolved,
      };

  factory Habit.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    // Legacy: v0.10 wrote {title, cadence}. Migrate on read.
    final legacyTitle = json['title']?.toString();
    final name = (json['name']?.toString().isNotEmpty ?? false)
        ? json['name'].toString()
        : (legacyTitle ?? '');
    final schedule = scheduleFromString(
      json['schedule']?.toString(),
      legacyCadence: json['cadence']?.toString(),
    );
    final legacyWeekly = json['schedule'] == null && json['cadence'] == 'weekly';
    return Habit(
      id: json['id']?.toString() ?? '',
      name: name,
      type: habitTypeFromString(json['type']?.toString()),
      target: (json['target'] as num?)?.toInt() ?? 1,
      unit: json['unit']?.toString() ?? '',
      schedule: schedule,
      daysMask: (json['daysMask'] as num?)?.toInt() ?? 127,
      timesPerWeek: legacyWeekly ? 1 : ((json['timesPerWeek'] as num?)?.toInt() ?? 3),
      monthDay: (json['monthDay'] as num?)?.toInt() ?? 0,
      routineId: json['routineId']?.toString(),
      color: json['color']?.toString() ?? 'green',
      position: (json['position'] as num?)?.toInt() ?? 0,
      archived: json['archived'] == true,
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
      notes: json['notes']?.toString() ?? '',
      negative: json['negative'] == true,
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt() ?? -1,
      focusMinutes: (json['focusMinutes'] as num?)?.toInt() ?? 0,
      breakMinutes: (json['breakMinutes'] as num?)?.toInt() ?? 0,
      checkIn: json['checkIn'] == true,
      checklist: json['checklist']?.toString() ?? '',
      timeOfDay: json['timeOfDay']?.toString() ?? '',
      pausedFrom: (json['pausedFrom'] as num?)?.toInt() ?? 0,
      pausedUntil: (json['pausedUntil'] as num?)?.toInt() ?? 0,
      minTarget: (json['minTarget'] as num?)?.toInt() ?? 0,
      rampTo: (json['rampTo'] as num?)?.toInt() ?? 0,
      rampWeeks: (json['rampWeeks'] as num?)?.toInt() ?? 0,
      rampStartDay: (json['rampStartDay'] as num?)?.toInt() ?? 0,
      anchorId: json['anchorId']?.toString(),
      anchorRemind: json['anchorRemind'] == true,
      area: json['area']?.toString() ?? '',
      chStart: (json['chStart'] as num?)?.toInt() ?? 0,
      chEnd: (json['chEnd'] as num?)?.toInt() ?? 0,
      chStake: (json['chStake'] as num?)?.toInt() ?? 0,
      chResolved: json['chResolved'] == true,
    );
  }
}

/// One row per habit per day. `value` is count for counters, minutes for
/// timers, 1/0 for checkbox. Keyed `"<habitId>|<yyyy-mm-dd>"`.
class HabitLog {
  HabitLog({
    required this.id,
    required this.habitId,
    required this.day,
    this.value = 0,
    this.completed = false,
    this.skipped = false,
    this.skipReason = '',
    this.note = '',
    this.mood = 0,
    this.items = 0,
    this.ruleId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String habitId;

  /// Epoch day.
  final int day;
  final int value;
  final bool completed;

  /// Day deliberately skipped — bridges the streak without spending a shield.
  final bool skipped;
  final String skipReason;
  final String note;

  /// Mood 1 (awful) … 5 (great); 0 = not recorded.
  final int mood;

  /// Checklist sub-item bitmask (bit i = item i); `value` is the popcount.
  final int items;

  /// Id of the SkipRule that auto-skipped this day; null = user-driven.
  final String? ruleId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  /// yyyy-mm-dd in local time (legacy display compatibility).
  String get date => dateKeyOfEpochDay(day);

  /// Legacy alias for [completed] (v0.10 readers).
  bool get done => completed;

  static String idFor(String habitId, String dateKey) => '$habitId|$dateKey';

  bool hasItem(int index) => index >= 0 && index < 63 && (items >> index) & 1 == 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'day': day,
        'date': date, // kept for debugging/export readability; readers use day
        'value': value,
        'completed': completed,
        'done': completed, // legacy alias
        'skipped': skipped,
        'skipReason': skipReason,
        'note': note,
        'mood': mood,
        'items': items,
        'ruleId': ruleId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    final habitId = json['habitId']?.toString() ?? '';
    // New format carries `day` (epoch day int); legacy carries `date` (yyyy-mm-dd).
    final int? day = (json['day'] as num?)?.toInt() ??
        (json['date'] != null ? parseEpochDay(json['date'].toString()) : null);
    final effectiveDay = day ?? 0;
    final dateKey = dateKeyOfEpochDay(effectiveDay);
    final completed = json['completed'] == true || (json['completed'] == null && json['done'] == true);
    return HabitLog(
      id: json['id']?.toString().isNotEmpty == true ? json['id'].toString() : HabitLog.idFor(habitId, dateKey),
      habitId: habitId,
      day: effectiveDay,
      value: (json['value'] as num?)?.toInt() ?? (completed ? 1 : 0),
      completed: completed,
      skipped: json['skipped'] == true,
      skipReason: json['skipReason']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      mood: (json['mood'] as num?)?.toInt() ?? 0,
      items: (json['items'] as num?)?.toInt() ?? 0,
      ruleId: json['ruleId']?.toString(),
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}

/// A named group of habits ("Morning Routine").
class Routine {
  Routine({
    required this.id,
    required this.name,
    this.icon = '>',
    this.position = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String icon;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  Routine copyWith({String? name, String? icon, int? position, DateTime? updatedAt, DateTime? deletedAt}) =>
      Routine(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        position: position ?? this.position,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'position': position,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory Routine.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return Routine(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '>',
      position: (json['position'] as num?)?.toInt() ?? 0,
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}

/// Streak-insurance rule: automatically skip matching days (travel, sick
/// leave, rest days) so a chain survives without spending a shield.
class SkipRule {
  SkipRule({
    required this.id,
    required this.name,
    this.kind = SkipRule.kindRange,
    this.fromDay,
    this.toDay,
    this.weekdayMask = 0,
    this.habitIds = '',
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const String kindRange = 'range';
  static const String kindWeekly = 'weekly';

  final String id;
  final String name;
  final String kind;
  final int? fromDay;
  final int? toDay;

  /// Weekly pattern, bit 0 = Monday.
  final int weekdayMask;

  /// Comma-separated habit ids; '' = every habit.
  final String habitIds;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;
  bool get isOpenEnded => kind == kindRange && toDay == null;
  Set<String> get habitIdSet =>
      habitIds.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

  SkipRule copyWith({
    String? name,
    String? kind,
    int? fromDay,
    int? toDay,
    bool clearToDay = false,
    int? weekdayMask,
    String? habitIds,
    bool? enabled,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      SkipRule(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        fromDay: fromDay ?? this.fromDay,
        toDay: clearToDay ? null : (toDay ?? this.toDay),
        weekdayMask: weekdayMask ?? this.weekdayMask,
        habitIds: habitIds ?? this.habitIds,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'fromDay': fromDay,
        'toDay': toDay,
        'weekdayMask': weekdayMask,
        'habitIds': habitIds,
        'enabled': enabled,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory SkipRule.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return SkipRule(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? kindRange,
      fromDay: (json['fromDay'] as num?)?.toInt(),
      toDay: (json['toDay'] as num?)?.toInt(),
      weekdayMask: (json['weekdayMask'] as num?)?.toInt() ?? 0,
      habitIds: json['habitIds']?.toString() ?? '',
      enabled: json['enabled'] != false,
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}

/// A streak shield consumed to bridge a missed day.
class ShieldUse {
  ShieldUse({required this.id, required this.habitId, required this.day, required this.usedAt, required this.createdAt, required this.updatedAt, this.deletedAt});

  /// `<habitId>|<yyyy-mm-dd>` for determinism.
  final String id;
  final String habitId;
  final int day;
  final DateTime usedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  static String idFor(String habitId, int day) => '$habitId|${dateKeyOfEpochDay(day)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'day': day,
        'usedAt': usedAt.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory ShieldUse.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    final habitId = json['habitId']?.toString() ?? '';
    final day = (json['day'] as num?)?.toInt() ?? parseEpochDay(json['date']?.toString());
    return ShieldUse(
      id: json['id']?.toString().isNotEmpty == true
          ? json['id'].toString()
          : ShieldUse.idFor(habitId, day),
      habitId: habitId,
      day: day,
      usedAt: parseTime(json['usedAt'] ?? json['createdAt']),
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt'] ?? json['createdAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}

/// Persisted XP ledger — one row per reward.
class XpEvent {
  XpEvent({
    required this.id,
    required this.day,
    required this.amount,
    required this.reason,
    this.habitId = '0',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const String reasonComplete = 'complete';
  static const String reasonStreak = 'streak';
  static const String reasonPerfectDay = 'perfect_day';
  static const String reasonMinimum = 'minimum';
  static const String reasonChallenge = 'challenge';

  final String id;
  final int day;
  final int amount;
  final String reason;

  /// '0' = day-level event (perfect day).
  final String habitId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'amount': amount,
        'reason': reason,
        'habitId': habitId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory XpEvent.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return XpEvent(
      id: json['id']?.toString() ?? '',
      day: (json['day'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      reason: json['reason']?.toString() ?? '',
      habitId: json['habitId']?.toString() ?? '0',
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt'] ?? json['createdAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}
