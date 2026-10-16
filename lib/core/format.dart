import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../lms/models.dart';
import 'strings.dart';

/// LMS-like blue used on lms.tuit.uz.
const lmsBlue = Color(0xFF2F73C8);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: lmsBlue, brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF4F8FA) : null,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: b == Brightness.light ? lmsBlue : null,
      foregroundColor: b == Brightness.light ? Colors.white : null,
      centerTitle: false,
    ),
    chipTheme: const ChipThemeData(showCheckmark: false),
  );
}

String _locale(String lang) => lang == 'uz' ? 'uz' : (lang == 'ru' ? 'ru' : 'en');

String fmtDate(DateTime d, String lang) => DateFormat('d MMM', _locale(lang)).format(d);
String fmtDateFull(DateTime d, String lang) => DateFormat('d MMM yyyy', _locale(lang)).format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);
String fmtDateTime(DateTime d, String lang) => '${fmtDate(d, lang)}, ${fmtTime(d)}';
String fmtWeekday(DateTime d, String lang) => DateFormat('EEEE', _locale(lang)).format(d);

/// "2d 4h", "3h 10m", "25m".
String fmtDuration(Duration d, String lang) {
  final u = switch (lang) {
    'uz' => ('k', 's', 'daq'),
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
  if (score >= 86) return const Color(0xFF2E9E5B);
  if (score >= 71) return lmsBlue;
  if (score >= 56) return const Color(0xFFE09A1A);
  return const Color(0xFFD64545);
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
      LessonType.lecture => lmsBlue,
      LessonType.practice => const Color(0xFF2E9E5B),
      LessonType.laboratory => const Color(0xFF8E5BD6),
    };

String weekdayShort(int weekday, S s) => s[const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'][weekday - 1]];
