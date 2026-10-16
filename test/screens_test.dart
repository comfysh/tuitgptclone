// Renders every screen with sample LMS data at phone and PC sizes.
// Catches layout exceptions; run with --update-goldens to write screenshots
// to test/goldens/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuitmate/app_state.dart';
import 'package:tuitmate/core/format.dart';
import 'package:tuitmate/core/settings.dart';
import 'package:tuitmate/core/storage.dart';
import 'package:tuitmate/lms/lms_client.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/snapshot.dart';
import 'package:tuitmate/ui/attendance_screen.dart';
import 'package:tuitmate/ui/chat_screen.dart';
import 'package:tuitmate/ui/courses_screen.dart';
import 'package:tuitmate/ui/deadlines_screen.dart';
import 'package:tuitmate/ui/exams_screen.dart';
import 'package:tuitmate/ui/home_shell.dart';
import 'package:tuitmate/ui/nav.dart';
import 'package:tuitmate/ui/schedule_screen.dart';
import 'package:tuitmate/ui/settings_screen.dart';
import 'package:tuitmate/ui/today_screen.dart';
import 'package:tuitmate/ui/welcome_screen.dart';

LmsSnapshot sampleSnapshot(DateTime now) {
  final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  DateTime at(int day, int h, int m) => monday.add(Duration(days: day, hours: h, minutes: m));
  const courses = [
    Course(id: 1, subject: 'Algoritmlar va ma\'lumotlar tuzilmasi', subjectId: 11, absenceCount: 2, teachers: ['Karimov A.'], streams: ['ALG301']),
    Course(id: 2, subject: 'Ma\'lumotlar bazasi', subjectId: 12, absenceCount: 1, teachers: ['Aliyeva D.'], streams: ['MB-21']),
    Course(id: 3, subject: 'Fizika', subjectId: 13, absenceCount: 0, teachers: ['Rahimov B.'], streams: ['FIZ12-a1']),
  ];
  final sched = <ScheduleItem>[];
  for (var d = 0; d < 6; d++) {
    sched.add(ScheduleItem(start: at(d, 8, 30), title: 't', subject: courses[d % 3].subject, room: 'A-${300 + d}', stream: 'ALG301', type: LessonType.lecture));
    sched.add(ScheduleItem(start: at(d, 10, 0), title: 't', subject: courses[(d + 1) % 3].subject, room: 'B-21$d', type: LessonType.practice, side: WeekSide.left));
    sched.add(ScheduleItem(start: at(d, 13, 30), title: 't', subject: courses[(d + 2) % 3].subject, room: 'C-10$d', type: LessonType.laboratory, side: WeekSide.right));
  }
  Assignment a(int c, String n, int days, {double? g, bool up = false}) => Assignment(
        courseId: courses[c].id,
        courseName: courses[c].subject,
        taskType: 'Laboratoriya',
        teacher: courses[c].teachers.first,
        name: n,
        deadline: now.add(Duration(days: days, hours: 5)),
        grade: g,
        maxGrade: 10,
        uploadId: 100 + n.length,
        taskFile: const LmsFile('topshiriq.pdf', 'https://lms.tuit.uz/storage/t.pdf'),
        uploadedFile: up ? const LmsFile('javob.docx', 'https://lms.tuit.uz/storage/a.docx') : null,
      );
  return LmsSnapshot(
    info: const StudentInfo(fullName: 'ALIYEV VALI ALIJON OʻGʻLI', group: '711-23', studentId: '230123', specialization: 'Dasturiy injiniring', year: '3', tutor: 'Saidova M.'),
    semesters: const [Semester(9, '2026-2027 Kuzgi semestr', selected: true)],
    semesterId: 9,
    courses: courses,
    schedule: sched,
    absences: [
      Absence(subject: courses[0].subject, date: now.subtract(const Duration(days: 9)), lessonType: 'Ma\'ruza', theme: 'Saralash algoritmlari', themeNumber: 4),
      Absence(subject: courses[0].subject, date: now.subtract(const Duration(days: 3)), lessonType: 'Amaliy', theme: 'Graf', themeNumber: 6),
      Absence(subject: courses[1].subject, date: now.subtract(const Duration(days: 5)), lessonType: 'Laboratoriya', theme: 'SQL JOIN', themeNumber: 3),
    ],
    finals: [
      ExamFinal(subject: courses[0].subject, date: now.add(const Duration(days: 12)), from: '09:00', to: '10:20', room: 'A-305', stream: 'ALG301', timeLimit: 80),
      ExamFinal(subject: courses[2].subject, date: now.subtract(const Duration(days: 20)), from: '13:30', grade: 88, room: 'C-101', testPoints: const [TestPoint(1, 42), TestPoint(2, 46)]),
    ],
    coursePages: {
      1: CoursePage(const CourseRating(achieved: 34, max: 50, ratingPercent: 68, grade: 3), [a(0, 'Lab 3: Binary search tree', 1), a(0, 'Lab 2: Stack va Queue', -6, g: 9, up: true)]),
      2: CoursePage(const CourseRating(achieved: 41, max: 50, ratingPercent: 82, grade: 4), [a(1, 'ER diagramma', 4), a(1, 'SQL so\'rovlar', -2, up: true)]),
      3: CoursePage(const CourseRating(achieved: 46, max: 50, ratingPercent: 92, grade: 5), [a(2, 'Kinematika masalalari', 9)]),
    },
    lessons: {
      1: [
        Lesson(type: LessonType.lecture, number: 1, theme: 'Kirish. Algoritm tushunchasi', date: monday.subtract(const Duration(days: 35)), files: const [LmsFile('Ma\'ruza 1.pptx', 'https://lms.tuit.uz/f/1.pptx')]),
        Lesson(type: LessonType.practice, number: 1, theme: 'Massivlar', date: monday.subtract(const Duration(days: 33))),
      ],
    },
    studyPlan: const [
      Discipline(title: 'Oliy matematika', semester: '1-semestr', credits: 6, grade: 91),
      Discipline(title: 'Dasturlash asoslari', semester: '1-semestr', credits: 6, grade: 78),
      Discipline(title: 'Fizika', semester: '2-semestr', credits: 4, grade: 64),
    ],
    news: [NewsItem(title: 'Yakuniy nazorat jadvali e\'lon qilindi', body: 'Kuzgi semestr yakuniy nazoratlari 15-dekabrdan boshlanadi.', date: now.subtract(const Duration(days: 1)))],
    updatedAt: now,
  );
}

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/root/sdk/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  late AppState app;
  late Directory tmp;

  setUpAll(() async {
    await initializeDateFormatting();
    await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'notifications': false, 'language': 'uz'});
    FlutterSecureStoragePlatformMock.install();
    tmp = Directory.systemTemp.createTempSync('tuitmate_test');
    final storage = AppStorage.useDirectory(tmp);
    final settings = await Settings.load();
    app = AppState(settings, storage, LmsClient('${tmp.path}/cookies/'), sampleSnapshot(DateTime.now()), false);
  });

  final screens = <String, Widget Function()>{
    'today': () => const TodayScreen(),
    'schedule': () => const ScheduleScreen(),
    'deadlines': () => const DeadlinesScreen(),
    'courses': () => const CoursesScreen(),
    'attendance': () => const AttendanceScreen(),
    'exams': () => const ExamsScreen(),
    'profile': () => const ProfileScreen(),
    'assistant': () => const ChatScreen(),
    'welcome': () => const WelcomeScreen(),
    'shell': () => const HomeShell(),
  };

  for (final size in const [Size(412, 900), Size(1280, 800)]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} @ ${size.width.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            ChangeNotifierProvider(create: (_) => NavController()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light).copyWith(
              textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: e.value(),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // Screenshots are only written with --update-goldens (data depends on today's date).
        if (autoUpdateGoldenFiles) {
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${size.width.toInt()}.png'));
        }
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
    }
  }
}

/// In-memory stand-in for the keystore plugin.
class FlutterSecureStoragePlatformMock {
  static void install() {
    final data = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = Map<String, dynamic>.from(call.arguments ?? const {});
        switch (call.method) {
          case 'read':
            return data[args['key']];
          case 'write':
            data[args['key']] = args['value'];
            return null;
          case 'delete':
            data.remove(args['key']);
            return null;
          default:
            return null;
        }
      },
    );
  }
}
