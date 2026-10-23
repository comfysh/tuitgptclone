import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ai/chat_models.dart';
import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../lms/changes.dart';
import 'courses_screen.dart' show CourseDetailPage;
import 'deadlines_screen.dart' show showAssignmentSheet;
import 'files.dart' show downloadAndOpen;
import 'lms_web_page.dart';
import 'nav.dart';
import 'news_screen.dart' show NewsDetailPage;
import 'widgets.dart';

/// "Ask": one box to search everything (tasks, courses, teacher files, exams,
/// news, pages) or to ask the AI, which gets your LMS data with the question.
/// The middle button on phones, Ctrl+K or the box at the top of the sidebar on PC.
class AskPalette {
  AskPalette._();

  /// The palette on screen, if any (Ctrl+K twice opens it once).
  static _AskPanelState? _shown;

  static Future<void> open(BuildContext context) async {
    if (_shown?.mounted ?? false) return;
    if (MediaQuery.sizeOf(context).width >= 840) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          alignment: Alignment.topCenter,
          insetPadding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 640, height: 540, child: _AskPanel(host: context, keyboard: true)),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: FractionallySizedBox(heightFactor: 0.9, child: _AskPanel(host: context, keyboard: false)),
        ),
      );
    }
  }
}

/// One line in the palette.
class _Entry {
  const _Entry(this.icon, this.color, this.title, this.run, {this.subtitle, this.keywords = ''});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  /// More words it is found by (pages: their names in all three languages).
  final String keywords;

  /// Runs with the page that opened the palette (the palette is closed first).
  final void Function(BuildContext host) run;
}

/// Lower case, one kind of apostrophe (o‘, o', oʻ…), single spaces.
String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp('[‘’ʻʼ`´]'), "'").replaceAll(RegExp(r'\s+'), ' ').trim();

/// Every word of the query appears in the text; 2 when the text starts with it.
int _score(String query, String text) {
  final t = _norm(text);
  final words = _norm(query).split(' ');
  if (!words.every(t.contains)) return 0;
  return t.startsWith(words.first) ? 2 : 1;
}

class _AskPanel extends StatefulWidget {
  const _AskPanel({required this.host, required this.keyboard});

  /// The page that opened the palette; entries run there.
  final BuildContext host;

  /// PC: arrow keys move a highlight, Enter opens it.
  final bool keyboard;

  @override
  State<_AskPanel> createState() => _AskPanelState();
}

class _AskPanelState extends State<_AskPanel> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _index = 0;

  static const _rowHeight = 58.0;

  @override
  void initState() {
    super.initState();
    AskPalette._shown = this;
    _query.addListener(() => setState(() => _index = 0));
  }

  @override
  void dispose() {
    if (AskPalette._shown == this) AskPalette._shown = null;
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(_Entry e) {
    final host = widget.host;
    Navigator.of(context).pop();
    if (host.mounted) e.run(host);
  }

  void _ask(BuildContext host, String prompt) =>
      host.read<NavController>().go(Dest.assistant, payload: ChatLaunch(prompt, send: true));

  List<(String, List<_Entry>)> _groups(S s) {
    final app = context.read<AppState>();
    final snap = app.snapshot;
    final q = _query.text.trim();
    final now = DateTime.now();
    final withContext = app.settings.aiUseLmsContext && !snap.isEmpty;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant; // neutral icons, light and dark

    final pages = <_Entry>[
      for (final d in Dest.values)
        _Entry(destInfo[d]!.icon, muted, s[destInfo[d]!.key], (host) {
          if (d == Dest.lms) {
            LmsWebPage.open(host);
          } else {
            host.read<NavController>().go(d);
          }
        },
            subtitle: switch (hubOf(d)) { null || Hub.today => null, final h => s[hubInfo[h]!.key] },
            keywords: [
              for (final lang in S.languages.keys) ...[
                S(lang)[destInfo[d]!.key],
                S(lang)[destInfo[d]!.tab],
                if (hubOf(d) case final h?) S(lang)[hubInfo[h]!.key],
              ],
            ].join(' ')),
    ];

    if (q.isEmpty) {
      final hasExam = snap.finals.any((f) => f.startsAt?.isAfter(now) ?? false);
      final prompts = withContext
          ? [
              (Icons.assignment_late_outlined, Brand.warning, 'chSugDue', 'chSugDueQ'),
              (Icons.calendar_month_outlined, Brand.primary, 'chSugTomorrow', 'chSugTomorrowQ'),
              (Icons.view_week_outlined, Brand.info, 'chSugWeek', 'qpPlanWeek'),
              if (hasExam) (Icons.fact_check_outlined, Brand.violet, 'chSugExam', 'chSugExamQ'),
              (Icons.insights_rounded, Brand.success, 'chSugGrades', 'chSugGradesQ'),
            ]
          : [
              (Icons.lightbulb_outline_rounded, Brand.warning, 'chSugExplain', 'chSugExplainQ'),
              (Icons.quiz_outlined, Brand.violet, 'chSugQuiz', 'chSugQuizQ'),
            ];
      return [
        (s['askSuggest'], [
          for (final p in prompts) _Entry(p.$1, p.$2, s[p.$3], (host) => _ask(host, s[p.$4])),
          _Entry(Icons.forum_outlined, muted, s['askOpenChat'], (host) => host.read<NavController>().go(Dest.assistant)),
        ]),
        (s['askGoTo'], pages),
        (s['askActions'], [
          _Entry(Icons.refresh_rounded, muted, s['refresh'], (host) => unawaited(host.read<AppState>().refresh())),
        ]),
      ];
    }

    List<_Entry> best(List<(int, _Entry)> scored, [int max = 5]) {
      scored.sort((a, b) => b.$1.compareTo(a.$1));
      return [for (final e in scored.take(max)) e.$2];
    }

    final tasks = <(int, _Entry)>[];
    for (final a in snap.assignments.sortedByDeadline()) {
      final sc = _score(q, '${a.title} ${a.courseName} ${a.taskType ?? ''}');
      if (sc == 0) continue;
      final due = a.deadline == null ? null : '${s['deadline']}: ${fmtDateTime(a.deadline!, s.lang)}';
      tasks.add((
        sc + (isOpenTask(a) ? 1 : 0),
        _Entry(Icons.assignment_outlined, Brand.primary, a.title, (host) => showAssignmentSheet(host, a),
            subtitle: [a.courseName, ?due].join(' · ')),
      ));
    }

    final courses = <(int, _Entry)>[
      for (final c in snap.courses)
        if (_score(q, '${c.subject} ${c.teachers.join(' ')}') case final sc when sc > 0)
          (sc, _Entry(Icons.school_outlined, courseColor(c.id, snap), c.subject, (host) => CourseDetailPage.open(host, c),
              subtitle: c.teachers.isEmpty ? null : c.teachers.join(', '))),
    ];

    final files = <(int, _Entry)>[
      for (final f in libraryFiles(snap))
        if (_score(q, '${f.file.name} ${f.course.subject} ${f.context}') case final sc when sc > 0)
          (sc, _Entry(Icons.description_outlined, Brand.info, f.file.name, (host) => downloadAndOpen(host, f.file.url, f.file.name),
              subtitle: [f.course.subject, if (f.context.isNotEmpty) f.context].join(' · '))),
    ];

    final exams = <(int, _Entry)>[
      for (final f in snap.finals)
        if (_score(q, '${f.subject} ${f.room ?? ''}') case final sc when sc > 0)
          (sc, _Entry(Icons.fact_check_outlined, Brand.violet, f.subject, (host) => host.read<NavController>().go(Dest.exams),
              subtitle: [if (f.startsAt != null) fmtDateTime(f.startsAt!, s.lang), ?f.room].join(' · '))),
    ];

    final news = <(int, _Entry)>[
      for (final n in snap.news)
        if (_score(q, '${n.title} ${n.body ?? ''}') case final sc when sc > 0)
          (sc, _Entry(Icons.campaign_outlined, muted, n.title, (host) => NewsDetailPage.open(host, n),
              subtitle: n.date == null ? null : fmtDate(n.date!, s.lang))),
    ];

    final goTo = <(int, _Entry)>[
      for (final p in pages)
        if (_score(q, '${p.title} ${p.subtitle ?? ''} ${p.keywords}') case final sc when sc > 0) (sc, p),
    ];

    return [
      ('', [
        _Entry(Icons.auto_awesome_rounded, Brand.primary, s.f('askAiQuery', {'q': q}), (host) => _ask(host, q),
            subtitle: withContext ? s['askAiSub'] : null),
      ]),
      (s['askGoTo'], best(goTo, 3)),
      (s['deadlines'], best(tasks)),
      (s['coursesShort'], best(courses, 4)),
      (s['navFiles'], best(files)),
      (s['exams'], best(exams, 3)),
      (s['news'], best(news, 3)),
    ];
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, List<_Entry> flat) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      if (flat.isEmpty) return KeyEventResult.handled;
      setState(() => _index = (_index + (k == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, flat.length - 1));
      _reveal();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Keeps the highlighted line in view (lines have a fixed height; group
  /// titles are not counted, so this errs towards showing a bit more).
  void _reveal() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final top = _index * _rowHeight;
    if (top < pos.pixels) {
      _scroll.jumpTo(top.clamp(0, pos.maxScrollExtent));
    } else if (top + _rowHeight * 2 > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo((top + _rowHeight * 2 - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final groups = [for (final g in _groups(s)) if (g.$2.isNotEmpty) g];
    final flat = [for (final g in groups) ...g.$2];
    final index = flat.isEmpty ? 0 : _index.clamp(0, flat.length - 1);
    final onlyAsk = _query.text.trim().isNotEmpty && flat.length == 1;

    var i = 0;
    final rows = <Widget>[];
    for (final g in groups) {
      if (g.$1.isNotEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(g.$1.toUpperCase(),
              style: TextStyle(fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        ));
      }
      for (final e in g.$2) {
        final at = i++;
        rows.add(_Row(entry: e, highlighted: widget.keyboard && at == index, onTap: () => _run(e)));
      }
    }
    if (onlyAsk) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(s['askNothing'], style: TextStyle(color: cs.onSurfaceVariant)),
      ));
    }

    return Material(
      color: cs.surface,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(children: [
            Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Focus(
                onKeyEvent: (node, e) => _onKey(node, e, flat),
                child: TextField(
                  controller: _query,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 17),
                  decoration: InputDecoration(
                    hintText: s['askHint'],
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    if (flat.isNotEmpty) _run(flat[widget.keyboard ? index : 0]);
                  },
                ),
              ),
            ),
            IconButton(
              tooltip: s['close'],
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.only(bottom: 12), children: rows),
        ),
        if (widget.keyboard) ...[
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(s['askKeys'], style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.highlighted, required this.onTap});
  final _Entry entry;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: highlighted ? cs.surfaceContainerHighest : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: _AskPanelState._rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              TintIcon(entry.icon, color: entry.color, size: 34, iconSize: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (entry.subtitle != null && entry.subtitle!.isNotEmpty)
                    Text(entry.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ]),
              ),
              if (highlighted) Icon(Icons.keyboard_return_rounded, size: 16, color: cs.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}
