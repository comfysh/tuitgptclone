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
import 'package:tuitmate/ai/chat_models.dart';
import 'package:tuitmate/app_state.dart';
import 'package:tuitmate/core/format.dart';
import 'package:tuitmate/core/settings.dart';
import 'package:tuitmate/core/storage.dart';
import 'package:tuitmate/core/strings.dart';
import 'package:tuitmate/lms/lms_client.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/snapshot.dart';
import 'package:tuitmate/lms/changes.dart';
import 'package:tuitmate/services/inbox.dart';
import 'package:tuitmate/ui/ask_palette.dart';
import 'package:tuitmate/ui/attendance_screen.dart';
import 'package:tuitmate/ui/automation_page.dart';
import 'package:tuitmate/ui/chat_screen.dart';
import 'package:tuitmate/ui/courses_screen.dart';
import 'package:tuitmate/ui/deadlines_screen.dart';
import 'package:tuitmate/ui/exams_screen.dart';
import 'package:tuitmate/ui/files_screen.dart';
import 'package:tuitmate/ui/grades_screen.dart';
import 'package:tuitmate/ui/design.dart' show Brand, AppStyle, AppCard;
import 'package:tuitmate/ui/home_shell.dart';
import 'package:tuitmate/ui/inbox_screen.dart';
import 'package:tuitmate/ui/nav.dart';
import 'package:tuitmate/ui/news_screen.dart';
import 'package:tuitmate/ui/schedule_screen.dart';
import 'package:tuitmate/ui/server_page.dart' show showServerConnect;
import 'package:tuitmate/ui/settings_screen.dart';
import 'package:tuitmate/ui/theme_picker.dart';
import 'package:tuitmate/ui/today_layout.dart';
import 'package:tuitmate/ui/today_screen.dart';
import 'package:tuitmate/ui/welcome_screen.dart';
import 'package:tuitmate/ui/widgets.dart' show HubTabs;

LmsSnapshot sampleSnapshot(DateTime now) {
  final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  DateTime at(int day, int h, int m) => monday.add(Duration(days: day, hours: h, minutes: m));
  const courses = [
    Course(id: 1, subject: 'Algoritmlar va ma\'lumotlar tuzilmasi', subjectId: 11, absenceCount: 2, teachers: ['Karimov A.'], streams: ['ALG301'], questionsUrl: 'https://lms.tuit.uz/student/questions/1'),
    Course(id: 2, subject: 'Ma\'lumotlar bazasi', subjectId: 12, absenceCount: 1, teachers: ['Aliyeva D.', 'Qodirov S.'], streams: ['MB-21']),
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
    info: const StudentInfo(fullName: 'ALIYEV VALI ALIJON OʻGʻLI', group: '711-23', studentId: '230123', specialization: 'Dasturiy injiniring', year: '3', tutor: 'Saidova M.', degree: 'Bakalavr', studyForm: 'Kunduzgi', studyLanguage: 'Ingliz'),
    contracts: const [
      ContractYear(year: '2026-2027', current: true, status: 'Qisman to‘langan', total: 17866395, paid: 8933198, debt: 8933197, paidPercent: 50, currency: 'UZS'),
      ContractYear(year: '2025-2026', status: 'To‘liq to‘langan', total: 16500000, paid: 16500000, debt: 0, paidPercent: 100, currency: 'UZS'),
    ],
    planSummary: const StudyPlanSummary(gpa: 3.6),
    semesters: const [Semester(9, '2026-2027 Kuzgi semestr', selected: true)],
    semesterId: 9,
    courses: courses,
    schedule: sched,
    absences: [
      Absence(subject: courses[0].subject, subjectId: 11, date: now.subtract(const Duration(days: 9)), lessonType: 'Ma\'ruza', theme: 'Saralash algoritmlari', themeNumber: 1),
      Absence(subject: courses[0].subject, subjectId: 11, date: now.subtract(const Duration(days: 3)), lessonType: 'Amaliy', theme: 'Graf', themeNumber: 6, excused: true),
      Absence(subject: courses[1].subject, subjectId: 12, date: now.subtract(const Duration(days: 5)), lessonType: 'Laboratoriya', theme: 'SQL JOIN', themeNumber: 3),
    ],
    finals: [
      ExamFinal(subject: courses[0].subject, subjectId: 11, date: now.add(const Duration(days: 12)), from: '09:00', to: '10:20', room: 'A-305', stream: 'ALG301', timeLimit: 80),
      ExamFinal(subject: courses[1].subject, subjectId: 12, stream: 'MB-21'),
      ExamFinal(subject: courses[2].subject, subjectId: 13, date: now.subtract(const Duration(days: 20)), from: '13:30', grade: 88, room: 'C-101', testPoints: const [TestPoint(1, 42), TestPoint(2, 46)]),
    ],
    coursePages: {
      1: CoursePage(const CourseRating(achieved: 34, max: 50, ratingPercent: 68, grade: 3), [a(0, 'Lab 3: Binary search tree', 1), a(0, 'Lab 2: Stack va Queue', -6, g: 9, up: true)]),
      2: CoursePage(const CourseRating(achieved: 41, max: 50, ratingPercent: 82, grade: 4), [a(1, 'ER diagramma', 4), a(1, 'SQL so\'rovlar', -2, up: true)]),
      3: CoursePage(const CourseRating(achieved: 46, max: 50, ratingPercent: 92, grade: 5), [a(2, 'Kinematika masalalari', 9)]),
    },
    lessons: {
      1: [
        Lesson(type: LessonType.lecture, number: 1, theme: 'Kirish. Algoritm tushunchasi', date: monday.subtract(const Duration(days: 35)), files: const [
          LmsFile('Ma\'ruza 1.pptx', 'https://dl.tuit.uz/f/1.pptx'),
          LmsFile('Algoritmlar_kirish.pdf', 'https://dl.tuit.uz/f/1.pdf'),
        ]),
        Lesson(type: LessonType.lecture, number: 2, theme: 'Saralash algoritmlari: pufakchali, tezkor va birlashtirib saralash', date: monday.subtract(const Duration(days: 28)), files: const [LmsFile('Saralash.pdf', 'https://dl.tuit.uz/f/2.pdf')]),
        Lesson(type: LessonType.practice, number: 1, theme: 'Massivlar', date: monday.subtract(const Duration(days: 33))),
        Lesson(type: LessonType.laboratory, number: 1, theme: 'Stack va Queue', date: monday.subtract(const Duration(days: 30)), files: const [LmsFile('lab1.docx', 'https://dl.tuit.uz/f/lab1.docx')]),
      ],
      2: [
        Lesson(type: LessonType.lecture, number: 1, theme: 'Relyatsion model', date: monday.subtract(const Duration(days: 34)), files: const [
          LmsFile('MB_1-maruza.pptx', 'https://dl.tuit.uz/f/mb1.pptx'),
          LmsFile('jadval.xlsx', 'https://dl.tuit.uz/f/mb1.xlsx'),
          LmsFile('misollar.zip', 'https://dl.tuit.uz/f/mb1.zip'),
        ]),
      ],
    },
    studyPlan: const [
      Discipline(title: 'Oliy matematika', semester: 'I semester', credits: 6, grade: 5),
      Discipline(title: 'Dasturlash asoslari', semester: 'I semester', credits: 6, grade: 4),
      Discipline(title: 'Fizika 1', semester: 'I semester', credits: 6, grade: 2),
      Discipline(title: 'Ingliz tili', semester: 'II semester', credits: 4, grade: 4),
      Discipline(title: 'Diskret matematika', semester: 'II semester', credits: 6, grade: 3),
      Discipline(title: 'Algoritmlar va ma\'lumotlar tuzilmasi', semester: 'III semester', credits: 6),
      Discipline(title: 'Ma\'lumotlar bazasi', semester: 'III semester', credits: 5),
      Discipline(title: 'Fizika', semester: 'III semester', credits: 4),
    ],
    news: [
      NewsItem(title: 'Yakuniy nazorat jadvali e\'lon qilindi', body: 'Kuzgi semestr yakuniy nazoratlari 15-dekabrdan boshlanadi. Talabalar jadval bilan LMS orqali tanishishlari mumkin.', date: now.subtract(const Duration(days: 1)), url: 'https://lms.tuit.uz/news/77'),
      NewsItem(title: 'Kutubxona ish vaqti o\'zgardi', body: 'Kutubxona dushanbadan shanbagacha 9:00 dan 20:00 gacha ishlaydi.', date: now.subtract(const Duration(days: 6)), url: 'https://lms.tuit.uz/news/76'),
    ],
    updatedAt: now,
  );
}

/// Updates as a few syncs would have recorded them (two unread).
List<InboxItem> sampleInbox(LmsSnapshot snap, DateTime now) {
  final lab = snap.coursePages[1]!.assignments.first;
  final graded = snap.coursePages[1]!.assignments.last;
  final news = snap.news.first;
  return [
    InboxItem(kind: ChangeKind.newAssignment, key: lab.key, subject: lab.courseName, detail: lab.title, when: lab.deadline, at: now.subtract(const Duration(minutes: 40))),
    InboxItem(kind: ChangeKind.gradePosted, key: graded.key, subject: graded.courseName, detail: graded.title, value: 9, max: 10, at: now.subtract(const Duration(hours: 3))),
    InboxItem(kind: ChangeKind.newFile, key: 'file|https://dl.tuit.uz/f/2.pdf', subject: snap.courses.first.subject, detail: 'Saralash.pdf', at: now.subtract(const Duration(days: 1, hours: 2)), read: true),
    InboxItem(kind: ChangeKind.newAbsence, key: snap.absences.last.key, subject: snap.absences.last.subject, detail: 'Laboratoriya', when: snap.absences.last.date, at: now.subtract(const Duration(days: 4)), read: true),
    InboxItem(kind: ChangeKind.news, key: news.key, subject: news.title, detail: news.body ?? '', when: news.date, at: now.subtract(const Duration(days: 1)), read: true),
  ];
}

Future<void> _loadFonts() async {
  final sdk = '${Platform.environment['FLUTTER_ROOT'] ?? '/root/sdk/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File(f);
      if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await load('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Inter-$w.ttf',
  ]);
  await load('SourceSerif', ['assets/fonts/SourceSerif4-Semibold.ttf', 'assets/fonts/SourceSerif4-Bold.ttf']);
  await load('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
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
    await storage.writeJson(storage.inboxFile, {
      'v': 1,
      'items': [for (final i in sampleInbox(app.snapshot, DateTime.now())) i.toJson()],
    });
    app.inbox = await Inbox.load(storage);
  });

  // Pages of a hub are shown inside it, as in the app (hub name and section tabs).
  Widget inHub(Dest d, Widget page) => HubSection(dest: d, child: page);

  final screens = <String, Widget Function()>{
    'today': () => const TodayScreen(),
    'schedule': () => inHub(Dest.schedule, const ScheduleScreen()),
    'deadlines': () => inHub(Dest.deadlines, const DeadlinesScreen()),
    'courses': () => inHub(Dest.courses, const CoursesScreen()),
    'attendance': () => inHub(Dest.attendance, const AttendanceScreen()),
    'exams': () => inHub(Dest.exams, const ExamsScreen()),
    'inbox': () => inHub(Dest.inbox, const InboxScreen()),
    'course_detail': () => CourseDetailPage(course: app.snapshot.courses.first),
    'task_sheet': () => _AutoOpen((ctx) => showAssignmentSheet(ctx, app.snapshot.coursePages[1]!.assignments.last)),
    'grades': () => inHub(Dest.grades, const GradesScreen()),
    'files': () => inHub(Dest.files, const FilesScreen()),
    'news': () => inHub(Dest.news, const NewsScreen()),
    'news_detail': () => NewsDetailPage(item: app.snapshot.news.first),
    'profile': () => const ProfileScreen(),
    'ai_settings': () => const AiSettingsPage(),
    'automation': () => const AutomationPage(),
    'assistant': () => const ChatScreen(),
    'welcome': () => const WelcomeScreen(),
    'shell': () => const HomeShell(),
    'shell_plan': () => const _StartAt(Dest.deadlines, HomeShell()),
    'shell_inbox': () => const _StartAt(Dest.inbox, HomeShell()),
    'shell_study': () => const _StartAt(Dest.grades, HomeShell()),
    'ask': () => _AutoOpen(AskPalette.open),
    'theme_picker': () => _AutoOpen(showThemePicker),
    'server_connect': () => _AutoOpen(showServerConnect),
    'today_customizer': () => _AutoOpen(showTodayCustomizer),
    'today_all': () => const _AllSections(TodayScreen()),
    'shell_start_inbox': () => const _StartHub('inbox', HomeShell()),
  };

  // Phone, small phone, PC; plus dark mode on a phone.
  const variants = [
    (Size(412, 900), Brightness.light, ''),
    (Size(360, 720), Brightness.light, ''),
    (Size(1280, 800), Brightness.light, ''),
    (Size(412, 900), Brightness.dark, '_dark'),
  ];
  for (final (size, brightness, suffix) in variants) {
    for (final e in screens.entries) {
      final name = '${e.key}_${size.width.toInt()}$suffix';
      testWidgets(name, (tester) async {
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
            theme: buildTheme(brightness),
            home: e.value(),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // Screenshots are only written with --update-goldens (data depends on today's date).
        if (autoUpdateGoldenFiles) {
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
        }
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
    }
  }

  // Every theme, light and dark, the way the app applies it (see main.dart).
  for (final style in AppStyle.values) {
    for (final b in Brightness.values) {
      testWidgets('theme_${style.name}_${b.name}', (tester) async {
        tester.view.physicalSize = const Size(412, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(() => Brand.apply(AppStyle.paper, Brightness.light));
        await tester.pumpWidget(MultiProvider(
          providers: [ChangeNotifierProvider.value(value: app), ChangeNotifierProvider(create: (_) => NavController())],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(b, style: style),
            builder: (context, child) {
              Brand.apply(style, b);
              return child!;
            },
            home: const _StartAt(Dest.grades, HomeShell()),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        if (autoUpdateGoldenFiles) {
          await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/theme_${style.name}_${b.name}.png'));
        }
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
    }
  }

  Future<NavController> pumpApp(WidgetTester tester, Widget home, {Size size = const Size(412, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nav = NavController();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: app), ChangeNotifierProvider.value(value: nav)],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return nav;
  }

  testWidgets('Ask finds a task by its words and opens it', (tester) async {
    await pumpApp(tester, _AutoOpen(AskPalette.open));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'binary lab');
    await tester.pump();
    final hit = find.text('Lab 3: Binary search tree');
    expect(hit, findsOneWidget);
    await tester.tap(hit);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byType(TextField), findsNothing); // the palette closed
    expect(find.text('topshiriq.pdf'), findsWidgets); // the task sheet is open
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('Ask finds pages by their name in any language', (tester) async {
    final nav = await pumpApp(tester, _AutoOpen(AskPalette.open));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'profile'); // the app is in Uzbek
    await tester.pump();
    final hit = find.text(S('uz')['profile']);
    expect(hit, findsOneWidget);
    await tester.tap(hit);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(nav.current, Dest.profile);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('Ask sends anything else to the AI with the question', (tester) async {
    final nav = await pumpApp(tester, _AutoOpen(AskPalette.open), size: const Size(1280, 800));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'ertaga nima bor');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search); // Enter: the first line is "Ask AI"
    await tester.pump(const Duration(milliseconds: 400));
    expect(nav.current, Dest.assistant);
    final launch = nav.takePayload() as ChatLaunch;
    expect(launch.prompt, 'ertaga nima bor');
    expect(launch.send, isTrue);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('Inbox: unread count, mark all read, tabs switch sections', (tester) async {
    final nav = await pumpApp(tester, HubSection(dest: Dest.inbox, child: const InboxScreen()));
    expect(app.unread, 2);
    expect(find.text('Xabarlar'), findsOneWidget); // the hub's name as the title
    await tester.tap(find.byTooltip(S('uz')['ibMarkAll']));
    await tester.pump();
    expect(app.unread, 0); // at once
    // The file write: real I/O, continued by the test's clock.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    final saved = (await tester.runAsync(() => Inbox.load(app.storage)))!;
    expect(saved, hasLength(5));
    expect(saved.every((i) => i.read), isTrue);
    await tester.tap(find.descendant(of: find.byType(HubTabs), matching: find.text(S('uz')['news'])));
    await tester.pump();
    expect(nav.current, Dest.news);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('Customize Today: switch a section off, drag to reorder; the start page', (tester) async {
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final nav = await pumpApp(tester, _AutoOpen(showTodayCustomizer));
    await settle();
    final s = S('uz');
    // Tomorrow off.
    final row = find.ancestor(of: find.text(s['tdTomorrow']), matching: find.byType(AppCard));
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await settle();
    expect(app.settings.todayLayout, contains('-tomorrow'));
    // Drag the agenda (first) below the next two sections.
    await tester.drag(find.byIcon(Icons.drag_indicator_rounded).first, const Offset(0, 140));
    await settle();
    final layout = todayLayout(app.settings);
    expect(layout.first.$1, isNot(TodaySection.agenda));
    expect(layout.map((e) => e.$1).toSet(), TodaySection.values.toSet()); // nothing lost or doubled
    // Opens on Plan.
    await tester.tap(find.text(s['hubPlan']));
    await settle();
    expect(app.settings.startHub, 'plan');
    expect(nav.current, Dest.today); // takes effect at the next start
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  test('Today layout: saved order, hidden sections, unknown and new names', () async {
    expect(todayLayout(app.settings).where((e) => e.$2).map((e) => e.$1), [
      TodaySection.agenda, TodaySection.whatsNew, TodaySection.due, TodaySection.numbers,
      TodaySection.nextExam, TodaySection.debt, TodaySection.tomorrow,
    ]);
    app.settings.todayLayout = ['due', '-agenda', 'gone', 'news', 'due'];
    final l = todayLayout(app.settings);
    expect(l.take(3), [(TodaySection.due, true), (TodaySection.agenda, false), (TodaySection.news, true)]);
    expect(l, hasLength(TodaySection.values.length)); // the rest joins at the end
    expect(l.last, (TodaySection.attendance, false)); // with its default
    saveTodayLayout(app.settings, null);
    expect(app.settings.todayLayout, isNull);
  });

}

/// Today with every section switched on, in the default order.
class _AllSections extends StatelessWidget {
  const _AllSections(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppState>().settings;
    settings.todayLayout = [for (final t in TodaySection.values) t.name];
    return child;
  }
}

/// The home shell with "Opens on" set to [hub].
class _StartHub extends StatelessWidget {
  const _StartHub(this.hub, this.child);
  final String hub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    context.read<AppState>().settings.startHub = hub;
    return child;
  }
}

/// Opens [child] (the home shell) on [dest] instead of Today.
class _StartAt extends StatefulWidget {
  const _StartAt(this.dest, this.child);
  final Dest dest;
  final Widget child;

  @override
  State<_StartAt> createState() => _StartAtState();
}

class _StartAtState extends State<_StartAt> {
  @override
  void initState() {
    super.initState();
    context.read<NavController>().current = widget.dest; // before the first build: no notify needed
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens a sheet or dialog on top of an empty page after the first frame.
class _AutoOpen extends StatefulWidget {
  const _AutoOpen(this.open);
  final void Function(BuildContext) open;

  @override
  State<_AutoOpen> createState() => _AutoOpenState();
}

class _AutoOpenState extends State<_AutoOpen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
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
