import '../core/format.dart';
import '../core/settings.dart';
import '../core/timetable.dart';
import '../lms/changes.dart';
import '../lms/models.dart';
import '../lms/snapshot.dart';

const _basePrompt = '''
You are TuitMate, a friendly study assistant for a student of Tashkent University of Information Technologies (TUIT, lms.tuit.uz).
- Reply in the language the student writes in (Uzbek, Russian or English).
- Explain clearly and step by step. Use Markdown; use LaTeX (\$...\$) for formulas and fenced code blocks for code.
- When the student shares a lecture or task file, base your answer on that file.
- Use the student's LMS data below when it is relevant (deadlines, timetable, grades, attendance, exams). Don't invent LMS data that isn't listed.
''';

String _type(LessonType t) => switch (t) {
      LessonType.lecture => 'lecture',
      LessonType.practice => 'practice',
      LessonType.laboratory => 'lab',
    };

/// System prompt with an LMS summary so the AI can answer personal questions.
String buildSystemPrompt(LmsSnapshot snap, Settings settings, {bool includeLms = true}) {
  final b = StringBuffer(_basePrompt);
  final now = DateTime.now();
  b.writeln('\nNow: ${fmtWeekday(now, 'en')}, ${fmtDateFull(now, 'en')} ${fmtTime(now)}.');
  if (!includeLms || snap.isEmpty) return b.toString();

  final side = weekSideFor(now, settings, snap);
  b.writeln('\n## Student LMS data (synced ${snap.updatedAt != null ? fmtDateTime(snap.updatedAt!, 'en') : '-'})');
  final i = snap.info;
  if (i != null) {
    b.writeln('Student: ${[
      i.fullName,
      if (i.group != null) 'group ${i.group}',
      if (i.year != null) 'course ${i.year}',
      i.specialization,
    ].whereType<String>().join(', ')}');
  }
  if (snap.semester != null) b.writeln('Semester: ${snap.semester!.name}');
  b.writeln('This week is the ${side == WeekSide.right ? 'even (right)' : 'odd (left)'} week.');

  // Timetable for the next 7 days.
  b.writeln('\n### Timetable (next 7 days)');
  for (var d = 0; d < 7; d++) {
    final day = now.add(Duration(days: d));
    final slots = classesOn(day, settings, snap);
    if (slots.isEmpty) continue;
    b.writeln('${fmtWeekday(day, 'en')} ${fmtDate(day, 'en')}: ${slots.map((s) => '${fmtTime(s.start)}-${fmtTime(s.end)} ${s.item.displaySubject} (${_type(s.item.type)}${s.item.room != null ? ', room ${s.item.room}' : ''})').join('; ')}');
  }

  final open = snap.assignments
      .where((a) => !a.isSubmitted && !a.isGraded && a.deadline != null && a.deadline!.isAfter(now))
      .toList()
      .sortedByDeadline();
  b.writeln('\n### Open assignments (not submitted)');
  if (open.isEmpty) b.writeln('none');
  for (final a in open.take(20)) {
    b.writeln('- ${a.courseName}: ${a.title}${a.taskType != null ? ' [${a.taskType}]' : ''}, due ${fmtDateTime(a.deadline!, 'en')}, max ${fmtNum(a.maxGrade)} pts');
  }
  final overdue = snap.assignments.where((a) => a.isOverdue).toList();
  if (overdue.isNotEmpty) {
    b.writeln('Overdue: ${overdue.take(10).map((a) => '${a.courseName}: ${a.title}').join('; ')}');
  }

  b.writeln('\n### Courses and current rating');
  for (final c in snap.courses) {
    final r = snap.coursePages[c.id]?.rating;
    b.writeln('- ${c.subject}: ${r == null ? 'no data' : '${fmtNum(r.achieved)}/${fmtNum(r.max)} pts${r.ratingPercent != null ? ' (${fmtNum(r.ratingPercent)}%)' : ''}'}'
        '${c.teachers.isNotEmpty ? '; teachers: ${c.teachers.join(', ')}' : ''}; absences: ${c.absenceCount}');
  }

  final graded = snap.assignments.where((a) => a.isGraded).toList()
    ..sort((a, b) => (b.deadline ?? DateTime(0)).compareTo(a.deadline ?? DateTime(0)));
  if (graded.isNotEmpty) {
    b.writeln('\n### Recent grades');
    for (final a in graded.take(10)) {
      b.writeln('- ${a.courseName}: ${a.title} = ${fmtNum(a.grade)}/${fmtNum(a.maxGrade)}');
    }
  }

  final att = AttendanceSummary.from(snap, settings);
  b.writeln('\n### Attendance');
  b.writeln('${att.absences} absences (NB) = ${att.hoursUsed} of ${att.limitHours} allowed academic hours '
      '(1 NB = ${att.hoursPerAbsence} hours); about ${att.classesLeft} more classes can be missed.');
  if (att.bySubject.isNotEmpty) {
    b.writeln('By subject: ${att.bySubject.entries.map((e) => '${e.key}: ${e.value}').join('; ')}');
  }

  if (snap.finals.isNotEmpty) {
    b.writeln('\n### Exams (100-point scale; 86+ excellent, 71+ good, 56+ pass)');
    for (final f in snap.finals) {
      b.writeln('- ${f.subject}: ${f.startsAt != null ? fmtDateTime(f.startsAt!, 'en') : 'date TBA'}'
          '${f.room != null ? ', room ${f.room}' : ''}${f.grade != null ? ', result ${f.grade}' : ''}');
    }
  }
  return b.toString();
}
