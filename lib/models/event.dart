// Local calendar event (private or shared). Every field the Phase 3-style
// sync needs exists NOW (updatedAt + tombstones) so merges need no migration.
//
// start/end are UTC instants. For all-day events they are local midnights and
// only the calendar day is meaningful.

class Event {
  Event({
    required this.id,
    required this.title,
    this.notes,
    this.location,
    required this.start,
    required this.end,
    this.allDay = false,
    this.visibility = 'private',
    this.done = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String? notes;
  final String? location;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// 'private' — stays on this device · 'shared' — headed for Google Calendar
  final String visibility;

  /// For SHARED events: set automatically once the event is spotted in the
  /// Google Calendar feed (or manually via the ✓ button). SHARED + done =
  /// auto-hidden from Today.
  final bool done;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;
  bool get isShared => visibility == 'shared';

  Event copyWith({
    String? title,
    String? notes,
    String? location,
    bool clearNotes = false,
    bool clearLocation = false,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? visibility,
    bool? done,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Event(
      id: id,
      title: title ?? this.title,
      notes: clearNotes ? null : (notes ?? this.notes),
      location: clearLocation ? null : (location ?? this.location),
      start: start ?? this.start,
      end: end ?? this.end,
      allDay: allDay ?? this.allDay,
      visibility: visibility ?? this.visibility,
      done: done ?? this.done,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'location': location,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'allDay': allDay,
        'visibility': visibility == 'shared' ? 'shared' : 'private',
        'done': done,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory Event.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return Event(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      notes: json['notes']?.toString().isNotEmpty == true ? json['notes'].toString() : null,
      location: json['location']?.toString().isNotEmpty == true ? json['location'].toString() : null,
      start: parseTime(json['start']),
      end: parseTime(json['end']),
      allDay: json['allDay'] == true,
      visibility: json['visibility'] == 'shared' ? 'shared' : 'private',
      done: json['done'] == true,
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null ? null : DateTime.tryParse(json['deletedAt'].toString())?.toUtc(),
    );
  }
}
