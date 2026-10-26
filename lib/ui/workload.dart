import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import 'widgets.dart';

/// Plan › Deadlines: how busy the next eight weeks are, one column per week
/// (open tasks in green ink, exams in plum), with the busiest week named.
/// Columns are labelled with the week's Monday; this week is underlined.
class WorkloadCard extends StatelessWidget {
  const WorkloadCard({super.key, this.onToday = false});

  /// On Today it sits among other sections (normal spacing above its title).
  final bool onToday;

  static const _barMax = 64.0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final weeks = workload(app.snapshot, now);
    final busiest = busiestWeek(weeks);
    final top = weeks.fold<int>(1, (m, w) => w.weight > m ? w.weight : m);

    Widget column(int i, WeekLoad w) {
      final h = w.weight == 0 ? 0.0 : (w.weight / top * _barMax).clamp(6.0, _barMax);
      final examPart = w.weight == 0 ? 0.0 : h * (w.exams * 3 / w.weight);
      final isBusiest = identical(w, busiest);
      return Expanded(
        child: Tooltip(
          message: '${fmtDate(w.monday, s.lang)} · ${s['wlTasks']}: ${w.tasks} · ${s['wlExams']}: ${w.exams}',
          child: Column(children: [
            SizedBox(
              height: 18,
              child: w.weight == 0
                  ? null
                  : Text('${w.tasks + w.exams}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isBusiest ? FontWeight.w800 : FontWeight.w600,
                        color: isBusiest ? cs.onSurface : cs.onSurfaceVariant,
                        fontFeatures: tabular,
                      )),
            ),
            SizedBox(
              height: _barMax,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: w.weight == 0
                    ? Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 6), color: cs.outlineVariant)
                    : Container(
                        height: h,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
                        child: Column(children: [
                          if (examPart > 0) Container(height: examPart, color: Brand.violet),
                          Expanded(child: Container(color: Brand.primary)),
                        ]),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            // Monday's date; this week in bold ink, underlined.
            Container(
              padding: const EdgeInsets.only(bottom: 1),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: i == 0 ? cs.onSurface : Colors.transparent, width: 2)),
              ),
              child: Text('${w.monday.day}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w500,
                    color: i == 0 ? cs.onSurface : cs.onSurfaceVariant,
                    fontFeatures: tabular,
                  )),
            ),
            Text(i == 0 || w.monday.day <= 7 ? fmtMonthShort(w.monday, s.lang) : '',
                style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
          ]),
        ),
      );
    }

    Widget key(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(s['wlTitle'], padding: onToday ? null : const EdgeInsets.fromLTRB(2, 4, 2, 8)),
      AppCard(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (final (i, w) in weeks.indexed) column(i, w)]),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              key(Brand.primary, s['wlTasks']),
              key(Brand.violet, s['wlExams']),
              Text(
                busiest == null
                    ? s['wlEmpty']
                    : s.f('wlBusiest', {
                        'range':
                            '${fmtDate(busiest.monday, s.lang)} – ${fmtDate(busiest.monday.add(const Duration(days: 6)), s.lang)}'
                      }),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
            ]),
          ),
        ]),
      ),
      if (!onToday) const SizedBox(height: 14),
    ]);
  }
}
