import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/chat_models.dart';
import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../core/timetable.dart' show AttendanceSummary;
import '../lms/models.dart';
import '../lms/parsers.dart' show lessonTypeOfName;
import '../lms/snapshot.dart' show LmsSnapshot;
import 'cards.dart' show DeadlineCard, deadlineLabel;
import 'deadlines_screen.dart' show showAssignmentSheet;
import 'files.dart';
import 'lms_web_page.dart';
import 'nav.dart';
import 'widgets.dart';

// ---------------------------------------------------------------- helpers

/// Rating percentage of a course (the LMS value, or achieved / max).
double? _percentOf(CourseRating? r) {
  if (r == null) return null;
  if (r.ratingPercent != null) return r.ratingPercent;
  final a = r.achieved, m = r.max;
  if (a != null && m != null && m > 0) return a / m * 100;
  return null;
}

/// The grade a course is heading for, from the work graded so far (see
/// [Standing]); null before anything is graded.
int? _expectedGrade(CoursePage? page) => standingFor(page).grade;

/// A task you still have to do (the same rule on every screen).
bool _isOpen(Assignment a) => isOpenTask(a);

int _byDeadlineAsc(Assignment a, Assignment b) {
  final x = a.deadline, y = b.deadline;
  if (x == null && y == null) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  return x.compareTo(y);
}

int _byDeadlineDesc(Assignment a, Assignment b) => (b.deadline ?? DateTime(0)).compareTo(a.deadline ?? DateTime(0));

/// Every absence recorded for [c], newest first.
List<Absence> _absencesOf(Course c, LmsSnapshot snap) {
  final name = c.subject.trim().toLowerCase();
  return [
    for (final a in snap.absences)
      if ((c.subjectId != 0 && a.subjectId == c.subjectId) ||
          ((c.subjectId == 0 || a.subjectId == 0) && a.subject.trim().toLowerCase() == name))
        a,
  ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
}

/// NB count of [c], counted like the Attendance screen: from the detailed
/// list when the LMS gave one, otherwise from the per-course counter.
int _nbCount(Course c, List<Absence> list, LmsSnapshot snap) =>
    snap.absences.isNotEmpty ? list.length : c.absenceCount;

int _fileCount(List<Lesson>? lessons) => (lessons ?? const <Lesson>[]).fold(0, (n, l) => n + l.files.length);

FileKind _kindOf(LmsFile f) {
  final k = fileKind(f.url);
  return k == FileKind.other ? fileKind(f.name) : k;
}

String _fileLabel(LmsFile f) => f.name.trim().isEmpty ? bestFileName(f.url, '') : f.name.trim();

String _initials(String name) =>
    name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

/// Points rounded to 0.1 (hides floating-point noise like 7.000000001).
String _pts(double v) => fmtNum((v * 10).round() / 10);

/// Hero gradient in a subject's colour, dark enough for white text.
LinearGradient _heroGradient(Color c, bool dark) {
  Color deepen(Color x, double maxLum) {
    var h = HSLColor.fromColor(x);
    while (h.toColor().computeLuminance() > maxLum && h.lightness > 0.12) {
      h = h.withLightness(h.lightness - 0.02);
    }
    return h.toColor();
  }

  final hsl = HSLColor.fromColor(c);
  return LinearGradient(
    colors: [
      deepen(c, dark ? 0.12 : 0.17),
      deepen(hsl.withHue((hsl.hue + 336) % 360).toColor(), dark ? 0.07 : 0.10),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

List<Widget> _spaced(List<Widget?> items, [double gap = 12]) {
  final out = <Widget>[];
  for (final w in items) {
    if (w == null) continue;
    if (out.isNotEmpty) out.add(SizedBox(height: gap));
    out.add(w);
  }
  return out;
}

/// Sends an LMS file to the AI chat with [prompt] (closes pushed pages first).
Future<void> _askAi(BuildContext context, String url, String name, String prompt) async {
  final nav = context.read<NavController>();
  final navigator = Navigator.of(context);
  final got = await fetchForAi(context, url, name);
  if (got == null) return;
  navigator.popUntil((r) => r.isFirst);
  nav.go(Dest.assistant, payload: ChatLaunch(prompt, fileName: got.$1, bytes: got.$2));
}

String _questionsName(Course c, S s) => '${c.subject} - ${s['crQuestionsShort']}';

void _openQuestions(BuildContext context, Course c) {
  final url = c.questionsUrl;
  if (url == null) return;
  downloadAndOpen(context, url, _questionsName(c, S.read(context)));
}

void _askAboutQuestions(BuildContext context, Course c) {
  final url = c.questionsUrl;
  if (url == null) return;
  final s = S.read(context);
  _askAi(context, url, _questionsName(c, s), '${s['crQuestionsAi']} (${c.subject})');
}

// ---------------------------------------------------------------- list

class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final nav = context.read<NavController>();
    final courses = snap.courses;

    final pcts = <double>[];
    final standing = <double>[];
    final split = <int, int>{};
    for (final c in courses) {
      final page = snap.coursePages[c.id];
      final r = page?.rating;
      final pct = _percentOf(r);
      if (r != null && pct != null && (r.max ?? 0) > 0) pcts.add(pct);
      final st = standingFor(page);
      final g = st.grade;
      if (g != null) {
        split[g] = (split[g] ?? 0) + 1;
        standing.add(st.percent!);
      }
    }
    final avg = pcts.isEmpty ? null : pcts.reduce((a, b) => a + b) / pcts.length;
    final expected = standing.isEmpty ? null : standing.reduce((a, b) => a + b) / standing.length;
    final open = [
      for (final c in courses) ...?snap.coursePages[c.id]?.assignments.where(_isOpen),
    ].length;
    final files = libraryFiles(snap).length; // same count as the Files screen
    final att = AttendanceSummary.from(snap, app.settings);

    final plan = <String, List<Discipline>>{};
    for (final d in snap.studyPlan) {
      plan.putIfAbsent(d.semester ?? '—', () => []).add(d);
    }

    final stats = [
      StatTile(
        icon: Icons.menu_book_rounded,
        value: '${courses.length}',
        label: s['crStatCourses'],
        color: Brand.primary,
      ),
      StatTile(
        icon: Icons.assignment_rounded,
        value: '$open',
        label: s['crStatOpen'],
        color: Brand.warning,
        onTap: () => nav.go(Dest.deadlines),
      ),
      StatTile(
        icon: Icons.event_busy_rounded,
        value: '${att.absences}',
        label: s.f('crStatNb', {'h': att.hoursUsed}),
        color: att.absences == 0
            ? Brand.success
            : att.ratio >= 0.75
                ? Brand.danger
                : Brand.violet,
        onTap: () => nav.go(Dest.attendance),
      ),
      StatTile(
        icon: Icons.folder_copy_rounded,
        value: '$files',
        label: s['crStatFiles'],
        color: Brand.info,
        onTap: () => nav.go(Dest.files),
      ),
    ];

    return PageScaffold(
      title: s['coursesShort'],
      lmsPath: '/student/my-courses',
      children: [
        if (snap.isEmpty) ...[
          if (!app.syncing)
            AppCard(child: EmptyView(icon: Icons.cloud_sync_rounded, title: s['crNotSynced'], subtitle: s['crNotSyncedSub'])),
        ] else ...[
          _SummaryHero(avg: avg, expected: expected, split: split),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 720 ? 4 : 2;
            final w = (c.maxWidth - 12 * (cols - 1)) / cols;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final t in stats) SizedBox(width: w, child: t),
            ]);
          }),
          SectionHeader(s.f('crSubjectsCount', {'n': courses.length})),
          if (courses.isEmpty)
            AppCard(child: EmptyView(icon: Icons.school_outlined, title: s['crNoCourses'], subtitle: s['crNoCoursesSub']))
          else
            _CardGrid(count: courses.length, builder: (i, fill) => _CourseCard(course: courses[i], fill: fill)),
          if (plan.isNotEmpty) ...[
            SectionHeader(s['studyPlan'], action: s['navGrades'], onAction: () => nav.go(Dest.grades)),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, e) in plan.entries.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _PlanSemester(name: e.key, items: e.value),
                ],
              ]),
            ),
          ],
          if (snap.updatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(s.f('updated', {'time': fmtAgo(snap.updatedAt, s)}),
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ],
    );
  }
}

/// Average rating, expected-grade split and the semester picker.
class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.avg, required this.expected, required this.split});
  final double? avg;

  /// Average result on graded work; the ring shows the grade it leads to.
  final double? expected;
  final Map<int, int> split;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final white70 = Colors.white.withValues(alpha: 0.78);
    final a = avg;
    final e = expected;
    final grade = e == null ? null : gradeForPercent(e);
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s['crAvgRating'], style: TextStyle(color: white70, fontWeight: FontWeight.w600))),
          const _SemesterPill(),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a == null ? '—' : '${fmtNum(a)}%',
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.1)),
              const SizedBox(height: 8),
              if (a == null)
                Text(s['crNoRatingSub'], style: TextStyle(color: white70, fontSize: 13))
              else if (split.isEmpty)
                Text(s['crNothingGraded'], style: TextStyle(color: white70, fontSize: 13))
              else ...[
                Text(s['crExpected'], style: TextStyle(color: white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final g in const [5, 4, 3, 2])
                    if ((split[g] ?? 0) > 0)
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                        decoration:
                            BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Text('$g',
                                style: TextStyle(color: gradeColor(g, cs), fontSize: 11.5, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 6),
                          Text('× ${split[g]}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ]),
                      ),
                ]),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Ring(
            value: (e ?? 0) / 100,
            color: Colors.white,
            track: Colors.white.withValues(alpha: 0.22),
            size: 92,
            stroke: 8,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(grade?.toString() ?? '—',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
              Text(s['grade'], style: TextStyle(fontSize: 11, color: white70, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

/// Current semester; a menu to switch when the LMS has several.
class _SemesterPill extends StatelessWidget {
  const _SemesterPill();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = app.snapshot;
    final sems = snap.semesters;
    final cur = snap.semester;
    if (cur == null && sems.isEmpty) return const SizedBox.shrink();
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.date_range_rounded, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(cur?.name ?? s['semester'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        if (sems.length > 1) const Icon(Icons.expand_more_rounded, size: 16, color: Colors.white),
      ]),
    );
    if (sems.length <= 1) return pill;
    return PopupMenuButton<int>(
      tooltip: s['crPickSemester'],
      initialValue: snap.semesterId,
      onSelected: (v) {
        // Picking the LMS's current semester means "follow the LMS", not "pin this one".
        final lmsCurrent = sems.where((x) => x.selected).map((x) => x.id).firstOrNull;
        final target = v == lmsCurrent ? null : v;
        // Compared with the saved choice too: after a failed sync the shown
        // semester differs from it, and picking the shown one must undo it.
        if (target == app.settings.semesterId && v == snap.semesterId) return;
        app.changeSemester(target);
      },
      itemBuilder: (_) => [
        for (final sem in sems)
          PopupMenuItem(
            value: sem.id,
            child: Row(children: [
              Expanded(child: Text(sem.name, overflow: TextOverflow.ellipsis)),
              if (sem.id == snap.semesterId) Icon(Icons.check_rounded, size: 18, color: cs.primary),
            ]),
          ),
      ],
      child: pill,
    );
  }
}

/// Grid whose cards in one row share the same height (1 column on phones).
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.count, required this.builder});
  final int count;
  final Widget Function(int index, bool fill) builder;

  static const _minItemWidth = 330.0;
  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = math.max(1, math.min(3, (c.maxWidth / _minItemWidth).floor()));
      if (cols == 1) {
        return Column(children: [
          for (var i = 0; i < count; i++) Padding(padding: const EdgeInsets.only(bottom: _spacing), child: builder(i, false)),
        ]);
      }
      return Column(children: [
        for (var i = 0; i < count; i += cols)
          Padding(
            padding: const EdgeInsets.only(bottom: _spacing),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: _spacing),
                  Expanded(child: i + j < count ? builder(i + j, true) : const SizedBox.shrink()),
                ],
              ]),
            ),
          ),
      ]);
    });
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.fill});
  final Course course;

  /// Stretch to the row height (grid) and keep the facts at the bottom.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = context.watch<AppState>().snapshot;
    final color = subjectColor(course.subjectId);
    final page = snap.coursePages[course.id];
    final pct = _percentOf(page?.rating);
    final grade = _expectedGrade(page);
    final open = (page?.assignments ?? const <Assignment>[]).where(_isOpen).toList();
    final next = (open.where((a) => a.deadline != null).toList()..sort(_byDeadlineAsc)).firstOrNull;
    final due = next == null ? null : deadlineLabel(next, s, cs);
    final nb = _nbCount(course, _absencesOf(course, snap), snap);
    final files = libraryFiles(snap).where((f) => f.course.id == course.id).length;
    final muted = cs.onSurfaceVariant;

    return AppCard(
      onTap: () => CourseDetailPage.open(context, course),
      padding: EdgeInsets.zero,
      accent: color,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.25)),
                if (course.teachers.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(course.teachers.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                ],
                if (course.failed || course.streams.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (course.failed) Tag(s['crFailed'], color: Brand.danger, icon: Icons.error_outline_rounded, filled: true),
                    for (final st in course.streams.take(3)) Tag(st, color: muted, icon: Icons.groups_2_outlined),
                  ]),
                ],
              ]),
            ),
            const SizedBox(width: 12),
            _RatingRing(pct: pct, grade: grade),
          ]),
          if (fill) const Spacer(),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 6, children: [
            _Fact(Icons.assignment_outlined, open.isEmpty ? s['crNoOpen'] : s.f('crOpenN', {'n': open.length}),
                open.isEmpty ? muted : cs.primary),
            if (due != null) _Fact(Icons.schedule_rounded, due.$1, due.$2),
            _Fact(Icons.event_busy_outlined, s.f('crNbN', {'n': nb}), nb > 0 ? Brand.danger : muted),
            _Fact(Icons.attach_file_rounded, s.f('crFilesN', {'n': files}), muted),
          ]),
        ]),
      ),
    );
  }
}

/// Rating ring with the 5-point grade badge on its corner.
class _RatingRing extends StatelessWidget {
  const _RatingRing({required this.pct, required this.grade});
  final double? pct;
  final int? grade;

  static const _size = 62.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = pct;
    return SizedBox(
      width: _size + 6,
      height: _size + 6,
      child: Stack(clipBehavior: Clip.none, children: [
        Ring(
          value: (p ?? 0) / 100,
          color: scoreColor(p, cs),
          size: _size,
          stroke: 6,
          child: Text(p == null ? '—' : '${p.round()}%',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13.5, color: p == null ? cs.onSurfaceVariant : cs.onSurface)),
        ),
        if (p != null || grade != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
              child: GradeBadge(grade, size: 24),
            ),
          ),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text, this.color);
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ]);
}

/// One semester of the study plan (collapsed).
class _PlanSemester extends StatelessWidget {
  const _PlanSemester({required this.name, required this.items});
  final String name;
  final List<Discipline> items;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final credits = items.fold<int>(0, (a, d) => a + (d.credits ?? 0));
    final gpa = estimatedGpa(items);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const TintIcon(Icons.layers_rounded, color: Brand.success, size: 36),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$credits ${s['credits']}${gpa == null ? '' : ' · GPA ${gpa.toStringAsFixed(2)}'}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final d in items)
            ListTile(
              dense: true,
              title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: d.credits != null ? Text('${d.credits} ${s['credits']}') : null,
              trailing: d.grade != null ? GradeBadge(d.grade, size: 32) : null,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- detail

class CourseDetailPage extends StatelessWidget {
  const CourseDetailPage({super.key, required this.course});
  final Course course;

  static Future<void> open(BuildContext context, Course c) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseDetailPage(course: c)));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    // Fresh copy after a sync; the passed one if the semester changed meanwhile.
    final c = snap.courseById(course.id) ?? course;
    final color = subjectColor(c.subjectId);
    final page = snap.coursePages[c.id];
    final lessons = snap.lessons[c.id] ?? const <Lesson>[];
    final absences = _absencesOf(c, snap);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          actions: [
            if (c.questionsUrl != null)
              HeaderButton(icon: Icons.quiz_outlined, tooltip: s['crQuestions'], onPressed: () => _openQuestions(context, c)),
            HeaderButton(
              icon: Icons.open_in_new_rounded,
              tooltip: s['openInLms'],
              onPressed: () => LmsWebPage.open(context, '/student/my-courses/show/${c.id}'),
            ),
            HeaderButton(icon: Icons.refresh_rounded, tooltip: s['refresh'], busy: app.syncing, onPressed: () => app.refresh()),
            const SizedBox(width: 6),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: _Centered(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: _CourseHero(course: c, page: page, nb: _nbCount(c, absences, snap), color: color),
              ),
            ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeader(labels: [s['crOverview'], s['assignments'], s['crLessonsTab']], color: color),
              ),
            ),
          ],
          body: TabBarView(children: [
            _OverviewTab(course: c, page: page, absences: absences, color: color),
            _TasksTab(page: page),
            _LessonsTab(course: c, lessons: lessons),
          ]),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// Scrollable body of one tab under the pinned tab bar.
class _TabBody extends StatelessWidget {
  const _TabBody({required this.name, required this.children});
  final String name;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: PageStorageKey<String>(name),
      slivers: [
        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        SliverToBoxAdapter(
          child: _Centered(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.labels, required this.color});
  final List<String> labels;
  final Color color;

  @override
  double get minExtent => 62;
  @override
  double get maxExtent => 62;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _Centered(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        child: Container(
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(radiusM),
            border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.06)) : null,
            boxShadow: dark
                ? null
                : [BoxShadow(color: const Color(0xFF1B2559).withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 3))],
          ),
          child: TabBar(
            tabs: [for (final l in labels) Tab(height: 40, text: l)],
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(radiusS)),
            splashBorderRadius: BorderRadius.circular(radiusS),
            labelColor: cs.onSurface,
            unselectedLabelColor: cs.onSurfaceVariant,
            labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13.5),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13.5),
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabsHeader old) => old.color != color || old.labels.join('|') != labels.join('|');
}

/// Gradient header: subject, teachers, rating ring and key numbers.
class _CourseHero extends StatelessWidget {
  const _CourseHero({required this.course, required this.page, required this.nb, required this.color});
  final Course course;
  final CoursePage? page;
  final int nb;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final white70 = Colors.white.withValues(alpha: 0.78);
    final r = page?.rating;
    final pct = _percentOf(r);
    final grade = _expectedGrade(page);
    final open = (page?.assignments ?? const <Assignment>[]).where(_isOpen).length;
    final divider = Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.2));

    return HeroCard(
      gradient: _heroGradient(color, Theme.of(context).brightness == Brightness.dark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (course.failed || course.streams.isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (course.failed) _HeroPill(s['crFailed'], icon: Icons.error_outline_rounded, strong: true),
                  for (final st in course.streams.take(3)) _HeroPill(st, icon: Icons.groups_2_outlined),
                ]),
                const SizedBox(height: 10),
              ],
              Text(course.subject,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.4)),
              if (course.teachers.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(course.teachers.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: white70, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Ring(
            value: (pct ?? 0) / 100,
            color: Colors.white,
            track: Colors.white.withValues(alpha: 0.22),
            size: 86,
            stroke: 8,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(pct == null ? '—' : '${fmtNum(pct)}%',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(s['rating'], style: TextStyle(fontSize: 11, color: white70, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(radiusM)),
          child: Row(children: [
            Expanded(
                child: _HeroStat(
                    label: s['crPointsLabel'],
                    value: r?.achieved == null && r?.max == null ? '—' : '${fmtNum(r?.achieved)}/${fmtNum(r?.max)}')),
            divider,
            Expanded(
              child: _HeroStat(
                label: s['crExpectedOne'],
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: GradeBadge(grade, size: 26),
                ),
              ),
            ),
            divider,
            Expanded(child: _HeroStat(label: s['crStatOpen'], value: '$open')),
            divider,
            Expanded(child: _HeroStat(label: s['nb'], value: '$nb')),
          ]),
        ),
      ]),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill(this.text, {required this.icon, this.strong = false});
  final String text;
  final IconData icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final fg = strong ? Brand.danger : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: strong ? Colors.white : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, this.value, this.child});
  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 30,
            child: Center(
              child: child ??
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value ?? '—',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
            ),
          ),
          const SizedBox(height: 4),
          // Two lines at most, broken between words and scaled down rather
          // than split inside a long word ("topshiriqlar") on small phones.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label.trim().replaceFirst(' ', '\n'),
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.78))),
          ),
        ]),
      );
}

// ---------------------------------------------------------------- overview tab

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.course, required this.page, required this.absences, required this.color});
  final Course course;
  final CoursePage? page;
  final List<Absence> absences;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = page;
    final next = ((p?.assignments ?? const <Assignment>[]).where(_isOpen).toList()..sort(_byDeadlineAsc)).firstOrNull;

    final Widget forecast = p == null
        ? AppCard(child: EmptyView(icon: Icons.cloud_sync_rounded, title: s['crNotLoaded'], subtitle: s['crNotLoadedSub']))
        : _ForecastCard(page: p);
    final Widget? nextTask = next == null
        ? null
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(
              s['crNextTask'],
              action: s['crAllTasks'],
              onAction: () => DefaultTabController.of(context).animateTo(1),
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            ),
            DeadlineCard(a: next, showCourse: false, onTap: () => showAssignmentSheet(context, next)),
          ]);
    final questions = course.questionsUrl == null ? null : _QuestionsCard(course: course);
    final attendance = _AttendanceCard(course: course, absences: absences);
    final about = _AboutCard(course: course, color: color);

    return _TabBody(name: 'overview', children: [
      LayoutBuilder(builder: (context, c) {
        final left = [questions, forecast, nextTask];
        final right = [attendance, about];
        if (c.maxWidth < 860) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced([...left, ...right]));
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(left))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(right))),
        ]);
      }),
    ]);
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.page});
  final CoursePage page;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final fc = forecastFor(page);
    final pct = (_percentOf(page.rating) ?? fc.percent).clamp(0, 100).toDouble();
    final best = math.max(fc.bestPercent, pct).clamp(0, 100).toDouble();
    final muted = cs.onSurfaceVariant;

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const TintIcon(Icons.insights_rounded, color: Brand.violet),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['crForecast'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(s['crForecastSub'], style: TextStyle(color: muted, fontSize: 12.5)),
            ]),
          ),
        ]),
        if (fc.maxSoFar <= 0) ...[
          const SizedBox(height: 14),
          Text(s['crNoForecast'], style: TextStyle(color: muted)),
        ] else ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _Figure(label: s['crCurrent'], value: '${fmtNum(pct)}%', color: scoreColor(pct, cs))),
            Expanded(child: _Figure(label: s['crBest'], value: '${fmtNum(best)}%', color: scoreColor(best, cs))),
            Expanded(child: _Figure(label: s['crOpenPoints'], value: '+${_pts(fc.openPoints)}', color: cs.onSurface)),
          ]),
          const SizedBox(height: 16),
          _ForecastBar(current: pct, best: best),
          const SizedBox(height: 8),
          for (final t in fc.targets.reversed) _TargetRow(target: t, openPoints: fc.openPoints),
        ],
        const SizedBox(height: 10),
        Text(
          s.f('crThresholds', {
            'g5': fmtNum(gradeThresholds[5]),
            'g4': fmtNum(gradeThresholds[4]),
            'g3': fmtNum(gradeThresholds[3]),
          }),
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ]),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4)),
        ),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
      ]);
}

/// 0–100 % bar: current rating, best case, and the 3/4/5 thresholds.
class _ForecastBar extends StatelessWidget {
  const _ForecastBar({required this.current, required this.best});
  final double current;
  final double best;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = scoreColor(current, cs);
    final bc = scoreColor(best, cs);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, k, _) => SizedBox(
          height: 38,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              right: 0,
              top: 4,
              height: 12,
              child: DecoratedBox(
                decoration:
                    BoxDecoration(color: cs.onSurface.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(6)),
              ),
            ),
            Positioned(
              left: 0,
              top: 4,
              height: 12,
              width: w * best / 100 * k,
              child: DecoratedBox(
                  decoration: BoxDecoration(color: bc.withValues(alpha: 0.30), borderRadius: BorderRadius.circular(6))),
            ),
            Positioned(
              left: 0,
              top: 4,
              height: 12,
              width: w * current / 100 * k,
              child: DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
            ),
            for (final e in gradeThresholds.entries) ...[
              Positioned(
                left: w * e.value / 100 - 1,
                top: 0,
                height: 20,
                width: 2,
                child: DecoratedBox(
                  decoration:
                      BoxDecoration(color: cs.onSurface.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(1)),
                ),
              ),
              Positioned(
                left: w * e.value / 100 - 20,
                width: 40,
                top: 22,
                child: Text('${fmtNum(e.value)}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: gradeColor(e.key, cs))),
              ),
            ],
          ]),
        ),
      );
    });
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, required this.openPoints});
  final GradeTarget target;
  final double openPoints;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = target;
    final reached = t.pointsNeeded <= 0.05;
    final (tag, tagColor) = reached
        ? (s['crReached'], Brand.success)
        : t.reachable
            ? (s['crPossible'], Brand.primary)
            : (s['crOutOfReach'], Brand.danger);
    final sub = reached
        ? null
        : t.reachable
            ? s.f('crNeedPoints', {'p': _pts(t.pointsNeeded)})
            : s.f('crOutOfReachSub', {'p': _pts(t.pointsNeeded), 'o': _pts(openPoints)});
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        GradeBadge(t.grade, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.f('crGradeFrom', {'g': t.grade, 'p': fmtNum(gradeThresholds[t.grade])}),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(width: 8),
        Tag(tag, color: tagColor, icon: reached ? Icons.check_rounded : null),
      ]),
    );
  }
}

class _QuestionsCard extends StatelessWidget {
  const _QuestionsCard({required this.course});
  final Course course;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppCard(
      accent: Brand.violet,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const TintIcon(Icons.quiz_rounded, color: Brand.violet),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['crQuestions'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(s['crQuestionsSub'],
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => _openQuestions(context, course),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(s['open']),
          ),
          OutlinedButton.icon(
            onPressed: () => _askAboutQuestions(context, course),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(s['askAi']),
          ),
        ]),
      ]),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.course, required this.absences});
  final Course course;
  final List<Absence> absences;

  static const _shown = 8;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    final hpa = app.settings.hoursPerAbsence;
    final nb = _nbCount(course, absences, app.snapshot);
    final excused = absences.where((a) => a.excused).length;
    return AppCard(
      onTap: () {
        final nav = context.read<NavController>();
        Navigator.of(context).popUntil((r) => r.isFirst);
        nav.go(Dest.attendance);
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          TintIcon(Icons.event_busy_rounded, color: nb == 0 ? Brand.success : Brand.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['attendance'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(s.f('crAttendanceSub', {'n': nb, 'h': nb * hpa}),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ]),
          ),
          if (excused > 0) ...[const SizedBox(width: 8), Tag(s.f('crExcusedN', {'n': excused}), color: Brand.warning)],
        ]),
        if (nb == 0) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: Brand.success, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(s['crNoAbsences'], style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ],
        if (absences.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final a in absences.take(_shown)) _AbsenceRow(a),
          if (absences.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+${absences.length - _shown}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ),
        ],
      ]),
    );
  }
}

class _AbsenceRow extends StatelessWidget {
  const _AbsenceRow(this.a);
  final Absence a;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final c = a.excused ? Brand.warning : Brand.danger;
    final d = a.date;
    final type = lessonTypeOfName(a.lessonType);
    final meta = [
      if (type != null) lessonTypeName(type, s) else if ((a.lessonType ?? '').trim().isNotEmpty) a.lessonType!.trim(),
      if (a.themeNumber > 0) s.f('crLessonNo', {'n': a.themeNumber}),
    ].join(' · ');
    final theme = (a.theme ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 46,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(d == null ? '—' : '${d.day}', style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w800)),
            if (d != null)
              Text(fmtDate(d, s.lang).split(' ').last,
                  maxLines: 1, style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(theme.isNotEmpty ? theme : (meta.isNotEmpty ? meta : '—'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3)),
            if (theme.isNotEmpty && meta.isNotEmpty)
              Text(meta, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Tag(a.excused ? s['crExcused'] : s['nb'], color: c, filled: !a.excused),
      ]),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.course, required this.color});
  final Course course;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final caption = TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TintIcon(Icons.menu_book_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(s['crAbout'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ]),
        if (course.teachers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(s['teachers'], style: caption),
          const SizedBox(height: 4),
          for (final t in course.teachers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Text(_initials(t),
                      style: TextStyle(color: cs.onSurface, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(child: SelectableText(t, style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
        ],
        if (course.streams.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(s['crStreams'], style: caption),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final st in course.streams) Tag(st, color: cs.onSurfaceVariant, icon: Icons.groups_2_outlined),
          ]),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => LmsWebPage.open(context, '/student/my-courses/show/${course.id}'),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(s['openInLms']),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- tasks tab

class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.page});
  final CoursePage? page;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = page;
    if (p == null) {
      return _TabBody(name: 'tasks', children: [
        AppCard(child: EmptyView(icon: Icons.cloud_sync_rounded, title: s['crNotLoaded'], subtitle: s['crNotLoadedSub'])),
      ]);
    }
    final all = p.assignments;
    if (all.isEmpty) {
      return _TabBody(name: 'tasks', children: [
        AppCard(child: EmptyView(icon: Icons.assignment_outlined, title: s['crNoTasks'], subtitle: s['crNoTasksSub'])),
      ]);
    }
    final groups = [
      (s['crToDo'], all.where(_isOpen).toList()..sort(_byDeadlineAsc)),
      (s['overdue'], all.where((a) => a.isOverdue).toList()..sort(_byDeadlineDesc)),
      (s['submitted'], all.where((a) => a.isSubmitted && !a.isGraded).toList()..sort(_byDeadlineDesc)),
      (s['graded'], all.where((a) => a.isGraded).toList()..sort(_byDeadlineDesc)),
    ].where((g) => g.$2.isNotEmpty).toList();

    return _TabBody(name: 'tasks', children: [
      for (final (i, g) in groups.indexed) ...[
        SectionHeader('${g.$1} · ${g.$2.length}', padding: i == 0 ? const EdgeInsets.fromLTRB(4, 4, 4, 10) : null),
        ResponsiveGrid(
          minItemWidth: 400,
          spacing: 10,
          children: [
            for (final a in g.$2) DeadlineCard(a: a, showCourse: false, onTap: () => showAssignmentSheet(context, a)),
          ],
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- lessons tab

enum _FileAction { open, summarize, explain, quiz }

class _LessonsTab extends StatelessWidget {
  const _LessonsTab({required this.course, required this.lessons});
  final Course course;
  final List<Lesson> lessons;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    if (lessons.isEmpty) {
      return _TabBody(name: 'lessons', children: [
        AppCard(child: EmptyView(icon: Icons.folder_open_rounded, title: s['crNoLessons'], subtitle: s['crNoLessonsSub'])),
      ]);
    }
    final snap = context.watch<AppState>().snapshot;
    final abs = absencesFor(course, snap);
    final files = _fileCount(lessons);
    final groups = [
      for (final t in LessonType.values)
        if (lessons.any((l) => l.type == t))
          (t, lessons.where((l) => l.type == t).toList()..sort((a, b) => a.number.compareTo(b.number))),
    ];

    return _TabBody(name: 'lessons', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Text(s.f('crLessonsCount', {'n': lessons.length, 'f': files}),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ),
      if (files > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: Brand.violet),
            const SizedBox(width: 8),
            Expanded(child: Text(s['crFileHint'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
          ]),
        )
      else
        const SizedBox(height: 6),
      ResponsiveGrid(
        minItemWidth: 440,
        children: [
          for (final (t, list) in groups) _LessonGroup(type: t, lessons: list, course: course, absences: abs),
        ],
      ),
    ]);
  }
}

class _LessonGroup extends StatelessWidget {
  const _LessonGroup({required this.type, required this.lessons, required this.course, required this.absences});
  final LessonType type;
  final List<Lesson> lessons;
  final Course course;
  final Map<String, Absence> absences;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = lessonTypeColor(type);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            TintIcon(lessonTypeIcon(type), color: c, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(lessonTypeName(type, s), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            Tag('${lessons.length}', color: c),
          ]),
        ),
        const Divider(height: 1),
        for (final (i, l) in lessons.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 62),
          _LessonRow(lesson: l, course: course, absence: absenceForLesson(l, absences), color: c),
        ],
      ]),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, required this.course, required this.absence, required this.color});
  final Lesson lesson;
  final Course course;
  final Absence? absence;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final l = lesson;
    final ab = absence;
    final d = l.date;
    final theme = (l.theme ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text('${l.number}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(theme.isEmpty ? '—' : theme,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.3)),
            if (d != null || ab != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (d != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_today_rounded, size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(fmtDateFull(d, s.lang),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w500)),
                  ]),
                if (ab != null)
                  ab.excused
                      ? Tag('${s['nb']} · ${s['crExcused']}', color: Brand.warning, icon: Icons.event_busy_rounded)
                      : Tag(s['nb'], color: Brand.danger, icon: Icons.event_busy_rounded, filled: true),
              ]),
            ],
            if (l.files.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in l.files)
                  _FileChip(
                    file: f,
                    onOpen: () => downloadAndOpen(context, f.url, f.name),
                    onMenu: () => _fileMenu(context, f, l, course),
                  ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Open / Ask-AI menu for a lesson file.
Future<void> _fileMenu(BuildContext context, LmsFile f, Lesson l, Course course) async {
  final s = S.read(context);
  final k = _kindOf(f);
  final theme = (l.theme ?? '').trim();
  final act = await showModalBottomSheet<_FileAction>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      ListTile item(IconData icon, String text, _FileAction a, {Color? color}) => ListTile(
            leading: Icon(icon, color: color),
            title: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, a),
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              leading: TintIcon(fileKindIcon(k), color: fileKindColor(k)),
              title: Text(_fileLabel(f),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: theme.isEmpty ? null : Text(theme, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(),
            item(Icons.download_rounded, s['open'], _FileAction.open),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Text(s['askAi'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            item(Icons.auto_awesome_rounded, s['qpSummarize'], _FileAction.summarize, color: Brand.violet),
            item(Icons.lightbulb_outline_rounded, s['qpExplain'], _FileAction.explain, color: Brand.violet),
            item(Icons.quiz_outlined, s['qpQuiz'], _FileAction.quiz, color: Brand.violet),
            const SizedBox(height: 8),
          ]),
        ),
      );
    },
  );
  if (act == null || !context.mounted) return;
  final prompt = switch (act) {
    _FileAction.open => null,
    _FileAction.summarize => s['qpSummarize'],
    _FileAction.explain => s['qpExplain'],
    _FileAction.quiz => s['qpQuiz'],
  };
  if (prompt == null) {
    await downloadAndOpen(context, f.url, f.name);
  } else {
    await _askAi(context, f.url, f.name, '$prompt: $theme (${course.subject})');
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.file, required this.onOpen, required this.onMenu});
  final LmsFile file;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final k = _kindOf(file);
    final c = fileKindColor(k);
    final radius = BorderRadius.circular(10);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Material(
        color: c.withValues(alpha: 0.10),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onOpen,
          onLongPress: onMenu,
          onSecondaryTap: onMenu,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(fileKindIcon(k), size: 16, color: c),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_fileLabel(file),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: s['askAi'],
                child: InkResponse(
                  onTap: onMenu,
                  radius: 16,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.auto_awesome_rounded, size: 15, color: Brand.violet),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
