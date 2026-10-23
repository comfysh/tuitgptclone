import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../lms/models.dart';
import '../ui/design.dart';
import 'strings.dart';

/// Main brand blue (kept under the old name for existing call sites).
const lmsBlue = Brand.primary;

ThemeData buildTheme(Brightness b) => buildAppTheme(b);

String _locale(String lang) => lang == 'uz' ? 'uz' : (lang == 'ru' ? 'ru' : 'en');

String fmtDate(DateTime d, String lang) => DateFormat('d MMM', _locale(lang)).format(d);
String fmtDateFull(DateTime d, String lang) => DateFormat('d MMM yyyy', _locale(lang)).format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);
String fmtDateTime(DateTime d, String lang) => '${fmtDate(d, lang)}, ${fmtTime(d)}';
String fmtMonthShort(DateTime d, String lang) => DateFormat('MMM', _locale(lang)).format(d);
String fmtWeekday(DateTime d, String lang) => DateFormat('EEEE', _locale(lang)).format(d);

/// "2d 4h", "3h 10m", "25m".
String fmtDuration(Duration d, String lang) {
  final u = switch (lang) {
    'uz' => ('kun', 'soat', 'daq'),
    'ru' => ('д', 'ч', 'мин'),
    _ => ('d', 'h', 'm'),
  };
  String n(int v, String unit) => unit.length > 1 ? '$v $unit' : '$v$unit';
  if (d.inDays >= 1) return '${n(d.inDays, u.$1)} ${n(d.inHours % 24, u.$2)}';
  if (d.inHours >= 1) return '${n(d.inHours, u.$2)} ${n(d.inMinutes % 60, u.$3)}';
  return n(d.inMinutes.clamp(0, 59), u.$3);
}

String fmtAgo(DateTime? t, S s) {
  if (t == null) return s['never'];
  final now = DateTime.now();
  if (now.difference(t).inDays == 0 && now.day == t.day) return fmtTime(t);
  return fmtDateTime(t, s.lang);
}

String fmtNum(double? v) {
  if (v == null) return '—';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// Colour for a score on the 100-point scale (86+ excellent, 71+ good, 56+ pass).
Color scoreColor(num? score, ColorScheme cs) {
  if (score == null) return cs.outline;
  if (score >= 86) return Brand.success;
  if (score >= 71) return Brand.primary;
  if (score >= 55) return Brand.warning;
  return Brand.danger;
}

/// Colour for points earned out of max.
Color ratioColor(double? v, double? max, ColorScheme cs) {
  if (v == null || max == null || max == 0) return cs.outline;
  return scoreColor(v / max * 100, cs);
}

String lessonTypeName(LessonType t, S s) => switch (t) {
      LessonType.lecture => s['lecture'],
      LessonType.practice => s['practice'],
      LessonType.laboratory => s['laboratory'],
    };

IconData lessonTypeIcon(LessonType t) => switch (t) {
      LessonType.lecture => Icons.co_present_outlined,
      LessonType.practice => Icons.edit_note,
      LessonType.laboratory => Icons.science_outlined,
    };

Color lessonTypeColor(LessonType t) => switch (t) {
      LessonType.lecture => Brand.primary,
      LessonType.practice => const Color(0xFF14B8A6),
      LessonType.laboratory => const Color(0xFF8B5CF6),
    };

String weekdayShort(int weekday, S s) => s[const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'][weekday - 1]];

/// "17 866 395" (space-grouped, no decimals).
String fmtMoney(double v) => NumberFormat('#,##0', 'en').format(v).replaceAll(',', ' ');
