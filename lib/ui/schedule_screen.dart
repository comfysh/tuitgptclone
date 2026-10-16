import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/models.dart';
import 'courses_screen.dart';
import 'lms_web_page.dart';
import 'widgets.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with TickerProviderStateMixin {
  int _weekOffset = 0;
  TabController? _tabs;
  int _days = 6;

  void _ensureTabs(int days) {
    if (_tabs != null && _days == days) return;
    _tabs?.dispose();
    _days = days;
    final todayIdx = (DateTime.now().weekday - 1).clamp(0, days - 1);
    _tabs = TabController(length: days, vsync: this, initialIndex: todayIdx);
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _fixWeek(BuildContext context) async {
    final app = context.read<AppState>();
    final s = S.read(context);
    final monday = mondayOf(DateTime.now());
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s['fixWeekTitle']),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: Text(s['fixWeekBody'])),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'odd'), child: Text(s['oddWeek'])),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'even'), child: Text(s['evenWeek'])),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'auto'), child: Text(s['resetAuto'])),
        ],
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
    final hasSunday = snap.schedule.any((e) => e.weekday == 7);
    _ensureTabs(hasSunday ? 7 : 6);
    final monday = mondayOf(DateTime.now()).add(Duration(days: 7 * _weekOffset));
    final side = weekSideFor(monday, app.settings, snap);
    final today = dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(s['schedule']),
        actions: [
          IconButton(
            tooltip: s['openInLms'],
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => LmsWebPage.open(context, '/student/schedule'),
          ),
          IconButton(tooltip: s['refresh'], icon: const Icon(Icons.refresh), onPressed: app.syncing ? null : () => app.refresh()),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: MediaQuery.sizeOf(context).width < 420,
          labelColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
          unselectedLabelColor: Theme.of(context).brightness == Brightness.light ? Colors.white70 : null,
          indicatorColor: Theme.of(context).brightness == Brightness.light ? Colors.white : null,
          tabs: [
            for (var i = 0; i < _days; i++)
              Tab(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(weekdayShort(i + 1, s), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${monday.add(Duration(days: i)).day}',
                      style: TextStyle(
                          fontSize: 12,
                          decoration: monday.add(Duration(days: i)) == today ? TextDecoration.underline : null)),
                ]),
              ),
          ],
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(s['thisWeek'])),
                  ButtonSegment(value: 1, label: Text(s['nextWeek'])),
                ],
                selected: {_weekOffset},
                onSelectionChanged: (v) => setState(() => _weekOffset = v.first),
              ),
              Pill(side == WeekSide.right ? s['evenWeek'] : s['oddWeek']),
              TextButton.icon(
                onPressed: () => _fixWeek(context),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(s['fixWeek']),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (var i = 0; i < _days; i++)
                RefreshIndicator(
                  onRefresh: () => app.refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SyncBanner(),
                      if (snap.schedule.isEmpty && !snap.isEmpty)
                        EmptyState(icon: Icons.event_note, text: s['noSchedule'])
                      else
                        Builder(builder: (_) {
                          final day = monday.add(Duration(days: i));
                          final slots = classesOn(day, app.settings, snap);
                          if (slots.isEmpty) return EmptyState(icon: Icons.weekend_outlined, text: s['noClassesToday']);
                          return DayTimeline(slots: slots, now: DateTime.now());
                        }),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Vertical list of classes with breaks between them.
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.slots, required this.now});
  final List<ClassSlot> slots;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final children = <Widget>[];
    for (var i = 0; i < slots.length; i++) {
      if (i > 0) {
        final gap = slots[i].start.difference(slots[i - 1].end).inMinutes;
        if (gap >= 20) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Row(children: [
              const SizedBox(width: 18),
              Icon(Icons.coffee_outlined, size: 16, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 8),
              Text(s.f('breakMin', {'min': gap}),
                  style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
            ]),
          ));
        }
      }
      children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: ClassCard(slot: slots[i], now: now)));
    }
    return Column(children: children);
  }
}

class ClassCard extends StatelessWidget {
  const ClassCard({super.key, required this.slot, required this.now});
  final ClassSlot slot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = lessonTypeColor(slot.item.type);
    final active = slot.isNow(now);
    final past = slot.end.isBefore(now);
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: active ? color : Theme.of(context).colorScheme.outlineVariant, width: active ? 2 : 1),
        ),
        child: InkWell(
          onTap: slot.courseId == null
              ? null
              : () {
                  final c = context.read<AppState>().snapshot.courseById(slot.courseId!);
                  if (c != null) CourseDetailPage.open(context, c);
                },
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 5, color: color),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(fmtTime(slot.start), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(fmtTime(slot.end), style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                ]),
              ),
              const VerticalDivider(width: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(slot.item.displaySubject, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      Pill(lessonTypeName(slot.item.type, s), color: color, icon: lessonTypeIcon(slot.item.type)),
                      if (slot.item.room != null) Pill('${s['room']} ${slot.item.room}', icon: Icons.meeting_room_outlined),
                      if (slot.item.stream != null) Pill(slot.item.stream!, icon: Icons.groups_outlined),
                      if (active) Pill(s['now'], color: Colors.red, icon: Icons.circle),
                    ]),
                    if (slot.topic != null) ...[
                      const SizedBox(height: 6),
                      Text('${s['topic']}: ${slot.topic}', style: Theme.of(context).textTheme.bodySmall),
                    ],
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
