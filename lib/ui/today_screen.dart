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
import 'cards.dart';
import 'courses_screen.dart';
import 'deadlines_screen.dart';
import 'nav.dart';
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
    final today = classesOn(now, app.settings, snap);
    final side = weekSideFor(now, app.settings, snap);
    final current = currentOrNext(today, now);
    final nav = context.read<NavController>();

    final open = snap.assignments.where(isOpenTask).toList().sortedByDeadline();
    final att = AttendanceSummary.from(snap, app.settings);
    // Same rule as the Courses screen: the LMS percentage, or achieved / max.
    final ratings = [for (final p in snap.coursePages.values) ?_ratingPercent(p.rating)];
    final gpa = snap.planSummary?.gpa ?? estimatedGpa(snap.studyPlan);
    final avgRating = ratings.isEmpty ? null : ratings.reduce((a, b) => a + b) / ratings.length;
    final nextExam = (snap.finals.where((f) => f.startsAt != null && f.startsAt!.isAfter(now)).toList()
          ..sort((a, b) => a.startsAt!.compareTo(b.startsAt!)))
        .firstOrNull;
    final debt = snap.contracts.where((c) => c.current && (c.debt ?? 0) > 0).firstOrNull;

    final stats = [
      StatTile(
        icon: Icons.assignment_rounded,
        value: '${open.length}',
        label: s['tdOpenTasks'],
        color: Brand.primary,
        onTap: () => nav.go(Dest.deadlines),
      ),
      StatTile(
        icon: Icons.event_busy_rounded,
        value: '${att.hoursUsed}/${att.limitHours}',
        label: s['tdNbHours'],
        color: att.ratio >= 0.75 ? Brand.danger : Brand.warning,
        onTap: () => nav.go(Dest.attendance),
      ),
      StatTile(
        icon: Icons.workspace_premium_rounded,
        value: gpa?.toStringAsFixed(2) ?? '—',
        label: s['tdGpa'],
        color: Brand.success,
        onTap: () => nav.go(Dest.grades),
      ),
      StatTile(
        icon: Icons.insights_rounded,
        value: avgRating == null ? '—' : '${fmtNum(avgRating)}%',
        label: s['tdAvgRating'],
        color: Brand.violet,
        onTap: () => nav.go(Dest.courses),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => app.refresh(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _Header(name: snap.info?.fullName, photo: snap.info?.photo),
                  const SizedBox(height: 14),
                  const SyncBanner(),
                  if (!snap.isEmpty) ...[
                    _Hero(now: now, side: side, hasSchedule: snap.schedule.isNotEmpty, slot: current, hasClasses: today.isNotEmpty,
                        tomorrowFirst: classesOn(now.add(const Duration(days: 1)), app.settings, snap).firstOrNull),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, c) {
                      final cols = c.maxWidth >= 720 ? 4 : 2;
                      final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                      return Wrap(spacing: 12, runSpacing: 12, children: [
                        for (final t in stats) SizedBox(width: w, child: t),
                      ]);
                    }),
                    if (debt != null) ...[
                      const SizedBox(height: 12),
                      AppCard(
                        onTap: () => nav.go(Dest.profile),
                        child: Row(children: [
                          const TintIcon(Icons.account_balance_wallet_rounded, color: Brand.danger),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s['tdDebt'], style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(s.f('tdDebtSub', {'amount': '${fmtMoney(debt.debt!)} ${debt.currency ?? ''}', 'year': debt.year}),
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ]),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ]),
                      ),
                    ],
                    LayoutBuilder(builder: (context, c) {
                      final wide = c.maxWidth >= 900;
                      final classes = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SectionHeader(s['classesToday'], action: s['schedule'], onAction: () => nav.go(Dest.schedule)),
                        if (today.isEmpty)
                          AppCard(child: EmptyView(icon: Icons.weekend_rounded, title: s['tdFreeDay'], subtitle: s['tdFreeDaySub']))
                        else
                          DayTimeline(
                            slots: today,
                            now: now,
                            onTapSlot: (slot) {
                              final c = slot.courseId == null ? null : snap.courseById(slot.courseId!);
                              if (c != null) CourseDetailPage.open(context, c);
                            },
                          ),
                      ]);
                      final deadlines = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SectionHeader(s['upcomingDeadlines'], action: s['all'], onAction: () => nav.go(Dest.deadlines)),
                        if (open.isEmpty)
                          AppCard(
                              child: EmptyView(
                                  icon: Icons.task_alt_rounded, title: s['tdAllDone'], subtitle: s['tdAllDoneSub'], color: Brand.success))
                        else
                          for (final a in open.take(5))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: DeadlineCard(a: a, onTap: () => showAssignmentSheet(context, a)),
                            ),
                        if (nextExam != null) ...[
                          SectionHeader(s['nextExam'], action: s['exams'], onAction: () => nav.go(Dest.exams)),
                          _ExamCard(nextExam),
                        ],
                      ]);
                      if (!wide) return Column(children: [classes, deadlines]);
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: classes),
                        const SizedBox(width: 16),
                        Expanded(child: deadlines),
                      ]);
                    }),
                    if (snap.updatedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(s.f('updated', {'time': fmtAgo(snap.updatedAt, s)}),
                            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.name, this.photo});
  final String? name;
  final String? photo;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? s['goodMorning']
        : now.hour < 18
            ? s['goodAfternoon']
            : s['goodEvening'];
    final parts = (name ?? '').split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final first = parts.length > 1 ? parts[1] : (parts.isNotEmpty ? parts[0] : '');
    final firstName = first.isEmpty ? '' : first[0].toUpperCase() + first.substring(1).toLowerCase();

    ImageProvider? img;
    final p = photo;
    if (p != null && p.startsWith('data:image')) {
      try {
        img = MemoryImage(base64Decode(p.substring(p.indexOf(',') + 1)));
      } catch (_) {}
    }
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      GestureDetector(
        onTap: () => context.read<NavController>().go(Dest.profile),
        child: CircleAvatar(
          radius: 24,
          backgroundColor: cs.primary.withValues(alpha: 0.15),
          backgroundImage: img,
          child: img == null ? Icon(Icons.person_rounded, color: cs.primary) : null,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greeting, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          Text(firstName.isEmpty ? s['tdHello'] : firstName,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall),
        ]),
      ),
      HeaderButton(icon: Icons.refresh_rounded, tooltip: s['refresh'], busy: app.syncing, onPressed: () => app.refresh()),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.now,
    required this.side,
    required this.hasSchedule,
    required this.slot,
    required this.hasClasses,
    this.tomorrowFirst,
  });
  final DateTime now;
  final WeekSide side;
  final bool hasSchedule;
  final ClassSlot? slot;
  final bool hasClasses;
  final ClassSlot? tomorrowFirst;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final white70 = Colors.white.withValues(alpha: 0.78);
    final header = Row(children: [
      Expanded(
        child: Text('${fmtWeekday(now, s.lang)}, ${fmtDate(now, s.lang)}',
            style: TextStyle(color: white70, fontWeight: FontWeight.w600)),
      ),
      if (hasSchedule)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
          child: Text(side == WeekSide.right ? s['evenWeek'] : s['oddWeek'],
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
    ]);

    if (slot == null) {
      return HeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          header,
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.nights_stay_rounded, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hasClasses ? s['classesDone'] : s['tdFreeDay'],
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  tomorrowFirst != null
                      ? s.f('tdTomorrowFirst', {'time': fmtTime(tomorrowFirst!.start)})
                      : (hasClasses ? s['tdDoneSub'] : s['tdFreeDaySub']),
                  style: TextStyle(color: white70),
                ),
              ]),
            ),
          ]),
        ]),
      );
    }

    final sl = slot!;
    final isNow = sl.isNow(now);
    final total = sl.end.difference(sl.start).inSeconds;
    final progress = isNow ? now.difference(sl.start).inSeconds / total : 0.0;
    final mins = isNow ? sl.end.difference(now).inMinutes : sl.start.difference(now).inMinutes;
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: isNow ? Colors.white : Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text('${isNow ? s['now'] : s['next']} · ${fmtTime(sl.start)}–${fmtTime(sl.end)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12, color: isNow ? Brand.primaryDeep : Colors.white)),
              ),
              const SizedBox(height: 10),
              Text(sl.item.displaySubject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.4)),
              const SizedBox(height: 8),
              Wrap(spacing: 14, runSpacing: 4, children: [
                _HeroMeta(lessonTypeIcon(sl.item.type), lessonTypeName(sl.item.type, s)),
                if (sl.item.room != null) _HeroMeta(Icons.location_on_rounded, sl.item.room!),
              ]),
              if (sl.topic != null) ...[
                const SizedBox(height: 8),
                Text(sl.topic!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: white70, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Ring(
            value: isNow ? progress : 0,
            color: Colors.white,
            track: Colors.white.withValues(alpha: 0.22),
            size: 86,
            stroke: 8,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(mins >= 120 ? '${(mins / 60).round()}' : '$mins',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(isNow ? s['tdMinsLeft'] : s[mins >= 120 ? 'tdHoursTo' : 'tdMinsTo'],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: white70, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

double? _ratingPercent(CourseRating r) {
  final max = r.max ?? 0, a = r.achieved;
  if (max <= 0) return null;
  return r.ratingPercent ?? (a == null ? null : a / max * 100);
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]);
}

class _ExamCard extends StatelessWidget {
  const _ExamCard(this.f);
  final ExamFinal f;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final days = dateOnly(f.startsAt!).difference(dateOnly(DateTime.now())).inDays;
    return AppCard(
      onTap: () => context.read<NavController>().go(Dest.exams),
      child: Row(children: [
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(gradient: Brand.sunrise, borderRadius: BorderRadius.circular(radiusS)),
          child: Column(children: [
            Text('${f.startsAt!.day}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(fmtDate(f.startsAt!, s.lang).split(' ').last,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text([fmtTime(f.startsAt!), if (f.room != null) '${s['room']} ${f.room}'].join(' · '),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        Tag(days == 0 ? s['todayLower'] : days == 1 ? s['tomorrow'] : s.f('inDays', {'n': days}), color: Brand.danger),
      ]),
    );
  }
}
