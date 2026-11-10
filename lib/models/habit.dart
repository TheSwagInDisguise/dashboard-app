// Habit + habit-log models, sync-ready (updatedAt + tombstones).
//
// A HabitLog is keyed "<habitId>|<yyyy-mm-dd>" so marking/unmarking the same
// day converges cleanly across devices.

class Habit {
  Habit({
    required this.id,
    required this.title,
    this.cadence = 'daily',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;

  /// 'daily' — streak counts consecutive days · 'weekly' — consecutive weeks with ≥1 log
  final String cadence;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  Habit copyWith({
    String? title,
    String? cadence,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Habit(
      id: id,
      title: title ?? this.title,
      cadence: cadence ?? this.cadence,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cadence': cadence == 'weekly' ? 'weekly' : 'daily',
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory Habit.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return Habit(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      cadence: json['cadence'] == 'weekly' ? 'weekly' : 'daily',
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : DateTime.tryParse(json['deletedAt'].toString())?.toUtc(),
    );
  }
}

class HabitLog {
  HabitLog({
    required this.id,
    required this.habitId,
    required this.date,
    required this.done,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// `habitId|yyyy-mm-dd` — deterministic so both devices make the same id.
  final String id;
  final String habitId;
  final String date; // yyyy-mm-dd (local day)
  final bool done;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  static String idFor(String habitId, String date) => '$habitId|$date';

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'date': date,
        'done': done,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    final habitId = json['habitId']?.toString() ?? '';
    final date = json['date']?.toString() ?? '';
    return HabitLog(
      id: json['id']?.toString().isNotEmpty == true ? json['id'].toString() : HabitLog.idFor(habitId, date),
      habitId: habitId,
      date: date,
      done: json['done'] == true,
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : DateTime.tryParse(json['deletedAt'].toString())?.toUtc(),
    );
  }
}
