// Data models for everything the app reads from lms.tuit.uz.
// Every model can round-trip through JSON so the last good copy is cached
// on disk and shown offline.

enum LessonType { lecture, practice, laboratory }

/// Odd/even week side used by the LMS timetable ("type" in schedule JSON).
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

  const Course({
    required this.id,
    required this.subject,
    required this.subjectId,
    this.absenceCount = 0,
    this.streams = const [],
    this.teachers = const [],
    this.failed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'subjectId': subjectId,
        'absenceCount': absenceCount,
        'streams': streams,
        'teachers': teachers,
        'failed': failed,
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: _int(j['id']) ?? 0,
        subject: j['subject'] ?? '',
        subjectId: _int(j['subjectId']) ?? 0,
        absenceCount: _int(j['absenceCount']) ?? 0,
        streams: List<String>.from(j['streams'] ?? const []),
        teachers: List<String>.from(j['teachers'] ?? const []),
        failed: j['failed'] == true,
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

  const ScheduleItem({
    required this.start,
    required this.title,
    this.subject,
    this.stream,
    this.room,
    this.side = WeekSide.full,
    this.type = LessonType.practice,
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
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        start: _date(j['start']) ?? DateTime(2000),
        title: j['title'] ?? '',
        subject: j['subject'],
        stream: j['stream'],
        room: j['room'],
        side: WeekSide.fromValue(_int(j['side'])),
        type: lessonTypeFromName(j['type']),
      );
}

class Absence {
  final String subject;
  final int subjectId;
  final DateTime? date;
  final String? lessonType;
  final String? theme;
  final int themeNumber;

  const Absence({
    required this.subject,
    this.subjectId = 0,
    this.date,
    this.lessonType,
    this.theme,
    this.themeNumber = 0,
  });

  String get key => '$subjectId|${date?.toIso8601String()}|$themeNumber|$lessonType';

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'subjectId': subjectId,
        'date': date?.toIso8601String(),
        'lessonType': lessonType,
        'theme': theme,
        'themeNumber': themeNumber,
      };

  factory Absence.fromJson(Map<String, dynamic> j) => Absence(
        subject: j['subject'] ?? '',
        subjectId: _int(j['subjectId']) ?? 0,
        date: _date(j['date']),
        lessonType: j['lessonType'],
        theme: j['theme'],
        themeNumber: _int(j['themeNumber']) ?? 0,
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
  });

  String get title => (name == null || name!.trim().isEmpty) ? (taskType ?? '—') : name!;

  /// Stable identity used to detect changes between syncs.
  String get key => '$courseId|${uploadId ?? ''}|${taskType ?? ''}|${name ?? ''}';

  bool get isGraded => grade != null && grade! > 0;
  bool get isSubmitted => uploadedFile != null;

  AssignmentStatus get status => isGraded
      ? AssignmentStatus.graded
      : isSubmitted
          ? AssignmentStatus.submitted
          : AssignmentStatus.notSubmitted;

  bool get isOverdue =>
      deadline != null && deadline!.isBefore(DateTime.now()) && !isSubmitted && !isGraded;

  bool get canUpload =>
      uploadId != null && (deadline == null || deadline!.isAfter(DateTime.now()));

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
      );
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
