// Task model. Every field needed by the Phase 3 GitHub sync exists NOW
// (updatedAt, soft-delete tombstones) so merges need no schema migration.

class Task {
  Task({
    required this.id,
    required this.title,
    this.done = false,
    this.priority = 'P2',
    this.dueDate,
    this.reminderAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final bool done;

  /// 'P1' high · 'P2' normal (default) · 'P3' low
  final String priority;

  /// 'YYYY-MM-DD' or null (no due date)
  final String? dueDate;

  /// UTC instant for the per-task reminder notification, or null (none).
  /// Only meaningful while the task is open; done/deleted tasks never fire.
  final DateTime? reminderAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;

  Task copyWith({
    String? title,
    bool? done,
    String? priority,
    String? dueDate,
    bool clearDueDate = false,
    DateTime? reminderAt,
    bool clearReminder = false,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      done: done ?? this.done,
      priority: priority ?? this.priority,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'priority': priority,
        'due': dueDate,
        'reminderAt': reminderAt?.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return Task(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      done: json['done'] == true,
      priority: (json['priority']?.toString() ?? 'P2'),
      dueDate: json['due']?.toString().isNotEmpty == true ? json['due'].toString() : null,
      reminderAt: json['reminderAt'] == null
          ? null
          : DateTime.tryParse(json['reminderAt'].toString())?.toUtc(),
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : DateTime.tryParse(json['deletedAt'].toString())?.toUtc(),
    );
  }
}
