import 'dart:async';

import 'lms_client.dart';
import 'models.dart';

/// Everything we know from the LMS at one point in time.
class LmsSnapshot {
  StudentInfo? info;
  List<Semester> semesters;
  int? semesterId;
  List<Course> courses;
  List<ScheduleItem> schedule;
  List<Absence> absences;
  List<ExamFinal> finals;
  Map<int, CoursePage> coursePages;
  Map<int, List<Lesson>> lessons;
  List<Discipline> studyPlan;
  List<NewsItem> news;
  DateTime? updatedAt;

  /// Last sync that also loaded teacher files, profile and study plan (a
  /// "light" check skips those; see [needsFullSync]).
  DateTime? fullAt;
  Map<String, String> errors;

  /// Monday of a week whose odd/even side the LMS told us, and that side.
  DateTime? weekRefMonday;
  WeekSide? weekRefSide;

  /// Tuition contract by academic year (current first).
  List<ContractYear> contracts;

  /// GPA badge and notice from the study plan page.
  StudyPlanSummary? planSummary;

  LmsSnapshot({
    this.info,
    this.semesters = const [],
    this.semesterId,
    this.courses = const [],
    this.schedule = const [],
    this.absences = const [],
    this.finals = const [],
    this.coursePages = const {},
    this.lessons = const {},
    this.studyPlan = const [],
    this.news = const [],
    this.updatedAt,
    this.fullAt,
    this.errors = const {},
    this.weekRefMonday,
    this.weekRefSide,
    this.contracts = const [],
    this.planSummary,
  });

  bool get isEmpty => updatedAt == null;

  Semester? get semester {
    for (final s in semesters) {
      if (s.id == semesterId) return s;
    }
    return null;
  }

  List<Assignment> get assignments => [for (final p in coursePages.values) ...p.assignments];

  Course? courseById(int id) {
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'info': info?.toJson(),
        'semesters': semesters.map((e) => e.toJson()).toList(),
        'semesterId': semesterId,
        'courses': courses.map((e) => e.toJson()).toList(),
        'schedule': schedule.map((e) => e.toJson()).toList(),
        'absences': absences.map((e) => e.toJson()).toList(),
        'finals': finals.map((e) => e.toJson()).toList(),
        'coursePages': coursePages.map((k, v) => MapEntry('$k', v.toJson())),
        'lessons': lessons.map((k, v) => MapEntry('$k', v.map((e) => e.toJson()).toList())),
        'studyPlan': studyPlan.map((e) => e.toJson()).toList(),
        'news': news.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt?.toIso8601String(),
        'fullAt': fullAt?.toIso8601String(),
        'errors': errors,
        'weekRefMonday': weekRefMonday?.toIso8601String(),
        'weekRefSide': weekRefSide?.value,
        'contracts': contracts.map((e) => e.toJson()).toList(),
        'planSummary': planSummary?.toJson(),
      };

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      ((v as List?) ?? const []).map((e) => f(Map<String, dynamic>.from(e))).toList();

  factory LmsSnapshot.fromJson(Map<String, dynamic> j) => LmsSnapshot(
        info: j['info'] == null ? null : StudentInfo.fromJson(Map<String, dynamic>.from(j['info'])),
        semesters: _list(j['semesters'], Semester.fromJson),
        semesterId: j['semesterId'],
        courses: _list(j['courses'], Course.fromJson),
        schedule: _list(j['schedule'], ScheduleItem.fromJson),
        absences: _list(j['absences'], Absence.fromJson),
        finals: _list(j['finals'], ExamFinal.fromJson),
        coursePages: ((j['coursePages'] as Map?) ?? const {}).map(
            (k, v) => MapEntry(int.parse('$k'), CoursePage.fromJson(Map<String, dynamic>.from(v)))),
        lessons: ((j['lessons'] as Map?) ?? const {})
            .map((k, v) => MapEntry(int.parse('$k'), _list(v, Lesson.fromJson))),
        studyPlan: _list(j['studyPlan'], Discipline.fromJson),
        news: _list(j['news'], NewsItem.fromJson),
        updatedAt: j['updatedAt'] == null ? null : DateTime.tryParse(j['updatedAt']),
        fullAt: j['fullAt'] == null ? null : DateTime.tryParse(j['fullAt']),
        errors: Map<String, String>.from(j['errors'] ?? const {}),
        weekRefMonday: j['weekRefMonday'] == null ? null : DateTime.tryParse(j['weekRefMonday']),
        weekRefSide: j['weekRefSide'] == null ? null : WeekSide.fromValue(j['weekRefSide']),
        contracts: _list(j['contracts'], ContractYear.fromJson),
        planSummary:
            j['planSummary'] == null ? null : StudyPlanSummary.fromJson(Map<String, dynamic>.from(j['planSummary'])),
      );
}

/// Runs [tasks] with at most [limit] in flight.
Future<void> _pool(List<Future<void> Function()> tasks, int limit) async {
  var i = 0;
  Future<void> worker() async {
    while (i < tasks.length) {
      final t = tasks[i++];
      await t();
    }
  }

  await Future.wait(List.generate(limit, (_) => worker()));
}

/// Downloads a fresh snapshot. Sections that fail keep their previous value
/// and record an error; an expired session aborts the whole sync.
Future<LmsSnapshot> fetchSnapshot(
  LmsClient c, {
  LmsSnapshot? previous,
  int? semesterId,
  bool full = true,
}) async {
  final prev = previous ?? LmsSnapshot();
  final errors = <String, String>{};

  Future<T> section<T>(String name, Future<T> Function() f, T fallback) async {
    try {
      return await f();
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      errors[name] = e.toString();
      return fallback;
    }
  }

  final semesters = await section('semesters', c.semesters, prev.semesters);
  int? semId = semesterId;
  if (semId == null || !semesters.any((s) => s.id == semId)) {
    semId = semesters.where((s) => s.selected).map((s) => s.id).firstOrNull ??
        semesters.map((s) => s.id).firstOrNull ??
        prev.semesterId;
  }
  if (semId == null) {
    throw LmsException(errors['semesters'] ?? 'Could not find your current semester on the LMS.');
  }
  final sid = semId;
  // Semester data only falls back to the previous copy of the same semester.
  final base = prev.semesterId == sid ? prev : LmsSnapshot();

  final results = await Future.wait<dynamic>([
    full || prev.info == null
        ? section<(StudentInfo, List<ContractYear>)?>('info', c.info, prev.info == null ? null : (prev.info!, prev.contracts))
        : Future.value(prev.info == null ? null : (prev.info!, prev.contracts)),
    section('courses', () => c.courses(sid), base.courses),
    section<(List<ScheduleItem>, (DateTime, WeekSide)?)>(
        'schedule',
        () => c.schedule(sid),
        (base.schedule, base.weekRefMonday == null ? null : (base.weekRefMonday!, base.weekRefSide!))),
    section('attendance', () => c.absences(sid), base.absences),
    section('exams', () => c.finals(sid), base.finals),
    full
        ? section<(List<Discipline>, StudyPlanSummary?)>(
            'studyPlan', () async => await c.studyPlan(), (prev.studyPlan, prev.planSummary))
        : Future.value((prev.studyPlan, prev.planSummary)),
    section('news', () async {
      final fresh = await c.news(limit: full ? 9 : 3, known: {for (final n in prev.news) n.key: n});
      final seen = {for (final n in fresh) n.key};
      // Keep older items so a light sync never shrinks the list (that would
      // make the next full sync announce old posts as new).
      return [...fresh, ...prev.news.where((n) => !seen.contains(n.key))].take(12).toList();
    }, prev.news),
  ]);

  final courses = results[1] as List<Course>;
  final pages = <int, CoursePage>{};
  final lessons = <int, List<Lesson>>{};

  final tasks = <Future<void> Function()>[];
  for (final course in courses) {
    tasks.add(() async {
      final p = await section('course:${course.id}', () => c.coursePage(course), base.coursePages[course.id]);
      if (p != null) pages[course.id] = p;
    });
    if (full) {
      tasks.add(() async {
        final l = await section('lessons:${course.id}', () => c.lessons(course.id), base.lessons[course.id]);
        if (l != null) lessons[course.id] = l;
      });
    } else if (base.lessons[course.id] != null) {
      lessons[course.id] = base.lessons[course.id]!;
    }
  }
  await _pool(tasks, 4);

  final infoRes = results[0] as (StudentInfo, List<ContractYear>)?;
  final planRes = results[5] as (List<Discipline>, StudyPlanSummary?);
  return LmsSnapshot(
    info: infoRes?.$1,
    contracts: infoRes?.$2 ?? prev.contracts,
    planSummary: planRes.$2,
    semesters: semesters,
    semesterId: sid,
    courses: courses,
    schedule: (results[2] as (List<ScheduleItem>, (DateTime, WeekSide)?)).$1,
    weekRefMonday: (results[2] as (List<ScheduleItem>, (DateTime, WeekSide)?)).$2?.$1,
    weekRefSide: (results[2] as (List<ScheduleItem>, (DateTime, WeekSide)?)).$2?.$2,
    absences: results[3] as List<Absence>,
    finals: results[4] as List<ExamFinal>,
    coursePages: pages,
    lessons: lessons,
    studyPlan: planRes.$1,
    news: results[6] as List<NewsItem>,
    updatedAt: DateTime.now(),
    fullAt: full ? DateTime.now() : (prev.semesterId == sid ? prev.fullAt : null),
    errors: errors,
  );
}

/// How old the teacher files, profile and study plan may get before a light
/// check loads everything again.
const fullSyncEvery = Duration(minutes: 60);

/// Whether the next sync should load everything (also teacher files, profile
/// and study plan), not just the parts that change during the day.
bool needsFullSync(LmsSnapshot s, DateTime now) {
  final at = s.fullAt;
  return at == null || now.difference(at) >= fullSyncEvery || now.isBefore(at);
}
