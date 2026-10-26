import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../lms/models.dart';
import '../lms/snapshot.dart';
import 'courses_screen.dart';
import 'nav.dart';
import 'widgets.dart';

/// Grades, GPA and the study plan.
class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  /// What-if picks: plan row key -> expected grade (3..5). UI state only.
  final Map<String, int> _picks = {};

  /// Semester cards the user opened or closed (label -> open).
  final Map<String, bool> _open = {};

  /// Semester shown in the simulator (label).
  String? _simSem;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final nav = context.read<NavController>();
    final plan = snap.studyPlan;
    final groups = _groupPlan(plan);
    final currentIdx = _currentSemester(groups, snap);
    final current = currentIdx == null ? null : groups[currentIdx].label;

    // ---- programme totals (same rule as the LMS: a 2 earns no credits / points)
    final estimate = estimatedGpa(plan);
    final lmsGpa = snap.planSummary?.gpa;
    final gpa = lmsGpa ?? estimate;
    var totalCredits = 0, earnedCredits = 0, gradedCredits = 0;
    for (final d in plan) {
      final c = d.credits ?? 0;
      if (c <= 0) continue;
      totalCredits += c;
      final g = d.grade;
      if (g != null) {
        gradedCredits += c;
        if (g >= 3) earnedCredits += c;
      }
    }
    final graded = plan.where((d) => d.grade != null).length;

    // ---- what-if simulator
    final simGroups = [
      for (final g in groups)
        if (g.items.any(_simulatable)) g,
    ];
    String? shown = _simSem;
    if (shown == null || !simGroups.any((g) => g.label == shown)) {
      // Default: the current semester, or the next one that still has ungraded subjects.
      final ahead = currentIdx == null ? null : simGroups.where((g) => groups.indexOf(g) >= currentIdx).firstOrNull;
      shown = (ahead ?? simGroups.firstOrNull)?.label;
    }
    final simRows = [
      for (final g in simGroups)
        if (g.label == shown) ...g.items.where(_simulatable),
    ];
    var points = (gpa ?? 0) * gradedCredits;
    var credits = gradedCredits;
    for (final g in groups) {
      for (final r in g.items) {
        final pick = _picks[r.key];
        final c = r.d.credits ?? 0;
        if (pick == null || r.d.grade != null || c <= 0) continue;
        points += c * (pick >= 3 ? pick : 0);
        credits += c;
      }
    }
    final projected = credits == 0 ? null : points / credits;

    final hasPlan = plan.isNotEmpty;
    final allOpen = groups.isNotEmpty && groups.every((g) => _isOpen(g.label, current));

    final thisSemester = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(s['grThisSemester'], action: s['coursesShort'], onAction: () => nav.go(Dest.courses)),
      _ThisSemesterCard(snap: snap),
    ]);
    final whatIf = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(s['grWhatIf']),
      _WhatIfCard(
        groups: simGroups,
        shown: shown,
        rows: simRows,
        picks: _picks,
        base: gpa,
        projected: projected,
        onShow: (label) => setState(() => _simSem = label),
        onPick: (key, g) => setState(() {
          if (g == null) {
            _picks.remove(key);
          } else {
            _picks[key] = g;
          }
        }),
        onFill: (g) => setState(() {
          for (final r in simRows) {
            _picks[r.key] = g;
          }
        }),
        onReset: () => setState(_picks.clear),
      ),
    ]);
    final distribution = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(s['grDistribution']),
      _DistributionCard(plan: plan),
    ]);
    final semesters = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        s['grSemesters'],
        action: groups.length > 1 ? (allOpen ? s['grCollapseAll'] : s['grExpandAll']) : null,
        onAction: () => setState(() {
          for (final g in groups) {
            _open[g.label] = !allOpen;
          }
        }),
      ),
      for (final g in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SemesterCard(
            group: g,
            current: g.label == current,
            open: _isOpen(g.label, current),
            onToggle: () => setState(() => _open[g.label] = !_isOpen(g.label, current)),
          ),
        ),
    ]);

    return PageScaffold(
      title: s['navGrades'],
      lmsPath: '/student/study-plan',
      children: [
        if (snap.isEmpty && !app.syncing)
          AppCard(
            child: EmptyView(icon: Icons.workspace_premium_rounded, title: s['grNoPlan'], subtitle: s['grNoPlanSub']),
          ),
        if (!snap.isEmpty && !hasPlan) ...[
          AppCard(
            child: EmptyView(
              icon: Icons.workspace_premium_rounded,
              title: s['grNoPlan'],
              subtitle: s['grNoPlanSub'],
              color: Brand.violet,
            ),
          ),
          if (snap.courses.isNotEmpty) thisSemester,
        ],
        if (!snap.isEmpty && hasPlan) ...[
          _GpaHero(
            gpa: gpa,
            fromLms: lmsGpa != null,
            estimate: estimate,
            earned: earnedCredits,
            totalCredits: totalCredits,
            graded: graded,
            subjects: plan.length,
            current: snap.planSummary?.currentGpa,
            currentLabel: snap.planSummary?.currentGpaLabel,
          ),
          if ((snap.planSummary?.notice ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const TintIcon(Icons.info_outline_rounded, color: Brand.info, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text(snap.planSummary?.notice?.trim() ?? '')),
              ]),
            ),
          ],
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 900) {
              return Column(children: [thisSemester, whatIf, distribution, semesters]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [thisSemester, whatIf])),
              const SizedBox(width: 16),
              Expanded(child: Column(children: [distribution, semesters])),
            ]);
          }),
        ],
        if (snap.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(s.f('updated', {'time': fmtAgo(snap.updatedAt, s)}),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  bool _isOpen(String label, String? current) => _open[label] ?? label == current;
}

// ---------------------------------------------------------------- data helpers

/// One row of the study plan with a key that stays stable for the what-if picks.
class _PlanRow {
  const _PlanRow(this.key, this.d);
  final String key;
  final Discipline d;
}

class _SemGroup {
  const _SemGroup(this.stats, this.items);
  final SemesterStats stats;
  final List<_PlanRow> items;
  String get label => stats.semester;
}

/// Subjects without a grade that count towards the GPA (they have credits).
bool _simulatable(_PlanRow r) => r.d.grade == null && (r.d.credits ?? 0) > 0;

/// Study plan grouped by semester, in programme order (I, II, III …).
List<_SemGroup> _groupPlan(List<Discipline> plan) {
  final items = <String, List<_PlanRow>>{};
  for (var i = 0; i < plan.length; i++) {
    final d = plan[i];
    final label = d.semester ?? '—';
    items.putIfAbsent(label, () => []).add(_PlanRow('$i|$label|${d.title}', d));
  }
  final stats = {for (final st in studyPlanStats(plan)) st.semester: st};
  final groups = [
    for (final e in items.entries)
      if (stats[e.key] case final st?) _SemGroup(st, e.value),
  ];
  // Stable sort by semester number; unnumbered ones keep their order at the end.
  final indexed = groups.indexed.toList()
    ..sort((a, b) {
      final na = semesterNumber(a.$2.label) ?? 1000;
      final nb = semesterNumber(b.$2.label) ?? 1000;
      return na != nb ? na.compareTo(nb) : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

String _norm(String v) => v.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// The semester the student is in: the one whose subjects match this
/// semester's courses; otherwise the first one after the last graded semester.
int? _currentSemester(List<_SemGroup> groups, LmsSnapshot snap) {
  if (groups.isEmpty) return null;
  final names = {for (final c in snap.courses) _norm(c.subject)}..removeWhere((n) => n.length < 3);
  var best = -1, bestHits = 0;
  if (names.isNotEmpty) {
    for (var i = 0; i < groups.length; i++) {
      final hits = groups[i].items.where((r) {
        final t = _norm(r.d.title);
        return t.length >= 3 && names.any((n) => n == t || n.contains(t) || t.contains(n));
      }).length;
      if (hits > bestHits) {
        best = i;
        bestHits = hits;
      }
    }
  }
  if (best >= 0) return best;
  var last = -1;
  for (var i = 0; i < groups.length; i++) {
    if (groups[i].stats.graded > 0) last = i;
  }
  if (last == -1) return 0;
  if (groups[last].stats.progress == SemesterProgress.completed && last + 1 < groups.length) return last + 1;
  return last;
}

/// Rating % of a course, only once it has graded work (max > 0).
double? _ratingPct(CourseRating? r) {
  if (r == null) return null;
  final max = r.max ?? 0;
  if (max <= 0) return null;
  final a = r.achieved;
  return r.ratingPercent ?? (a == null ? null : a / max * 100);
}

String _gpaText(double? v) => v == null ? '—' : v.toStringAsFixed(2);

// ---------------------------------------------------------------- hero

class _GpaHero extends StatelessWidget {
  const _GpaHero({
    required this.gpa,
    required this.fromLms,
    required this.estimate,
    required this.earned,
    required this.totalCredits,
    required this.graded,
    required this.subjects,
    this.current,
    this.currentLabel,
  });
  final double? gpa;
  final bool fromLms;
  final double? estimate;
  final int earned, totalCredits, graded, subjects;
  final double? current;
  final String? currentLabel;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final white70 = Colors.white.withValues(alpha: 0.78);
    final progress = totalCredits > 0 ? earned / totalCredits : (subjects > 0 ? graded / subjects : 0.0);
    final g = gpa, e = estimate, cur = current;
    final curLabel = (currentLabel ?? '').trim();
    return HeroCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(s['grGpa'], style: TextStyle(color: white70, fontWeight: FontWeight.w700)),
              _HeroPill(
                icon: fromLms ? Icons.verified_rounded : Icons.calculate_rounded,
                text: fromLms ? s['grFromLms'] : s['grEstimated'],
              ),
            ]),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(_gpaText(g),
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.1)),
              const SizedBox(width: 6),
              Text('/ 5', style: TextStyle(color: white70, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            if (fromLms && g != null && e != null && (e - g).abs() >= 0.01)
              Text(s.f('grEstimateNote', {'gpa': _gpaText(e)}), style: TextStyle(color: white70, fontSize: 12.5)),
            if (cur != null)
              Text('${curLabel.isEmpty ? s['grCurrentGpa'] : curLabel}: ${_gpaText(cur)}',
                  style: TextStyle(color: white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _HeroMeta(Icons.stars_rounded, s.f('grCreditsLine', {'a': earned, 'b': totalCredits})),
            const SizedBox(height: 6),
            _HeroMeta(Icons.task_alt_rounded, s.f('grGradedLine', {'a': graded, 'b': subjects})),
          ]),
        ),
        const SizedBox(width: 12),
        Ring(
          value: progress,
          color: Colors.white,
          track: Colors.white.withValues(alpha: 0.22),
          size: 92,
          stroke: 8,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${(progress * 100).round()}%',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white)),
            Text(s['grDone'], style: TextStyle(fontSize: 11, color: white70, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        ),
      ]);
}

// ---------------------------------------------------------------- this semester

class _ThisSemesterCard extends StatelessWidget {
  const _ThisSemesterCard({required this.snap});
  final LmsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    if (snap.courses.isEmpty) {
      return AppCard(child: EmptyView(icon: Icons.school_rounded, title: s['grNoCourses'], subtitle: s['grNoCoursesSub']));
    }
    final rows = [
      for (final c in snap.courses)
        (c, _ratingPct(snap.coursePages[c.id]?.rating), standingFor(snap.coursePages[c.id])),
    ];
    final rated = [for (final r in rows) ?r.$2];
    final avg = rated.isEmpty ? null : rated.reduce((a, b) => a + b) / rated.length;
    // Badges show the grade each course is heading for on the work graded so
    // far; the LMS rating also counts tasks that aren't due yet as zero.
    final standing = [for (final r in rows) ?r.$3.percent];
    final expected = standing.isEmpty ? null : gradeForPercent(standing.reduce((a, b) => a + b) / standing.length);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TintIcon(Icons.school_rounded, color: Brand.primary, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((snap.semester?.name ?? '').trim().isEmpty ? s['grThisSemester'] : (snap.semester?.name ?? '').trim(),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                avg == null
                    ? s.f('grSubjectsN', {'n': snap.courses.length})
                    : '${s.f('grSubjectsN', {'n': snap.courses.length})} · ${s.f('grAvgRating', {'pct': fmtNum(avg)})}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
              ),
            ]),
          ),
          if (expected != null) ...[
            const SizedBox(width: 8),
            Tooltip(message: s['grHeadingFor'], child: GradeBadge(expected, size: 36)),
          ],
        ]),
        const SizedBox(height: 8),
        const Divider(),
        for (final r in rows) _CourseGradeRow(course: r.$1, pct: r.$2, expected: r.$3.grade),
      ]),
    );
  }
}

class _CourseGradeRow extends StatelessWidget {
  const _CourseGradeRow({required this.course, required this.pct, required this.expected});
  final Course course;
  final double? pct;
  final int? expected;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = subjectColor(course.subjectId);
    final p = pct;
    return InkWell(
      borderRadius: BorderRadius.circular(radiusS),
      onTap: () => CourseDetailPage.open(context, course),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course.subject,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 6),
              if (p == null)
                Text(s['grNoRating'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))
              else
                Row(children: [
                  Expanded(child: Bar(value: p / 100, color: color, height: 6)),
                  const SizedBox(width: 10),
                  Text('${fmtNum(p)}%',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: cs.onSurfaceVariant)),
                ]),
            ]),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: s['grHeadingFor'],
            child: GradeBadge(expected, size: 34),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- distribution

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.plan});
  final List<Discipline> plan;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final counts = {5: 0, 4: 0, 3: 0, 2: 0};
    for (final d in plan) {
      final g = d.grade;
      if (g == null) continue;
      final k = g >= 5 ? 5 : (g <= 2 ? 2 : g);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return AppCard(
        child: EmptyView(icon: Icons.bar_chart_rounded, title: s['grNoGradesYet'], subtitle: s['grNoGradesYetSub']),
      );
    }
    final labels = {5: s['grExcellent'], 4: s['grGood'], 3: s['grSatisfactory'], 2: s['grFail']};
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.f('grGradedN', {'n': total}), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        // Stacked overview bar.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              for (final g in const [5, 4, 3, 2])
                if ((counts[g] ?? 0) > 0)
                  Expanded(
                    flex: counts[g] ?? 0,
                    child: Container(margin: const EdgeInsets.symmetric(horizontal: 1), color: gradeColor(g, cs)),
                  ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        for (final g in const [5, 4, 3, 2])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              GradeBadge(g, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(labels[g] ?? '$g',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text('${counts[g] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('  ·  ${((counts[g] ?? 0) / total * 100).round()}%',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  Bar(value: (counts[g] ?? 0) / total, color: gradeColor(g, cs), height: 7),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- semesters

class _SemesterCard extends StatelessWidget {
  const _SemesterCard({required this.group, required this.current, required this.open, required this.onToggle});
  final _SemGroup group;
  final bool current;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final st = group.stats;
    final (status, statusColor) = switch (st.progress) {
      SemesterProgress.completed => (s['grCompleted'], Brand.success),
      SemesterProgress.inProgress => (s['grInProgress'], Brand.primary),
      SemesterProgress.upcoming => (s['grUpcoming'], cs.outline),
    };
    final n = semesterNumber(st.semester);
    final gpa = st.gpa;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: n == null
                    ? Icon(Icons.layers_rounded, color: statusColor, size: 22)
                    : Text('$n', style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(st.semester,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    if (current) ...[const SizedBox(width: 8), Tag(s['grCurrent'], color: Brand.primary)],
                  ]),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
                      TextSpan(text: ' · ${s.f('grSemSub', {'credits': st.credits, 'n': st.subjects})}'),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_gpaText(gpa),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: gpa == null ? cs.onSurfaceVariant : gradeColor(gpa.round(), cs))),
                Text(s['grGpa'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final r in group.items) _DisciplineRow(r.d),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        Tag(s.f('grEarnedOf', {'a': st.earnedCredits, 'b': st.credits}),
                            color: Brand.success, icon: Icons.stars_rounded),
                        if (st.failed > 0)
                          Tag(s.f('grFailedN', {'n': st.failed}), color: Brand.danger, icon: Icons.error_outline_rounded),
                      ]),
                    ]),
                  ),
                ]),
        ),
      ]),
    );
  }
}

class _DisciplineRow extends StatelessWidget {
  const _DisciplineRow(this.d);
  final Discipline d;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(d.title,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        const SizedBox(width: 10),
        if (d.credits != null)
          Text('${d.credits} ${s['grCr']}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        GradeBadge(d.grade, size: 30),
      ]),
    );
  }
}

// ---------------------------------------------------------------- what-if simulator

class _WhatIfCard extends StatelessWidget {
  const _WhatIfCard({
    required this.groups,
    required this.shown,
    required this.rows,
    required this.picks,
    required this.base,
    required this.projected,
    required this.onShow,
    required this.onPick,
    required this.onFill,
    required this.onReset,
  });
  final List<_SemGroup> groups;
  final String? shown;
  final List<_PlanRow> rows;
  final Map<String, int> picks;
  final double? base;
  final double? projected;
  final ValueChanged<String> onShow;
  final void Function(String key, int? grade) onPick;
  final ValueChanged<int> onFill;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    // The projection counts picks in every semester, so the count does too.
    final all = [for (final g in groups) ...g.items.where(_simulatable)];
    final picked = all.where((r) => picks.containsKey(r.key)).length;
    final rule = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, size: 15, color: cs.onSurfaceVariant),
      const SizedBox(width: 6),
      Expanded(child: Text(s['grGpaRule'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
    ]);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const TintIcon(Icons.auto_graph_rounded, color: Brand.violet, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(s['grWhatIfSub'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 14),
        if (rows.isEmpty) ...[
          Text(s['grNothingToSim'], style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          rule,
        ] else ...[
          _Projection(base: base, projected: projected, picked: picked, total: all.length),
          if (groups.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in groups)
                ChoiceChip(
                  label: Text(g.label),
                  selected: g.label == shown,
                  onSelected: (_) => onShow(g.label),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(s['grSetAll'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
            for (final g in const [5, 4, 3])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _MiniGradeButton(grade: g, onTap: () => onFill(g)),
              ),
            IconButton(
              tooltip: s['grReset'],
              visualDensity: VisualDensity.compact,
              onPressed: picks.isEmpty ? null : onReset,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ]),
          const Divider(),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.d.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('${r.d.credits ?? 0} ${s['grCr']}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 12),
                _GradePicker(value: picks[r.key], onChanged: (g) => onPick(r.key, g)),
              ]),
            ),
          const SizedBox(height: 8),
          rule,
        ],
      ]),
    );
  }
}

class _Projection extends StatelessWidget {
  const _Projection({required this.base, required this.projected, required this.picked, required this.total});
  final double? base;
  final double? projected;
  final int picked, total;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final p = projected, b = base;
    final delta = (p == null || b == null || picked == 0) ? null : p - b;
    final (String? deltaText, Color deltaColor, IconData? deltaIcon) = switch (delta) {
      null => (null, cs.outline, null),
      final double d when d >= 0.005 => ('+${d.toStringAsFixed(2)}', Brand.success, Icons.arrow_upward_rounded),
      final double d when d <= -0.005 => ('−${(-d).toStringAsFixed(2)}', Brand.danger, Icons.arrow_downward_rounded),
      _ => ('±0.00', cs.outline, Icons.drag_handle_rounded),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.violet.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(radiusM),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s['grProjected'], style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 2),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: p ?? 0),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text(p == null ? '—' : v.toStringAsFixed(2),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: Brand.violet)),
          ),
          if (deltaText != null) Tag(deltaText, color: deltaColor, icon: deltaIcon),
        ]),
        const SizedBox(height: 2),
        Text(
          '${s.f('grNow', {'gpa': _gpaText(b)})} · ${s.f('grPicked', {'n': picked, 'm': total})}',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
        ),
      ]),
    );
  }
}

/// 3 / 4 / 5 segmented picker; tapping the selected grade clears it.
class _GradePicker extends StatelessWidget {
  const _GradePicker({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(radiusS),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final g in const [3, 4, 5])
          Semantics(
            button: true,
            selected: value == g,
            label: '$g',
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onChanged(value == g ? null : g),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == g ? gradeColor(g, cs) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('$g',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: value == g ? Colors.white : gradeColor(g, cs),
                    )),
              ),
            ),
          ),
      ]),
    );
  }
}

class _MiniGradeButton extends StatelessWidget {
  const _MiniGradeButton({required this.grade, required this.onTap});
  final int grade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = gradeColor(grade, Theme.of(context).colorScheme);
    return Material(
      color: c.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text('$grade', style: TextStyle(color: c, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}
