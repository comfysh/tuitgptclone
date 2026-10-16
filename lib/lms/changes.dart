import 'models.dart';
import 'snapshot.dart';

enum ChangeKind { newAssignment, deadlineChanged, gradePosted, examGrade, examChanged, newAbsence, news, reminder }

class LmsChange {
  final ChangeKind kind;
  final String key;
  final String subject;
  final String detail;
  final DateTime? when;
  final double? value;
  final double? max;
  const LmsChange(this.kind, this.key, this.subject, this.detail, {this.when, this.value, this.max});
}

/// What changed between two syncs. Returns nothing on the very first sync so
/// you aren't flooded with notifications for old data.
List<LmsChange> diffSnapshots(LmsSnapshot old, LmsSnapshot now) {
  if (old.isEmpty || old.semesterId != now.semesterId) return const [];
  final out = <LmsChange>[];

  // Only compare courses that were fetched successfully both times.
  final oldA = {for (final a in old.assignments) a.key: a};
  for (final courseId in now.coursePages.keys) {
    if (!old.coursePages.containsKey(courseId)) continue;
    for (final a in now.coursePages[courseId]!.assignments) {
      final before = oldA[a.key];
      if (before == null) {
        out.add(LmsChange(ChangeKind.newAssignment, a.key, a.courseName, a.title, when: a.deadline));
        continue;
      }
      if (a.deadline != null && before.deadline != null && a.deadline != before.deadline) {
        out.add(LmsChange(ChangeKind.deadlineChanged, a.key, a.courseName, a.title, when: a.deadline));
      }
      if (a.isGraded && (before.grade ?? 0) != a.grade) {
        out.add(LmsChange(ChangeKind.gradePosted, a.key, a.courseName, a.title, value: a.grade, max: a.maxGrade));
      }
    }
  }

  if (old.finals.isNotEmpty || now.finals.isEmpty) {
    final oldF = {for (final f in old.finals) f.key: f};
    for (final f in now.finals) {
      final b = oldF[f.key];
      if (b == null) {
        if (old.finals.isNotEmpty) {
          out.add(LmsChange(ChangeKind.examChanged, f.key, f.subject, f.room ?? '', when: f.startsAt));
        }
        continue;
      }
      if (f.grade != null && f.grade != b.grade) {
        out.add(LmsChange(ChangeKind.examGrade, f.key, f.subject, '', value: f.grade?.toDouble(), max: 100));
      }
      if (f.startsAt != b.startsAt || f.room != b.room) {
        out.add(LmsChange(ChangeKind.examChanged, f.key, f.subject, f.room ?? '', when: f.startsAt));
      }
    }
  }

  if (old.absences.isNotEmpty || now.absences.length <= 3) {
    final oldAbs = old.absences.map((a) => a.key).toSet();
    for (final a in now.absences) {
      if (!oldAbs.contains(a.key)) {
        out.add(LmsChange(ChangeKind.newAbsence, a.key, a.subject, a.lessonType ?? '', when: a.date));
      }
    }
  }

  if (old.news.isNotEmpty) {
    final oldN = old.news.map((n) => n.key).toSet();
    for (final n in now.news) {
      if (!oldN.contains(n.key)) out.add(LmsChange(ChangeKind.news, n.key, n.title, n.body ?? '', when: n.date));
    }
  }
  return out;
}

/// Deadline reminders for work you haven't submitted yet: one ~24h before
/// and one ~3h before. [sent] holds keys already notified.
List<LmsChange> dueReminders(LmsSnapshot s, Set<String> sent, DateTime now) {
  final out = <LmsChange>[];
  for (final a in s.assignments) {
    if (a.deadline == null || a.isSubmitted || a.isGraded || a.uploadId == null) continue;
    final left = a.deadline!.difference(now);
    if (left.isNegative) continue;
    final h = left <= const Duration(hours: 3)
        ? 3
        : left <= const Duration(hours: 24)
            ? 24
            : null;
    if (h == null) continue;
    final key = 'rem$h|${a.key}|${a.deadline!.toIso8601String()}';
    if (!sent.contains(key)) {
      out.add(LmsChange(ChangeKind.reminder, key, a.courseName, a.title, when: a.deadline, value: h.toDouble()));
    }
  }
  return out;
}

extension AssignmentSorting on List<Assignment> {
  List<Assignment> sortedByDeadline() {
    final l = [...this];
    l.sort((a, b) {
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1;
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);
    });
    return l;
  }
}
