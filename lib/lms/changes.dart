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

  // Assignments are matched by their stable key. Several rows can share a key
  // (same type, teacher and name); inside such a group the upload id tells
  // them apart, and if that doesn't work we don't guess.
  final oldCount = <String, int>{}, nowCount = <String, int>{};
  for (final a in old.assignments) {
    oldCount[a.key] = (oldCount[a.key] ?? 0) + 1;
  }
  for (final a in now.assignments) {
    nowCount[a.key] = (nowCount[a.key] ?? 0) + 1;
  }
  String withId(Assignment a) => '${a.key}|${a.uploadId}';
  final oldByKey = {for (final a in old.assignments) a.key: a};
  final oldById = {for (final a in old.assignments) if (a.uploadId != null) withId(a): a};
  // Groups where every old row had an upload id: an unseen id there is a new task.
  final oldAllHaveIds = <String, bool>{};
  for (final a in old.assignments) {
    oldAllHaveIds[a.key] = (oldAllHaveIds[a.key] ?? true) && a.uploadId != null;
  }
  // Rows with an upload id that wasn't there before, per group.
  final unseen = <String, int>{};
  for (final a in now.assignments) {
    if (a.uploadId != null && !oldById.containsKey(withId(a))) unseen[a.key] = (unseen[a.key] ?? 0) + 1;
  }
  // Closed rows (no upload id) can still be matched by your uploaded file.
  String withFile(Assignment a) => '${a.key}|${a.uploadedFile?.url}';
  final oldByFile = {for (final o in old.assignments) if (o.uploadedFile != null) withFile(o): o};

  // Only compare courses that were fetched successfully both times.
  for (final courseId in now.coursePages.keys) {
    if (!old.coursePages.containsKey(courseId)) continue;
    for (final a in now.coursePages[courseId]!.assignments) {
      final dup = (oldCount[a.key] ?? 0) > 1 || (nowCount[a.key] ?? 0) > 1;
      final id = dup ? withId(a) : a.key;
      Assignment? before;
      if (!dup) {
        before = oldByKey[a.key];
      } else if (a.uploadId != null && oldById.containsKey(withId(a))) {
        before = oldById[withId(a)];
      } else if (a.uploadedFile != null && oldByFile.containsKey(withFile(a))) {
        before = oldByFile[withFile(a)];
      } else if ((oldCount[a.key] ?? 0) == 0 ||
          (a.uploadId != null &&
              (oldAllHaveIds[a.key] == true ||
                  (unseen[a.key] ?? 0) <= (nowCount[a.key] ?? 0) - (oldCount[a.key] ?? 0)))) {
        before = null; // new task: the whole group, or no more unseen ids than added rows
      } else {
        continue;
      }
      if (before == null) {
        out.add(LmsChange(ChangeKind.newAssignment, id, a.courseName, a.title, when: a.deadline));
        continue;
      }
      if (a.deadline != null && before.deadline != null && a.deadline != before.deadline) {
        out.add(LmsChange(ChangeKind.deadlineChanged, id, a.courseName, a.title, when: a.deadline));
      }
      if (a.isGraded && (before.grade ?? 0) != a.grade) {
        out.add(LmsChange(ChangeKind.gradePosted, id, a.courseName, a.title, value: a.grade, max: a.maxGrade));
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

  // An empty old list from a failed fetch says nothing about what is new.
  final oldAbsUnknown = old.absences.isEmpty && old.errors.containsKey('attendance');
  if (!oldAbsUnknown && (old.absences.isNotEmpty || now.absences.length <= 3)) {
    final oldAbs = old.absences.map((a) => a.key).toSet();
    for (final a in now.absences) {
      if (!oldAbs.contains(a.key)) {
        out.add(LmsChange(ChangeKind.newAbsence, a.key, a.subject, a.lessonType ?? '', when: a.date));
      }
    }
  }

  if (old.news.isNotEmpty) {
    final oldN = old.news.map((n) => n.key).toSet();
    DateTime? oldest;
    for (final n in old.news) {
      if (n.date != null && (oldest == null || n.date!.isBefore(oldest))) oldest = n.date;
    }
    for (final n in now.news) {
      if (oldN.contains(n.key)) continue;
      // Older than everything we had: it was just outside a shorter list.
      if (oldest != null && n.date != null && n.date!.isBefore(oldest)) continue;
      out.add(LmsChange(ChangeKind.news, n.key, n.title, n.body ?? '', when: n.date));
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
    final iso = a.deadline!.toIso8601String();
    final key = 'rem$h|${a.key}|${a.uploadId}|$iso';
    // Format used by version 1.0.0, so reminders already sent aren't repeated.
    final legacy = 'rem$h|${a.courseId}|${a.uploadId}|${a.taskType ?? ''}|${a.name ?? ''}|$iso';
    if (!sent.contains(key) && !sent.contains(legacy)) {
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
