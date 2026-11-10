// Minimal, dependency-free iCal (RFC 5545) reader tailored for Google's feed.
//
// Supported (the "simple" profile, as chosen 2026-11-10):
//   * VEVENTs: UID, DTSTART, DTEND, SUMMARY, DESCRIPTION, LOCATION, STATUS (cancelled events skipped)
//   * All-day events (VALUE=DATE)
//   * UTC datetimes (…Z), floating/local datetimes (interpreted as device-local time),
//     TZID=… datetimes (also interpreted as device-local time — correct when the
//     phone is in the same zone as the calendar, e.g. Australia/Sydney)
//   * RRULE: FREQ=DAILY|WEEKLY|MONTHLY|YEARLY with INTERVAL, UNTIL, COUNT, BYDAY (weekly),
//     BYMONTHDAY (monthly)
//   * EXDATE (comma-separated), RECURRENCE-ID overrides (same UID)
//
// Not supported: BYSETPOS, BYWEEKNO, RDATE, WKST, full timezone tables. A rule we
// can't parse is surfaced via CalendarExpand.skipped so the UI can say so instead
// of silently dropping the event.

class IcsRawEvent {
  IcsRawEvent({
    required this.uid,
    required this.start,
    this.end,
    this.title = '(no title)',
    this.notes,
    this.location,
    this.allDay = false,
    this.rrule,
    this.duration,
    this.exdates = const [],
    this.recurrenceId,
    this.cancelled = false,
  });

  final String uid;
  final DateTime start; // local DateTime (device zone) or UTC for …Z
  final DateTime? end;
  final String title;
  final String? notes;
  final String? location;
  final bool allDay;
  final Map<String, String>? rrule;
  final Duration? duration;
  final List<DateTime> exdates;
  final DateTime? recurrenceId;
  final bool cancelled;
}

class CalendarEventItem {
  const CalendarEventItem({
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.notes,
  });

  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'title': title,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'allDay': allDay,
        'location': location,
        'notes': notes,
      };

  static CalendarEventItem fromJson(Map<String, dynamic> json) {
    DateTime t(String key) => DateTime.tryParse(json[key]?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc();
    return CalendarEventItem(
      uid: json['uid']?.toString() ?? '',
      title: json['title']?.toString() ?? '(no title)',
      start: t('start').toLocal(),
      end: t('end').toLocal(),
      allDay: json['allDay'] == true,
      location: json['location']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

class ExpandResult {
  const ExpandResult({required this.events, required this.skippedRules});
  final List<CalendarEventItem> events;

  /// Human-readable notes about rules that couldn't be expanded.
  final List<String> skippedRules;
}

// ================= parsing =================

/// Parses a whole .ics document into raw VEVENTs.
List<IcsRawEvent> parseIcs(String raw) {
  // Unfold continuation lines (CRLF or LF followed by space/tab).
  final unfolded = raw.replaceAll('\r\n', '\n').replaceAllMapped(RegExp(r'\n[ \t]'), (_) => '');
  final lines = unfolded.split('\n');

  final events = <IcsRawEvent>[];
  Map<String, List<String>>? current;

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;

    if (line == 'BEGIN:VEVENT') {
      current = {};
      continue;
    }
    if (line == 'END:VEVENT') {
      if (current != null) events.add(_buildEvent(current));
      current = null;
      continue;
    }
    if (current == null) continue;

    final colon = _findValueColon(line);
    if (colon < 0) continue;
    final head = line.substring(0, colon);
    final value = _unescapeText(line.substring(colon + 1));
    final parts = head.split(';');
    final name = parts.first.toUpperCase();
    final params = <String, String>{};
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1);
    }
    current.putIfAbsent(name, () => []).add(_paramLine(params, value));
  }
  return events;
}

/// "PARAM1=V1,PARAM2=V2::value" — params and value joined by \x00 so the
/// value itself can keep its colon.
String _paramLine(Map<String, String> params, String value) {
  if (params.isEmpty) return value;
  final encoded = params.entries.map((e) => '${e.key}=${e.value}').join(',');
  return '$encoded\x00$value';
}

int _findValueColon(String line) {
  // The colon separating name/params from value — skip colons inside quotes
  // (e.g. TZID="UTC+10:00").
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == ':' && !inQuotes) return i;
  }
  return -1;
}

String _unescapeText(String v) => v
    .replaceAll('\\n', '\n')
    .replaceAll('\\N', '\n')
    .replaceAll('\\,', ',')
    .replaceAll('\\;', ';')
    .replaceAll('\\\\', '\\');

({Map<String, String> params, String value}) _splitParamLine(String line) {
  final idx = line.indexOf('\x00');
  if (idx < 0) return (params: <String, String>{}, value: line);
  final params = <String, String>{};
  for (final p in line.substring(0, idx).split(',')) {
    final eq = p.indexOf('=');
    if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1);
  }
  return (params: params, value: line.substring(idx + 1));
}

IcsRawEvent _buildEvent(Map<String, List<String>> props) {
  String? first(String key) => props[key]?.isNotEmpty == true ? props[key]!.first : null;

  final startLine = first('DTSTART');
  final startParsed = startLine == null ? null : _parseDateProp(startLine);
  final endParsed = first('DTEND') == null ? null : _parseDateProp(first('DTEND')!);
  final ridParsed = first('RECURRENCE-ID') == null ? null : _parseDateProp(first('RECURRENCE-ID')!);
  final duration = first('DURATION') == null ? null : _parseDuration(first('DURATION')!);

  final exdates = <DateTime>[];
  for (final line in props['EXDATE'] ?? const <String>[]) {
    final parsed = _splitParamLine(line);
    for (final v in parsed.value.split(',')) {
      final dt = _parseDateValue(v.trim(), parsed.params['VALUE']?.toUpperCase() == 'DATE');
      if (dt != null) exdates.add(dt);
    }
  }

  final rruleLine = first('RRULE');
  Map<String, String>? rrule;
  if (rruleLine != null) {
    rrule = {};
    for (final part in rruleLine.split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) rrule[part.substring(0, eq).toUpperCase()] = part.substring(eq + 1).toUpperCase();
    }
  }

  final isAllDay = props['DTSTART']?.first != null &&
      _splitParamLine(props['DTSTART']!.first).params['VALUE']?.toUpperCase() == 'DATE';

  return IcsRawEvent(
    uid: first('UID') ?? 'no-uid-${startParsed?.millisecondsSinceEpoch ?? props.hashCode}',
    start: startParsed ?? DateTime.now(),
    end: endParsed,
    title: (first('SUMMARY') ?? '(no title)').trim(),
    notes: first('DESCRIPTION')?.trim(),
    location: first('LOCATION')?.trim(),
    allDay: isAllDay,
    rrule: rrule,
    duration: duration,
    exdates: exdates,
    recurrenceId: ridParsed,
    cancelled: (first('STATUS') ?? '').toUpperCase() == 'CANCELLED',
  );
}

DateTime? _parseDateProp(String line) {
  final parsed = _splitParamLine(line);
  final valueDate = parsed.params['VALUE']?.toUpperCase() == 'DATE';
  return _parseDateValue(parsed.value.trim(), valueDate);
}

/// Parses 'YYYYMMDD', 'YYYYMMDDTHHMMSS', 'YYYYMMDDTHHMMSSZ'.
DateTime? _parseDateValue(String value, bool forceDateOnly) {
  try {
    if (forceDateOnly || RegExp(r'^\d{8}$').hasMatch(value)) {
      final y = int.parse(value.substring(0, 4));
      final m = int.parse(value.substring(4, 6));
      final d = int.parse(value.substring(6, 8));
      return DateTime(y, m, d); // local midnight, all-day
    }
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$').firstMatch(value);
    if (match == null) return null;
    final y = int.parse(match.group(1)!);
    final mo = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final h = int.parse(match.group(4)!);
    final mi = int.parse(match.group(5)!);
    final s = int.parse(match.group(6)!);
    if (match.group(7) == 'Z') return DateTime.utc(y, mo, d, h, mi, s);
    // Floating / TZID datetime — interpreted as device-local time.
    return DateTime(y, mo, d, h, mi, s);
  } catch (_) {
    return null;
  }
}

Duration? _parseDuration(String value) {
  // Durations like PT30M, PT1H30M, P1D — only time parts we care about.
  final match = RegExp(r'P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?').firstMatch(value.toUpperCase());
  if (match == null) return null;
  final days = int.tryParse(match.group(1) ?? '0') ?? 0;
  final hours = int.tryParse(match.group(2) ?? '0') ?? 0;
  final minutes = int.tryParse(match.group(3) ?? '0') ?? 0;
  return Duration(days: days, hours: hours, minutes: minutes);
}

// ================= recurrence expansion =================

ExpandResult expandEvents(List<IcsRawEvent> raw, DateTime windowStart, DateTime windowEnd) {
  final skipped = <String>{};

  final masters = <IcsRawEvent>[];
  final overrides = <String, IcsRawEvent>{}; // uid|ridKey → override
  final singles = <IcsRawEvent>[];

  for (final event in raw) {
    if (event.cancelled) continue;
    if (event.recurrenceId != null) {
      overrides['${event.uid}|${_instantKey(event.recurrenceId!)}'] = event;
    } else if (event.rrule != null) {
      masters.add(event);
    } else {
      singles.add(event);
    }
  }

  final output = <CalendarEventItem>[];

  CalendarEventItem toItem(IcsRawEvent e, DateTime starts) {
    final defaultDuration = e.allDay ? const Duration(days: 1) : const Duration(hours: 1);
    final duration = e.end != null ? e.end!.difference(e.start) : (e.duration ?? defaultDuration);
    return CalendarEventItem(
      uid: e.uid,
      title: e.title,
      start: starts,
      end: starts.add(duration),
      allDay: e.allDay,
      location: e.location,
      notes: e.notes,
    );
  }

  bool inWindow(DateTime start, DateTime end) => end.isAfter(windowStart) && start.isBefore(windowEnd);

  // Singles (and one-off overrides without a master).
  for (final single in singles) {
    final end = single.end ?? single.start.add(single.duration ?? (single.allDay ? const Duration(days: 1) : const Duration(hours: 1)));
    if (inWindow(single.start, end)) output.add(toItem(single, single.start));
  }

  // Recurring masters.
  for (final master in masters) {
    final rule = master.rrule!;
    final freq = rule['FREQ'];
    if (freq == null || !const ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'].contains(freq)) {
      skipped.add('${master.title}: unsupported FREQ=${freq ?? '?'}');
      continue;
    }
    final interval = int.tryParse(rule['INTERVAL'] ?? '1') ?? 1;
    if (interval < 1) {
      skipped.add('${master.title}: INTERVAL<1');
      continue;
    }
    final count = rule['COUNT'] == null ? null : int.tryParse(rule['COUNT']!);
    DateTime? until = rule['UNTIL'] == null ? null : _parseDateValue(rule['UNTIL']!, rule['UNTIL']!.length == 8);
    if (until != null && until.hour == 0 && until.minute == 0 && rule['UNTIL']!.length > 8) {
      // keep as-is
    }

    final occurrences = _expandOccurrences(
      master: master,
      freq: freq,
      interval: interval,
      count: count,
      until: until,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

    for (final occurrence in occurrences) {
      final ridKey = '${master.uid}|${_instantKey(occurrence)}';
      final override = overrides.remove(ridKey);
      final source = override ?? master;
      final starts = override != null ? override.start : occurrence;
      final item = toItem(source, starts);
      if (inWindow(item.start, item.end)) output.add(item);
    }
  }

  // Overrides whose master wasn't in this feed/window still deserve a slot.
  for (final override in overrides.values) {
    final end = override.end ?? override.start.add(override.duration ?? const Duration(hours: 1));
    if (inWindow(override.start, end)) output.add(toItem(override, override.start));
  }

  output.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return a.start.compareTo(b.start);
  });

  return ExpandResult(events: output, skippedRules: skipped.toList());
}

List<DateTime> _expandOccurrences({
  required IcsRawEvent master,
  required String freq,
  required int interval,
  required int? count,
  required DateTime? until,
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  final out = <DateTime>[];
  final exkeys = master.exdates.map(_instantKey).toSet();
  final timeOfDay = (master.start.hour, master.start.minute, master.start.second);

  // Fast-forward unbounded series to just before the window — but never skip
  // when COUNT is set, because every occurrence from DTSTART counts towards it.
  var candidate = master.start;
  var emitted = 0;
  if (count == null) {
    final lead = windowStart.subtract(const Duration(days: 2));
    if (candidate.isBefore(lead)) {
      if (freq == 'DAILY') {
        final steps = lead.difference(candidate).inDays ~/ interval;
        candidate = candidate.add(Duration(days: steps * interval));
      } else if (freq == 'WEEKLY') {
        final steps = lead.difference(candidate).inDays ~/ (7 * interval);
        candidate = candidate.add(Duration(days: steps * 7 * interval));
      } else if (freq == 'MONTHLY') {
        final months = (lead.year - candidate.year) * 12 + (lead.month - candidate.month);
        final steps = months ~/ interval;
        candidate = _addMonthsPreservingTime(candidate, steps * interval, master.start.day);
      } else if (freq == 'YEARLY') {
        final steps = (lead.year - candidate.year) ~/ interval;
        candidate = DateTime(candidate.year + steps * interval, candidate.month, master.start.day,
            candidate.hour, candidate.minute, candidate.second);
      }
    }
  }

  final maxIterations = count == null ? 1500 : 20000;
  final hardStop = windowEnd.add(const Duration(days: 400));

  for (var i = 0; i < maxIterations; i++) {
    if (until != null && candidate.isAfter(until)) break;
    if (candidate.isAfter(hardStop)) break;
    if (count != null && emitted >= count) break;

    if (freq == 'DAILY') {
      _within(candidate, exkeys, until, windowStart, windowEnd, out);
      emitted++;
      candidate = candidate.add(Duration(days: interval));
    } else if (freq == 'WEEKLY') {
      final byDays = _parseByDays(master.rrule?['BYDAY'], master.start.weekday);
      final weekStart = DateTime(candidate.year, candidate.month, candidate.day)
          .subtract(Duration(days: candidate.weekday - DateTime.monday));
      for (var d = 0; d < 7 && (count == null || emitted < count); d++) {
        if (until != null && weekStart.add(Duration(days: d)).isAfter(until)) break;
        final day = weekStart.add(Duration(days: d));
        if (!byDays.contains(day.weekday)) continue;
        final occurrence = DateTime(day.year, day.month, day.day, timeOfDay.$1, timeOfDay.$2, timeOfDay.$3);
        if (occurrence.isBefore(master.start)) continue;
        _within(occurrence, exkeys, until, windowStart, windowEnd, out);
        emitted++;
      }
      candidate = weekStart.add(Duration(days: 7 * interval));
    } else if (freq == 'MONTHLY') {
      final preferredDay = int.tryParse(master.rrule?['BYMONTHDAY'] ?? '') ?? master.start.day;
      final lastDay = DateTime(candidate.year, candidate.month + 1, 0).day;
      if (preferredDay <= lastDay) {
        final occurrence = DateTime(candidate.year, candidate.month, preferredDay,
            timeOfDay.$1, timeOfDay.$2, timeOfDay.$3);
        if (!occurrence.isBefore(master.start)) {
          _within(occurrence, exkeys, until, windowStart, windowEnd, out);
        }
        emitted++;
      }
      candidate = _addMonthsPreservingTime(candidate, interval, preferredDay);
    } else if (freq == 'YEARLY') {
      final lastDay = DateTime(candidate.year, candidate.month + 1, 0).day;
      if (master.start.day <= lastDay) {
        final occurrence = DateTime(candidate.year, candidate.month, master.start.day,
            timeOfDay.$1, timeOfDay.$2, timeOfDay.$3);
        if (!occurrence.isBefore(master.start)) {
          _within(occurrence, exkeys, until, windowStart, windowEnd, out);
        }
        emitted++;
      }
      candidate = DateTime(candidate.year + interval, candidate.month, candidate.day,
          timeOfDay.$1, timeOfDay.$2, timeOfDay.$3);
    }

    if (count != null && emitted >= count) break;
    if (out.length > 400) break;
  }

  return out;
}

/// Adds [candidate] to [out] if it is inside the window and not excluded.
/// Returns true when the candidate was emitted (unused for COUNT math —
/// every iterated occurrence counts).
bool _within(
  DateTime candidate,
  Set<String> exkeys,
  DateTime? until,
  DateTime windowStart,
  DateTime windowEnd,
  List<DateTime> out,
) {
  if (until != null && candidate.isAfter(until)) return false;
  if (exkeys.contains(_instantKey(candidate))) return false;
  if (candidate.isBefore(windowStart.subtract(const Duration(days: 1)))) return false;
  if (candidate.isAfter(windowEnd.add(const Duration(days: 1)))) return false;
  out.add(candidate);
  return true;
}

DateTime _addMonthsPreservingTime(DateTime seed, int months, int preferredDay) {
  var year = seed.year;
  var month = seed.month + months;
  while (month > 12) {
    month -= 12;
    year += 1;
  }
  while (month < 1) {
    month += 12;
    year -= 1;
  }
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = preferredDay.clamp(1, lastDay);
  return DateTime(year, month, day, seed.hour, seed.minute, seed.second);
}





Set<int> _parseByDays(String? raw, int fallbackWeekday) {
  if (raw == null || raw.isEmpty) return {fallbackWeekday};
  const codes = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};
  final result = <int>{};
  for (final part in raw.split(',')) {
    // Strip numeric prefixes like "2TU" (every 2nd Tuesday) — unsupported, skip those.
    final cleaned = part.replaceAll(RegExp(r'^[+-]?\d+'), '');
    final weekday = codes[cleaned];
    if (weekday != null) result.add(weekday);
  }
  return result.isEmpty ? {fallbackWeekday} : result;
}

String _instantKey(DateTime t) => t.toUtc().millisecondsSinceEpoch.toString();
