import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/chat_models.dart';
import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../lms/changes.dart';
import '../lms/models.dart';
import 'files.dart';
import 'lms_web_page.dart';
import 'nav.dart';
import 'widgets.dart';

enum _Filter { all, notSubmitted, submitted, graded, overdue }

class DeadlinesScreen extends StatefulWidget {
  const DeadlinesScreen({super.key});

  @override
  State<DeadlinesScreen> createState() => _DeadlinesScreenState();
}

class _DeadlinesScreenState extends State<DeadlinesScreen> {
  _Filter _filter = _Filter.notSubmitted;
  int? _course;

  bool _match(Assignment a, _Filter f) => switch (f) {
        _Filter.all => true,
        _Filter.notSubmitted => a.status == AssignmentStatus.notSubmitted && !a.isOverdue,
        _Filter.submitted => a.status == AssignmentStatus.submitted,
        _Filter.graded => a.status == AssignmentStatus.graded,
        _Filter.overdue => a.isOverdue,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    // Forget a course filter that no longer exists (e.g. after changing semester).
    final course = app.snapshot.courses.any((c) => c.id == _course) ? _course : null;
    final all = app.snapshot.assignments.where((a) => course == null || a.courseId == course).toList();
    final shown = all.where((a) => _match(a, _filter)).toList().sortedByDeadline();
    if (_filter == _Filter.graded || _filter == _Filter.all) {
      // Most recent first for finished work.
      shown.sort((a, b) => (b.deadline ?? DateTime(0)).compareTo(a.deadline ?? DateTime(0)));
    }
    final labels = {
      _Filter.all: s['all'],
      _Filter.notSubmitted: s['notSubmitted'],
      _Filter.submitted: s['submitted'],
      _Filter.graded: s['graded'],
      _Filter.overdue: s['overdue'],
    };

    return PageScaffold(
      title: s['deadlines'],
      lmsPath: '/student/my-courses',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in _Filter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${labels[f]} · ${all.where((a) => _match(a, f)).length}'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        if (app.snapshot.courses.length > 1)
          DropdownButton<int?>(
            value: course,
            isExpanded: true,
            hint: Text(s['courses']),
            items: [
              DropdownMenuItem(value: null, child: Text(s['all'])),
              for (final c in app.snapshot.courses)
                DropdownMenuItem(value: c.id, child: Text(c.subject, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _course = v),
          ),
        const SizedBox(height: 8),
        if (shown.isEmpty && !app.snapshot.isEmpty)
          EmptyState(icon: Icons.task_alt, text: s['noData'])
        else
          Card(child: Column(children: [for (final a in shown) AssignmentTile(a)])),
      ],
    );
  }
}

class AssignmentTile extends StatelessWidget {
  const AssignmentTile(this.a, {super.key, this.dense = false, this.showCourse = true});
  final Assignment a;
  final bool dense;
  final bool showCourse;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final (icon, color) = switch (a.status) {
      AssignmentStatus.graded => (Icons.verified, ratioColor(a.grade, a.maxGrade, cs)),
      AssignmentStatus.submitted => (Icons.upload_file, lmsBlue),
      AssignmentStatus.notSubmitted => a.isOverdue
          ? (Icons.error_outline, cs.error)
          : (Icons.radio_button_unchecked, const Color(0xFFE09A1A)),
    };
    String? due;
    if (a.deadline != null) {
      final left = a.deadline!.difference(now);
      due = left.isNegative
          ? '${fmtDateTime(a.deadline!, s.lang)} · ${s['duePassed']}'
          : '${fmtDateTime(a.deadline!, s.lang)} · ${s.f('dueIn', {'t': fmtDuration(left, s.lang)})}';
    }
    final urgent = a.status == AssignmentStatus.notSubmitted &&
        a.deadline != null &&
        a.deadline!.isAfter(now) &&
        a.deadline!.difference(now) < const Duration(hours: 24);
    return ListTile(
      dense: dense,
      leading: Icon(icon, color: color),
      title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (showCourse) a.courseName, if (due != null) due].join('\n'),
        style: urgent ? TextStyle(color: cs.error, fontWeight: FontWeight.w600) : null,
      ),
      isThreeLine: showCourse && due != null && !dense,
      trailing: a.maxGrade != null
          ? Pill('${fmtNum(a.grade)}/${fmtNum(a.maxGrade)}', color: a.isGraded ? color : cs.outline)
          : null,
      onTap: () => showAssignmentSheet(context, a),
    );
  }
}

Future<void> showAssignmentSheet(BuildContext context, Assignment a) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => _AssignmentSheet(a),
  );
}

class _AssignmentSheet extends StatefulWidget {
  const _AssignmentSheet(this.a);
  final Assignment a;

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

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final a = this.a;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(a.courseName, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Pill(switch (a.status) {
              AssignmentStatus.graded => s['graded'],
              AssignmentStatus.submitted => s['submitted'],
              AssignmentStatus.notSubmitted => a.isOverdue ? s['overdue'] : s['notSubmitted'],
            }),
            if (a.failed) Pill(s['failedTask'], color: cs.error),
            if (a.maxGrade != null)
              Pill('${s['grade']}: ${fmtNum(a.grade)} / ${fmtNum(a.maxGrade)}', color: ratioColor(a.grade, a.maxGrade, cs)),
          ]),
          const SizedBox(height: 12),
          InfoRow(s['type'], a.taskType),
          InfoRow(s['teacher'], a.teacher),
          InfoRow(
              s['deadline'],
              a.deadline == null
                  ? null
                  : '${fmtDateTime(a.deadline!, s.lang)}'
                      '${a.deadline!.isAfter(DateTime.now()) ? ' (${s.f('dueIn', {'t': fmtDuration(a.deadline!.difference(DateTime.now()), s.lang)})})' : ''}'),
          const Divider(height: 28),
          if (a.taskFile != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(s['taskFile']),
              subtitle: Text(a.taskFile!.name),
              trailing: const Icon(Icons.download),
              onTap: () => downloadAndOpen(context, a.taskFile!.url, a.taskFile!.name, onStatus: _setStatus),
            ),
          if (a.uploadedFile != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.upload_file),
              title: Text(s['yourAnswer']),
              subtitle: Text(a.uploadedFile!.name),
              trailing: const Icon(Icons.download),
              onTap: () => downloadAndOpen(context, a.uploadedFile!.url, a.uploadedFile!.name, onStatus: _setStatus),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (a.canUpload)
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_busy ? s['uploading'] : (a.isSubmitted ? s['replaceAnswer'] : s['uploadAnswer'])),
              )
            else if (!a.isGraded && a.uploadId == null && !a.isSubmitted)
              Text(s['uploadClosed'], style: TextStyle(color: cs.outline)),
            FilledButton.tonalIcon(onPressed: _askAi, icon: const Icon(Icons.auto_awesome), label: Text(s['askAi'])),
            OutlinedButton.icon(
              onPressed: () => LmsWebPage.open(context, '/student/my-courses/show/${a.courseId}'),
              icon: const Icon(Icons.open_in_browser),
              label: Text(s['openInLms']),
            ),
          ]),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_statusBusy)
                  const Padding(
                    padding: EdgeInsets.only(right: 10, top: 2),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Expanded(
                  child: SelectableText(_status!,
                      style: TextStyle(color: _statusError ? cs.error : cs.onSurfaceVariant)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
