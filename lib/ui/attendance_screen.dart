import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/models.dart';
import '../lms/parsers.dart' show lessonTypeOfName;
import '../lms/snapshot.dart';
import 'widgets.dart';

/// Attendance ("Davomat"): hours used against the semester limit, a
/// per-subject breakdown and every recorded absence (NB).
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  /// Group the absence list by subject instead of by date.
  bool _bySubject = false;

  /// Subject the list is filtered to (tap in the breakdown).
  String? _filter;

  bool _wide = false;
  final _listKey = GlobalKey();

  void _select(String subject) {
    final picked = _filter == subject ? null : subject;
    setState(() => _filter = picked);
    if (picked == null || _wide) return;
    // On phones the list sits below the breakdown: bring it into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _listKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final att = AttendanceSummary.from(snap, app.settings);

    if (snap.isEmpty) {
      return PageScaffold(
        title: s['attendance'],
        lmsPath: '/student/attendance',
        children: [
          if (!app.syncing)
            AppCard(child: EmptyView(icon: Icons.cloud_sync_rounded, title: s['noData'], subtitle: s['atNotSynced'])),
        ],
      );
    }

    final stats = _subjectStats(att, snap);
    final colors = {for (final e in stats) e.name: e.color};
    final filter = stats.any((e) => e.name == _filter) ? _filter : null;
    final absences = [...snap.absences]..sort(_newestFirst);
    final shown = filter == null ? absences : absences.where((a) => a.subject == filter).toList();
    final excused = snap.absences.where((a) => a.excused).length;
    final hasDetails = absences.isNotEmpty;

    return PageScaffold(
      title: s['attendance'],
      subtitle: s.f('atSubtitle', {'h': att.hoursPerAbsence, 'limit': att.limitHours}),
      lmsPath: '/student/attendance',
      children: [
        _Hero(att: att, excused: excused),
        if (att.absences == 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppCard(
              child: EmptyView(
                icon: Icons.celebration_rounded,
                title: s['noAbsences'],
                subtitle: s['atEmptySub'],
                color: Brand.success,
              ),
            ),
          )
        else
          LayoutBuilder(builder: (context, c) {
            _wide = c.maxWidth >= 900;
            final breakdown = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionHeader(
                s['bySubject'],
                action: filter != null ? s['atShowAll'] : null,
                onAction: () => setState(() => _filter = null),
              ),
              _SubjectBreakdown(
                stats: stats,
                hoursPer: att.hoursPerAbsence,
                selected: filter,
                onSelect: hasDetails ? _select : null,
              ),
              if (hasDetails && stats.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Row(children: [
                    Icon(Icons.touch_app_outlined, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s['atTapHint'], style: Theme.of(context).textTheme.bodySmall)),
                  ]),
                ),
            ]);
            final list = KeyedSubtree(
              key: _listKey,
              child: _AbsenceList(
                absences: shown,
                total: absences.length,
                hasDetails: hasDetails,
                bySubject: _bySubject,
                onGrouping: (v) => setState(() => _bySubject = v),
                filter: filter,
                onClearFilter: () => setState(() => _filter = null),
                colors: colors,
                subjectOrder: [for (final e in stats) e.name],
                hoursPer: att.hoursPerAbsence,
              ),
            );
            if (!_wide) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [breakdown, list]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: breakdown),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: list),
            ]);
          }),
      ],
    );
  }
}

// ---------------------------------------------------------------- helpers

int _newestFirst(Absence a, Absence b) {
  final da = a.date, db = b.date;
  if (da == null && db == null) return a.subject.compareTo(b.subject);
  if (da == null) return 1;
  if (db == null) return -1;
  final c = db.compareTo(da);
  return c != 0 ? c : a.themeNumber.compareTo(b.themeNumber);
}

String _cap(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

String _dayLabel(DateTime d, S s) => '${_cap(fmtWeekday(d, s.lang))}, ${fmtDateFull(d, s.lang)}';

/// Ring / notice colour as the limit fills up.
Color _levelColor(double ratio) => ratio >= 0.75
    ? Brand.danger
    : ratio >= 0.5
        ? Brand.warning
        : Brand.success;

class _SubjectStat {
  const _SubjectStat(this.name, this.count, this.excused, this.color);
  final String name;
  final int count;
  final int excused;
  final Color color;
}

/// One entry per subject of [AttendanceSummary.bySubject], most missed first.
List<_SubjectStat> _subjectStats(AttendanceSummary att, LmsSnapshot snap) {
  final out = <_SubjectStat>[];
  for (final e in att.bySubject.entries) {
    final rows = snap.absences.where((a) => a.subject == e.key).toList();
    out.add(_SubjectStat(e.key, e.value, rows.where((a) => a.excused).length, _colorFor(e.key, rows, snap)));
  }
  out.sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out;
}

Color _colorFor(String name, List<Absence> rows, LmsSnapshot snap) {
  for (final a in rows) {
    if (a.subjectId != 0) return subjectColor(a.subjectId);
  }
  for (final c in snap.courses) {
    if (c.subject == name) return subjectColor(c.subjectId);
  }
  return colorForCourseName(name, snap);
}

// ---------------------------------------------------------------- hero

class _Hero extends StatelessWidget {
  const _Hero({required this.att, required this.excused});
  final AttendanceSummary att;
  final int excused;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final c = _levelColor(att.ratio);
    final over = att.hoursUsed - att.limitHours;

    final (IconData noticeIcon, String noticeText, Color tone) = over > 0
        ? (Icons.error_rounded, s.f('atOverLimit', {'n': over}), Brand.danger)
        : att.limitHours > 0 && att.ratio >= 1
            ? (Icons.error_rounded, s['limitReached'], Brand.danger)
            : att.ratio >= 0.75
                ? (
                    Icons.warning_amber_rounded,
                    '${s['limitWarning']} ${s.f('classesLeft', {'n': att.classesLeft})}',
                    Brand.danger
                  )
                : att.ratio >= 0.5
                    ? (Icons.info_rounded, s['atHalfway'], Brand.warning)
                    : (Icons.verified_rounded, s['atOnTrack'], Brand.success);

    final summary = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s['atMissedHours'],
          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 4),
      Text(s.f('hoursUsed', {'used': att.hoursUsed, 'limit': att.limitHours}),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
      if (excused > 0) ...[
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.verified_outlined, size: 15, color: Brand.info),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(s.f('atExcusedIncluded', {'n': excused}),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        ]),
      ],
    ]);

    final metrics = IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _Metric('${att.absences}', s['atNbTotal'], c)),
        const SizedBox(width: 8),
        Expanded(child: _Metric('${att.hoursLeft}', s['atHoursLeft'], Brand.primary)),
        const SizedBox(width: 8),
        Expanded(child: _Metric('${att.classesLeft}', s['atClassesLeft'], Brand.violet)),
      ]),
    );

    final notice = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(radiusS)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(noticeIcon, size: 20, color: tone),
        const SizedBox(width: 10),
        Expanded(
          child: Text(noticeText, style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface, height: 1.3)),
        ),
      ]),
    );

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 640;
        final ring = Ring(
          value: att.ratio,
          color: c,
          size: wide ? 136 : 116,
          stroke: wide ? 13 : 11,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${att.hoursUsed}',
                style: TextStyle(
                    fontSize: wide ? 36 : 30, fontWeight: FontWeight.w800, color: c, height: 1.1, letterSpacing: -1)),
            Text(s.f('atOfLimit', {'limit': att.limitHours}),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          ]),
        );
        if (wide) {
          return Column(children: [
            Row(children: [
              ring,
              const SizedBox(width: 24),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  summary,
                  const SizedBox(height: 16),
                  metrics,
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            notice,
          ]);
        }
        return Column(children: [
          Row(children: [ring, const SizedBox(width: 16), Expanded(child: summary)]),
          const SizedBox(height: 16),
          metrics,
          const SizedBox(height: 12),
          notice,
        ]);
      }),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(radiusS)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.4)),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.2, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- by subject

class _SubjectBreakdown extends StatelessWidget {
  const _SubjectBreakdown({required this.stats, required this.hoursPer, required this.selected, this.onSelect});
  final List<_SubjectStat> stats;
  final int hoursPer;
  final String? selected;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final maxCount = stats.fold<int>(1, (m, e) => e.count > m ? e.count : m);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const Divider(indent: 16, endIndent: 16),
          _SubjectRow(
            stat: stats[i],
            share: stats[i].count / maxCount,
            hours: stats[i].count * hoursPer,
            selected: stats[i].name == selected,
            onTap: onSelect == null ? null : () => onSelect?.call(stats[i].name),
          ),
        ],
      ]),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.stat, required this.share, required this.hours, required this.selected, this.onTap});
  final _SubjectStat stat;
  final double share;
  final int hours;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Ink(
        color: selected ? stat.color.withValues(alpha: 0.10) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: stat.color, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(stat.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Text('${stat.count} ${s['nb']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(selected ? Icons.filter_alt_rounded : Icons.chevron_right_rounded,
                    size: 18, color: selected ? stat.color : cs.onSurfaceVariant),
              ],
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Row(children: [
                Expanded(child: Bar(value: share, color: stat.color, height: 6)),
                const SizedBox(width: 10),
                Text(s.f('atHours', {'n': hours}),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ]),
            ),
            if (stat.excused > 0)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 6),
                child: Text(s.f('atExcusedShort', {'n': stat.excused}),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.info)),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- absence list

class _AbsenceList extends StatelessWidget {
  const _AbsenceList({
    required this.absences,
    required this.total,
    required this.hasDetails,
    required this.bySubject,
    required this.onGrouping,
    required this.filter,
    required this.onClearFilter,
    required this.colors,
    required this.subjectOrder,
    required this.hoursPer,
  });

  final List<Absence> absences; // already filtered, newest first
  final int total;
  final bool hasDetails;
  final bool bySubject;
  final ValueChanged<bool> onGrouping;
  final String? filter;
  final VoidCallback onClearFilter;
  final Map<String, Color> colors;
  final List<String> subjectOrder;
  final int hoursPer;

  Color _color(String subject, Absence? a) =>
      colors[subject] ?? (a != null && a.subjectId != 0 ? subjectColor(a.subjectId) : subjectPalette.first);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;

    if (!hasDetails) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(s['absenceList']),
        AppCard(
          child: EmptyView(
            icon: Icons.info_outline_rounded,
            title: s['atNoDetails'],
            subtitle: s['atNoDetailsSub'],
            color: Brand.info,
          ),
        ),
      ]);
    }

    // Groups in display order.
    final groups = <({String title, Color? color, List<Absence> items})>[];
    if (bySubject) {
      final map = <String, List<Absence>>{};
      for (final a in absences) {
        map.putIfAbsent(a.subject, () => []).add(a);
      }
      final order = [...subjectOrder.where(map.containsKey), ...map.keys.where((k) => !subjectOrder.contains(k))];
      for (final name in order) {
        final items = map[name] ?? const <Absence>[];
        groups.add((title: name, color: _color(name, items.firstOrNull), items: items));
      }
    } else {
      final map = <DateTime?, List<Absence>>{};
      for (final a in absences) {
        final d = a.date;
        map.putIfAbsent(d == null ? null : dateOnly(d), () => []).add(a);
      }
      for (final e in map.entries) {
        final d = e.key;
        groups.add((title: d == null ? s['atNoDate'] : _dayLabel(d, s), color: null, items: e.value));
      }
    }

    final picked = filter;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(s['absenceList']),
      Row(children: [
        Expanded(
          child: Text(
            '${absences.length}${picked != null ? ' / $total' : ''} ${s['nb']} · ${s.f('atHours', {'n': absences.length * hoursPer})}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, icon: const Icon(Icons.event_rounded, size: 18), label: Text(s['atDate'])),
            ButtonSegment(value: true, icon: const Icon(Icons.menu_book_rounded, size: 18), label: Text(s['atSubject'])),
          ],
          selected: {bySubject},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onSelectionChanged: (v) => onGrouping(v.first),
        ),
      ]),
      if (picked != null) ...[
        const SizedBox(height: 10),
        _FilterPill(text: picked, color: _color(picked, null), onClear: onClearFilter),
      ],
      for (final g in groups) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (g.color != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: g.color, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(g.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Text('${g.items.length} ${s['nb']} · ${s.f('atHours', {'n': g.items.length * hoursPer})}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          ]),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < g.items.length; i++) ...[
              if (i > 0) const Divider(indent: 66, endIndent: 14),
              _AbsenceRow(
                a: g.items[i],
                color: _color(g.items[i].subject, g.items[i]),
                hours: hoursPer,
                showSubject: !bySubject,
              ),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.text, required this.color, required this.onClear});
  final String text;
  final Color color;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onClear,
        child: Tooltip(
          message: s['atShowAll'],
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.filter_alt_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(width: 6),
              Icon(Icons.close_rounded, size: 16, color: color),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AbsenceRow extends StatelessWidget {
  const _AbsenceRow({required this.a, required this.color, required this.hours, required this.showSubject});
  final Absence a;
  final Color color;
  final int hours;

  /// true: subject is the title (list grouped by date); false: the date is.
  final bool showSubject;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final type = lessonTypeOfName(a.lessonType);
    final rawType = a.lessonType?.trim() ?? '';
    final tone = a.excused ? Brand.info : Brand.danger;
    final theme = a.theme?.trim() ?? '';
    final topic = [if (a.themeNumber > 0) '#${a.themeNumber}', if (theme.isNotEmpty) theme].join(' · ');
    final date = a.date;
    final hasTags = type != null || rawType.isNotEmpty || a.excused;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(radiusS)),
          child: a.excused
              ? Icon(Icons.verified_rounded, size: 20, color: tone)
              : Text(s['nb'], style: TextStyle(color: tone, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showSubject)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(a.subject.isEmpty ? '—' : a.subject,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ])
            else
              Text(date == null ? s['atNoDate'] : _dayLabel(date, s),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (topic.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
            if (hasTags) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (type != null)
                  Tag(lessonTypeName(type, s), color: lessonTypeColor(type), icon: lessonTypeIcon(type))
                else if (rawType.isNotEmpty)
                  Tag(rawType, color: cs.onSurfaceVariant),
                if (a.excused) Tag(s['atExcused'], color: Brand.info, icon: Icons.verified_outlined),
              ]),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Text(s.f('atHours', {'n': hours}), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tone)),
      ]),
    );
  }
}
