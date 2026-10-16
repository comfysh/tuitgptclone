import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import 'widgets.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final att = AttendanceSummary.from(app.snapshot, app.settings);
    final color = att.ratio >= 1
        ? cs.error
        : att.ratio >= 0.75
            ? const Color(0xFFE09A1A)
            : const Color(0xFF2E9E5B);
    final absences = [...app.snapshot.absences]
      ..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    final maxBy = att.bySubject.values.fold<int>(1, (a, b) => b > a ? b : a);

    return PageScaffold(
      title: s['attendance'],
      lmsPath: '/student/attendance',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: att.ratio,
                      strokeWidth: 10,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.15),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${att.hoursUsed}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
                    Text('/ ${att.limitHours}', style: TextStyle(color: cs.outline)),
                  ]),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.f('hoursUsed', {'used': att.hoursUsed, 'limit': att.limitHours}),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(s.f('hoursLeft', {'left': att.hoursLeft})),
                  const SizedBox(height: 6),
                  Text(s.f('classesLeft', {'n': att.classesLeft}), style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text('${att.absences} ${s['nb']} × ${att.hoursPerAbsence} h',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (att.ratio >= 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(s['limitReached'], style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                    )
                  else if (att.ratio >= 0.75)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(s['limitWarning'], style: const TextStyle(color: Color(0xFFE09A1A))),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        if (att.bySubject.isNotEmpty) ...[
          SectionTitle(s['bySubject']),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                for (final e in (att.bySubject.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text('${e.value} ${s['nb']} · ${e.value * att.hoursPerAbsence} h',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: e.value / maxBy,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                        color: cs.error.withValues(alpha: 0.75),
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        ],
        SectionTitle(s['absenceList']),
        if (absences.isEmpty && !app.snapshot.isEmpty)
          EmptyState(icon: Icons.celebration_outlined, text: s['noAbsences'])
        else
          Card(
            child: Column(children: [
              for (final a in absences)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.errorContainer,
                    child: Text(s['nb'], style: TextStyle(color: cs.onErrorContainer, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(a.subject),
                  subtitle: Text([
                    if (a.date != null) fmtDateFull(a.date!, s.lang),
                    if (a.lessonType != null) a.lessonType!,
                    if (a.theme != null) '#${a.themeNumber} ${a.theme}',
                  ].join(' · ')),
                ),
            ]),
          ),
      ],
    );
  }
}
