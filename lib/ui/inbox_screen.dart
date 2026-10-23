import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/timetable.dart' show dateOnly;
import '../lms/changes.dart';
import '../services/inbox.dart';
import '../services/notifier.dart';
import 'deadlines_screen.dart' show showAssignmentSheet;
import 'files.dart' show downloadAndOpen;
import 'nav.dart';
import 'news_screen.dart' show NewsDetailPage;
import 'widgets.dart';

/// Inbox › Updates: everything that changed in LMS (new tasks, deadlines,
/// grades, NB, exams, teacher files, news), grouped by day, unread first in
/// bold. Tapping an update opens what it is about.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

enum _Filter { all, tasks, grades, nb, exams, files, news }

class _InboxScreenState extends State<InboxScreen> {
  _Filter _filter = _Filter.all;

  static bool _matches(_Filter f, ChangeKind k) => switch (f) {
        _Filter.all => true,
        _Filter.tasks => k == ChangeKind.newAssignment || k == ChangeKind.deadlineChanged,
        _Filter.grades => k == ChangeKind.gradePosted || k == ChangeKind.examGrade,
        _Filter.nb => k == ChangeKind.newAbsence,
        _Filter.exams => k == ChangeKind.examChanged || k == ChangeKind.examGrade,
        _Filter.files => k == ChangeKind.newFile,
        _Filter.news => k == ChangeKind.news,
      };

  String _label(_Filter f, S s) => switch (f) {
        _Filter.all => s['all'],
        _Filter.tasks => s['ibTasks'],
        _Filter.grades => s['ibGrades'],
        _Filter.nb => s['nb'],
        _Filter.exams => s['ibExams'],
        _Filter.files => s['ibFiles'],
        _Filter.news => s['news'],
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final items = app.inbox;
    final unread = app.unread;
    final shown = [for (final i in items) if (_matches(_filter, i.kind)) i];
    final present = {for (final i in items) for (final f in _Filter.values) if (_matches(f, i.kind)) f};

    // Newest day first; inside a day newest first (the list is kept that way).
    final groups = <DateTime, List<InboxItem>>{};
    for (final i in shown) {
      (groups[dateOnly(i.at)] ??= []).add(i);
    }

    return PageScaffold(
      title: s['ibUpdates'],
      subtitle: items.isEmpty ? null : (unread > 0 ? s.f('ibNew', {'n': unread}) : s['ibCaughtUp']),
      actions: [
        if (unread > 0)
          HeaderButton(icon: Icons.done_all_rounded, tooltip: s['ibMarkAll'], onPressed: () => app.markInboxRead()),
      ],
      children: [
        if (items.isEmpty)
          AppCard(child: EmptyView(icon: Icons.inbox_outlined, title: s['ibEmpty'], subtitle: s['ibEmptySub']))
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in _Filter.values)
                if (f == _Filter.all || present.contains(f))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_label(f, s)),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
            ]),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AppCard(child: EmptyView(icon: Icons.filter_alt_off_outlined, title: s['ibNoneHere'])),
            ),
          for (final e in groups.entries) ...[
            SectionHeader(_dayLabel(e.key, s)),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < e.value.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 64, color: Theme.of(context).colorScheme.outlineVariant),
                  InboxRow(item: e.value[i]),
                ],
              ]),
            ),
          ],
        ],
      ],
    );
  }

  static String _dayLabel(DateTime day, S s) {
    final today = dateOnly(DateTime.now());
    if (day == today) return s['today'];
    if (day == today.subtract(const Duration(days: 1))) return s['ibYesterday'];
    return fmtDate(day, s.lang);
  }
}

/// One update: what kind (icon and label), when, about what, and the details.
/// Unread ones are bold with a dot. Also used on Today ("What's new").
class InboxRow extends StatelessWidget {
  const InboxRow({super.key, required this.item, this.showDay = false});
  final InboxItem item;

  /// Show the date too (outside the Inbox's day groups).
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = inboxKindStyle(item.kind, cs);
    final at = item.at;
    final time = showDay && dateOnly(at) != dateOnly(DateTime.now()) ? '${fmtDate(at, s.lang)}, ${fmtTime(at)}' : fmtTime(at);
    final text = Notifier.textOf(item.change, s);
    return InkWell(
      onTap: () => openInboxItem(context, item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TintIcon(icon, color: color, size: 36, iconSize: 19),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${Notifier.headOf(item.kind, s)} · $time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600, fontFeatures: tabular)),
              const SizedBox(height: 2),
              Text(item.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: item.read ? FontWeight.w500 : FontWeight.w700, color: cs.onSurface)),
              if (text.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontFeatures: tabular)),
              ],
            ]),
          ),
          SizedBox(
            width: 18,
            child: item.read
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 6, left: 8),
                    child: Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                  ),
          ),
        ]),
      ),
    );
  }
}

(IconData, Color) inboxKindStyle(ChangeKind k, ColorScheme cs) => switch (k) {
      ChangeKind.newAssignment => (Icons.add_task_rounded, Brand.primary),
      ChangeKind.deadlineChanged => (Icons.update_rounded, Brand.warning),
      ChangeKind.gradePosted => (Icons.workspace_premium_rounded, Brand.success),
      ChangeKind.examGrade => (Icons.emoji_events_outlined, Brand.success),
      ChangeKind.examChanged => (Icons.event_rounded, Brand.violet),
      ChangeKind.newAbsence => (Icons.event_busy_rounded, Brand.danger),
      ChangeKind.newFile => (Icons.description_outlined, Brand.info),
      ChangeKind.news => (Icons.campaign_outlined, cs.onSurfaceVariant),
      ChangeKind.reminder => (Icons.alarm_rounded, Brand.warning),
    };

/// Marks [item] read and opens what it is about: the task, the exam list,
/// attendance, the file or the news article.
Future<void> openInboxItem(BuildContext context, InboxItem item) async {
  final app = context.read<AppState>();
  final nav = context.read<NavController>();
  unawaited(app.markInboxRead(ids: {item.id}));
  final snap = app.snapshot;
  void gone() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.read(context)['ibGone'])));
  switch (item.kind) {
    case ChangeKind.newAssignment || ChangeKind.deadlineChanged || ChangeKind.gradePosted || ChangeKind.reminder:
      final a = taskForChange(snap, item.key);
      if (a == null) return gone();
      await showAssignmentSheet(context, a);
    case ChangeKind.examChanged || ChangeKind.examGrade:
      nav.go(Dest.exams);
    case ChangeKind.newAbsence:
      nav.go(Dest.attendance);
    case ChangeKind.newFile:
      if (!item.key.startsWith('file|')) return gone();
      await downloadAndOpen(context, item.key.substring(5), item.detail);
    case ChangeKind.news:
      final n = snap.news.where((n) => n.key == item.key).firstOrNull;
      if (n == null) return gone();
      await NewsDetailPage.open(context, n);
  }
}
