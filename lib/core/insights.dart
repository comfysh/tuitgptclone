// Derived information the LMS doesn't show directly: grade forecasts,
// missed lessons, the file library and per-subject colours.

import 'package:flutter/material.dart';

import '../lms/models.dart';
import '../lms/parsers.dart';
import '../lms/snapshot.dart';

/// Stable colour per subject (the LMS's own colour classes change between pages).
const subjectPalette = [
  Color(0xFF2F6F9F), // blue ink
  Color(0xFF2C7A6B), // teal ink
  Color(0xFFB0662A), // ochre
  Color(0xFF6E5A9C), // plum
  Color(0xFF9F4C6B), // rose
  Color(0xFF3E7D3A), // leaf green
  Color(0xFF8A7A2C), // olive
  Color(0xFF2E7F94), // petrol
  Color(0xFFB4412F), // brick
  Color(0xFF4B5394), // indigo
];

Color subjectColor(int subjectId) => subjectPalette[subjectId.abs() % subjectPalette.length];

/// Colour of a course by its id (falls back to the name).
Color courseColor(int courseId, LmsSnapshot snap, {String? name}) {
  final c = snap.courseById(courseId);
  if (c != null) return subjectColor(c.subjectId);
  return name == null ? subjectPalette.first : colorForCourseName(name, snap);
}

/// Course for a name shown elsewhere (timetable subject, assignment course name).
Color colorForCourseName(String name, LmsSnapshot snap) {
  final n = name.trim().toLowerCase();
  for (final c in snap.courses) {
    final cs = c.subject.trim().toLowerCase();
    if (cs == n || cs.contains(n) || n.contains(cs)) return subjectColor(c.subjectId);
  }
  return subjectPalette[n.hashCode.abs() % subjectPalette.length];
}

// ---------------------------------------------------------------- grades

/// 5-point grade from a rating percentage (TUIT: 86+ = 5, 71+ = 4, 55+ = 3).
int gradeForPercent(double pct) => pct >= 86
    ? 5
    : pct >= 71
        ? 4
        : pct >= 55
            ? 3
            : 2;

const gradeThresholds = {3: 55.0, 4: 71.0, 5: 86.0};

class GradeTarget {
  final int grade;
  final double pointsNeeded; // more points needed (0 when already reached)
  final bool reachable; // with the tasks still open
  const GradeTarget(this.grade, this.pointsNeeded, this.reachable);
}

class GradeForecast {
  final double achieved; // points so far
  final double maxSoFar; // max points of all tasks published so far
  final double openPoints; // max points of tasks not graded yet
  const GradeForecast(this.achieved, this.maxSoFar, this.openPoints);

  double get percent => maxSoFar == 0 ? 0 : achieved / maxSoFar * 100;

  /// Best case if every open task gets full marks.
  double get bestPercent => maxSoFar == 0 ? 0 : (achieved + openPoints) / maxSoFar * 100;

  List<GradeTarget> get targets => [
        for (final e in gradeThresholds.entries)
          GradeTarget(
            e.key,
            (e.value / 100 * maxSoFar - achieved).clamp(0, double.infinity).toDouble(),
            achieved + openPoints >= e.value / 100 * maxSoFar - 1e-9,
          ),
      ];
}

GradeForecast forecastFor(CoursePage page) {
  var achieved = 0.0, max = 0.0, open = 0.0;
  for (final a in page.assignments) {
    final m = a.maxGrade ?? 0;
    max += m;
    if (a.isGraded) {
      achieved += a.grade!;
    } else if (!a.isOverdue || a.midterm) {
      // Missed tasks can't earn points any more; midterms are graded in class.
      open += m;
    }
  }
  // Prefer the LMS's own totals when it shows them.
  final r = page.rating;
  return GradeForecast(r.achieved ?? achieved, (r.max != null && r.max! > 0) ? r.max! : max, open);
}

/// How the work so far went, without counting tasks that are still open.
///
/// The LMS rating divides by every published task, so early in the semester
/// it reads 10–30 % (and grade 2) only because most tasks aren't due yet.
/// Here only graded tasks and missed ones (deadline passed, no answer) count.
class Standing {
  final double earned;
  final double counted; // max points of the graded + missed tasks
  const Standing(this.earned, this.counted);

  double? get percent => counted > 0 ? (earned / counted * 100).clamp(0, 100).toDouble() : null;

  /// The grade the course is heading for, or null before anything is graded.
  int? get grade {
    final p = percent;
    return p == null ? null : gradeForPercent(p);
  }
}

Standing standingFor(CoursePage? page) {
  var earned = 0.0, counted = 0.0;
  for (final a in page?.assignments ?? const <Assignment>[]) {
    final m = a.maxGrade;
    if (m == null || m <= 0) continue;
    if (a.isGraded) {
      earned += a.grade!;
      counted += m;
    } else if (a.isOverdue && !a.midterm) {
      counted += m;
    }
  }
  return Standing(earned, counted);
}

/// A task still to do: no answer yet, not graded, deadline not passed.
/// The one rule for "open tasks" on every screen and the home-screen widget.
bool isOpenTask(Assignment a) => !a.isSubmitted && !a.isGraded && !a.isOverdue;

// ---------------------------------------------------------------- attendance x lessons

/// Absences of [course] keyed by "type|themeNumber", to mark lessons you missed.
Map<String, Absence> absencesFor(Course course, LmsSnapshot snap) {
  final out = <String, Absence>{};
  for (final a in snap.absences) {
    if (a.subjectId != course.subjectId) continue;
    final t = lessonTypeOfName(a.lessonType);
    if (t == null) continue;
    out['${t.name}|${a.themeNumber}'] = a;
  }
  return out;
}

Absence? absenceForLesson(Lesson l, Map<String, Absence> map) => map['${l.type.name}|${l.number}'];

// ---------------------------------------------------------------- file library

enum FileKind { pdf, slides, doc, sheet, archive, video, image, other }

FileKind fileKind(String nameOrUrl) {
  final path = (Uri.tryParse(nameOrUrl)?.path ?? nameOrUrl).toLowerCase();
  final ext = path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : '';
  return switch (ext) {
    'pdf' => FileKind.pdf,
    'ppt' || 'pptx' || 'key' || 'odp' => FileKind.slides,
    'doc' || 'docx' || 'odt' || 'rtf' || 'txt' => FileKind.doc,
    'xls' || 'xlsx' || 'csv' || 'ods' => FileKind.sheet,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => FileKind.archive,
    'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => FileKind.video,
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => FileKind.image,
    _ => FileKind.other,
  };
}

IconData fileKindIcon(FileKind k) => switch (k) {
      FileKind.pdf => Icons.picture_as_pdf_outlined,
      FileKind.slides => Icons.slideshow_outlined,
      FileKind.doc => Icons.description_outlined,
      FileKind.sheet => Icons.table_chart_outlined,
      FileKind.archive => Icons.folder_zip_outlined,
      FileKind.video => Icons.movie_outlined,
      FileKind.image => Icons.image_outlined,
      FileKind.other => Icons.insert_drive_file_outlined,
    };

Color fileKindColor(FileKind k) => switch (k) {
      FileKind.pdf => const Color(0xFFB4412F),
      FileKind.slides => const Color(0xFFB0662A),
      FileKind.doc => const Color(0xFF2F6F9F),
      FileKind.sheet => const Color(0xFF2E8B57),
      FileKind.archive => const Color(0xFF6E5A9C),
      FileKind.video => const Color(0xFF9F4C6B),
      FileKind.image => const Color(0xFF2E7F94),
      FileKind.other => const Color(0xFF6A665C),
    };

/// A teacher file with where it comes from.
class LibraryFile {
  final LmsFile file;
  final Course course;
  final String context; // lesson theme or task name
  final LessonType? lessonType;
  final int? lessonNumber;
  final DateTime? date;
  final bool fromTask;
  const LibraryFile(this.file, this.course, this.context,
      {this.lessonType, this.lessonNumber, this.date, this.fromTask = false});

  FileKind get kind => fileKind(file.url);
}

/// Every teacher file of the semester: lesson materials and task files.
List<LibraryFile> libraryFiles(LmsSnapshot snap) {
  final out = <LibraryFile>[];
  final seen = <String>{};
  for (final c in snap.courses) {
    for (final l in snap.lessons[c.id] ?? const <Lesson>[]) {
      for (final f in l.files) {
        if (!seen.add(f.url)) continue;
        out.add(LibraryFile(f, c, l.theme ?? '', lessonType: l.type, lessonNumber: l.number, date: l.date));
      }
    }
    for (final a in snap.coursePages[c.id]?.assignments ?? const <Assignment>[]) {
      final f = a.taskFile;
      if (f == null || !seen.add(f.url)) continue;
      out.add(LibraryFile(f, c, a.title, date: a.deadline, fromTask: true));
    }
  }
  return out;
}
