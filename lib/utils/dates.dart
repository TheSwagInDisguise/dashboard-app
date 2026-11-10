// Small date helpers for due-date handling. All dates are day-granularity
// and stored as 'YYYY-MM-DD' strings — no timezone drift, easy to compare.

enum DueStatus { overdue, today, tomorrow, future, none }

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayKey() => dateKey(DateTime.now());

DateTime? parseDateKey(String? key) {
  if (key == null) return null;
  return DateTime.tryParse(key);
}

/// Describes a due date relative to today, e.g. "overdue · +2d", "due today",
/// "tomorrow" or "23/11" (or "23/11/2027" when outside this year).
({String label, DueStatus status}) describeDue(String? key) {
  final d = parseDateKey(key);
  if (d == null) return (label: '', status: DueStatus.none);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(d.year, d.month, d.day);
  final delta = due.difference(today).inDays;

  if (delta < 0) return (label: 'overdue · +${-delta}d', status: DueStatus.overdue);
  if (delta == 0) return (label: 'due today', status: DueStatus.today);
  if (delta == 1) return (label: 'tomorrow', status: DueStatus.tomorrow);

  final short = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  return (label: d.year == now.year ? short : '$short/${d.year}', status: DueStatus.future);
}
