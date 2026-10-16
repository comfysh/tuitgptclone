import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/changes.dart';
import '../lms/models.dart';
import 'deadlines_screen.dart';
import 'nav.dart';
import 'schedule_screen.dart';
import 'widgets.dart';

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
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
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
    final today = classesOn(now, app.settings, snap);
    final side = weekSideFor(now, app.settings, snap);
    final current = currentOrNext(today, now);
    final rawFirst = (snap.info?.fullName ?? '').split(RegExp(r'\s+')).skip(1).firstOrNull ?? '';
    final firstName = rawFirst.isEmpty ? '' : rawFirst[0].toUpperCase() + rawFirst.substring(1).toLowerCase();
    final greeting = now.hour < 12
        ? s['goodMorning']
        : now.hour < 18
            ? s['goodAfternoon']
            : s['goodEvening'];

    final upcoming = snap.assignments
        .where((a) => a.deadline != null && a.deadline!.isAfter(now) && !a.isSubmitted && !a.isGraded)
        .toList()
        .sortedByDeadline()
        .take(5)
        .toList();
    final att = AttendanceSummary.from(snap, app.settings);
    final nextExam = (snap.finals.where((f) => f.startsAt != null && f.startsAt!.isAfter(now)).toList()
          ..sort((a, b) => a.startsAt!.compareTo(b.startsAt!)))
        .firstOrNull;

    return PageScaffold(
      title: s['today'],
      children: [
        Text('$greeting${firstName.isNotEmpty ? ', $firstName' : ''}!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Row(children: [
          Text('${fmtWeekday(now, s.lang)}, ${fmtDateFull(now, s.lang)}'),
          const SizedBox(width: 8),
          if (snap.schedule.isNotEmpty) Pill(side == WeekSide.right ? s['evenWeek'] : s['oddWeek']),
        ]),
        const SizedBox(height: 14),
        if (!snap.isEmpty) _NowCard(slot: current, hasClasses: today.isNotEmpty),
        if (today.isNotEmpty) ...[
          SectionTitle(s['classesToday'],
              trailing: TextButton(
                  onPressed: () => context.read<NavController>().go(Dest.schedule), child: Text(s['schedule']))),
          DayTimeline(slots: today, now: now),
        ],
        SectionTitle(s['upcomingDeadlines'],
            trailing: TextButton(
                onPressed: () => context.read<NavController>().go(Dest.deadlines), child: Text(s['all']))),
        if (upcoming.isEmpty)
          Card(child: ListTile(leading: const Icon(Icons.task_alt), title: Text(s['noDeadlines'])))
        else
          Card(
            child: Column(children: [for (final a in upcoming) AssignmentTile(a, dense: true)]),
          ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final cards = [
            _AttendanceMini(att),
            if (nextExam != null) _ExamMini(nextExam),
          ];
          if (c.maxWidth > 640) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final w in cards) ...[Expanded(child: w), if (w != cards.last) const SizedBox(width: 12)],
            ]);
          }
          return Column(children: [
            for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
          ]);
        }),
        if (snap.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.f('updated', {'time': fmtAgo(snap.updatedAt, s)}),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.slot, required this.hasClasses});
  final ClassSlot? slot;
  final bool hasClasses;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final now = DateTime.now();
    if (slot == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.weekend_outlined),
          title: Text(hasClasses ? s['classesDone'] : s['noClassesToday']),
        ),
      );
    }
    final isNow = slot!.isNow(now);
    final color = lessonTypeColor(slot!.item.type);
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(isNow ? s['now'] : s['next'], color: color, icon: isNow ? Icons.circle : Icons.schedule),
            const Spacer(),
            Text(isNow
                ? s.f('endsIn', {'t': fmtDuration(slot!.end.difference(now), s.lang)})
                : s.f('startsIn', {'t': fmtDuration(slot!.start.difference(now), s.lang)})),
          ]),
          const SizedBox(height: 10),
          Text(slot!.item.displaySubject,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Pill('${fmtTime(slot!.start)}–${fmtTime(slot!.end)}', icon: Icons.access_time, color: color),
            Pill(lessonTypeName(slot!.item.type, s), icon: lessonTypeIcon(slot!.item.type), color: color),
            if (slot!.item.room != null) Pill('${s['room']} ${slot!.item.room}', icon: Icons.meeting_room_outlined, color: color),
          ]),
          if (slot!.topic != null) ...[
            const SizedBox(height: 8),
            Text('${s['topic']}: ${slot!.topic}', style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (isNow) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: now.difference(slot!.start).inSeconds / slot!.end.difference(slot!.start).inSeconds,
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ]),
      ),
    );
  }
}

class _AttendanceMini extends StatelessWidget {
  const _AttendanceMini(this.att);
  final AttendanceSummary att;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = att.ratio >= 0.85 ? cs.error : (att.ratio >= 0.6 ? const Color(0xFFE09A1A) : const Color(0xFF2E9E5B));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.read<NavController>().go(Dest.attendance),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.event_busy_outlined),
              const SizedBox(width: 8),
              Text(s['attendance'], style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${att.hoursUsed}/${att.limitHours}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: att.ratio, color: color, minHeight: 8, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 8),
            Text(s.f('classesLeft', {'n': att.classesLeft}), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _ExamMini extends StatelessWidget {
  const _ExamMini(this.f);
  final ExamFinal f;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final days = dateOnly(f.startsAt!).difference(dateOnly(DateTime.now())).inDays;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.read<NavController>().go(Dest.exams),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.assignment_turned_in_outlined),
              const SizedBox(width: 8),
              Text(s['nextExam'], style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Pill(days == 0 ? s['todayLower'] : days == 1 ? s['tomorrow'] : s.f('inDays', {'n': days})),
            ]),
            const SizedBox(height: 10),
            Text(f.subject, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text([
              fmtDateTime(f.startsAt!, s.lang),
              if (f.room != null) '${s['room']} ${f.room}',
            ].join(' · ')),
          ]),
        ),
      ),
    );
  }
}
