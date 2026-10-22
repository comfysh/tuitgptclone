import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/models.dart';
import '../lms/snapshot.dart';
import 'files.dart';
import 'widgets.dart';

/// Exams ("Imtihonlar"): upcoming finals with a countdown, exams without a
/// date yet, and results with test points.
class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps the countdowns fresh.
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

    if (snap.isEmpty) {
      return PageScaffold(
        title: s['exams'],
        lmsPath: '/student/finals',
        children: [
          if (!app.syncing)
            AppCard(child: EmptyView(icon: Icons.cloud_sync_rounded, title: s['noData'], subtitle: s['exNotSynced'])),
        ],
      );
    }

    final upcoming = <_Exam>[], unscheduled = <_Exam>[], results = <_Exam>[];
    for (final f in snap.finals) {
      final e = _Exam(f, snap);
      final start = e.start;
      if (f.grade != null) {
        results.add(e);
      } else if (start == null) {
        unscheduled.add(e);
      } else if (e.endAt(start).isAfter(now)) {
        upcoming.add(e);
      } else {
        results.add(e); // took place, no grade yet
      }
    }
    upcoming.sort((a, b) => (a.start ?? DateTime(9999)).compareTo(b.start ?? DateTime(9999)));
    unscheduled.sort((a, b) => a.f.subject.compareTo(b.f.subject));
    results.sort((a, b) {
      final da = a.start, db = b.start;
      if (da == null && db == null) return a.f.subject.compareTo(b.f.subject);
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    final next = upcoming.firstOrNull;
    final nextStart = next?.start;

    return PageScaffold(
      title: s['exams'],
      subtitle: snap.finals.isEmpty ? null : s.f('exSubtitle', {'up': upcoming.length, 'done': results.length}),
      lmsPath: '/student/finals',
      children: [
        if (snap.finals.isEmpty)
          AppCard(
            child: EmptyView(
              icon: Icons.fact_check_rounded,
              title: s['noExams'],
              subtitle: s['exEmptySub'],
            ),
          )
        else ...[
          if (next != null && nextStart != null)
            _NextExamHero(e: next, start: nextStart, now: now)
          else
            AppCard(
              child: Row(children: [
                const TintIcon(Icons.event_available_rounded, color: Brand.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['exNoUpcoming'], style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (results.isNotEmpty)
                      Text(s['exNoUpcomingSub'], style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
                ),
              ]),
            ),
          if (upcoming.length > 1) ...[
            SectionHeader(s['upcoming']),
            ResponsiveGrid(minItemWidth: 400, children: [
              for (final e in upcoming.skip(1))
                if (e.start case final start?) _UpcomingCard(e: e, start: start, now: now),
            ]),
          ],
          if (unscheduled.isNotEmpty) ...[
            SectionHeader(s['exNotScheduled']),
            ResponsiveGrid(minItemWidth: 400, children: [
              for (final e in unscheduled) _UnscheduledCard(e: e),
            ]),
          ],
          if (results.isNotEmpty) ...[
            SectionHeader(s['past']),
            ResponsiveGrid(minItemWidth: 400, children: [
              for (final e in results) _ResultCard(e: e),
            ]),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- model helpers

final _timeRe = RegExp(r'(\d{1,2}):(\d{2})');

/// [day] at the "HH:mm" found in [text], or null.
DateTime? _at(DateTime day, String? text) {
  final m = _timeRe.firstMatch(text ?? '');
  if (m == null) return null;
  final h = int.tryParse(m.group(1) ?? ''), min = int.tryParse(m.group(2) ?? '');
  if (h == null || min == null || h > 23 || min > 59) return null;
  return DateTime(day.year, day.month, day.day, h, min);
}

int _daysBetween(DateTime from, DateTime to) => (dateOnly(to).difference(dateOnly(from)).inHours / 24).round();

String _cap(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

/// An exam with what the cards need: start/end, colour, questions file.
class _Exam {
  _Exam(this.f, LmsSnapshot snap)
      : color = f.subjectId != 0 ? subjectColor(f.subjectId) : colorForCourseName(f.subject, snap),
        questionsUrl = _questionsUrl(f, snap);

  final ExamFinal f;
  final Color color;
  final String? questionsUrl;

  DateTime? get start => f.startsAt;

  /// Whether the LMS gave a start time (not just a date).
  bool get timed {
    final d = f.date;
    return d != null && _at(d, f.from) != null;
  }

  /// When the exam is over: "to" time, else start + time limit, else start + 3 h.
  /// Exams without a time count for the whole day.
  DateTime endAt(DateTime start) {
    if (!timed) return dateOnly(start).add(const Duration(days: 1));
    final to = _at(start, f.to);
    if (to != null && to.isAfter(start)) return to;
    final limit = f.timeLimit ?? 0;
    return start.add(Duration(minutes: limit > 0 ? limit : 180));
  }

  bool liveAt(DateTime start, DateTime now) => timed && !now.isBefore(start) && now.isBefore(endAt(start));

  /// "09:00–10:20", or null when the LMS has no time.
  String? get timeText {
    final from = f.from?.trim() ?? '';
    if (from.isEmpty) return null;
    final to = f.to?.trim() ?? '';
    return to.isEmpty ? from : '$from–$to';
  }

  static String? _questionsUrl(ExamFinal f, LmsSnapshot snap) {
    final name = f.subject.trim().toLowerCase();
    for (final c in snap.courses) {
      final url = c.questionsUrl?.trim() ?? '';
      if (url.isEmpty) continue;
      final same = f.subjectId != 0 ? c.subjectId == f.subjectId : c.subject.trim().toLowerCase() == name;
      if (same) return url;
    }
    return null;
  }
}

/// Countdown label and whether it should be highlighted (today / tomorrow / live).
({String label, bool hot, bool live}) _when(_Exam e, DateTime start, DateTime now, S s) {
  if (e.liveAt(start, now)) return (label: s['exNow'], hot: true, live: true);
  final days = _daysBetween(now, start);
  final time = e.timed ? ' · ${fmtTime(start)}' : '';
  if (days <= 0) return (label: '${s['today']}$time', hot: true, live: false);
  if (days == 1) return (label: '${s['exTomorrow']}$time', hot: true, live: false);
  return (label: s.f('exInDays', {'n': days}), hot: false, live: false);
}

// ---------------------------------------------------------------- hero

class _NextExamHero extends StatelessWidget {
  const _NextExamHero({required this.e, required this.start, required this.now});
  final _Exam e;
  final DateTime start;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final f = e.f;
    final white70 = Colors.white.withValues(alpha: 0.82);
    final when = _when(e, start, now, s);
    final time = e.timeText;
    final room = f.room?.trim() ?? '';
    final stream = f.stream?.trim() ?? '';
    final limit = f.timeLimit ?? 0;
    final url = e.questionsUrl;

    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(s['nextExam'], style: TextStyle(color: white70, fontWeight: FontWeight.w600)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: when.hot ? Colors.white : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(when.label,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: when.hot ? Brand.danger : Colors.white)),
        ),
      ]),
      const SizedBox(height: 12),
      Text(f.subject,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.4)),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        _HeroMeta(Icons.event_rounded, '${_cap(fmtWeekday(start, s.lang))}, ${fmtDateFull(start, s.lang)}'),
        if (time != null) _HeroMeta(Icons.schedule_rounded, time),
        if (room.isNotEmpty) _HeroMeta(Icons.location_on_rounded, '${s['room']} $room'),
        if (stream.isNotEmpty) _HeroMeta(Icons.groups_rounded, stream),
        if (limit > 0) _HeroMeta(Icons.hourglass_bottom_rounded, s.f('exTimeLimit', {'n': limit})),
      ]),
    ]);

    Widget? countdown;
    if (when.live) {
      countdown = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.play_circle_fill_rounded, size: 26),
        const SizedBox(width: 8),
        Flexible(
          child: Text('${s['exNow']} · ${s.f('exEndsAt', {'time': fmtTime(e.endAt(start))})}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ]);
    } else {
      final diff = start.difference(now);
      final boxes = e.timed
          ? [
              if (diff.inDays > 0) (diff.inDays, s['exDays']),
              (diff.inHours % 24, s['exHours']),
              (diff.inMinutes % 60, s['exMins']),
            ]
          : [
              if (_daysBetween(now, start) > 0) (_daysBetween(now, start), s['exDays']),
            ];
      if (boxes.isNotEmpty && !diff.isNegative) {
        countdown = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(s['exStartsIn'], style: TextStyle(color: white70, fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < boxes.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 62),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(radiusS),
                ),
                child: Column(children: [
                  Text('${boxes[i].$1}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5)),
                  Text(boxes[i].$2, style: TextStyle(fontSize: 11, color: white70, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ]),
        ]);
      }
    }

    final button = url == null
        ? null
        : FilledButton.icon(
            onPressed: () => downloadAndOpen(context, url, '${f.subject} - ${s['exWrittenQuestions']}'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.quiz_rounded, size: 18),
            label: Text(s['exWrittenQuestions']),
          );

    return HeroCard(
      gradient: Brand.sunrise,
      child: LayoutBuilder(builder: (context, c) {
        final side = countdown;
        if (c.maxWidth >= 640 && side != null) {
          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                info,
                if (button != null) ...[const SizedBox(height: 16), button],
              ]),
            ),
            const SizedBox(width: 24),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45), child: side),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          info,
          if (side != null) ...[const SizedBox(height: 16), side],
          if (button != null) ...[const SizedBox(height: 16), button],
        ]);
      }),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]);
}

// ---------------------------------------------------------------- cards

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: c),
      const SizedBox(width: 4),
      Flexible(child: Text(text, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w600))),
    ]);
  }
}

List<Widget> _metaFor(_Exam e, S s, {bool withDate = false}) {
  final f = e.f;
  final start = e.start;
  final time = e.timeText;
  final room = f.room?.trim() ?? '';
  final stream = f.stream?.trim() ?? '';
  final limit = f.timeLimit ?? 0;
  return [
    if (withDate && start != null) _Meta(Icons.event_rounded, fmtDateFull(start, s.lang)),
    if (time != null) _Meta(Icons.schedule_rounded, time),
    if (room.isNotEmpty) _Meta(Icons.location_on_outlined, '${s['room']} $room'),
    if (stream.isNotEmpty) _Meta(Icons.groups_outlined, stream),
    if (limit > 0) _Meta(Icons.hourglass_bottom_rounded, s.f('exTimeLimit', {'n': limit})),
  ];
}

class _QuestionsButton extends StatelessWidget {
  const _QuestionsButton({required this.url, required this.subject});
  final String url;
  final String subject;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return OutlinedButton.icon(
      onPressed: () => downloadAndOpen(context, url, '$subject - ${s['exWrittenQuestions']}'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: const Icon(Icons.quiz_outlined, size: 18),
      label: Text(s['exWrittenQuestions']),
    );
  }
}

/// Weekday, day number and month in a small block (gradient when soon).
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date, required this.hot, required this.color});
  final DateTime date;
  final bool hot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final fg = hot ? Colors.white : color;
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: hot ? Brand.sunrise : null,
        color: hot ? null : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radiusS),
      ),
      child: Column(children: [
        Text(weekdayShort(date.weekday, s),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
        Text('${date.day}', style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
        Text(fmtDate(date, s.lang).split(' ').last,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.e, required this.start, required this.now});
  final _Exam e;
  final DateTime start;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final when = _when(e, start, now, s);
    final meta = _metaFor(e, s);
    final url = e.questionsUrl;
    return AppCard(
      accent: e.color,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _DateBlock(date: start, hot: when.hot, color: e.color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.f.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
              const SizedBox(height: 6),
              Tag(
                when.label,
                color: when.hot ? Brand.danger : e.color,
                icon: when.live ? Icons.play_arrow_rounded : Icons.timer_outlined,
                filled: when.live,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: meta),
              ],
            ]),
          ),
        ]),
        if (url != null) ...[
          const SizedBox(height: 12),
          _QuestionsButton(url: url, subject: e.f.subject),
        ],
      ]),
    );
  }
}

class _UnscheduledCard extends StatelessWidget {
  const _UnscheduledCard({required this.e});
  final _Exam e;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final meta = _metaFor(e, s);
    final url = e.questionsUrl;
    return AppCard(
      accent: e.color,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TintIcon(Icons.event_busy_rounded, color: e.color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.f.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
              const SizedBox(height: 6),
              Tag(s['exNoDate'], color: Brand.warning, icon: Icons.help_outline_rounded),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: meta),
              ],
            ]),
          ),
        ]),
        if (url != null) ...[
          const SizedBox(height: 12),
          _QuestionsButton(url: url, subject: e.f.subject),
        ],
      ]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.e});
  final _Exam e;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final f = e.f;
    final meta = _metaFor(e, s, withDate: true);
    final url = f.grade == null ? e.questionsUrl : null;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ResultBadge(f.grade),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4, children: meta),
            ],
            if (f.grade == null) ...[
              const SizedBox(height: 8),
              Tag(s['exAwaiting'], color: cs.onSurfaceVariant, icon: Icons.hourglass_empty_rounded),
            ],
            if (f.testPoints.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(s['testPoints'],
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in f.testPoints) _PointChip(p),
              ]),
            ],
            if (url != null) ...[
              const SizedBox(height: 12),
              _QuestionsButton(url: url, subject: f.subject),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Final grade: a 2–5 grade as [GradeBadge]; anything else (the scale is not
/// fixed in the LMS) as a score coloured on the 100-point scale.
class _ResultBadge extends StatelessWidget {
  const _ResultBadge(this.grade);
  final int? grade;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final g = grade;
    const size = 52.0;
    final Widget badge;
    String? caption;
    if (g == null || (g >= 2 && g <= 5)) {
      badge = GradeBadge(g, size: size);
      if (g != null) caption = s['grade'];
    } else {
      final c = scoreColor(g, cs);
      badge = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.3)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('$g', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
        ),
      );
      caption = s['score'];
    }
    return SizedBox(
      width: 60,
      child: Column(children: [
        badge,
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        ],
      ]),
    );
  }
}

class _PointChip extends StatelessWidget {
  const _PointChip(this.p);
  final TestPoint p;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: Brand.violet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '#${p.number}  ', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          TextSpan(text: fmtNum(p.point.toDouble()), style: const TextStyle(color: Brand.violet, fontWeight: FontWeight.w800)),
        ]),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
