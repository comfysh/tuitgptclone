// Tasks ("Topshiriqlar"): a status summary, course and search filters, tasks
// grouped by when they are due, and the task sheet (deadline, grade, criteria,
// files, upload, Ask AI).

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/chat_models.dart';
import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../core/timetable.dart' show dateOnly;
import '../lms/models.dart';
import 'cards.dart';
import 'files.dart';
import 'lms_web_page.dart';
import 'nav.dart';
import 'widgets.dart';
import 'workload.dart';

/// Where a task stands (the four summary tiles).
enum _Status { todo, overdue, submitted, graded }

/// List sections, in display order.
enum _Group { overdue, today, tomorrow, thisWeek, later, noDeadline, submitted, graded }

/// Sections that show only their first few tasks until expanded (when no
/// status filter is active).
const _collapsible = {_Group.overdue, _Group.submitted, _Group.graded};
const _collapsedCount = 6;

_Status _statusOf(Assignment a) => a.isGraded
    ? _Status.graded
    : a.isSubmitted
        ? _Status.submitted
        : a.isOverdue
            ? _Status.overdue
            : _Status.todo;

_Group _groupOf(Assignment a, DateTime now) {
  switch (_statusOf(a)) {
    case _Status.graded:
      return _Group.graded;
    case _Status.submitted:
      return _Group.submitted;
    case _Status.overdue:
      return _Group.overdue;
    case _Status.todo:
      break;
  }
  final d = a.deadline;
  if (d == null) return _Group.noDeadline;
  final today = dateOnly(now);
  final day = dateOnly(d);
  if (day == today) return _Group.today;
  if (day == DateTime(today.year, today.month, today.day + 1)) return _Group.tomorrow;
  final nextMonday = DateTime(today.year, today.month, today.day + 8 - today.weekday);
  return d.isBefore(nextMonday) ? _Group.thisWeek : _Group.later;
}

(String, IconData, Color) _statusMeta(_Status st, S s) => switch (st) {
      _Status.todo => (s['dlToDo'], Icons.pending_actions_rounded, Brand.primary),
      _Status.overdue => (s['overdue'], Icons.running_with_errors_rounded, Brand.danger),
      _Status.submitted => (s['submitted'], Icons.cloud_done_rounded, Brand.info),
      _Status.graded => (s['graded'], Icons.verified_rounded, Brand.success),
    };

(String, IconData, Color) _groupMeta(_Group g, S s, ColorScheme cs) => switch (g) {
      _Group.overdue => (s['overdue'], Icons.error_rounded, Brand.danger),
      _Group.today => (s['today'], Icons.today_rounded, Brand.warning),
      _Group.tomorrow => (s['dlTomorrow'], Icons.event_rounded, Brand.warning),
      _Group.thisWeek => (s['thisWeek'], Icons.date_range_rounded, Brand.primary),
      _Group.later => (s['dlLater'], Icons.event_note_rounded, Brand.violet),
      _Group.noDeadline => (s['dlNoDeadline'], Icons.all_inclusive_rounded, cs.outline),
      _Group.submitted => (s['dlWaitingGrade'], Icons.hourglass_top_rounded, Brand.info),
      _Group.graded => (s['graded'], Icons.verified_rounded, Brand.success),
    };

/// By deadline (tasks without one last); ties by title so the order is stable.
int _byDeadline(Assignment a, Assignment b, {bool newestFirst = false}) {
  final x = a.deadline, y = b.deadline;
  final int c;
  if (x == null || y == null) {
    c = x == null ? (y == null ? 0 : 1) : -1;
  } else {
    c = newestFirst ? y.compareTo(x) : x.compareTo(y);
  }
  return c != 0 ? c : a.title.compareTo(b.title);
}

IconData _taskIcon(Assignment a) => a.isGraded
    ? Icons.verified_rounded
    : a.isSubmitted
        ? Icons.cloud_done_rounded
        : Icons.assignment_outlined;

String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

// ---------------------------------------------------------------- screen

class DeadlinesScreen extends StatefulWidget {
  const DeadlinesScreen({super.key});

  @override
  State<DeadlinesScreen> createState() => _DeadlinesScreenState();
}

class _DeadlinesScreenState extends State<DeadlinesScreen> {
  _Status? _filter;
  int? _course;
  String _query = '';
  final _search = TextEditingController();
  final _expanded = <_Group>{};
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps countdowns and the Today / Tomorrow sections current.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _filter = null;
      _course = null;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = app.snapshot;
    final now = DateTime.now();
    final all = snap.assignments;

    // Only courses that have tasks. A course filter that no longer exists
    // (e.g. after changing semester) is forgotten.
    final withTasks = {for (final a in all) a.courseId};
    final courses = [for (final c in snap.courses) if (withTasks.contains(c.id)) c];
    final course = courses.any((c) => c.id == _course) ? _course : null;

    final q = _query.trim().toLowerCase();
    bool found(Assignment a) =>
        q.isEmpty || [a.title, a.courseName, a.taskType ?? '', a.teacher ?? ''].any((t) => t.toLowerCase().contains(q));

    final searched = [for (final a in all) if (found(a)) a];
    final scoped = [for (final a in searched) if (course == null || a.courseId == course) a];

    // Tile counts follow the course and search filters.
    final counts = {for (final st in _Status.values) st: 0};
    for (final a in scoped) {
      counts.update(_statusOf(a), (n) => n + 1);
    }
    // Course counts follow the status and search filters.
    final perCourse = <int, int>{};
    var allCount = 0;
    for (final a in searched) {
      if (_filter != null && _statusOf(a) != _filter) continue;
      perCourse.update(a.courseId, (n) => n + 1, ifAbsent: () => 1);
      allCount++;
    }

    final shown = [for (final a in scoped) if (_filter == null || _statusOf(a) == _filter) a];
    final groups = <_Group, List<Assignment>>{};
    for (final a in shown) {
      (groups[_groupOf(a, now)] ??= []).add(a);
    }
    final filtering = _filter != null || course != null || q.isNotEmpty;

    final sections = <Widget>[];
    for (final g in _Group.values) {
      final list = groups[g];
      if (list == null || list.isEmpty) continue;
      // Finished and missed work: most recent first. Everything else: soonest first.
      final newest = g == _Group.graded || g == _Group.overdue;
      list.sort((a, b) => _byDeadline(a, b, newestFirst: newest));
      final canCollapse = _filter == null && _collapsible.contains(g) && list.length > _collapsedCount + 2;
      final open = !canCollapse || _expanded.contains(g);
      final visible = open ? list : list.take(_collapsedCount).toList();
      final (title, icon, color) = _groupMeta(g, s, cs);
      sections.add(_GroupHeader(
        title: title,
        icon: icon,
        color: color,
        count: list.length,
        first: sections.isEmpty,
        action: canCollapse ? (open ? s['dlShowLess'] : s['dlShowAll']) : null,
        onAction: () => setState(() {
          if (open) {
            _expanded.remove(g);
          } else {
            _expanded.add(g);
          }
        }),
      ));
      sections.add(ResponsiveGrid(
        minItemWidth: 420,
        spacing: 10,
        children: [
          for (final a in visible)
            DeadlineCard(a: a, showCourse: course == null, onTap: () => showAssignmentSheet(context, a)),
        ],
      ));
    }

    return PageScaffold(
      title: s['deadlines'],
      lmsPath: '/student/my-courses',
      children: [
        if (snap.isEmpty) ...[
          if (!app.syncing)
            AppCard(
              child: EmptyView(icon: Icons.cloud_sync_rounded, title: s['dlNotSynced'], subtitle: s['dlNotSyncedSub']),
            ),
        ] else if (all.isEmpty)
          AppCard(
            child: EmptyView(
                icon: Icons.task_alt_rounded, title: s['dlEmpty'], subtitle: s['dlEmptySub'], color: Brand.success),
          )
        else ...[
          const WorkloadCard(),
          _SummaryRow(
            counts: counts,
            selected: _filter,
            onSelect: (st) => setState(() => _filter = _filter == st ? null : st),
          ),
          const SizedBox(height: 12),
          _filterBar(s, courses: courses, course: course, perCourse: perCourse, allCount: allCount, filtering: filtering),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _noMatch(s, allDone: _filter == _Status.todo && course == null && q.isEmpty),
            )
          else
            ...sections,
        ],
        if (snap.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(s.f('updated', {'time': fmtAgo(snap.updatedAt, s)}),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _noMatch(S s, {required bool allDone}) {
    return AppCard(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: [
        EmptyView(
          icon: allDone ? Icons.task_alt_rounded : Icons.search_off_rounded,
          title: allDone ? s['dlAllDone'] : s['dlNoMatch'],
          subtitle: allDone ? s['dlAllDoneSub'] : s['dlNoMatchSub'],
          color: allDone ? Brand.success : null,
        ),
        TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
          label: Text(s['dlClearFilters']),
        ),
      ]),
    );
  }

  Widget _filterBar(
    S s, {
    required List<Course> courses,
    required int? course,
    required Map<int, int> perCourse,
    required int allCount,
    required bool filtering,
  }) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusM),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
    );
    final search = TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: s['dlSearch'],
        isDense: true,
        filled: true,
        fillColor: cs.surface,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: s['dlClearSearch'],
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: cs.primary, width: 1.5)),
      ),
    );
    final clear = TextButton.icon(
      onPressed: _clearFilters,
      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
      label: Text(s['dlClearFilters'], maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final showCourses = courses.length > 1;

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 600) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: search),
              ),
            ),
            if (filtering) ...[const SizedBox(width: 12), clear],
          ]),
          if (showCourses) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _courseChip(null, s['dlAllCourses'], null, allCount, course == null),
              for (final x in courses)
                _courseChip(x.id, x.subject, subjectColor(x.subjectId), perCourse[x.id] ?? 0, course == x.id),
            ]),
          ],
        ]);
      }
      final selected = courses.where((x) => x.id == course).firstOrNull;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: search),
          if (showCourses) ...[
            const SizedBox(width: 8),
            _coursePicker(s, courses: courses, course: course, perCourse: perCourse, allCount: allCount),
          ],
        ]),
        if (filtering)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: selected == null
                      ? const SizedBox.shrink()
                      : InputChip(
                          avatar: _ChipDot(subjectColor(selected.subjectId)),
                          label: Text(selected.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onDeleted: () => setState(() => _course = null),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          deleteButtonTooltipMessage: s['dlAllCourses'],
                        ),
                ),
              ),
              const SizedBox(width: 8),
              clear,
            ]),
          ),
      ]);
    });
  }

  Widget _courseChip(int? id, String name, Color? color, int n, bool selected) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return ChoiceChip(
      tooltip: name,
      avatar: color == null ? null : _ChipDot(color),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        Text('$n', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
      selected: selected,
      selectedColor: c.withValues(alpha: 0.16),
      side: BorderSide(color: selected ? c.withValues(alpha: 0.7) : cs.outlineVariant.withValues(alpha: 0.6)),
      onSelected: (_) => setState(() => _course = id),
    );
  }

  Widget _coursePicker(
    S s, {
    required List<Course> courses,
    required int? course,
    required Map<int, int> perCourse,
    required int allCount,
  }) {
    final cs = Theme.of(context).colorScheme;
    final active = course != null;
    Widget row(Widget lead, String name, int n) => Row(children: [
          SizedBox(width: 18, child: Center(child: lead)),
          const SizedBox(width: 12),
          Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text('$n', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
        ]);
    return PopupMenuButton<int>(
      tooltip: s['dlCourseFilter'],
      initialValue: course ?? -1,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusM)),
      onSelected: (v) => setState(() => _course = v < 0 ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: -1,
          child: row(Icon(Icons.apps_rounded, size: 18, color: cs.onSurfaceVariant), s['dlAllCourses'], allCount),
        ),
        for (final x in courses)
          PopupMenuItem(value: x.id, child: row(_Dot(subjectColor(x.subjectId)), x.subject, perCourse[x.id] ?? 0)),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? Color.alphaBlend(cs.primary.withValues(alpha: 0.12), cs.surface) : cs.surface,
          borderRadius: BorderRadius.circular(radiusM),
          border: Border.all(color: active ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Icon(Icons.tune_rounded, size: 20, color: active ? cs.primary : cs.onSurfaceVariant),
      ),
    );
  }
}

/// Four status tiles; tapping one filters the list (tap again to clear).
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.counts, required this.selected, required this.onSelect});
  final Map<_Status, int> counts;
  final _Status? selected;
  final ValueChanged<_Status> onSelect;

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    Widget tile(_Status st) =>
        _SummaryTile(status: st, count: counts[st] ?? 0, selected: selected == st, onTap: () => onSelect(st));
    Widget row(List<_Status> items) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: tile(items[i])),
            ],
          ]),
        );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 720) return row(_Status.values);
      return Column(children: [
        row(const [_Status.todo, _Status.overdue]),
        const SizedBox(height: gap),
        row(const [_Status.submitted, _Status.graded]),
      ]);
    });
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.status, required this.count, required this.selected, required this.onTap});
  final _Status status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final (label, icon, color) = _statusMeta(status, s);
    return Semantics(
      selected: selected,
      child: Container(
        foregroundDecoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(radiusM),
                border: Border.all(color: color, width: 1.6),
              )
            : null,
        child: AppCard(
          onTap: onTap,
          radius: radiusM,
          color: selected ? Color.alphaBlend(color.withValues(alpha: 0.12), cs.surface) : null,
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(children: [
            TintIcon(icon, color: color, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('$count',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, height: 1.1, color: count == 0 ? cs.onSurfaceVariant : null)),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Section title with an icon, a count and an optional action.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    this.first = false,
    this.action,
    this.onAction,
  });
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final bool first;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 16 : 22, 0, 10),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            Tag('$count', color: color),
          ]),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Course colour dot sized for a chip's avatar slot.
class _ChipDot extends StatelessWidget {
  const _ChipDot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(width: 18, height: 18, child: Center(child: _Dot(color)));
}

// ---------------------------------------------------------------- tile

/// A task with its course colour, deadline and status; opens the task sheet.
/// The default look is [DeadlineCard] (a standalone card: put spacing between
/// tiles). [dense] is a compact flat row for lists inside another card.
/// [showCourse] false hides the course name (e.g. on the course's own page).
class AssignmentTile extends StatelessWidget {
  const AssignmentTile(this.a, {super.key, this.dense = false, this.showCourse = true});
  final Assignment a;
  final bool dense;
  final bool showCourse;

  @override
  Widget build(BuildContext context) {
    if (!dense) {
      return DeadlineCard(a: a, showCourse: showCourse, onTap: () => showAssignmentSheet(context, a));
    }
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = courseColor(a.courseId, context.watch<AppState>().snapshot, name: a.courseName);
    final (label, labelColor) = deadlineLabel(a, s, cs);
    final sub = [
      if (showCourse) a.courseName,
      if (a.deadline != null) fmtDateTime(a.deadline!, s.lang),
    ].join(' · ');
    return InkWell(
      onTap: () => showAssignmentSheet(context, a),
      borderRadius: BorderRadius.circular(radiusS),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          TintIcon(_taskIcon(a), color: color, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Tag(label, color: labelColor),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- task sheet

/// Task details: a bottom sheet on phones, a centred dialog on PC-sized windows.
Future<void> showAssignmentSheet(BuildContext context, Assignment a) {
  if (MediaQuery.sizeOf(context).width >= 840) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: _AssignmentSheet(a, dialog: true),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => _AssignmentSheet(a),
  );
}

class _AssignmentSheet extends StatefulWidget {
  const _AssignmentSheet(this.a, {this.dialog = false});
  final Assignment a;
  final bool dialog;

  @override
  State<_AssignmentSheet> createState() => _AssignmentSheetState();
}

class _AssignmentSheetState extends State<_AssignmentSheet> {
  bool _busy = false;

  // Messages are shown inside the sheet: a SnackBar would appear behind it.
  String? _status;
  bool _statusBusy = false;
  bool _statusError = false;

  /// The task file couldn't be downloaded; the next "Ask AI" goes without it.
  bool _fileFailed = false;

  void _setStatus(String? message, {bool busy = false, bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusBusy = busy;
      _statusError = error;
    });
  }

  Assignment get a {
    // Pick up the refreshed copy after an upload. Rows can share a key, so
    // never swap in another row (its upload id would receive the file).
    final app = context.read<AppState>();
    final same = [
      for (final x in app.snapshot.coursePages[widget.a.courseId]?.assignments ?? const <Assignment>[])
        if (x.key == widget.a.key) x,
    ];
    if (same.length == 1) return same.single;
    if (widget.a.uploadId != null) {
      for (final x in same) {
        if (x.uploadId == widget.a.uploadId) return x;
      }
    }
    return widget.a;
  }

  Future<void> _upload() async {
    final s = S.read(context);
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    // If the sheet was closed meanwhile, report the result as a SnackBar.
    void report(String m, {bool error = false}) {
      if (mounted) {
        _setStatus(m, error: error);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(m)));
      }
    }

    final f = await FilePicker.pickFile(dialogTitle: s['uploadAnswer']);
    if (f == null) return;
    final size = await f.length() ?? 0;
    if (size > 50 * 1024 * 1024) {
      _setStatus(s['uploadTooBig'], error: true);
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.f('uploadConfirm', {'file': f.name, 'task': a.title})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s['uploadAnswer'])),
        ],
      ),
    );
    if (ok != true) return;
    final task = a;
    setState(() => _busy = true);
    _setStatus(s['uploading'], busy: true);
    try {
      final bytes = await f.readAsBytes();
      await app.upload(task, f.name, bytes);
      report('✓ ${s['uploadOk']}');
    } catch (e) {
      report('${s['error']}: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askAi() async {
    final s = S.read(context);
    final nav = context.read<NavController>();
    final navigator = Navigator.of(context);
    final task = a;
    final prompt = '${s['qpExplain']}.\n\n${s['assignments']}: ${task.title}\n${task.courseName}'
        '${task.taskType != null ? ' · ${task.taskType}' : ''}'
        '${task.deadline != null ? '\n${s['deadline']}: ${fmtDateTime(task.deadline!, s.lang)}' : ''}';
    ChatLaunch launch = ChatLaunch(prompt);
    if (task.taskFile != null && task.taskFile!.looksLikeFile && !_fileFailed) {
      final got = await fetchForAi(context, task.taskFile!.url, task.taskFile!.name, onStatus: _setStatus);
      if (got == null) {
        _fileFailed = true; // keep the sheet open so the error stays visible; next tap asks without the file
        return;
      }
      launch = ChatLaunch(prompt, fileName: got.$1, bytes: got.$2);
    }
    navigator.popUntil((r) => r.isFirst);
    nav.go(Dest.assistant, payload: launch);
  }

  void _openInLms(Assignment a) => LmsWebPage.open(context, '/student/my-courses/show/${a.courseId}');

  @override
  Widget build(BuildContext context) {
    final snap = context.watch<AppState>().snapshot;
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final a = this.a;
    final color = courseColor(a.courseId, snap, name: a.courseName);
    final taskFile = a.taskFile;
    final answer = a.uploadedFile;

    // Upload is the main action while the task is open or still unsubmitted;
    // finished work gets "Open in LMS" instead.
    final uploadable = a.canUpload || (!a.isGraded && !a.isSubmitted);
    final String? closedReason = a.canUpload || a.isGraded || a.isSubmitted
        ? null
        : a.midterm
            ? s['dlNoUploadMidterm']
            : (a.expired || (a.deadline?.isBefore(DateTime.now()) ?? false))
                ? s['dlNoUploadExpired']
                : s['uploadClosed'];

    final criteria = [
      for (final c in a.criteria)
        if (c.text.trim().isNotEmpty || c.points != null) c,
    ];
    final pointed = [for (final c in criteria) c.points].whereType<double>();
    final total = pointed.isEmpty ? null : pointed.reduce((x, y) => x + y);

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _DeadlinePanel(a),
        if (a.isGraded) ...[const SizedBox(height: 10), _GradePanel(a)],
        if (a.isSubmitted && !a.isGraded) ...[
          const SizedBox(height: 10),
          _Notice(icon: Icons.hourglass_top_rounded, color: Brand.info, text: s['dlAwaitingSub']),
        ],
        if (criteria.isNotEmpty) ...[
          _SheetLabel(s['dlCriteria'], trailing: total == null ? null : s.f('dlCriteriaTotal', {'n': fmtNum(total)})),
          _CriteriaPanel(criteria),
        ],
        if (taskFile != null || answer != null) ...[
          _SheetLabel(s['dlFiles']),
          if (taskFile != null)
            _FileCard(
              file: taskFile,
              label: s['taskFile'],
              onOpen: () => downloadAndOpen(context, taskFile.url, taskFile.name, onStatus: _setStatus),
              onAskAi: _askAi,
            ),
          if (taskFile != null && answer != null) const SizedBox(height: 10),
          if (answer != null)
            _FileCard(
              file: answer,
              label: s['yourAnswer'],
              onOpen: () => downloadAndOpen(context, answer.url, answer.name, onStatus: _setStatus),
            ),
        ],
        if (uploadable) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => _openInLms(a),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(s['openInLms']),
            ),
          ),
        ],
      ]),
    );

    final compact = FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14));
    final status = _status;
    final bar = DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (status != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: (_statusError ? cs.error : cs.primary).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(radiusS),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_statusBusy)
                    const Padding(
                      padding: EdgeInsets.only(right: 10, top: 2),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_statusError)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
                    ),
                  Expanded(
                    child: SelectableText(status,
                        style: TextStyle(
                            fontSize: 13, color: _statusError ? cs.error : cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            if (closedReason != null) ...[
              Row(children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(closedReason,
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                ),
              ]),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Expanded(
                child: uploadable
                    ? FilledButton.icon(
                        onPressed: a.canUpload && !_busy ? _upload : null,
                        style: compact,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(a.canUpload ? Icons.cloud_upload_rounded : Icons.lock_rounded, size: 18),
                        label: Text(
                          _busy ? s['uploading'] : (a.isSubmitted ? s['replaceAnswer'] : s['uploadAnswer']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _openInLms(a),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13)),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(s['openInLms'], maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
              ),
              // With a task file, Ask AI sits on the file card.
              if (taskFile == null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _askAi,
                    style: compact,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(s['askAi'], maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );

    final content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context, a, color),
            body,
          ]),
        ),
      ),
      bar,
    ]);
    if (widget.dialog) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: content,
    );
  }

  Widget _header(BuildContext context, Assignment a, Color color) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (status, statusColor) = switch (a.status) {
      AssignmentStatus.graded => (s['graded'], Brand.success),
      AssignmentStatus.submitted => (s['submitted'], Brand.primary),
      AssignmentStatus.notSubmitted => a.isOverdue ? (s['overdue'], Brand.danger) : (s['notSubmitted'], Brand.warning),
    };
    final type = a.taskType?.trim() ?? '';
    final teacher = a.teacher?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: dark ? 0.24 : 0.16), color.withValues(alpha: dark ? 0.07 : 0.04)],
        ),
      ),
      child: Stack(children: [
        Positioned(
          right: -40,
          top: -56,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.10)),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, widget.dialog ? 14 : 8, 8, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!widget.dialog)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 12, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Row(children: [
              _Dot(color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(a.courseName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface.withValues(alpha: 0.8))),
              ),
              IconButton(
                tooltip: s['close'],
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(a.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Tag(status, color: statusColor, filled: true),
                  if (type.isNotEmpty && type != a.title.trim()) Tag(type, color: color, icon: Icons.category_outlined),
                  if (a.midterm) Tag(s['dlMidterm'], color: Brand.violet, icon: Icons.fact_check_rounded),
                  if (a.expired) Tag(s['dlExpired'], color: Brand.danger, icon: Icons.lock_clock_rounded),
                  if (a.failed) Tag(s['failedTask'], color: Brand.danger, icon: Icons.block_rounded),
                ]),
                if (teacher.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(Icons.person_outline_rounded, size: 17, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(teacher,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- sheet parts

TextStyle _labelStyle(ColorScheme cs) =>
    TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1);

/// Soft rounded block used inside the sheet.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color ?? cs.onSurface.withValues(alpha: 0.035),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusM),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
      child: Row(children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        if (trailing != null)
          Text(trailing!, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      color: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
      ]),
    );
  }
}

/// Deadline date with weekday, countdown and the task's maximum points.
class _DeadlinePanel extends StatelessWidget {
  const _DeadlinePanel(this.a);
  final Assignment a;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = a.deadline;
    final (String?, Color) due;
    if (d == null) {
      due = (null, cs.outline);
    } else if (!a.isSubmitted && !a.isGraded) {
      due = deadlineLabel(a, s, cs);
    } else {
      // Done work: a plain countdown, without the urgency colours.
      final left = d.difference(DateTime.now());
      due = left.isNegative
          ? (_cap(s['duePassed']), cs.outline)
          : (s.f('dueIn', {'t': fmtDuration(left, s.lang)}), Brand.primary);
    }
    final showMax = a.maxGrade != null && !a.isGraded;
    return _Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TintIcon(d == null ? Icons.all_inclusive_rounded : Icons.event_rounded, color: due.$2, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['deadline'], style: _labelStyle(cs)),
            const SizedBox(height: 2),
            Text(
              d == null ? s['dlNoDeadline'] : '${_cap(fmtWeekday(d, s.lang))}, ${fmtDateTime(d, s.lang)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.3),
            ),
            if (due.$1 != null || showMax) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (due.$1 case final t?) Tag(t, color: due.$2, icon: Icons.schedule_rounded),
                if (showMax)
                  Tag(s.f('dlMaxPoints', {'n': fmtNum(a.maxGrade)}),
                      color: cs.onSurfaceVariant, icon: Icons.star_outline_rounded),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Grade ring with points and percentage.
class _GradePanel extends StatelessWidget {
  const _GradePanel(this.a);
  final Assignment a;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final g = a.grade ?? 0;
    final max = a.maxGrade;
    final hasMax = max != null && max > 0;
    final c = ratioColor(a.grade, max, cs);
    final pct = hasMax ? (g / max * 100).round() : null;
    return _Panel(
      color: c.withValues(alpha: 0.07),
      child: Row(children: [
        Ring(
          value: hasMax ? g / max : 1,
          color: c,
          size: 72,
          stroke: 7,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(fmtNum(a.grade), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c, height: 1.1)),
            if (max != null)
              Text('/${fmtNum(max)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['grade'], style: _labelStyle(cs)),
            const SizedBox(height: 2),
            Text(
              max != null ? s.f('dlGradeOf', {'grade': fmtNum(a.grade), 'max': fmtNum(max)}) : fmtNum(a.grade),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            if (pct != null) ...[
              const SizedBox(height: 8),
              Tag('$pct%', color: c),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// The teacher's grading criteria: numbered, with points.
class _CriteriaPanel extends StatelessWidget {
  const _CriteriaPanel(this.items);
  final List<Criterion> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Text('${i + 1}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cs.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(items[i].text.trim().isEmpty ? '—' : items[i].text.trim(),
                      style: const TextStyle(fontSize: 13.5, height: 1.35)),
                ),
              ),
              if (items[i].points != null) ...[
                const SizedBox(width: 10),
                Tag(fmtNum(items[i].points), color: cs.primary),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

/// A file with its type icon. With [onAskAi] it shows Open and Ask AI
/// buttons; otherwise a download button.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.label, required this.onOpen, this.onAskAi});
  final LmsFile file;
  final String label;
  final VoidCallback onOpen;
  final VoidCallback? onAskAi;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final name = bestFileName(file.url, file.name.trim());
    final byName = fileKind(name);
    final kind = byName != FileKind.other ? byName : fileKind(file.url);
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && dot < name.length - 1 ? name.substring(dot + 1).toUpperCase() : '';
    final compact = FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14));
    return _Panel(
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          TintIcon(fileKindIcon(kind), color: fileKindColor(kind), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([label, if (ext.isNotEmpty && ext.length <= 5) ext].join(' · '), style: _labelStyle(cs)),
              const SizedBox(height: 2),
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
            ]),
          ),
          if (onAskAi == null)
            IconButton(onPressed: onOpen, tooltip: s['download'], icon: const Icon(Icons.download_rounded)),
        ]),
        if (onAskAi != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpen,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13)),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(s['open'], maxLines: 1)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: onAskAi,
                style: compact,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                // Scaled down rather than cut ("AI'dan so'r…") on small phones.
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(s['askAi'], maxLines: 1)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
