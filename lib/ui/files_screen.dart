import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/chat_models.dart';
import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../lms/models.dart';
import '../lms/snapshot.dart';
import 'files.dart';
import 'nav.dart';
import 'widgets.dart';

/// All teacher files of the semester: search, filter by kind and course,
/// open them or hand them to the AI assistant.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

/// What a row is busy with.
enum _Act { open, ai }

/// A library file plus the values the filters need.
class _Item {
  _Item(this.f, this.order)
      : kind = _kindOf(f),
        hay = '${f.file.name}\n${f.context}\n${f.course.subject}'.toLowerCase();
  final LibraryFile f;
  final int order; // position in libraryFiles(), keeps the sort stable
  final FileKind kind;
  final String hay; // lower-cased text the search looks in
}

/// The URL decides the kind; links without an extension fall back to the name.
FileKind _kindOf(LibraryFile f) {
  final k = f.kind;
  return k == FileKind.other ? fileKind(f.file.name) : k;
}

/// Newest first; undated files last; then by lesson type and number.
int _byDate(_Item a, _Item b) {
  final da = a.f.date, db = b.f.date;
  if (da != null && db != null) {
    final c = db.compareTo(da);
    if (c != 0) return c;
  } else if (da != null) {
    return -1;
  } else if (db != null) {
    return 1;
  }
  final ta = a.f.lessonType?.index ?? 99, tb = b.f.lessonType?.index ?? 99;
  if (ta != tb) return ta.compareTo(tb);
  final na = a.f.lessonNumber ?? 0, nb = b.f.lessonNumber ?? 0;
  if (na != nb) return nb.compareTo(na);
  return a.order.compareTo(b.order);
}

String _kindLabel(FileKind k, S s) => s[switch (k) {
      FileKind.pdf => 'flKindPdf',
      FileKind.slides => 'flKindSlides',
      FileKind.doc => 'flKindDocs',
      FileKind.sheet => 'flKindSheets',
      FileKind.archive => 'flKindArchives',
      FileKind.video => 'flKindVideo',
      FileKind.image => 'flKindImages',
      FileKind.other => 'flKindOther',
    }];

/// "{n} files" with the right plural form ([base] + One / Few / Many).
String _count(S s, String base, int n) {
  final form = switch (s.lang) {
    'ru' => n % 10 == 1 && n % 100 != 11
        ? 'One'
        : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14))
            ? 'Few'
            : 'Many',
    _ => n == 1 ? 'One' : 'Many',
  };
  return s.f('$base$form', {'n': n});
}

class _FilesScreenState extends State<FilesScreen> {
  /// Files per course shown before "Show all".
  static const _collapsed = 6;

  final _search = TextEditingController();
  String _query = '';
  FileKind? _kind;
  int? _course;
  bool _tasksOnly = false;
  final _expanded = <int>{};
  final _busy = <String, _Act>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _kind = null;
      _course = null;
      _tasksOnly = false;
    });
  }

  Future<void> _open(LibraryFile f) async {
    final url = f.file.url;
    if (_busy.containsKey(url)) return;
    setState(() => _busy[url] = _Act.open);
    try {
      await downloadAndOpen(context, url, f.file.name);
    } finally {
      if (mounted) setState(() => _busy.remove(url));
    }
  }

  /// Same hand-over as the course and task screens: fetch the file, then open
  /// the AI chat with a prompt and the file attached.
  Future<void> _askAi(LibraryFile f) async {
    final url = f.file.url;
    if (_busy.containsKey(url)) return;
    final s = S.read(context);
    final nav = context.read<NavController>();
    final navigator = Navigator.of(context);
    setState(() => _busy[url] = _Act.ai);
    try {
      final got = await fetchForAi(context, url, f.file.name);
      if (got == null || !mounted) return;
      final topic = f.context.trim().isEmpty ? f.file.name : f.context.trim();
      final prompt = f.fromTask
          ? '${s['qpExplain']}.\n\n${s['assignments']}: $topic\n${f.course.subject}'
          : f.lessonType == LessonType.lecture
              ? '${s['qpSummarize']}: $topic (${f.course.subject})'
              : '${s['qpExplain']}.\n\n$topic (${f.course.subject})';
      navigator.popUntil((r) => r.isFirst);
      nav.go(Dest.assistant, payload: ChatLaunch(prompt, fileName: got.$1, bytes: got.$2));
    } finally {
      if (mounted) setState(() => _busy.remove(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final lib = libraryFiles(snap);
    final items = [for (var i = 0; i < lib.length; i++) _Item(lib[i], i)];

    // Forget filters that no longer apply (e.g. after changing semester).
    final course = items.any((e) => e.f.course.id == _course) ? _course : null;
    final kind = items.any((e) => e.kind == _kind) ? _kind : null;
    final hasTaskFiles = items.any((e) => e.f.fromTask);
    final tasksOnly = _tasksOnly && hasTaskFiles;
    final q = _query.trim().toLowerCase();

    bool byText(_Item e) => q.isEmpty || e.hay.contains(q);
    bool byTask(_Item e) => !tasksOnly || e.f.fromTask;
    bool byKind(_Item e) => kind == null || e.kind == kind;
    bool byCourse(_Item e) => course == null || e.f.course.id == course;

    // Chips list every kind / course of the library; counts follow the other filters.
    final kinds = [for (final k in FileKind.values) if (items.any((e) => e.kind == k)) k];
    final courses = [for (final c in snap.courses) if (items.any((e) => e.f.course.id == c.id)) c];
    final kindCounts = <FileKind, int>{};
    final courseCounts = <int, int>{};
    for (final e in items) {
      if (!byText(e) || !byTask(e)) continue;
      if (byCourse(e)) kindCounts[e.kind] = (kindCounts[e.kind] ?? 0) + 1;
      if (byKind(e)) courseCounts[e.f.course.id] = (courseCounts[e.f.course.id] ?? 0) + 1;
    }

    final shown = items.where((e) => byText(e) && byTask(e) && byKind(e) && byCourse(e)).toList()..sort(_byDate);
    final filtered = q.isNotEmpty || kind != null || course != null || tasksOnly;

    return PageScaffold(
      title: s['navFiles'],
      subtitle: items.isEmpty
          ? null
          : s.f('flSummary', {'files': _count(s, 'flFiles', items.length), 'courses': _count(s, 'flCourses', courses.length)}),
      lmsPath: '/student/my-courses',
      children: [
        if (items.isEmpty) ...[
          if (!(snap.isEmpty && app.syncing))
            AppCard(
              child: snap.isEmpty
                  ? EmptyView(
                      icon: Icons.cloud_sync_rounded,
                      title: s['flNotSynced'],
                      subtitle: s['flNotSyncedSub'],
                      color: Brand.violet)
                  : EmptyView(
                      icon: Icons.folder_off_rounded,
                      title: s['flEmptyTitle'],
                      subtitle: s['flEmptySub'],
                      color: Brand.violet),
            ),
        ] else ...[
          _SearchField(
            controller: _search,
            hint: s['flSearchHint'],
            clearTooltip: s['flClearSearch'],
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          _ChipBar([
            _Choice(
              label: s['all'],
              count: kindCounts.values.fold<int>(0, (a, b) => a + b),
              selected: kind == null,
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.apps_rounded,
              onTap: () => setState(() => _kind = null),
            ),
            for (final k in kinds)
              _Choice(
                label: _kindLabel(k, s),
                count: kindCounts[k] ?? 0,
                selected: kind == k,
                color: fileKindColor(k),
                icon: fileKindIcon(k),
                onTap: () => setState(() => _kind = kind == k ? null : k),
              ),
            if (hasTaskFiles)
              _Choice(
                label: s['flTasksOnly'],
                selected: tasksOnly,
                color: Brand.warning,
                icon: tasksOnly ? Icons.check_circle_rounded : Icons.assignment_outlined,
                onTap: () => setState(() => _tasksOnly = !tasksOnly),
              ),
          ]),
          if (courses.length > 1) ...[
            const SizedBox(height: 8),
            _ChipBar([
              _Choice(
                label: s['flAllCourses'],
                count: courseCounts.values.fold<int>(0, (a, b) => a + b),
                selected: course == null,
                color: Theme.of(context).colorScheme.primary,
                onTap: () => setState(() => _course = null),
              ),
              for (final c in courses)
                _Choice(
                  label: c.subject,
                  count: courseCounts[c.id] ?? 0,
                  selected: course == c.id,
                  color: courseColor(c.id, snap, name: c.subject),
                  dot: true,
                  onTap: () => setState(() => _course = course == c.id ? null : c.id),
                ),
            ]),
          ],
          if (filtered)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 0, 0),
              child: Row(children: [
                Expanded(
                  child: Text(s.f('flShown', {'n': shown.length}),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: _clearFilters,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: Text(s['flClearFilters']),
                ),
              ]),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppCard(
                child: Column(children: [
                  EmptyView(icon: Icons.search_off_rounded, title: s['flNoMatch'], subtitle: s['flNoMatchSub']),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.tonalIcon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      label: Text(s['flClearFilters']),
                    ),
                  ),
                ]),
              ),
            )
          else
            ..._groups(s, snap, shown, collapsible: course == null && q.isEmpty),
        ],
      ],
    );
  }

  /// Section per course (just one when a course is picked), files in pairs.
  List<Widget> _groups(S s, LmsSnapshot snap, List<_Item> shown, {required bool collapsible}) {
    final out = <Widget>[];
    var first = true;
    for (final c in snap.courses) {
      final files = shown.where((e) => e.f.course.id == c.id).toList();
      if (files.isEmpty) continue;
      final open = !collapsible || _expanded.contains(c.id);
      final visible = open ? files : files.take(_collapsed).toList();
      out.add(_GroupHeader(
        title: c.subject,
        count: files.length,
        color: courseColor(c.id, snap, name: c.subject),
        first: first,
      ));
      first = false;
      for (var i = 0; i < visible.length; i += 2) {
        out.add(_Pair(_tile(visible[i]), i + 1 < visible.length ? _tile(visible[i + 1]) : null));
      }
      if (collapsible && files.length > _collapsed) {
        out.add(Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => open ? _expanded.remove(c.id) : _expanded.add(c.id)),
            icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text(open ? s['flShowLess'] : s.f('flShowAll', {'n': files.length})),
          ),
        ));
      }
    }
    return out;
  }

  Widget _tile(_Item e) {
    final busy = _busy[e.f.file.url];
    return _FileTile(
      item: e,
      busy: busy,
      onOpen: busy == null ? () => _open(e.f) : null,
      // The AI can't read archives.
      onAi: e.kind == FileKind.archive ? null : (busy == null ? () => _askAi(e.f) : null),
      showAi: e.kind != FileKind.archive,
    );
  }
}

// ---------------------------------------------------------------- pieces

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hint, required this.clearTooltip, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final String clearTooltip;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusM),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: clearTooltip,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          fillColor: cs.surface,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: cs.primary, width: 1.4)),
        ),
      ),
    );
  }
}

/// Chips in a horizontal scroller on phones, wrapped on wide screens.
class _ChipBar extends StatelessWidget {
  const _ChipBar(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 700) return Wrap(spacing: 8, runSpacing: 8, children: children);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < children.length; i++)
            Padding(padding: EdgeInsets.only(right: i == children.length - 1 ? 0 : 8), child: children[i]),
        ]),
      );
    });
  }
}

/// Selectable filter pill with an icon or colour dot and a count.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
    this.dot = false,
    this.count,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  final bool dot;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusS),
      side: BorderSide(color: selected ? color.withValues(alpha: 0.6) : cs.outlineVariant.withValues(alpha: 0.6)),
    );
    final n = count;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color.withValues(alpha: 0.14) : cs.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 6)],
              if (dot) ...[
                Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? color : cs.onSurface,
                    )),
              ),
              if (n != null) ...[
                const SizedBox(width: 6),
                Text('$n',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? color : cs.onSurfaceVariant,
                    )),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count, required this.color, this.first = false});
  final String title;
  final int count;
  final Color color;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 16 : 22, 4, 10),
      child: Row(children: [
        Container(width: 4, height: 22, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Tag('$count', color: color, icon: Icons.attach_file_rounded),
      ]),
    );
  }
}

/// Two cards side by side with equal height on wide screens, stacked on phones.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a;
  final Widget? b;

  @override
  Widget build(BuildContext context) {
    final b = this.b;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(children: [a, if (b != null) ...[const SizedBox(height: 10), b]]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b ?? const SizedBox.shrink()),
          ]),
        );
      }),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.item, required this.busy, required this.onOpen, required this.onAi, required this.showAi});
  final _Item item;
  final _Act? busy;
  final VoidCallback? onOpen;
  final VoidCallback? onAi;
  final bool showAi;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final f = item.f;
    final type = f.lessonType;
    final number = f.lessonNumber ?? 0;
    final date = f.date;

    // "Lecture 3" / "Task" in its colour, then "theme · 12 Oct".
    final (String? lead, Color leadColor) = f.fromTask
        ? (s['flTask'], Brand.warning)
        : type != null
            ? ('${lessonTypeName(type, s)}${number > 0 ? ' $number' : ''}', lessonTypeColor(type))
            : (null, cs.onSurfaceVariant);
    final rest = [
      if (f.context.trim().isNotEmpty) f.context.trim(),
      if (date != null) fmtDate(date, s.lang),
    ].join(' · ');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      onTap: onOpen,
      child: Row(children: [
        TintIcon(fileKindIcon(item.kind), color: fileKindColor(item.kind), size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(f.file.name.trim().isEmpty ? '—' : f.file.name.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.25)),
            if (lead != null || rest.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  if (lead != null) TextSpan(text: lead, style: TextStyle(color: leadColor, fontWeight: FontWeight.w700)),
                  if (lead != null && rest.isNotEmpty) const TextSpan(text: ' · '),
                  TextSpan(text: rest),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.3, color: cs.onSurfaceVariant),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        if (showAi) ...[
          _ActionButton(
            icon: Icons.auto_awesome_rounded,
            tooltip: s['askAi'],
            color: Brand.violet,
            busy: busy == _Act.ai,
            onPressed: onAi,
          ),
          const SizedBox(width: 6),
        ],
        _ActionButton(
          icon: Icons.download_rounded,
          tooltip: s['download'],
          color: cs.primary,
          busy: busy == _Act.open,
          onPressed: onOpen,
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.tooltip, required this.color, required this.busy, this.onPressed});
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: enabled || busy ? 0.12 : 0.05),
        borderRadius: BorderRadius.circular(radiusS),
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusS),
          onTap: onPressed,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: busy
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: color))
                  : Icon(icon, size: 20, color: enabled ? color : color.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ),
    );
  }
}
