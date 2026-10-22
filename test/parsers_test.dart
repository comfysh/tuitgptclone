import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/ai/file_text.dart';
import 'package:tuitmate/core/timetable.dart';
import 'package:tuitmate/lms/lms_client.dart';
import 'package:tuitmate/ui/files.dart';
import 'package:tuitmate/lms/changes.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/parsers.dart';
import 'package:tuitmate/lms/snapshot.dart';

void main() {
  test('parseLmsDate handles LMS formats', () {
    expect(parseLmsDate('05-10-2026'), DateTime(2026, 10, 5));
    expect(parseLmsDate('05-10-2026 23:59:00'), DateTime(2026, 10, 5, 23, 59));
    expect(parseLmsDate('12-09-2026 (Shanba)'), DateTime(2026, 9, 12));
    expect(parseLmsDate('2026-09-01'), DateTime(2026, 9, 1));
    expect(parseLmsDate('—'), isNull);
  });

  test('semesters from my-courses page', () {
    final d = parseHtml('''
<select class="js-semester"><option value="12" selected> 2026-2027  Kuzgi </option><option value="11">2025-2026 Bahorgi</option></select>''');
    final s = parseSemesters(d);
    expect(s.map((e) => e.id), [12, 11]);
    expect(s.first.name, '2026-2027 Kuzgi');
    expect(s.first.selected, isTrue);
  });

  test('courses, absences, finals JSON', () {
    final courses = parseCourses({
      'data': [
        {'id': 501, 'subject': 'Data structures &#039;A&#039;', 'subject_id': 9, 'attendance': 3, 'streams': 'DS-201###DS-201-a1', 'teachers': 'Aliyev A.###Karimova B.###Aliyev A.', 'falied': false}
      ]
    });
    expect(courses.single.subject, "Data structures 'A'");
    // Listed once per class type on the LMS; shown once.
    expect(courses.single.teachers, ['Aliyev A.', 'Karimova B.']);
    expect(courses.single.absenceCount, 3);

    final abs = parseAbsences(jsonEncode({
      'data': [
        {'subject': 'Physics', 'subject_id': 3, 'date': '01-10-2026', 'type': 'Amaliy', 'calendar': 'Kinematics', 'theme_number': 4}
      ]
    }));
    expect(abs.single.date, DateTime(2026, 10, 1));
    expect(abs.single.themeNumber, 4);

    final f = parseFinals({
      'data': [
        {'subject': 'Math', 'subject_id': 1, 'f_grade': '87', 'stream': 'M-1', 'room': 'A-305', 'date': '20-12-2026', 'from': '09:00', 'to': '10:20', 'final_limit': 80, 'final_info': '[{"number":1,"point":40},{"number":2,"point":47}]'}
      ]
    });
    expect(f.single.grade, 87);
    expect(f.single.startsAt, DateTime(2026, 12, 20, 9, 0));
    expect(f.single.testPoints.length, 2);
  });

  test('schedule JSON', () {
    final items = parseSchedule({
      'json': [
        {'title': '(A-305) Algorithms - ALG301', 'start': '2026-09-07T08:30:00', 'type': 2},
        {'title': '(B-210) Physics - FIZ12-a1', 'start': '2026-09-08T10:00:00', 'type': 1},
      ]
    });
    expect(items.length, 2);
    expect(items[0].subject, 'Algorithms');
    expect(items[0].side, WeekSide.left);
    expect(items[0].type, LessonType.lecture);
    expect(items[0].weekday, DateTime.monday);
    expect(items[1].type, LessonType.laboratory);
  });

  test('course page with assignments', () {
    final course = const Course(id: 77, subject: 'Databases', subjectId: 5);
    final d = parseHtml('''
<html><head><meta name="csrf-token" content="tok123"></head><body>
<div class="page-inner"><div class="panel">
<table><tbody><tr><td><h4>34.5</h4></td><td><h4>60</h4></td><td><h4>57.5%</h4></td><td><h4>3</h4></td></tr></tbody></table>
<table id="simple-table1"><tbody>
<tr><td>Laboratoriya</td><td>Aliyev A.</td><td><div><p>Lab 1: ER diagram</p><a href="/storage/tasks/lab1.pdf">lab1.pdf</a></div></td><td>10-10-2026 23:59:00</td>
<td class="text-center"><div><button>8</button><button>10</button></div></td><td><a href="/storage/answers/me.docx">me.docx</a><div><button class="js-btn-upload" data-id="9001">Upload</button></div></td></tr>
<tr><td>Amaliy</td><td>Aliyev A.</td><td><div><p>Practice 2</p><a href="#"> </a></div></td><td>30-12-2026 23:59:00</td>
<td class="text-center"><div><button>0</button><button>5</button></div></td><td><a href="#" data-id="9002">Upload</a></td></tr>
<tr class="criteria-row"><td colspan="6">criteria</td></tr>
</tbody></table></div></div></body></html>''');
    expect(csrfToken(d), 'tok123');
    final page = parseCoursePage(d, course)!;
    expect(page.rating.achieved, 34.5);
    expect(page.rating.ratingPercent, 57.5);
    expect(page.rating.grade, 3);
    expect(page.assignments.length, 2);
    final a = page.assignments[0];
    expect(a.title, 'Lab 1: ER diagram');
    expect(a.taskFile!.url, 'https://lms.tuit.uz/storage/tasks/lab1.pdf');
    expect(a.uploadedFile!.name, 'me.docx');
    expect(a.uploadId, 9001);
    expect(a.grade, 8);
    expect(a.status, AssignmentStatus.graded);
    final b = page.assignments[1];
    expect(b.uploadId, 9002);
    expect(b.taskFile, isNull);
    expect(b.status, AssignmentStatus.notSubmitted);
    expect(b.deadline, DateTime(2026, 12, 30, 23, 59));
  });

  test('lessons with files', () {
    final d = parseHtml('''
<div id="lecture"><table><tbody>
<tr><td>1</td><td><p>Introduction</p></td><td>02-09-2026 (Chorshanba)</td><td><a href="/files/l1.pptx">Slides</a></td></tr>
</tbody></table></div>
<div id="lab"><table><tbody><tr><td>1</td><td><p>Setup</p></td><td>04-09-2026</td><td></td></tr></tbody></table></div>''');
    final l = parseLessons(d);
    expect(l.length, 2);
    expect(l.first.type, LessonType.lecture);
    expect(l.first.date, DateTime(2026, 9, 2));
    expect(l.first.files.single.url, 'https://lms.tuit.uz/files/l1.pptx');
    expect(l.last.type, LessonType.laboratory);
  });

  test('login page detection', () {
    expect(isLoginPage('<input type="hidden" name="g-recaptcha-response">'), isTrue);
    expect(isLoginPage('<div>Dashboard</div>'), isFalse);
  });

  test('diff detects new assignment and grade', () {
    final c = const Course(id: 1, subject: 'Math', subjectId: 1);
    Assignment a(String name, {double? grade}) =>
        Assignment(courseId: 1, courseName: 'Math', name: name, uploadId: name.hashCode, grade: grade, maxGrade: 10);
    final old = LmsSnapshot(
      semesterId: 1,
      courses: [c],
      coursePages: {1: CoursePage(const CourseRating(), [a('HW1')])},
      updatedAt: DateTime(2026),
    );
    final now = LmsSnapshot(
      semesterId: 1,
      courses: [c],
      coursePages: {1: CoursePage(const CourseRating(), [a('HW1', grade: 9), a('HW2')])},
      updatedAt: DateTime(2026),
    );
    final changes = diffSnapshots(old, now);
    expect(changes.map((e) => e.kind), containsAll([ChangeKind.gradePosted, ChangeKind.newAssignment]));
    expect(diffSnapshots(LmsSnapshot(), now), isEmpty);
  });

  test('snapshot JSON round trip', () {
    final s = LmsSnapshot(
      semesterId: 3,
      semesters: [const Semester(3, 'Fall')],
      schedule: [ScheduleItem(start: DateTime(2026, 9, 7, 8, 30), title: 't', side: WeekSide.right)],
      updatedAt: DateTime(2026, 10, 1),
    );
    final back = LmsSnapshot.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.semesterId, 3);
    expect(back.schedule.single.side, WeekSide.right);
  });

  test('docx text extraction', () {
    final xml = '<w:document><w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p><w:p><w:r><w:t xml:space="preserve">World &amp; you</w:t></w:r></w:p></w:body></w:document>';
    final arc = Archive()..addFile(ArchiveFile.string('word/document.xml', xml));
    final bytes = Uint8List.fromList(ZipEncoder().encode(arc));
    expect(extractText('a.docx', 'application/octet-stream', bytes), 'Hello\nWorld & you');
  });

  test('WebView cookie expiry: seconds (Windows) and milliseconds (Android)', () {
    final secs = makeCookie('tuitlms_session', 'abc', expires: 1893456000); // 2030-01-01
    final ms = makeCookie('tuitlms_session', 'abc', expires: 1893456000000);
    expect(secs.expires!.toUtc().year, 2030);
    expect(secs.expires, ms.expires);
    expect(makeCookie('x', 'y', expires: -1).expires, isNull); // session cookie
  });

  test('file names from URLs and Content-Disposition', () {
    expect(LmsClient.fileNameFromUrl('https://lms.tuit.uz/storage/Lab%20100%25.docx'), 'Lab 100%.docx');
    expect(LmsClient.fileNameFromUrl('https://lms.tuit.uz/storage/Ma%27ruza%201.pptx'), "Ma'ruza 1.pptx");
    expect(fileNameFromDisposition('attachment; filename="Lab 1.docx"'), 'Lab 1.docx');
    expect(fileNameFromDisposition("attachment; filename*=UTF-8''%D0%9B%D0%B5%D0%BA.pdf"), 'Лек.pdf');
    expect(fileNameFromDisposition('Lab 1.docx'), isNull);
  });

  test('assignment identity ignores upload state; duplicates are not guessed', () {
    Assignment a(String name, {int? up, double? grade}) =>
        Assignment(courseId: 1, courseName: 'Math', taskType: 'Amaliy', name: name, uploadId: up, grade: grade, maxGrade: 10);
    expect(a('HW1', up: 5).key, a('HW1').key);
    final c = const Course(id: 1, subject: 'Math', subjectId: 1);
    final old = LmsSnapshot(semesterId: 1, courses: [c], coursePages: {1: CoursePage(const CourseRating(), [a('HW1', up: 5), a('Dup'), a('Dup')])}, updatedAt: DateTime(2026));
    final now = LmsSnapshot(semesterId: 1, courses: [c], coursePages: {1: CoursePage(const CourseRating(), [a('HW1'), a('Dup', grade: 7), a('Dup')])}, updatedAt: DateTime(2026));
    expect(diffSnapshots(old, now), isEmpty);
  });

  test('timetable entry links to the exactly matching course', () {
    const courses = [
      Course(id: 1, subject: 'Kvant fizikasi', subjectId: 1),
      Course(id: 2, subject: 'Fizika', subjectId: 2),
    ];
    final item = ScheduleItem(start: DateTime(2026, 9, 7, 8, 30), title: 't', subject: 'Fizika');
    expect(courseForItem(item, courses)!.id, 2);
  });

  test('xlsx extraction keeps numbers and rows', () {
    const sharedXml = '<sst><si><t>Name</t></si><si><t>Score</t></si><si><t>Vali</t></si></sst>';
    const sheetXml = '<worksheet><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>87</v></c></row>'
        '</sheetData></worksheet>';
    final arc = Archive()
      ..addFile(ArchiveFile.string('xl/sharedStrings.xml', sharedXml))
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheetXml));
    final text = extractText('grades.xlsx', 'application/octet-stream', Uint8List.fromList(ZipEncoder().encode(arc)))!;
    expect(text, contains('Name\tScore'));
    expect(text, contains('Vali\t87'));
  });

  test('same-named tasks are told apart by upload id', () {
    Assignment a(int up, {double? grade}) =>
        Assignment(courseId: 1, courseName: 'Math', taskType: 'Amaliy', name: 'Amaliy ish', uploadId: up, grade: grade, maxGrade: 5);
    final c = const Course(id: 1, subject: 'Math', subjectId: 1);
    LmsSnapshot snap(List<Assignment> l) =>
        LmsSnapshot(semesterId: 1, courses: [c], coursePages: {1: CoursePage(const CourseRating(), l)}, updatedAt: DateTime(2026));
    final changes = diffSnapshots(snap([a(1), a(2)]), snap([a(1), a(2, grade: 4), a(3)]));
    expect(changes.where((e) => e.kind == ChangeKind.gradePosted).length, 1);
    expect(changes.where((e) => e.kind == ChangeKind.newAssignment).length, 1);
  });

  test('no absence alerts when the previous attendance fetch failed', () {
    final old = LmsSnapshot(semesterId: 1, updatedAt: DateTime(2026), errors: {'attendance': 'timeout'});
    final now = LmsSnapshot(semesterId: 1, updatedAt: DateTime(2026), absences: [Absence(subject: 'Fizika', date: DateTime(2026, 10, 1))]);
    expect(diffSnapshots(old, now).where((e) => e.kind == ChangeKind.newAbsence), isEmpty);
  });

  test('same-named group with a closed row still announces a new task', () {
    Assignment a(int? up) =>
        Assignment(courseId: 1, courseName: 'Math', taskType: 'Amaliy', name: 'Amaliy ish', uploadId: up, maxGrade: 5);
    final c = const Course(id: 1, subject: 'Math', subjectId: 1);
    LmsSnapshot snap(List<Assignment> l) =>
        LmsSnapshot(semesterId: 1, courses: [c], coursePages: {1: CoursePage(const CourseRating(), l)}, updatedAt: DateTime(2026));
    final changes = diffSnapshots(snap([a(null), a(9002)]), snap([a(null), a(9002), a(9003)]));
    expect(changes.where((e) => e.kind == ChangeKind.newAssignment).length, 1);
  });

  test('older news that was just outside a shorter list is not announced', () {
    final old = LmsSnapshot(semesterId: 1, updatedAt: DateTime(2026), news: [NewsItem(title: 'B', date: DateTime(2026, 10, 10), url: 'b')]);
    final now = LmsSnapshot(semesterId: 1, updatedAt: DateTime(2026), news: [
      NewsItem(title: 'C', date: DateTime(2026, 10, 12), url: 'c'),
      NewsItem(title: 'B', date: DateTime(2026, 10, 10), url: 'b'),
      NewsItem(title: 'A', date: DateTime(2026, 9, 1), url: 'a'),
    ]);
    expect(diffSnapshots(old, now).where((e) => e.kind == ChangeKind.news).map((e) => e.subject), ['C']);
  });
}
