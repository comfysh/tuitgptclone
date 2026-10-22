// Data models for everything the app reads from lms.tuit.uz.
// Every model can round-trip through JSON so the last good copy is cached
// on disk and shown offline.

enum LessonType { lecture, practice, laboratory }

/// Week of a timetable entry ("type" in the LMS schedule JSON):
/// 1 = every week, 2 = odd weeks, 3 = even weeks.
enum WeekSide {
  full(1),
  left(2),
  right(3);

  final int value;
  const WeekSide(this.value);

  static WeekSide fromValue(int? v) =>
      WeekSide.values.firstWhere((e) => e.value == v, orElse: () => WeekSide.full);
}

LessonType lessonTypeFromName(String? s) => LessonType.values
    .firstWhere((e) => e.name == s, orElse: () => LessonType.practice);

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
double? _dbl(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int? _int(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

class StudentInfo {
  final String? fullName;
  final String? studentId;
  final String? birthDate;
  final String? gender;
  final String? address;
  final String? tempAddress;
  final String? specialization;
  final String? studyLanguage;
  final String? degree;
  final String? studyForm;
  final String? year;
  final String? group;
  final String? tutor;
  final String? stipend;
  final String? photo; // data: URI or URL

  const StudentInfo({
    this.fullName,
    this.studentId,
    this.birthDate,
    this.gender,
    this.address,
    this.tempAddress,
    this.specialization,
    this.studyLanguage,
    this.degree,
    this.studyForm,
    this.year,
    this.group,
    this.tutor,
    this.stipend,
    this.photo,
  });

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'studentId': studentId,
        'birthDate': birthDate,
        'gender': gender,
        'address': address,
        'tempAddress': tempAddress,
        'specialization': specialization,
        'studyLanguage': studyLanguage,
        'degree': degree,
        'studyForm': studyForm,
        'year': year,
        'group': group,
        'tutor': tutor,
        'stipend': stipend,
        'photo': photo,
      };

  factory StudentInfo.fromJson(Map<String, dynamic> j) => StudentInfo(
        fullName: j['fullName'],
        studentId: j['studentId'],
        birthDate: j['birthDate'],
        gender: j['gender'],
        address: j['address'],
        tempAddress: j['tempAddress'],
        specialization: j['specialization'],
        studyLanguage: j['studyLanguage'],
        degree: j['degree'],
        studyForm: j['studyForm'],
        year: j['year'],
        group: j['group'],
        tutor: j['tutor'],
        stipend: j['stipend'],
        photo: j['photo'],
      );
}

class Semester {
  final int id;
  final String name;
  final bool selected;
  const Semester(this.id, this.name, {this.selected = false});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'selected': selected};
  factory Semester.fromJson(Map<String, dynamic> j) =>
      Semester(_int(j['id']) ?? 0, j['name'] ?? '', selected: j['selected'] == true);
}

class Course {
  final int id;
  final String subject;
  final int subjectId;
  final int absenceCount;
  final List<String> streams;
  final List<String> teachers;
  final bool failed;

  /// "Written final questions" file, when the teacher published one.
  final String? questionsUrl;

  const Course({
    required this.id,
    required this.subject,
    required this.subjectId,
    this.absenceCount = 0,
    this.streams = const [],
    this.teachers = const [],
    this.failed = false,
    this.questionsUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'subjectId': subjectId,
        'absenceCount': absenceCount,
        'streams': streams,
        'teachers': teachers,
        'failed': failed,
        'questionsUrl': questionsUrl,
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: _int(j['id']) ?? 0,
        subject: j['subject'] ?? '',
        subjectId: _int(j['subjectId']) ?? 0,
        absenceCount: _int(j['absenceCount']) ?? 0,
        streams: List<String>.from(j['streams'] ?? const []),
        teachers: List<String>.from(j['teachers'] ?? const []),
        failed: j['failed'] == true,
        questionsUrl: j['questionsUrl'],
      );
}

class ScheduleItem {
  /// Template start time; only weekday + time of day are meaningful.
  final DateTime start;
  final String title; // raw title from LMS
  final String? subject;
  final String? stream;
  final String? room;
  final WeekSide side;
  final LessonType type;

  /// Colour class the LMS gives each subject (bg-teal, bg-danger, …).
  final String? colorClass;

  const ScheduleItem({
    required this.start,
    required this.title,
    this.subject,
    this.stream,
    this.room,
    this.side = WeekSide.full,
    this.type = LessonType.practice,
    this.colorClass,
  });

  int get weekday => start.weekday;
  String get displaySubject => subject ?? title;

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'title': title,
        'subject': subject,
        'stream': stream,
        'room': room,
        'side': side.value,
        'type': type.name,
        'colorClass': colorClass,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        start: _date(j['start']) ?? DateTime(2000),
        title: j['title'] ?? '',
        subject: j['subject'],
        stream: j['stream'],
        room: j['room'],
        side: WeekSide.fromValue(_int(j['side'])),
        type: lessonTypeFromName(j['type']),
        colorClass: j['colorClass'],
      );
}

class Absence {
  final String subject;
  final int subjectId;
  final DateTime? date;
  final String? lessonType;
  final String? theme;
  final int themeNumber;

  /// Absence with a valid reason (LMS "has_reason").
  final bool excused;

  const Absence({
    required this.subject,
    this.subjectId = 0,
    this.date,
    this.lessonType,
    this.theme,
    this.themeNumber = 0,
    this.excused = false,
  });

  String get key => '$subjectId|${date?.toIso8601String()}|$themeNumber|$lessonType';

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'subjectId': subjectId,
        'date': date?.toIso8601String(),
        'lessonType': lessonType,
        'theme': theme,
        'themeNumber': themeNumber,
        'excused': excused,
      };

  factory Absence.fromJson(Map<String, dynamic> j) => Absence(
        subject: j['subject'] ?? '',
        subjectId: _int(j['subjectId']) ?? 0,
        date: _date(j['date']),
        lessonType: j['lessonType'],
        theme: j['theme'],
        themeNumber: _int(j['themeNumber']) ?? 0,
        excused: j['excused'] == true,
      );
}

class TestPoint {
  final int number;
  final num point;
  const TestPoint(this.number, this.point);
  Map<String, dynamic> toJson() => {'number': number, 'point': point};
  factory TestPoint.fromJson(Map<String, dynamic> j) =>
      TestPoint(_int(j['number']) ?? 0, (j['point'] as num?) ?? 0);
}

class ExamFinal {
  final String subject;
  final int subjectId;
  final int? grade;
  final String? stream;
  final String? room;
  final DateTime? date;
  final String? from;
  final String? to;
  final int? timeLimit;
  final List<TestPoint> testPoints;

  const ExamFinal({
    required this.subject,
    this.subjectId = 0,
    this.grade,
    this.stream,
    this.room,
    this.date,
    this.from,
    this.to,
    this.timeLimit,
    this.testPoints = const [],
  });

  /// Exam start as a full DateTime when both date and time are known.
  DateTime? get startsAt {
    if (date == null) return null;
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(from ?? '');
    if (m == null) return date;
    return DateTime(date!.year, date!.month, date!.day, int.parse(m[1]!), int.parse(m[2]!));
  }

  String get key => '$subjectId|$stream';

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'subjectId': subjectId,
        'grade': grade,
        'stream': stream,
        'room': room,
        'date': date?.toIso8601String(),
        'from': from,
        'to': to,
        'timeLimit': timeLimit,
        'testPoints': testPoints.map((e) => e.toJson()).toList(),
      };

  factory ExamFinal.fromJson(Map<String, dynamic> j) => ExamFinal(
        subject: j['subject'] ?? '',
        subjectId: _int(j['subjectId']) ?? 0,
        grade: _int(j['grade']),
        stream: j['stream'],
        room: j['room'],
        date: _date(j['date']),
        from: j['from'],
        to: j['to'],
        timeLimit: _int(j['timeLimit']),
        testPoints: ((j['testPoints'] as List?) ?? const [])
            .map((e) => TestPoint.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class LmsFile {
  final String name;
  final String url;
  const LmsFile(this.name, this.url);

  bool get looksLikeFile {
    final path = Uri.tryParse(url)?.path ?? url;
    return path.lastIndexOf('/') < path.lastIndexOf('.');
  }

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
  factory LmsFile.fromJson(Map<String, dynamic> j) => LmsFile(j['name'] ?? '', j['url'] ?? '');
}

enum AssignmentStatus { notSubmitted, submitted, graded }

class Assignment {
  final int courseId;
  final String courseName;
  final String? taskType;
  final String? teacher;
  final String? name;
  final LmsFile? taskFile;
  final DateTime? deadline;
  final double? grade;
  final double? maxGrade;
  final int? uploadId;
  final LmsFile? uploadedFile;
  final bool failed;

  /// LMS id of the task (from the criteria button / upload button).
  final int? activityId;

  /// Grading criteria the teacher set: description and points.
  final List<Criterion> criteria;

  /// LMS says the deadline passed without a submission.
  final bool expired;

  /// Midterm/control task: no file upload in LMS.
  final bool midterm;

  const Assignment({
    required this.courseId,
    required this.courseName,
    this.taskType,
    this.teacher,
    this.name,
    this.taskFile,
    this.deadline,
    this.grade,
    this.maxGrade,
    this.uploadId,
    this.uploadedFile,
    this.failed = false,
    this.activityId,
    this.criteria = const [],
    this.expired = false,
    this.midterm = false,
  });

  String get title => (name == null || name!.trim().isEmpty) ? (taskType ?? '—') : name!;

  /// Stable identity used to detect changes between syncs: the LMS task id
  /// when the page shows it, otherwise the task's visible details.
  String get key => activityId != null ? '$courseId|#$activityId' : contentKey;

  /// Identity from visible details (used before task ids were read).
  String get contentKey => '$courseId|${taskType ?? ''}|${teacher ?? ''}|${name ?? ''}|${taskFile?.url ?? ''}';

  /// The LMS shows "—" until a teacher grades; 0 is a real grade.
  bool get isGraded => grade != null;
  bool get isSubmitted => uploadedFile != null;

  AssignmentStatus get status => isGraded
      ? AssignmentStatus.graded
      : isSubmitted
          ? AssignmentStatus.submitted
          : AssignmentStatus.notSubmitted;

  bool get isOverdue =>
      !isSubmitted && !isGraded && (expired || (deadline != null && deadline!.isBefore(DateTime.now())));

  bool get canUpload =>
      uploadId != null && !expired && !midterm && (deadline == null || deadline!.isAfter(DateTime.now()));

  Map<String, dynamic> toJson() => {
        'courseId': courseId,
        'courseName': courseName,
        'taskType': taskType,
        'teacher': teacher,
        'name': name,
        'taskFile': taskFile?.toJson(),
        'deadline': deadline?.toIso8601String(),
        'grade': grade,
        'maxGrade': maxGrade,
        'uploadId': uploadId,
        'uploadedFile': uploadedFile?.toJson(),
        'failed': failed,
        'activityId': activityId,
        'criteria': criteria.map((e) => e.toJson()).toList(),
        'expired': expired,
        'midterm': midterm,
      };

  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
        courseId: _int(j['courseId']) ?? 0,
        courseName: j['courseName'] ?? '',
        taskType: j['taskType'],
        teacher: j['teacher'],
        name: j['name'],
        taskFile: j['taskFile'] == null ? null : LmsFile.fromJson(Map<String, dynamic>.from(j['taskFile'])),
        deadline: _date(j['deadline']),
        grade: _dbl(j['grade']),
        maxGrade: _dbl(j['maxGrade']),
        uploadId: _int(j['uploadId']),
        uploadedFile:
            j['uploadedFile'] == null ? null : LmsFile.fromJson(Map<String, dynamic>.from(j['uploadedFile'])),
        failed: j['failed'] == true,
        activityId: _int(j['activityId']),
        criteria: ((j['criteria'] as List?) ?? const [])
            .map((e) => Criterion.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        expired: j['expired'] == true,
        midterm: j['midterm'] == true,
      );
}

class Criterion {
  final String text;
  final double? points;
  const Criterion(this.text, this.points);
  Map<String, dynamic> toJson() => {'text': text, 'points': points};
  factory Criterion.fromJson(Map<String, dynamic> j) => Criterion(j['text'] ?? '', _dbl(j['points']));
}

class CourseRating {
  final double? achieved;
  final double? max;
  final double? ratingPercent;
  final int? grade;
  const CourseRating({this.achieved, this.max, this.ratingPercent, this.grade});

  Map<String, dynamic> toJson() =>
      {'achieved': achieved, 'max': max, 'ratingPercent': ratingPercent, 'grade': grade};
  factory CourseRating.fromJson(Map<String, dynamic> j) => CourseRating(
        achieved: _dbl(j['achieved']),
        max: _dbl(j['max']),
        ratingPercent: _dbl(j['ratingPercent']),
        grade: _int(j['grade']),
      );
}

class CoursePage {
  final CourseRating rating;
  final List<Assignment> assignments;
  const CoursePage(this.rating, this.assignments);

  Map<String, dynamic> toJson() =>
      {'rating': rating.toJson(), 'assignments': assignments.map((e) => e.toJson()).toList()};
  factory CoursePage.fromJson(Map<String, dynamic> j) => CoursePage(
        CourseRating.fromJson(Map<String, dynamic>.from(j['rating'] ?? const {})),
        ((j['assignments'] as List?) ?? const [])
            .map((e) => Assignment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Lesson {
  final LessonType type;
  final int number;
  final String? theme;
  final DateTime? date;
  final List<LmsFile> files;

  const Lesson({required this.type, this.number = 0, this.theme, this.date, this.files = const []});

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'number': number,
        'theme': theme,
        'date': date?.toIso8601String(),
        'files': files.map((e) => e.toJson()).toList(),
      };

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        type: lessonTypeFromName(j['type']),
        number: _int(j['number']) ?? 0,
        theme: j['theme'],
        date: _date(j['date']),
        files: ((j['files'] as List?) ?? const [])
            .map((e) => LmsFile.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Discipline {
  final String title;
  final String? semester;
  final int? credits;
  final int? grade;
  const Discipline({required this.title, this.semester, this.credits, this.grade});

  Map<String, dynamic> toJson() =>
      {'title': title, 'semester': semester, 'credits': credits, 'grade': grade};
  factory Discipline.fromJson(Map<String, dynamic> j) => Discipline(
        title: j['title'] ?? '',
        semester: j['semester'],
        credits: _int(j['credits']),
        grade: _int(j['grade']),
      );
}

class NewsItem {
  final String title;
  final String? body;
  final DateTime? date;
  final String? url;
  const NewsItem({required this.title, this.body, this.date, this.url});

  String get key => url ?? title;

  Map<String, dynamic> toJson() =>
      {'title': title, 'body': body, 'date': date?.toIso8601String(), 'url': url};
  factory NewsItem.fromJson(Map<String, dynamic> j) =>
      NewsItem(title: j['title'] ?? '', body: j['body'], date: _date(j['date']), url: j['url']);
}

/// One academic year of the tuition contract on /student/info.
class ContractYear {
  final String year; // "2025-2026"
  final bool current; // top card (.si-contract-badge) vs. "Previous academic years"
  final String? status; // .si-acc-sum, e.g. "Fully paid"
  final String? notice; // .si-empty-contract text ("… has not been generated yet.")
  final double? total; // .si-stat.total  "Tuition fee"
  final double? paid; // .si-stat.paid
  final double? debt; // .si-stat.debt
  final double? paidPercent; // .si-progress-pct
  final String? currency; // <small>UZS</small>

  const ContractYear({
    required this.year,
    this.current = false,
    this.status,
    this.notice,
    this.total,
    this.paid,
    this.debt,
    this.paidPercent,
    this.currency,
  });

  bool get hasData => total != null || paid != null || debt != null;

  Map<String, dynamic> toJson() => {
        'year': year,
        'current': current,
        'status': status,
        'notice': notice,
        'total': total,
        'paid': paid,
        'debt': debt,
        'paidPercent': paidPercent,
        'currency': currency,
      };

  factory ContractYear.fromJson(Map<String, dynamic> j) => ContractYear(
        year: j['year'] ?? '',
        current: j['current'] == true,
        status: j['status'],
        notice: j['notice'],
        total: _dbl(j['total']),
        paid: _dbl(j['paid']),
        debt: _dbl(j['debt']),
        paidPercent: _dbl(j['paidPercent']),
        currency: j['currency'],
      );
}

class StudyPlanSummary {
  final double? gpa; // overall, from div.gpa-badge
  final double? currentGpa; // div.gpa-badge.gpa-badge-current (not seen yet)
  final String? currentGpaLabel;
  final String? notice; // div.sp-info
  const StudyPlanSummary({this.gpa, this.currentGpa, this.currentGpaLabel, this.notice});

  Map<String, dynamic> toJson() =>
      {'gpa': gpa, 'currentGpa': currentGpa, 'currentGpaLabel': currentGpaLabel, 'notice': notice};
  factory StudyPlanSummary.fromJson(Map<String, dynamic> j) => StudyPlanSummary(
        gpa: (j['gpa'] as num?)?.toDouble(),
        currentGpa: (j['currentGpa'] as num?)?.toDouble(),
        currentGpaLabel: j['currentGpaLabel'],
        notice: j['notice'],
      );
}

enum SemesterProgress { completed, inProgress, upcoming }

class SemesterStats {
  final String semester;
  final int subjects, graded, failed;
  final int credits, earnedCredits;
  final double? gpa; // estimated with the LMS formula
  const SemesterStats(this.semester, {required this.subjects, required this.graded, required this.failed,
      required this.credits, required this.earnedCredits, this.gpa});
  SemesterProgress get progress => graded == 0
      ? SemesterProgress.upcoming
      : (graded == subjects ? SemesterProgress.completed : SemesterProgress.inProgress);
}

/// LMS GPA (verified against the badge): sum(credits * grade, a 2 counts as 0) / sum(credits of graded rows).
double? estimatedGpa(Iterable<Discipline> ds) {
  var points = 0.0;
  var credits = 0;
  for (final d in ds) {
    final g = d.grade, c = d.credits;
    if (g == null || c == null || c <= 0) continue;
    points += c * (g >= 3 ? g : 0);
    credits += c;
  }
  return credits == 0 ? null : points / credits;
}

List<SemesterStats> studyPlanStats(List<Discipline> plan) {
  final groups = <String, List<Discipline>>{};
  for (final d in plan) {
    groups.putIfAbsent(d.semester ?? '—', () => []).add(d);
  }
  return groups.entries.map((e) {
    final ds = e.value;
    return SemesterStats(
      e.key,
      subjects: ds.length,
      graded: ds.where((d) => d.grade != null).length,
      failed: ds.where((d) => d.grade != null && d.grade! <= 2).length,
      credits: ds.fold(0, (a, d) => a + (d.credits ?? 0)),
      earnedCredits: ds.where((d) => (d.grade ?? 0) >= 3).fold(0, (a, d) => a + (d.credits ?? 0)),
      gpa: estimatedGpa(ds),
    );
  }).toList();
}

/// "VII semester" -> 7 (for sorting); accepts plain digits too.
int? semesterNumber(String? label) {
  final tok = (label ?? '').trim().split(RegExp(r'\s+')).first.toUpperCase();
  final n = int.tryParse(tok);
  if (n != null) return n;
  const v = {'I': 1, 'V': 5, 'X': 10};
  var total = 0;
  for (var i = 0; i < tok.length; i++) {
    final c = v[tok[i]];
    if (c == null) return null;
    final next = i + 1 < tok.length ? (v[tok[i + 1]] ?? 0) : 0;
    total += c < next ? -c : c;
  }
  return total == 0 ? null : total;
}
