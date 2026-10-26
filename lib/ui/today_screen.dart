import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/changes.dart';
import '../lms/models.dart';
import 'cards.dart' show deadlineLabel;
import 'inbox_screen.dart' show InboxRow;
import 'courses_screen.dart';
import 'deadlines_screen.dart';
import 'nav.dart';
import 'news_screen.dart' show NewsDetailPage;
import 'today_layout.dart';
import 'widgets.dart';
import 'workload.dart';

/// Today as one agenda in time order: classes, the gaps between them, what is
/// due today and exams, with a "now" line. Then what's new, what is due this
/// week, a strip of numbers, tomorrow and more; the student picks which
/// sections show and in what order (lib/ui/today_layout.dart).
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final now = DateTime.now();
    final day = dateOnly(now);
    final nav = context.read<NavController>();

    final classes = classesOn(now, app.settings, snap);
    final tomorrow = classesOn(DateTime(now.year, now.month, now.day + 1), app.settings, snap);
    final open = snap.assignments.where(isOpenTask).toList().sortedByDeadline();
    final endOfDay = DateTime(now.year, now.month, now.day + 1);
    final dueToday = [for (final a in open) if (a.deadline != null && a.deadline!.isBefore(endOfDay)) a];
    final dueWeek = [
      for (final a in open)
        if (a.deadline == null || !a.deadline!.isBefore(endOfDay)) a,
    ];
    final examsToday = [
      for (final f in snap.finals)
        if (f.startsAt != null && !f.startsAt!.isBefore(day) && f.startsAt!.isBefore(endOfDay)) f,
    ];
    final nextExam = (snap.finals.where((f) => f.startsAt != null && !f.startsAt!.isBefore(endOfDay)).toList()
          ..sort((a, b) => a.startsAt!.compareTo(b.startsAt!)))
        .firstOrNull;
    final debt = snap.contracts.where((c) => c.current && (c.debt ?? 0) > 0).firstOrNull;

    final agenda = _Agenda(
      now: now,
      classes: classes,
      due: dueToday,
      exams: examsToday,
      onClass: (slot) {
        final c = slot.courseId == null ? null : snap.courseById(slot.courseId!);
        if (c != null) CourseDetailPage.open(context, c);
      },
    );
    final week = _DueWeek(tasks: dueWeek.take(6).toList(), total: dueWeek.length, now: now);
    final fresh = [for (final i in app.inbox) if (!i.read) i];
    final numbers = _Numbers(open: open.length);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => app.refresh(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final cs = Theme.of(context).colorScheme;
                // Every section; "Customize Today" decides which show and in what order.
                final parts = <TodaySection, List<Widget>>{
                  TodaySection.agenda: [
                    SectionHeader(s['tdAgenda'], action: s['schedule'], onAction: () => nav.go(Dest.schedule)),
                    agenda,
                  ],
                  // Unread updates from the Inbox, newest first.
                  TodaySection.whatsNew: [
                    if (fresh.isNotEmpty) ...[
                      SectionHeader(s['tdWhatsNew'], action: s.f('ibNew', {'n': fresh.length}), onAction: () => nav.go(Dest.inbox)),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          for (final (i, item) in fresh.take(3).indexed) ...[
                            if (i > 0) Divider(height: 1, indent: 64, color: cs.outlineVariant),
                            InboxRow(item: item, showDay: true),
                          ],
                        ]),
                      ),
                    ],
                  ],
                  TodaySection.due: [
                    SectionHeader(s['tdDueNext'], action: s['all'], onAction: () => nav.go(Dest.deadlines)),
                    week,
                  ],
                  TodaySection.numbers: [const SizedBox(height: 12), numbers],
                  TodaySection.nextExam: [
                    if (nextExam != null) ...[
                      const SizedBox(height: 12),
                      _Line(
                        icon: Icons.fact_check_outlined,
                        color: Brand.danger,
                        title: '${s['nextExam']}: ${nextExam.subject}',
                        subtitle: [
                          '${fmtWeekday(nextExam.startsAt!, s.lang)}, ${fmtDate(nextExam.startsAt!, s.lang)}',
                          if (nextExam.from != null) nextExam.from!,
                          if (nextExam.room != null) nextExam.room!,
                        ].join(' · '),
                        onTap: () => nav.go(Dest.exams),
                      ),
                    ],
                  ],
                  TodaySection.debt: [
                    if (debt != null) ...[
                      const SizedBox(height: 12),
                      _Line(
                        icon: Icons.account_balance_wallet_outlined,
                        color: Brand.danger,
                        title: s['tdDebt'],
                        subtitle: s.f('tdDebtSub', {'amount': '${fmtMoney(debt.debt!)} ${debt.currency ?? ''}'.trim(), 'year': debt.year}),
                        onTap: () => nav.go(Dest.profile),
                      ),
                    ],
                  ],
                  TodaySection.tomorrow: [
                    SectionHeader(s['tdTomorrow'], padding: const EdgeInsets.fromLTRB(2, 18, 2, 8)),
                    _Tomorrow(slots: tomorrow),
                  ],
                  TodaySection.workload: [const WorkloadCard(onToday: true)],
                  TodaySection.attendance: [
                    SectionHeader(s['tlAttendance'], action: s['all'], onAction: () => nav.go(Dest.attendance)),
                    const _AttendanceCard(),
                  ],
                  TodaySection.news: [
                    if (snap.news.isNotEmpty) ...[
                      SectionHeader(s['tlNews'], action: s['all'], onAction: () => nav.go(Dest.news)),
                      _NewsCard(items: snap.news.take(2).toList()),
                    ],
                  ],
                };
                final shown = [for (final (t, on) in todayLayout(app.settings)) if (on) t];
                final left = [for (final t in shown) if (!wide || isDayColumn(t)) ...parts[t]!];
                final right = [for (final t in shown) if (wide && !isDayColumn(t)) ...parts[t]!];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _Masthead(now: now, name: snap.info?.fullName, photo: snap.info?.photo, showWeek: snap.schedule.isNotEmpty),
                    const SizedBox(height: 6),
                    const SyncBanner(),
                    if (!snap.isEmpty) ...[
                      if (wide && left.isNotEmpty && right.isNotEmpty)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 11, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                          const SizedBox(width: 24),
                          Expanded(flex: 9, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                        ])
                      else ...[
                        ...left,
                        ...right,
                      ],
                      if (snap.updatedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Text(s.f('updated', {'time': fmtAgo(snap.updatedAt, s)}),
                              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- masthead

class _Masthead extends StatelessWidget {
  const _Masthead({required this.now, this.name, this.photo, required this.showWeek});
  final DateTime now;
  final String? name;
  final String? photo;
  final bool showWeek;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final side = weekSideFor(now, app.settings, app.snapshot);
    final greeting = now.hour < 12
        ? s['goodMorning']
        : now.hour < 18
            ? s['goodAfternoon']
            : s['goodEvening'];
    final parts = (name ?? '').split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final first = parts.length > 1 ? parts[1] : (parts.isNotEmpty ? parts[0] : '');
    final firstName = first.isEmpty ? '' : first[0].toUpperCase() + first.substring(1).toLowerCase();
    final weekday = fmtWeekday(now, s.lang);

    ImageProvider? img;
    final p = photo;
    if (p != null && p.startsWith('data:image')) {
      try {
        img = MemoryImage(base64Decode(p.substring(p.indexOf(',') + 1)));
      } catch (_) {}
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            [firstName.isEmpty ? greeting : '$greeting, $firstName', if (showWeek) side == WeekSide.right ? s['evenWeek'] : s['oddWeek']]
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text('${weekday.isEmpty ? '' : weekday[0].toUpperCase() + weekday.substring(1)}, ${fmtDate(now, s.lang)}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineMedium),
        ]),
      ),
      const SizedBox(width: 8),
      HeaderButton(icon: Icons.tune_rounded, tooltip: s['tlCustomize'], onPressed: () => showTodayCustomizer(context)),
      HeaderButton(icon: Icons.refresh_rounded, tooltip: s['refresh'], busy: app.syncing, onPressed: () => app.refresh()),
      GestureDetector(
        onTap: () => context.read<NavController>().go(Dest.profile),
        child: CircleAvatar(
          radius: 20,
          backgroundColor: cs.surfaceContainerHighest,
          backgroundImage: img,
          child: img == null ? Icon(Icons.person_outline_rounded, color: cs.onSurfaceVariant, size: 22) : null,
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- agenda

enum _Kind { klass, gap, due, exam }

class _Entry {
  final _Kind kind;
  final DateTime at;
  final DateTime? end;
  final ClassSlot? slot;
  final Assignment? task;
  final ExamFinal? exam;
  const _Entry(this.kind, this.at, {this.end, this.slot, this.task, this.exam});
}

/// The day in time order with a "now" rule between the past and the rest.
class _Agenda extends StatelessWidget {
  const _Agenda({required this.now, required this.classes, required this.due, required this.exams, required this.onClass});
  final DateTime now;
  final List<ClassSlot> classes;
  final List<Assignment> due;
  final List<ExamFinal> exams;
  final void Function(ClassSlot) onClass;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final entries = <_Entry>[];
    for (var i = 0; i < classes.length; i++) {
      final c = classes[i];
      if (i > 0) {
        final prevEnd = classes[i - 1].end;
        if (c.start.difference(prevEnd).inMinutes >= 20) entries.add(_Entry(_Kind.gap, prevEnd, end: c.start));
      }
      entries.add(_Entry(_Kind.klass, c.start, end: c.end, slot: c));
    }
    for (final a in due) {
      entries.add(_Entry(_Kind.due, a.deadline!, task: a));
    }
    for (final f in exams) {
      entries.add(_Entry(_Kind.exam, f.startsAt!, exam: f));
    }
    entries.sort((a, b) => a.at.compareTo(b.at));

    if (entries.isEmpty) {
      return AppCard(
        child: EmptyView(icon: Icons.wb_sunny_outlined, title: s['tdFreeDay'], subtitle: s['tdFreeDaySub'], color: Brand.success),
      );
    }

    // The "now" rule goes before the first entry that hasn't started yet, so a
    // class in progress sits above it (its bar shows how far along it is).
    final nowAt = entries.indexWhere((e) => e.at.isAfter(now));
    final running = entries.any((e) => (e.end ?? e.at).isAfter(now));
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i == nowAt) rows.add(_NowRule(now: now));
      final e = entries[i];
      final past = !(e.end ?? e.at).isAfter(now);
      rows.add(Opacity(opacity: past ? 0.5 : 1, child: _row(context, e, s, cs)));
      if (i < entries.length - 1 && i + 1 != nowAt) rows.add(Divider(height: 1, indent: 72, color: cs.outlineVariant));
    }
    if (nowAt == -1) {
      rows.add(_NowRule(now: now));
      if (!running) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(72, 4, 16, 14),
          child: Text(s['tdDayDone'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ));
      }
    }
    return AppCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: rows));
  }

  Widget _row(BuildContext context, _Entry e, S s, ColorScheme cs) {
    switch (e.kind) {
      case _Kind.gap:
        final min = e.end!.difference(e.at).inMinutes;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            SizedBox(width: 56, child: Text(fmtTime(e.at), style: _timeStyle(cs, muted: true))),
            Icon(Icons.more_vert_rounded, size: 16, color: cs.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(s.f('tdGap', {'t': fmtDuration(Duration(minutes: min), s.lang)}),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontStyle: FontStyle.italic)),
            ),
          ]),
        );
      case _Kind.klass:
        final slot = e.slot!;
        final color = _subjectColorOf(context, slot);
        final active = slot.isNow(now);
        final meta = [
          lessonTypeName(slot.item.type, s),
          if (slot.item.room != null) slot.item.room!,
          if (slot.item.stream != null) slot.item.stream!,
        ].join(' · ');
        return InkWell(
          onTap: () => onClass(slot),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 56,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtTime(slot.start), style: _timeStyle(cs)),
                  Text(fmtTime(slot.end), style: _timeStyle(cs, muted: true, small: true)),
                ]),
              ),
              Container(width: 3, height: 40, margin: const EdgeInsets.only(right: 12, top: 2), color: color),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(slot.item.displaySubject,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Tag(s.f('tdLeftShort', {'t': fmtDuration(slot.end.difference(now), s.lang)}), color: cs.primary),
                    ] else if (slot.start.isAfter(now) && slot.start.difference(now) < const Duration(hours: 2)) ...[
                      const SizedBox(width: 8),
                      Tag(s.f('tdInShort', {'t': fmtDuration(slot.start.difference(now), s.lang)}), color: cs.onSurfaceVariant),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  if (slot.topic != null) ...[
                    const SizedBox(height: 4),
                    Text(slot.topic!,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.3)),
                  ],
                  if (active) ...[
                    const SizedBox(height: 8),
                    Bar(
                      value: now.difference(slot.start).inSeconds / slot.end.difference(slot.start).inSeconds.clamp(1, 1 << 30),
                      color: cs.primary,
                      height: 3,
                    ),
                  ],
                ]),
              ),
            ]),
          ),
        );
      case _Kind.due:
        final a = e.task!;
        return InkWell(
          onTap: () => showAssignmentSheet(context, a),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(children: [
              SizedBox(width: 56, child: Text(fmtTime(a.deadline!), style: _timeStyle(cs, color: Brand.danger))),
              const Icon(Icons.flag_outlined, size: 18, color: Brand.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${s['tdDue']} · ${a.courseName}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
        );
      case _Kind.exam:
        final f = e.exam!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(children: [
            SizedBox(width: 56, child: Text(fmtTime(e.at), style: _timeStyle(cs))),
            const Icon(Icons.fact_check_outlined, size: 18, color: Brand.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['tdExam']}: ${f.subject}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (f.room != null) Text(f.room!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ]),
            ),
          ]),
        );
    }
  }
}

Color _subjectColorOf(BuildContext context, ClassSlot slot) {
  final snap = context.read<AppState>().snapshot;
  return slot.courseId != null
      ? courseColor(slot.courseId!, snap, name: slot.item.displaySubject)
      : colorForCourseName(slot.item.displaySubject, snap);
}

TextStyle _timeStyle(ColorScheme cs, {bool muted = false, bool small = false, Color? color}) => TextStyle(
      fontWeight: small ? FontWeight.w500 : FontWeight.w700,
      fontSize: small ? 12 : 14.5,
      color: color ?? (muted ? cs.onSurfaceVariant : cs.onSurface),
      fontFeatures: tabular,
    );

class _NowRule extends StatelessWidget {
  const _NowRule({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    const c = Brand.danger;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(children: [
        SizedBox(
          width: 56,
          child: Text(fmtTime(now), style: const TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12, fontFeatures: tabular)),
        ),
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: c, shape: BoxShape.circle)),
        Expanded(child: Container(height: 1.4, color: c)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- this week

class _DueWeek extends StatelessWidget {
  const _DueWeek({required this.tasks, required this.total, required this.now});
  final List<Assignment> tasks;
  final int total;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    if (tasks.isEmpty) {
      return AppCard(child: EmptyView(icon: Icons.task_alt_rounded, title: s['tdAllDone'], subtitle: s['tdAllDoneSub'], color: Brand.success));
    }
    final rows = <Widget>[];
    for (var i = 0; i < tasks.length; i++) {
      final a = tasks[i];
      final d = a.deadline;
      final (label, color) = deadlineLabel(a, s, cs, now: now);
      rows.add(InkWell(
        onTap: () => showAssignmentSheet(context, a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Column(children: [
                Text(d == null ? '—' : weekdayShort(d.weekday, s),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5, fontWeight: FontWeight.w600)),
                Text(d == null ? '' : '${d.day}',
                    style: TextStyle(fontFamily: serif, fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface, height: 1.1, fontFeatures: tabular)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(a.courseName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Tag(label, color: color),
          ]),
        ),
      ));
      if (i < tasks.length - 1) rows.add(Divider(height: 1, indent: 68, color: cs.outlineVariant));
    }
    if (total > tasks.length) {
      rows.add(Divider(height: 1, color: cs.outlineVariant));
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Text(s.f('nfMore', {'n': total - tasks.length}), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
      ));
    }
    return AppCard(padding: const EdgeInsets.symmetric(vertical: 2), child: Column(children: rows));
  }
}

// ---------------------------------------------------------------- numbers

/// Open tasks · NB hours · GPA · rating in one bordered strip.
/// Attendance at a glance: hours used against the limit and what is left.
class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final att = AttendanceSummary.from(app.snapshot, app.settings);
    final color = att.ratio >= 0.75 ? Brand.danger : (att.ratio >= 0.5 ? Brand.warning : Brand.success);
    return AppCard(
      onTap: () => context.read<NavController>().go(Dest.attendance),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${att.hoursUsed}',
              style: TextStyle(fontFamily: serif, fontSize: 26, fontWeight: FontWeight.w700, color: color, height: 1, fontFeatures: tabular)),
          Text(' / ${att.limitHours} ${s['tdNbHours']}',
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: att.ratio, minHeight: 6, color: color, backgroundColor: cs.surfaceContainerHighest),
        ),
        const SizedBox(height: 8),
        Text(att.classesLeft > 0 ? s.f('tlCanMiss', {'n': att.classesLeft}) : s['tlNoneLeft'],
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// The latest LMS news, title and date.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.items});
  final List<NewsItem> items;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (final (i, n) in items.indexed) ...[
          if (i > 0) Divider(height: 1, indent: 16, color: cs.outlineVariant),
          InkWell(
            onTap: () => NewsDetailPage.open(context, n),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (n.date != null)
                      Text(fmtDate(n.date!, s.lang), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.outline),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.open});
  final int open;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    final nav = context.read<NavController>();
    final att = AttendanceSummary.from(app.snapshot, app.settings);
    final ratings = [for (final p in app.snapshot.coursePages.values) ?_ratingPercent(p.rating)];
    final avg = ratings.isEmpty ? null : ratings.reduce((a, b) => a + b) / ratings.length;
    final gpa = app.snapshot.planSummary?.gpa ?? estimatedGpa(app.snapshot.studyPlan);
    final cells = [
      (s['tdOpenTasks'], '$open', cs.onSurface, Dest.deadlines),
      (s['tdNbHours'], '${att.hoursUsed}/${att.limitHours}', att.ratio >= 0.75 ? Brand.danger : cs.onSurface, Dest.attendance),
      (s['tdGpa'], gpa?.toStringAsFixed(2) ?? '—', cs.onSurface, Dest.grades),
      (s['tdAvgRating'], avg == null ? '—' : '${fmtNum(avg)}%', cs.onSurface, Dest.courses),
    ];
    Widget cell((String, String, Color, Dest) c) => InkWell(
          onTap: () => nav.go(c.$4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.$2,
                  maxLines: 1,
                  style: TextStyle(fontFamily: serif, fontSize: 22, fontWeight: FontWeight.w700, color: c.$3, fontFeatures: tabular)),
              const SizedBox(height: 2),
              Text(c.$1,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5, height: 1.2)),
            ]),
          ),
        );
    return AppCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(builder: (context, box) {
        final two = box.maxWidth < 380;
        final divider = VerticalDivider(width: 1, color: cs.outlineVariant);
        if (!two) {
          return IntrinsicHeight(
            child: Row(children: [
              for (var i = 0; i < cells.length; i++) ...[if (i > 0) divider, Expanded(child: cell(cells[i]))],
            ]),
          );
        }
        return Column(children: [
          IntrinsicHeight(child: Row(children: [Expanded(child: cell(cells[0])), divider, Expanded(child: cell(cells[1]))])),
          Divider(height: 1, color: cs.outlineVariant),
          IntrinsicHeight(child: Row(children: [Expanded(child: cell(cells[2])), divider, Expanded(child: cell(cells[3]))])),
        ]);
      }),
    );
  }
}

double? _ratingPercent(CourseRating r) {
  final max = r.max ?? 0, a = r.achieved;
  if (max <= 0) return null;
  return r.ratingPercent ?? (a == null ? null : a / max * 100);
}

// ---------------------------------------------------------------- tomorrow, lines

class _Tomorrow extends StatelessWidget {
  const _Tomorrow({required this.slots});
  final List<ClassSlot> slots;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    if (slots.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Text(s['tdNoClassesTomorrow'], style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.f('tdTomorrowLine', {'n': slots.length, 'time': fmtTime(slots.first.start)}),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final c in slots)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(children: [
              SizedBox(width: 48, child: Text(fmtTime(c.start), style: _timeStyle(cs, muted: true, small: true))),
              Container(width: 3, height: 14, margin: const EdgeInsets.only(right: 8), color: _subjectColorOf(context, c)),
              Expanded(
                child: Text(
                    '${c.item.displaySubject}${c.item.room != null ? ' · ${c.item.room}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: cs.outline),
      ]),
    );
  }
}
