import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/models.dart';
import 'widgets.dart';

class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final now = DateTime.now();
    final finals = app.snapshot.finals;
    final upcoming = finals.where((f) => f.grade == null && (f.startsAt == null || f.startsAt!.isAfter(now.subtract(const Duration(hours: 3))))).toList()
      ..sort((a, b) => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)));
    final done = finals.where((f) => !upcoming.contains(f)).toList()
      ..sort((a, b) => (b.startsAt ?? DateTime(0)).compareTo(a.startsAt ?? DateTime(0)));

    return PageScaffold(
      title: s['exams'],
      lmsPath: '/student/finals',
      children: [
        if (finals.isEmpty && !app.snapshot.isEmpty) EmptyState(icon: Icons.fact_check_outlined, text: s['noExams']),
        if (upcoming.isNotEmpty) ...[
          SectionTitle(s['upcoming']),
          for (final f in upcoming) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ExamCard(f)),
        ],
        if (done.isNotEmpty) ...[
          SectionTitle(s['past']),
          for (final f in done) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ExamCard(f)),
        ],
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard(this.f);
  final ExamFinal f;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final start = f.startsAt;
    String? countdown;
    if (start != null && f.grade == null) {
      final days = dateOnly(start).difference(dateOnly(DateTime.now())).inDays;
      if (days >= 0) {
        countdown = days == 0 ? s['todayLower'] : days == 1 ? s['tomorrow'] : s.f('inDays', {'n': days});
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ScoreBadge(
            text: f.grade?.toString() ?? '—',
            color: f.grade == null ? cs.outline : scoreColor(f.grade, cs),
            size: 56,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.subject, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (countdown != null) Pill(countdown, icon: Icons.timer_outlined, color: cs.error),
                if (f.date != null) Pill(fmtDateFull(f.date!, s.lang), icon: Icons.event),
                if (f.from != null) Pill('${f.from}${f.to != null ? '–${f.to}' : ''}', icon: Icons.access_time),
                if (f.room != null) Pill('${s['room']} ${f.room}', icon: Icons.meeting_room_outlined),
                if (f.stream != null) Pill(f.stream!, icon: Icons.groups_outlined),
                if (f.timeLimit != null && f.timeLimit! > 0) Pill('${f.timeLimit} ${s['minutes']}', icon: Icons.hourglass_bottom),
              ]),
              if (f.testPoints.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(s['testPoints'], style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in f.testPoints) Pill('#${p.number}: ${p.point}', color: cs.secondary),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
