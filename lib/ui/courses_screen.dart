import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/chat_models.dart';
import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../lms/models.dart';
import 'deadlines_screen.dart';
import 'files.dart';
import 'lms_web_page.dart';
import 'nav.dart';
import 'widgets.dart';

class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = app.snapshot;

    final plan = <String, List<Discipline>>{};
    for (final d in snap.studyPlan) {
      plan.putIfAbsent(d.semester ?? '—', () => []).add(d);
    }

    return PageScaffold(
      title: s['courses'],
      lmsPath: '/student/my-courses',
      children: [
        if (snap.semester != null) SectionTitle('${s['currentSemester']} · ${snap.semester!.name}'),
        if (snap.courses.isEmpty && !snap.isEmpty) EmptyState(icon: Icons.school_outlined, text: s['noData']),
        for (final c in snap.courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => CourseDetailPage.open(context, c),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Builder(builder: (_) {
                      final r = snap.coursePages[c.id]?.rating;
                      final pct = r?.ratingPercent ??
                          ((r?.achieved != null && (r?.max ?? 0) > 0) ? r!.achieved! / r.max! * 100 : null);
                      return ScoreBadge(text: pct == null ? '—' : fmtNum(pct), color: scoreColor(pct, cs), size: 52);
                    }),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.subject, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 4),
                        if (c.teachers.isNotEmpty)
                          Text(c.teachers.join(', '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          if (snap.coursePages[c.id]?.rating.achieved != null)
                            Pill('${fmtNum(snap.coursePages[c.id]!.rating.achieved)} / ${fmtNum(snap.coursePages[c.id]!.rating.max)} ${s['points']}'),
                          if (c.absenceCount > 0)
                            Pill('${c.absenceCount} ${s['absences']}', color: cs.error, icon: Icons.event_busy),
                          if (c.failed) Pill(s['failedTask'], color: cs.error),
                        ]),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            ),
          ),
        if (plan.isNotEmpty) ...[
          SectionTitle(s['studyPlan']),
          for (final e in plan.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${e.value.fold<int>(0, (a, d) => a + (d.credits ?? 0))} ${s['credits']}'),
                  children: [
                    for (final d in e.value)
                      ListTile(
                        dense: true,
                        title: Text(d.title),
                        subtitle: d.credits != null ? Text('${d.credits} ${s['credits']}') : null,
                        trailing: d.grade != null
                            ? ScoreBadge(text: '${d.grade}', color: scoreColor(d.grade, cs), size: 36)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class CourseDetailPage extends StatelessWidget {
  const CourseDetailPage({super.key, required this.course});
  final Course course;

  static Future<void> open(BuildContext context, Course c) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseDetailPage(course: c)));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final page = app.snapshot.coursePages[course.id];
    final lessons = app.snapshot.lessons[course.id] ?? const <Lesson>[];
    final r = page?.rating;
    final white = Theme.of(context).brightness == Brightness.light;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(course.subject),
          actions: [
            IconButton(
              tooltip: s['openInLms'],
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => LmsWebPage.open(context, '/student/my-courses/show/${course.id}'),
            ),
          ],
          bottom: TabBar(
            labelColor: white ? Colors.white : null,
            unselectedLabelColor: white ? Colors.white70 : null,
            indicatorColor: white ? Colors.white : null,
            tabs: [Tab(text: s['assignments']), Tab(text: s['lessons'])],
          ),
        ),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(16), children: [
            if (r != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _Stat(s['points'], '${fmtNum(r.achieved)} / ${fmtNum(r.max)}'),
                    _Stat(s['rating'], r.ratingPercent == null ? '—' : '${fmtNum(r.ratingPercent)}%',
                        color: scoreColor(r.ratingPercent, cs)),
                    _Stat(s['grade'], r.grade?.toString() ?? '—'),
                  ]),
                ),
              ),
            if (course.teachers.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoRow(s['teachers'], course.teachers.join('\n')),
            ],
            const SizedBox(height: 8),
            if (page == null || page.assignments.isEmpty)
              EmptyState(icon: Icons.assignment_outlined, text: s['noData'])
            else
              Card(child: Column(children: [for (final a in page.assignments) AssignmentTile(a, showCourse: false)])),
          ]),
          ListView(padding: const EdgeInsets.all(16), children: [
            if (lessons.isEmpty) EmptyState(icon: Icons.folder_open, text: s['noFiles']),
            for (final type in LessonType.values)
              if (lessons.any((l) => l.type == type)) ...[
                SectionTitle(lessonTypeName(type, s)),
                Card(
                  child: Column(children: [
                    for (final l in lessons.where((l) => l.type == type)) _LessonTile(l, course),
                  ]),
                ),
              ],
          ]),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _LessonTile extends StatelessWidget {
  const _LessonTile(this.l, this.course);
  final Lesson l;
  final Course course;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ExpansionTile(
      shape: const Border(),
      leading: CircleAvatar(radius: 16, child: Text('${l.number}', style: const TextStyle(fontSize: 12))),
      title: Text(l.theme ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        if (l.date != null) fmtDateFull(l.date!, s.lang),
        if (l.files.isNotEmpty) '📎 ${l.files.length}',
      ].join(' · ')),
      children: [
        if (l.files.isEmpty) ListTile(dense: true, title: Text(s['noFiles'])),
        for (final f in l.files)
          ListTile(
            dense: true,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(f.name),
            onTap: () => downloadAndOpen(context, f.url, f.name),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: s['askAi'],
                icon: const Icon(Icons.auto_awesome),
                onPressed: () async {
                  final nav = context.read<NavController>();
                  final navigator = Navigator.of(context);
                  final got = await fetchForAi(context, f.url, f.name);
                  if (got == null) return;
                  navigator.popUntil((r) => r.isFirst);
                  nav.go(Dest.assistant,
                      payload: ChatLaunch('${s['qpSummarize']}: ${l.theme ?? ''} (${course.subject})',
                          fileName: got.$1, bytes: got.$2));
                },
              ),
              IconButton(
                tooltip: s['download'],
                icon: const Icon(Icons.download),
                onPressed: () => downloadAndOpen(context, f.url, f.name),
              ),
            ]),
          ),
      ],
    );
  }
}
