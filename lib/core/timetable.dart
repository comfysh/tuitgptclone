import '../lms/models.dart';
import '../lms/snapshot.dart';
import 'settings.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime mondayOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));
int weeksBetween(DateTime a, DateTime b) =>
    (mondayOf(b).difference(mondayOf(a)).inHours / (24 * 7)).round();

WeekSide _other(WeekSide s) => s == WeekSide.left ? WeekSide.right : WeekSide.left;

/// Which side (left/right, i.e. odd/even week) applies on [day].
/// Uses the user's correction if set, otherwise assumes the week of the
/// earliest lesson in the LMS calendar is the "left" week.
WeekSide weekSideFor(DateTime day, Settings settings, LmsSnapshot snap) {
  final anchor = settings.weekAnchorMonday;
  final anchorSide = settings.weekAnchorSide;
  if (anchor != null && anchorSide != null) {
    return weeksBetween(anchor, day).isEven ? anchorSide : _other(anchorSide);
  }
  // The LMS says which week it is.
  if (snap.weekRefMonday != null && snap.weekRefSide != null) {
    return weeksBetween(snap.weekRefMonday!, day).isEven ? snap.weekRefSide! : _other(snap.weekRefSide!);
  }
  DateTime? first;
  for (final ls in snap.lessons.values) {
    for (final l in ls) {
      if (l.date != null && (first == null || l.date!.isBefore(first))) first = l.date;
    }
  }
  if (first == null) return WeekSide.left;
  return weeksBetween(first, day).isEven ? WeekSide.left : WeekSide.right;
}

class ClassSlot {
  final ScheduleItem item;
  final DateTime start;
  final DateTime end;
  final String? topic;
  final int? courseId;
  const ClassSlot(this.item, this.start, this.end, {this.topic, this.courseId});

  bool isNow(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9ʻʼ]+'), '');

/// Finds the course that a timetable entry belongs to.
Course? courseForItem(ScheduleItem item, List<Course> courses) {
  final subj = _norm(item.subject ?? item.title);
  if (subj.isEmpty) return null;
  final cands = <Course>[];
  for (final c in courses) {
    final cs = _norm(c.subject);
    if (cs.isEmpty) continue;
    if (cs == subj) return c; // exact name wins
    if (cs.contains(subj) || subj.contains(cs)) cands.add(c);
  }
  if (cands.length > 1 && item.stream != null) {
    // e.g. "Web" (cut at a hyphen) matches several courses: the group decides.
    for (final c in cands) {
      if (c.streams.any((s) => s.trim() == item.stream)) return c;
    }
  }
  if (cands.isNotEmpty) {
    return cands.reduce((a, b) =>
        (_norm(a.subject).length - subj.length).abs() <= (_norm(b.subject).length - subj.length).abs() ? a : b);
  }
  if (item.stream != null) {
    for (final c in courses) {
      if (c.streams.any((s) => s.trim() == item.stream)) return c;
    }
  }
  return null;
}

List<ClassSlot> classesOn(DateTime day, Settings settings, LmsSnapshot snap) {
  final side = weekSideFor(day, settings, snap);
  final d = dateOnly(day);
  final slots = <ClassSlot>[];
  for (final it in snap.schedule) {
    if (it.weekday != day.weekday) continue;
    if (it.side != WeekSide.full && it.side != side) continue;
    final start = DateTime(d.year, d.month, d.day, it.start.hour, it.start.minute);
    final course = courseForItem(it, snap.courses);
    String? topic;
    if (course != null) {
      for (final l in snap.lessons[course.id] ?? const <Lesson>[]) {
        if (l.date != null && dateOnly(l.date!) == d && l.type == it.type) {
          topic = l.theme;
          break;
        }
      }
    }
    slots.add(ClassSlot(it, start, start.add(Duration(minutes: settings.lessonMinutes)),
        topic: topic, courseId: course?.id));
  }
  slots.sort((a, b) => a.start.compareTo(b.start));
  return slots;
}

/// The class happening now, or the next one today.
ClassSlot? currentOrNext(List<ClassSlot> today, DateTime now) {
  for (final s in today) {
    if (s.isNow(now) || s.start.isAfter(now)) return s;
  }
  return null;
}

/// Attendance math: each recorded absence ("NB") costs [hoursPerAbsence]
/// academic hours, against a semester limit of [limitHours].
class AttendanceSummary {
  final int absences;
  final int hoursUsed;
  final int limitHours;
  final int hoursPerAbsence;
  final Map<String, int> bySubject;

  AttendanceSummary(this.absences, this.hoursUsed, this.limitHours, this.hoursPerAbsence, this.bySubject);

  int get hoursLeft => (limitHours - hoursUsed).clamp(0, limitHours);
  int get classesLeft => hoursPerAbsence == 0 ? 0 : hoursLeft ~/ hoursPerAbsence;
  double get ratio => limitHours == 0 ? 0 : (hoursUsed / limitHours).clamp(0, 1).toDouble();

  static AttendanceSummary from(LmsSnapshot s, Settings settings) {
    final by = <String, int>{};
    for (final a in s.absences) {
      by[a.subject] = (by[a.subject] ?? 0) + 1;
    }
    var count = s.absences.length;
    if (count == 0) {
      // Fall back to per-course counters when the detailed list is empty.
      for (final c in s.courses) {
        if (c.absenceCount > 0) by[c.subject] = c.absenceCount;
      }
      count = by.values.fold(0, (a, b) => a + b);
    }
    return AttendanceSummary(
        count, count * settings.hoursPerAbsence, settings.absenceLimitHours, settings.hoursPerAbsence, by);
  }
}
