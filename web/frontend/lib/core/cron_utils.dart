/// Cron expression utilities: human-readable descriptions and simple-mode
/// schedule building. Zero external dependencies.

// ---------------------------------------------------------------------------
// Schedule frequency enum for the simple schedule builder
// ---------------------------------------------------------------------------

enum ScheduleFrequency {
  everyNMinutes,
  everyNHours,
  dailyAt,
  weeklyOn,
  monthlyOn,
  inNMinutes, // one-shot (+Nm)
}

const frequencyLabels = {
  ScheduleFrequency.everyNMinutes: 'every N minutes',
  ScheduleFrequency.everyNHours: 'every N hours',
  ScheduleFrequency.dailyAt: 'daily at',
  ScheduleFrequency.weeklyOn: 'weekly on',
  ScheduleFrequency.monthlyOn: 'monthly on day',
  ScheduleFrequency.inNMinutes: 'in N minutes',
};

const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
// Cron uses 0=Sun,1=Mon,...,6=Sat  -- but the standard 5-field also allows
// 7=Sun. We normalise to 1-7 (Mon=1..Sun=7) in the UI and map to cron's
// 1=Mon..7=Sun (or 0).
const _cronDayMap = [1, 2, 3, 4, 5, 6, 0]; // index 0=Mon->cron 1, ... 6=Sun->cron 0

// ---------------------------------------------------------------------------
// Build a cron expression from simple-mode fields
// ---------------------------------------------------------------------------

/// Returns a cron expression string (5 fields) or a one-shot "+Nm" string.
String buildCronExpression({
  required ScheduleFrequency frequency,
  int intervalMinutes = 15,
  int intervalHours = 1,
  int hour = 7,
  int minute = 0,
  List<int> selectedDays = const [], // 0=Mon..6=Sun
  int dayOfMonth = 1,
  int oneShotMinutes = 20,
}) {
  switch (frequency) {
    case ScheduleFrequency.everyNMinutes:
      return '*/$intervalMinutes * * * *';
    case ScheduleFrequency.everyNHours:
      return '0 */$intervalHours * * *';
    case ScheduleFrequency.dailyAt:
      return '$minute $hour * * *';
    case ScheduleFrequency.weeklyOn:
      if (selectedDays.isEmpty) return '$minute $hour * * 1'; // default Mon
      final cronDays = selectedDays.map((d) => _cronDayMap[d]).toList()..sort();
      return '$minute $hour * * ${cronDays.join(',')}';
    case ScheduleFrequency.monthlyOn:
      return '$minute $hour $dayOfMonth * *';
    case ScheduleFrequency.inNMinutes:
      return '+${oneShotMinutes}m';
  }
}

// ---------------------------------------------------------------------------
// Attempt to reverse-parse a cron expression into simple-mode fields.
// Returns null if the expression doesn't map cleanly.
// ---------------------------------------------------------------------------

class SimpleSchedule {
  final ScheduleFrequency frequency;
  final int intervalMinutes;
  final int intervalHours;
  final int hour;
  final int minute;
  final List<int> selectedDays;
  final int dayOfMonth;
  final int oneShotMinutes;

  const SimpleSchedule({
    required this.frequency,
    this.intervalMinutes = 15,
    this.intervalHours = 1,
    this.hour = 7,
    this.minute = 0,
    this.selectedDays = const [],
    this.dayOfMonth = 1,
    this.oneShotMinutes = 20,
  });
}

SimpleSchedule? tryParseSimple(String expr) {
  final s = expr.trim();

  // One-shot: +20m
  final oneShotMatch = RegExp(r'^\+(\d+)m$').firstMatch(s);
  if (oneShotMatch != null) {
    return SimpleSchedule(
      frequency: ScheduleFrequency.inNMinutes,
      oneShotMinutes: int.parse(oneShotMatch.group(1)!),
    );
  }

  final parts = s.split(RegExp(r'\s+'));
  if (parts.length != 5) return null;

  final pMin = parts[0];
  final pHour = parts[1];
  final pDom = parts[2];
  final pMonth = parts[3];
  final pDow = parts[4];

  // every N minutes: */N * * * *
  final everyMin = RegExp(r'^\*/(\d+)$').firstMatch(pMin);
  if (everyMin != null && pHour == '*' && pDom == '*' && pMonth == '*' && pDow == '*') {
    return SimpleSchedule(
      frequency: ScheduleFrequency.everyNMinutes,
      intervalMinutes: int.parse(everyMin.group(1)!),
    );
  }

  // every N hours: 0 */N * * *
  final everyHr = RegExp(r'^\*/(\d+)$').firstMatch(pHour);
  if (pMin == '0' && everyHr != null && pDom == '*' && pMonth == '*' && pDow == '*') {
    return SimpleSchedule(
      frequency: ScheduleFrequency.everyNHours,
      intervalHours: int.parse(everyHr.group(1)!),
    );
  }

  // Parse minute & hour as literals
  final min = int.tryParse(pMin);
  final hr = int.tryParse(pHour);
  if (min == null || hr == null) return null;

  // daily: M H * * *
  if (pDom == '*' && pMonth == '*' && pDow == '*') {
    return SimpleSchedule(frequency: ScheduleFrequency.dailyAt, hour: hr, minute: min);
  }

  // weekly: M H * * D,D,...
  if (pDom == '*' && pMonth == '*' && pDow != '*') {
    final cronDays = pDow.split(',').map((d) => int.tryParse(d)).toList();
    if (cronDays.any((d) => d == null)) return null;
    // Map cron day numbers back to our 0=Mon..6=Sun index
    final uiDays = cronDays.map((d) {
      final cd = d!;
      // cron: 0=Sun,1=Mon..6=Sat
      if (cd == 0 || cd == 7) return 6; // Sun
      return cd - 1; // 1=Mon->0, 2=Tue->1, ...
    }).toList()..sort();
    return SimpleSchedule(frequency: ScheduleFrequency.weeklyOn, hour: hr, minute: min, selectedDays: uiDays);
  }

  // monthly: M H D * *
  final dom = int.tryParse(pDom);
  if (dom != null && pMonth == '*' && pDow == '*') {
    return SimpleSchedule(frequency: ScheduleFrequency.monthlyOn, hour: hr, minute: min, dayOfMonth: dom);
  }

  return null;
}

// ---------------------------------------------------------------------------
// Cron expression -> human-readable description
// ---------------------------------------------------------------------------

String describeCron(String expr) {
  final s = expr.trim();
  if (s.isEmpty) return '';

  // One-shot
  final oneShotMatch = RegExp(r'^\+(\d+)([mhds])$').firstMatch(s);
  if (oneShotMatch != null) {
    final n = oneShotMatch.group(1)!;
    final unit = switch (oneShotMatch.group(2)) {
      'm' => 'minute',
      'h' => 'hour',
      'd' => 'day',
      's' => 'second',
      _ => 'unit',
    };
    final plural = int.parse(n) == 1 ? unit : '${unit}s';
    return 'in $n $plural (one-shot)';
  }

  // ISO timestamp
  if (s.contains('T')) return 'at $s (one-shot)';

  final parts = s.split(RegExp(r'\s+'));
  if (parts.length < 5 || parts.length > 6) return s;

  // Drop optional seconds field (6-part cron)
  final p = parts.length == 6 ? parts.sublist(1) : parts;

  final pMin = p[0];
  final pHour = p[1];
  final pDom = p[2];
  final pMonth = p[3];
  final pDow = p[4];

  try {
    return _describe(pMin, pHour, pDom, pMonth, pDow);
  } catch (_) {
    return s;
  }
}

String _describe(String pMin, String pHour, String pDom, String pMonth, String pDow) {
  final buf = StringBuffer();

  // -- Minute/hour patterns --

  // */N * * * * -> every N minutes
  final everyMin = RegExp(r'^\*/(\d+)$').firstMatch(pMin);
  if (everyMin != null && pHour == '*') {
    final n = int.parse(everyMin.group(1)!);
    buf.write(n == 1 ? 'every minute' : 'every $n minutes');
    _appendDomMonthDow(buf, pDom, pMonth, pDow);
    return buf.toString();
  }

  // * * -> every minute
  if (pMin == '*' && pHour == '*') {
    buf.write('every minute');
    _appendDomMonthDow(buf, pDom, pMonth, pDow);
    return buf.toString();
  }

  // 0 */N -> every N hours
  final everyHr = RegExp(r'^\*/(\d+)$').firstMatch(pHour);
  if (everyHr != null && (pMin == '0' || pMin == '*')) {
    final n = int.parse(everyHr.group(1)!);
    buf.write(n == 1 ? 'every hour' : 'every $n hours');
    _appendDomMonthDow(buf, pDom, pMonth, pDow);
    return buf.toString();
  }

  // M */N -> every N hours at minute M
  if (everyHr != null) {
    final n = int.parse(everyHr.group(1)!);
    buf.write(n == 1 ? 'every hour' : 'every $n hours');
    final m = int.tryParse(pMin);
    if (m != null && m > 0) buf.write(' at minute $m');
    _appendDomMonthDow(buf, pDom, pMonth, pDow);
    return buf.toString();
  }

  // Specific time(s)
  final hours = _parseFieldValues(pHour);
  final minutes = _parseFieldValues(pMin);

  if (hours.isNotEmpty && minutes.isNotEmpty) {
    final times = <String>[];
    for (final h in hours) {
      for (final m in minutes) {
        times.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
      }
    }
    if (times.length == 1) {
      buf.write('at ${times.first}');
    } else if (times.length <= 4) {
      buf.write('at ${times.join(' and ')}');
    } else {
      buf.write('at ${times.first} and ${times.length - 1} more times');
    }
  } else {
    // fallback: show raw
    buf.write('at $pMin $pHour');
  }

  _appendDomMonthDow(buf, pDom, pMonth, pDow);
  return buf.toString();
}

void _appendDomMonthDow(StringBuffer buf, String pDom, String pMonth, String pDow) {
  // Day of month
  if (pDom != '*' && pDom != '?') {
    final doms = _parseFieldValues(pDom);
    if (doms.isNotEmpty) {
      buf.write(', on day ${doms.map(_ordinal).join(', ')} of the month');
    }
  }

  // Month
  if (pMonth != '*' && pMonth != '?') {
    final months = _parseFieldValues(pMonth);
    if (months.isNotEmpty) {
      buf.write(', in ${months.map(_monthName).join(', ')}');
    }
  }

  // Day of week
  if (pDow != '*' && pDow != '?') {
    final dows = _parseFieldValues(pDow);
    if (dows.isNotEmpty) {
      final dowNames = dows.map(_dowName).toList();
      if (dowNames.length == 5 && !dows.contains(0) && !dows.contains(6) && !dows.contains(7)) {
        buf.write(', weekdays');
      } else if (dowNames.length == 2 && (dows.contains(0) || dows.contains(7)) && dows.contains(6)) {
        buf.write(', weekends');
      } else {
        buf.write(', on ${dowNames.join(', ')}');
      }
    }
  }

  // If none were appended and it's daily
  if (pDom == '*' && pMonth == '*' && pDow == '*') {
    buf.write(', every day');
  }
}

/// Parse a single cron field into individual integer values.
/// Handles: literal, comma-separated, ranges (N-M), steps (*/N, N-M/S).
List<int> _parseFieldValues(String field) {
  if (field == '*' || field == '?') return [];
  final results = <int>{};

  for (final part in field.split(',')) {
    final stepMatch = RegExp(r'^(\*|\d+-\d+)/(\d+)$').firstMatch(part);
    if (stepMatch != null) {
      // */N or N-M/S
      final range = stepMatch.group(1)!;
      final step = int.parse(stepMatch.group(2)!);
      int start = 0, end = 59; // default for minute
      if (range != '*') {
        final bounds = range.split('-');
        start = int.parse(bounds[0]);
        end = int.parse(bounds[1]);
      }
      for (var i = start; i <= end; i += step) {
        results.add(i);
      }
      continue;
    }

    final rangeMatch = RegExp(r'^(\d+)-(\d+)$').firstMatch(part);
    if (rangeMatch != null) {
      final a = int.parse(rangeMatch.group(1)!);
      final b = int.parse(rangeMatch.group(2)!);
      for (var i = a; i <= b; i++) {
        results.add(i);
      }
      continue;
    }

    final literal = int.tryParse(part);
    if (literal != null) results.add(literal);
  }

  return results.toList()..sort();
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

String _monthName(int m) {
  const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return (m >= 1 && m <= 12) ? names[m] : '$m';
}

String _dowName(int d) {
  // cron: 0=Sun, 1=Mon, ..., 6=Sat, 7=Sun
  const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return (d >= 0 && d <= 7) ? names[d] : '$d';
}

/// Validate a cron expression. Returns null if valid, or an error string.
String? validateCron(String expr) {
  final s = expr.trim();
  if (s.isEmpty) return 'expression is empty';

  // One-shot
  if (s.startsWith('+') || s.contains('T')) return null;

  final parts = s.split(RegExp(r'\s+'));
  if (parts.length < 5 || parts.length > 6) {
    return 'expected 5 fields (min hour dom month dow), got ${parts.length}';
  }

  final fieldPattern = RegExp(r'^(\*|[0-9,\-/\*\?]+)$');
  for (var i = 0; i < parts.length; i++) {
    if (!fieldPattern.hasMatch(parts[i])) {
      return 'invalid characters in field ${i + 1}: "${parts[i]}"';
    }
  }

  return null;
}
