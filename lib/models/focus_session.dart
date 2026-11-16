// Focus (pomodoro) session records. Each row is a finished countdown or
// stopwatch session; minutes feed the heatmap and per-habit history.

class FocusSession {
  FocusSession({
    required this.id,
    this.habitId = '0',
    required this.day,
    required this.startedAt,
    required this.endedAt,
    required this.minutes,
    this.kind = kindFocus,
    this.completed = true,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const String kindFocus = 'focus';
  static const String kindStopwatch = 'stopwatch';

  final String id;

  /// '0' = free session not bound to a habit.
  final String habitId;

  /// Epoch day the session started on.
  final int day;

  /// Epoch millis.
  final int startedAt;
  final int endedAt;

  /// Whole minutes of focus credited.
  final int minutes;
  final String kind;

  /// False when the phase was stopped/skipped before it finished.
  final bool completed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'day': day,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'minutes': minutes,
        'kind': kind,
        'completed': completed,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory FocusSession.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return FocusSession(
      id: json['id']?.toString() ?? '',
      habitId: json['habitId']?.toString() ?? '0',
      day: (json['day'] as num?)?.toInt() ?? 0,
      startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
      endedAt: (json['endedAt'] as num?)?.toInt() ?? 0,
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? kindFocus,
      completed: json['completed'] != false,
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : parseTime(json['deletedAt']),
    );
  }
}
