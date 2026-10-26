// Timetable ("Dars jadvali"): a week at a time with odd/even weeks.
// Phones get a week strip and the selected day's timeline; wide windows get
// a weekly grid with one column per day.

import 'dart:async';

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
import 'cards.dart' show ClassCard, DayTimeline;
import 'courses_screen.dart' show CourseDetailPage;
import 'widgets.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  Timer? _tick;
  late DateTime _monday;
  late DateTime _day;

  /// The date [_goToday] last ran for, and whether the view still follows
  /// today (until the user picks another day or week). The screen lives as
  /// long as the app, so after midnight it moves on by itself.
  DateTime? _anchor;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _goToday(context.read<AppState>());
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Today, or the coming Monday when today is a Sunday without classes.
  void _goToday(AppState app) {
    final today = dateOnly(DateTime.now());
    _anchor = today;
    _follow = true;
    if (today.weekday == DateTime.sunday && classesOn(today, app.settings, app.snapshot).isEmpty) {
      _monday = _addDays(today, 1);
      _day = _monday;
    } else {
      _monday = _mondayOf(today);
      _day = today;
    }
  }

  /// Mon–Sat, plus Sunday when that Sunday has classes.
  List<DateTime> _weekDays(DateTime monday, AppState app) {
    final sunday = _addDays(monday, 6);
    final withSunday = classesOn(sunday, app.settings, app.snapshot).isNotEmpty;
    return [for (var i = 0; i < (withSunday ? 7 : 6); i++) _addDays(monday, i)];
  }

  void _shiftWeek(int delta) {
    final app = context.read<AppState>();
    final monday = _addDays(_monday, 7 * delta);
    final today = dateOnly(DateTime.now());
    final days = _weekDays(monday, app);
    final day = days.any((d) => _sameDay(d, today))
        ? today
        : days[(_day.weekday - 1).clamp(0, days.length - 1)];
    setState(() {
      _monday = monday;
      _day = day;
      _follow = false;
    });
  }

  void _shiftDay(int delta) {
    final app = context.read<AppState>();
    var day = _addDays(_day, delta);
    if (day.weekday == DateTime.sunday && classesOn(day, app.settings, app.snapshot).isEmpty) {
      day = _addDays(day, delta); // skip a hidden Sunday
    }
    setState(() {
      _day = day;
      _monday = _mondayOf(day);
      _follow = false;
    });
  }

  void _onSwipe(DragEndDetails d, void Function(int) shift) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 250) return;
    shift(v < 0 ? 1 : -1);
  }

  void _openSlot(ClassSlot slot) {
    final id = slot.courseId;
    final course = id == null ? null : context.read<AppState>().snapshot.courseById(id);
    if (course != null) CourseDetailPage.open(context, course);
  }

  Future<void> _pickParity(DateTime monday, String range) async {
    final app = context.read<AppState>();
    final s = S.read(context);
    final auto = app.settings.weekAnchorMonday == null || app.settings.weekAnchorSide == null;
    final side = weekSideFor(monday, app.settings, app.snapshot);
    final sideName = side == WeekSide.right ? s['evenWeek'] : s['oddWeek'];
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(s['scParityTitle'], style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(s.f('scParityBody', {'range': range}),
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            _ParityOption(
              icon: Icons.looks_one_rounded,
              title: s['oddWeek'],
              selected: !auto && side == WeekSide.left,
              onTap: () => Navigator.pop(ctx, 'odd'),
            ),
            const SizedBox(height: 8),
            _ParityOption(
              icon: Icons.looks_two_rounded,
              title: s['evenWeek'],
              selected: !auto && side == WeekSide.right,
              onTap: () => Navigator.pop(ctx, 'even'),
            ),
            const SizedBox(height: 8),
            _ParityOption(
              icon: Icons.autorenew_rounded,
              title: s['resetAuto'],
              subtitle: auto ? s.f('scParityDetected', {'side': sideName}) : s['scParityAutoSub'],
              selected: auto,
              onTap: () => Navigator.pop(ctx, 'auto'),
            ),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'auto') {
      app.settings.setWeekAnchor(null, null);
    } else {
      app.settings.setWeekAnchor(monday, choice == 'odd' ? WeekSide.left : WeekSide.right);
    }
    app.touch();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final now = DateTime.now();
    final today = dateOnly(now);
    // A new day (rebuilt by the 30 s tick or on resume): move to it.
    if (_follow && _anchor != today) _goToday(app);

    final days = _weekDays(_monday, app);
    final selected = days.firstWhere((d) => _sameDay(d, _day), orElse: () => days.last);
    final week = [for (final d in days) classesOn(d, app.settings, snap)];
    final allSlots = [for (final l in week) ...l];
    final absIdx = _absenceIndex(snap);
    final absent = <ClassSlot>{for (final l in week) ..._absentSlots(l, absIdx, snap, now)};
    final side = weekSideFor(_monday, app.settings, snap);
    final range = _rangeLabel(days.first, days.last, s.lang);
    final rel = (_monday.difference(_mondayOf(today)).inHours / (24 * 7)).round();
    final relative = switch (rel) {
      0 => s['thisWeek'],
      1 => s['nextWeek'],
      -1 => s['scLastWeek'],
      _ => null,
    };
    final hasSchedule = snap.schedule.isNotEmpty;

    final header = _Header(
      range: range,
      relative: relative,
      side: side,
      showParity: hasSchedule,
      onPrev: () => _shiftWeek(-1),
      onNext: () => _shiftWeek(1),
      onToday: () => setState(() => _goToday(app)),
      onParity: () => _pickParity(_monday, range),
    );

    return Scaffold(
      appBar: pageAppBar(context, title: s['schedule'], lmsPath: '/student/schedule'),
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => app.refresh(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: LayoutBuilder(builder: (context, c) {
                final width = c.maxWidth - 32;
                final wide = width >= 900;

                final List<Widget> body;
                if (snap.isEmpty) {
                  body = [
                    if (!app.syncing)
                      AppCard(
                          child: EmptyView(
                              icon: Icons.cloud_sync_rounded, title: s['noData'], subtitle: s['scNotSynced'])),
                  ];
                } else if (!hasSchedule) {
                  body = [
                    AppCard(
                        child: EmptyView(
                            icon: Icons.event_note_rounded, title: s['noSchedule'], subtitle: s['scNoScheduleSub'])),
                  ];
                } else if (wide) {
                  body = [
                    _WeekSummary(slots: allSlots, missed: absent.length, horizontal: true),
                    const SizedBox(height: 12),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (d) => _onSwipe(d, _shiftWeek),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _WeekGrid(
                          key: ValueKey(_monday),
                          days: days,
                          week: week,
                          today: today,
                          now: now,
                          absent: absent,
                          onTapSlot: _openSlot,
                        ),
                      ),
                    ),
                  ];
                } else {
                  final i = days.indexOf(selected);
                  final slots = i < 0 ? const <ClassSlot>[] : week[i];
                  final dayView = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (d) => _onSwipe(d, _shiftDay),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _DayHeader(day: selected, slots: slots, isToday: _sameDay(selected, today)),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey(selected),
                          child: slots.isEmpty
                              ? SizedBox(
                                  width: double.infinity,
                                  child: AppCard(
                                    child: EmptyView(
                                      icon: Icons.weekend_rounded,
                                      title: s['scFreeDay'],
                                      subtitle: s['scFreeDaySub'],
                                      color: Brand.success,
                                    ),
                                  ),
                                )
                              : slots.any(absent.contains)
                                  ? _Timeline(slots: slots, now: now, absent: absent, onTapSlot: _openSlot)
                                  : DayTimeline(slots: slots, now: now, onTapSlot: _openSlot),
                        ),
                      ),
                    ]),
                  );
                  final summary = _WeekSummary(slots: allSlots, missed: absent.length, horizontal: false);
                  body = [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (d) => _onSwipe(d, _shiftWeek),
                      child: _WeekStrip(
                        days: days,
                        week: week,
                        selected: selected,
                        today: today,
                        onSelect: (d) => setState(() {
                          _day = d;
                          _follow = false;
                        }),
                      ),
                    ),
                    if (width >= 700)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 3, child: dayView),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(top: 20), child: summary)),
                      ])
                    else ...[
                      dayView,
                      const SizedBox(height: 6),
                      summary,
                    ],
                  ];
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    header,
                    const SizedBox(height: 14),
                    const SyncBanner(),
                    ...body,
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

// ---------------------------------------------------------------- helpers

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
DateTime _mondayOf(DateTime d) => _addDays(d, 1 - d.weekday);
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
String _cap(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
int _minuteOfDay(DateTime d) => d.hour * 60 + d.minute;

String _rangeLabel(DateTime a, DateTime b, String lang) {
  if (a.year == b.year && a.month == b.month) return '${a.day}–${fmtDate(b, lang)}';
  return '${fmtDate(a, lang)} – ${fmtDate(b, lang)}';
}

/// "1 class" / "3 classes", with Russian plural forms.
String _classesLabel(int n, S s) {
  final String key;
  if (s.lang == 'ru') {
    final d = n % 10, h = n % 100;
    key = d == 1 && h != 11
        ? 'scCls1'
        : d >= 2 && d <= 4 && (h < 12 || h > 14)
            ? 'scCls2'
            : 'scCls5';
  } else {
    key = n == 1 ? 'scCls1' : 'scCls5';
  }
  return s.f(key, {'n': n});
}

Color _slotColor(ClassSlot slot, LmsSnapshot snap) {
  final id = slot.courseId;
  return id != null
      ? courseColor(id, snap, name: slot.item.displaySubject)
      : colorForCourseName(slot.item.displaySubject, snap);
}

/// Absences keyed by subject id and date ("i…|date") and, for rows or
/// courses without an id, by subject name and date ("n…|date").
Map<String, List<Absence>> _absenceIndex(LmsSnapshot snap) {
  final out = <String, List<Absence>>{};
  for (final a in snap.absences) {
    final d = a.date;
    if (d == null) continue;
    final day = _dayKey(d.toLocal());
    if (a.subjectId != 0) (out['i${a.subjectId}|$day'] ??= []).add(a);
    (out['n${_normName(a.subject)}|$day'] ??= []).add(a);
  }
  return out;
}

String _normName(String s) => s.trim().toLowerCase();

/// Classes of one day that already ended and have a recorded absence (NB).
Set<ClassSlot> _absentSlots(List<ClassSlot> slots, Map<String, List<Absence>> index, LmsSnapshot snap, DateTime now) {
  final out = <ClassSlot>{};
  for (final slot in slots) {
    if (!slot.end.isBefore(now)) continue;
    final id = slot.courseId;
    final course = id == null ? null : snap.courseById(id);
    if (course == null) continue;
    final day = _dayKey(slot.start);
    final found = (course.subjectId != 0 ? index['i${course.subjectId}|$day'] : null) ??
        index['n${_normName(course.subject)}|$day'];
    if (found == null || found.isEmpty) continue;
    // Two classes of the same subject that day: the lesson type decides.
    final sameSubject = slots.where((o) => o.courseId == id).length;
    if (sameSubject <= 1 ||
        found.any((a) {
          final t = lessonTypeOfName(a.lessonType);
          return t == null || t == slot.item.type;
        })) {
      out.add(slot);
    }
  }
  return out;
}

// ---------------------------------------------------------------- header

class _Header extends StatelessWidget {
  const _Header({
    required this.range,
    required this.relative,
    required this.side,
    required this.showParity,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onParity,
  });
  final String range;
  final String? relative;
  final WeekSide side;
  final bool showParity;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onParity;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    // The page title, LMS and refresh buttons are in the app bar (pageAppBar).
    final subtitle = Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text([?relative, range].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
      if (showParity) _ParityChip(side: side, onTap: onParity),
    ]);
    return Row(children: [
      Expanded(child: subtitle),
      HeaderButton(icon: Icons.chevron_left_rounded, tooltip: s['scPrevWeek'], onPressed: onPrev),
      HeaderButton(icon: Icons.today_rounded, tooltip: s['today'], onPressed: onToday),
      HeaderButton(icon: Icons.chevron_right_rounded, tooltip: s['nextWeek'], onPressed: onNext),
    ]);
  }
}

/// Odd/even week label that opens the "fix week" sheet.
class _ParityChip extends StatelessWidget {
  const _ParityChip({required this.side, required this.onTap});
  final WeekSide side;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: s['fixWeek'],
      child: Material(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(side == WeekSide.right ? s['evenWeek'] : s['oddWeek'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 16, color: cs.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ParityOption extends StatelessWidget {
  const _ParityOption({required this.icon, required this.title, required this.selected, required this.onTap, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusM),
        side: BorderSide(color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7), width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            TintIcon(icon, color: cs.primary, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (subtitle case final sub?)
                  Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? cs.primary : cs.outline),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- phone: week strip + day

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.week,
    required this.selected,
    required this.today,
    required this.onSelect,
  });
  final List<DateTime> days;
  final List<List<ClassSlot>> week;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final snap = context.watch<AppState>().snapshot;
    return AppCard(
      padding: const EdgeInsets.all(6),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Row(key: ValueKey(days.first), children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _DayPill(
                day: days[i],
                colors: [for (final x in week[i]) _slotColor(x, snap)],
                selected: _sameDay(days[i], selected),
                isToday: _sameDay(days[i], today),
                past: days[i].isBefore(today),
                onTap: () => onSelect(days[i]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.colors,
    required this.selected,
    required this.isToday,
    required this.past,
    required this.onTap,
  });
  final DateTime day;
  final List<Color> colors;
  final bool selected;
  final bool isToday;
  final bool past;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final fg = selected
        ? Colors.white
        : isToday
            ? cs.primary
            : past
                ? cs.onSurfaceVariant
                : cs.onSurface;
    final sub = selected ? Colors.white.withValues(alpha: 0.82) : (isToday ? cs.primary : cs.onSurfaceVariant);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusS),
      side: isToday && !selected ? BorderSide(color: cs.primary, width: 1.5) : BorderSide.none,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? Brand.primary : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(children: [
              Text(weekdayShort(day.weekday, s),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('${day.day}', style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SizedBox(
                height: 5,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < colors.length && i < 4; i++)
                    Container(
                      width: 5,
                      height: 5,
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? Colors.white.withValues(alpha: 0.9) : colors[i],
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.slots, required this.isToday});
  final DateTime day;
  final List<ClassSlot> slots;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final line = [
      if (isToday) s['today'],
      fmtDateFull(day, s.lang),
      if (slots.isNotEmpty) '${fmtTime(slots.first.start)}–${fmtTime(slots.last.end)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_cap(fmtWeekday(day, s.lang)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
          ]),
        ),
        if (slots.isNotEmpty) ...[
          const SizedBox(width: 8),
          Tag(_classesLabel(slots.length, s), color: cs.primary, icon: Icons.event_note_rounded),
        ],
      ]),
    );
  }
}

/// Same look as [DayTimeline], but marks classes you were absent from.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.slots, required this.now, required this.absent, required this.onTapSlot});
  final List<ClassSlot> slots;
  final DateTime now;
  final Set<ClassSlot> absent;
  final void Function(ClassSlot) onTapSlot;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < slots.length; i++) {
      if (i > 0) {
        final gap = slots[i].start.difference(slots[i - 1].end).inMinutes;
        if (gap >= 20) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 8, 10),
            child: Row(children: [
              Icon(Icons.coffee_rounded, size: 16, color: cs.outline),
              const SizedBox(width: 8),
              Text(s.f('breakMin', {'min': gap}),
                  style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5))),
            ]),
          ));
        }
      }
      final slot = slots[i];
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ClassCard(slot: slot, now: now, absent: absent.contains(slot), onTap: () => onTapSlot(slot)),
      ));
    }
    return Column(children: children);
  }
}

// ---------------------------------------------------------------- week summary

class _WeekSummary extends StatelessWidget {
  const _WeekSummary({required this.slots, required this.missed, required this.horizontal});
  final List<ClassSlot> slots;
  final int missed;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final counts = List.filled(LessonType.values.length, 0);
    for (final x in slots) {
      counts[x.item.type.index]++;
    }
    final total = slots.length;

    final head = Row(mainAxisSize: MainAxisSize.min, children: [
      TintIcon(Icons.calendar_view_week_rounded, color: Brand.primary),
      const SizedBox(width: 12),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('$total', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
          Text(s['scWeekTotal'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w500)),
        ]),
      ),
    ]);
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TypeBar(counts: counts),
      const SizedBox(height: 10),
      Wrap(spacing: 16, runSpacing: 8, children: [
        for (final t in LessonType.values)
          if (counts[t.index] > 0) _LegendItem(type: t, count: counts[t.index]),
      ]),
    ]);
    final nb = missed > 0 ? Tag('${s['nb']} · $missed', color: Brand.danger, icon: Icons.event_busy_rounded) : null;

    if (horizontal) {
      return AppCard(
        child: Row(children: [
          head,
          const SizedBox(width: 28),
          Expanded(child: legend),
          if (nb != null) ...[const SizedBox(width: 16), nb],
        ]),
      );
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: head),
          if (nb != null) ...[const SizedBox(width: 8), nb],
        ]),
        const SizedBox(height: 14),
        legend,
      ]),
    );
  }
}

/// One bar split by lesson type.
class _TypeBar extends StatelessWidget {
  const _TypeBar({required this.counts});
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final t in LessonType.values)
        if (counts[t.index] > 0) (t, counts[t.index]),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        width: double.infinity,
        child: parts.isEmpty
            ? ColoredBox(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4))
            : Row(children: [
                for (var i = 0; i < parts.length; i++)
                  Expanded(
                    flex: parts[i].$2,
                    child: Container(
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                      color: lessonTypeColor(parts[i].$1),
                    ),
                  ),
              ]),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.type, required this.count});
  final LessonType type;
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = lessonTypeColor(type);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(lessonTypeIcon(type), size: 16, color: color),
      const SizedBox(width: 6),
      Text(lessonTypeName(type, s), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(width: 6),
      Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
    ]);
  }
}

// ---------------------------------------------------------------- wide: weekly grid

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    super.key,
    required this.days,
    required this.week,
    required this.today,
    required this.now,
    required this.absent,
    required this.onTapSlot,
  });
  final List<DateTime> days;
  final List<List<ClassSlot>> week;
  final DateTime today;
  final DateTime now;
  final Set<ClassSlot> absent;
  final void Function(ClassSlot) onTapSlot;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final times = <int>{for (final l in week) for (final x in l) _minuteOfDay(x.start)}.toList()..sort();
    if (times.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: AppCard(
          child: EmptyView(icon: Icons.weekend_rounded, title: s['scFreeWeek'], color: Brand.success),
        ),
      );
    }

    // Today's column is tinted from the header down to the last row.
    Widget cell(int col, Widget child, {bool top = false, bool bottom = false}) {
      final tinted = _sameDay(days[col], today);
      const r = Radius.circular(radiusS);
      return Container(
        padding: EdgeInsets.fromLTRB(4, top ? 8 : 4, 4, bottom ? 8 : 4),
        decoration: tinted
            ? BoxDecoration(
                color: cs.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.vertical(top: top ? r : Radius.zero, bottom: bottom ? r : Radius.zero),
              )
            : null,
        child: child,
      );
    }

    Widget slotCell(int col, int row) {
      final slots = week[col].where((x) => _minuteOfDay(x.start) == times[row]).toList();
      if (slots.isEmpty) {
        return row == 0 && week[col].isEmpty ? const _FreeCell() : const SizedBox.shrink();
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var j = 0; j < slots.length; j++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: j == 0 ? 0 : 6),
              child: _GridTile(
                slot: slots[j],
                now: now,
                absent: absent.contains(slots[j]),
                onTap: slots[j].courseId == null ? null : () => onTapSlot(slots[j]),
              ),
            ),
          ),
      ]);
    }

    return AppCard(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: cell(
                  i,
                  _GridHead(day: days[i], count: week[i].length, isToday: _sameDay(days[i], today)),
                  top: true,
                ),
              ),
          ]),
        ),
        for (var r = 0; r < times.length; r++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < days.length; i++)
                Expanded(child: cell(i, slotCell(i, r), bottom: r == times.length - 1)),
            ]),
          ),
      ]),
    );
  }
}

class _GridHead extends StatelessWidget {
  const _GridHead({required this.day, required this.count, required this.isToday});
  final DateTime day;
  final int count;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(children: [
        Text(weekdayShort(day.weekday, s),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isToday ? cs.primary : cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('${day.day}',
            style: TextStyle(color: isToday ? cs.primary : cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(count == 0 ? '—' : _classesLabel(count, s),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _FreeCell extends StatelessWidget {
  const _FreeCell();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        Icon(Icons.weekend_outlined, size: 22, color: cs.outline),
        const SizedBox(height: 4),
        Text(s['scFreeDay'],
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Compact class tile for the weekly grid.
class _GridTile extends StatelessWidget {
  const _GridTile({required this.slot, required this.now, required this.absent, this.onTap});
  final ClassSlot slot;
  final DateTime now;
  final bool absent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = context.watch<AppState>().snapshot;
    final color = _slotColor(slot, snap);
    final item = slot.item;
    final active = slot.isNow(now);
    final past = slot.end.isBefore(now);
    final time = '${fmtTime(slot.start)}–${fmtTime(slot.end)}';
    final tip = [
      item.displaySubject,
      '${lessonTypeName(item.type, s)} · $time',
      if (item.room != null) '${s['room']}: ${item.room}',
      if (item.stream != null) '${s['stream']}: ${item.stream}',
      if (slot.topic != null) '${s['topic']}: ${slot.topic}',
    ].join('\n');

    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Color.alphaBlend(color.withValues(alpha: active ? 0.16 : 0.09), cs.surface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusS),
            side: active ? BorderSide(color: color, width: 1.5) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 8, 8, 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(item.displaySubject,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.25)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (active) Tag(s['now'], color: Brand.danger, icon: Icons.circle, filled: true),
                      if (absent) Tag(s['nb'], color: Brand.danger, filled: true),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(lessonTypeIcon(item.type), size: 14, color: lessonTypeColor(item.type)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(item.room ?? lessonTypeName(item.type, s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
