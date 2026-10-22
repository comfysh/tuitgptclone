// Cards shared by several screens: a class in the timetable, a day's
// timeline with breaks, and an assignment with its deadline.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/models.dart';
import 'design.dart';

/// One class: time, subject (in its colour), type, room, group, topic.
class ClassCard extends StatelessWidget {
  const ClassCard({super.key, required this.slot, required this.now, this.onTap, this.absent = false});
  final ClassSlot slot;
  final DateTime now;
  final VoidCallback? onTap;
  final bool absent;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = context.watch<AppState>().snapshot;
    final color = slot.courseId != null
        ? courseColor(slot.courseId!, snap, name: slot.item.displaySubject)
        : colorForCourseName(slot.item.displaySubject, snap);
    final active = slot.isNow(now);
    final past = slot.end.isBefore(now);
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        accent: color,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 52,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtTime(slot.start), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(fmtTime(slot.end), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(slot.item.displaySubject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (active) Tag(s['now'], color: Brand.danger, icon: Icons.circle, filled: true),
                  Tag(lessonTypeName(slot.item.type, s), color: color, icon: lessonTypeIcon(slot.item.type)),
                  if (slot.item.room != null) Tag(slot.item.room!, color: cs.onSurfaceVariant, icon: Icons.location_on_outlined),
                  if (slot.item.stream != null) Tag(slot.item.stream!, color: cs.onSurfaceVariant, icon: Icons.groups_2_outlined),
                  if (slot.item.side != WeekSide.full)
                    Tag(slot.item.side == WeekSide.right ? s['evenWeek'] : s['oddWeek'], color: cs.onSurfaceVariant),
                  if (absent) Tag(s['nb'], color: Brand.danger, filled: true),
                ]),
                if (slot.topic != null) ...[
                  const SizedBox(height: 8),
                  Text(slot.topic!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A day's classes with breaks between them.
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key, required this.slots, required this.now, this.onTapSlot});
  final List<ClassSlot> slots;
  final DateTime now;
  final void Function(ClassSlot)? onTapSlot;

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
        child: ClassCard(slot: slot, now: now, onTap: onTapSlot == null ? null : () => onTapSlot!(slot)),
      ));
    }
    return Column(children: children);
  }
}

/// Countdown text and colour for a deadline.
(String, Color) deadlineLabel(Assignment a, S s, ColorScheme cs, {DateTime? now}) {
  final t = now ?? DateTime.now();
  if (a.isGraded) return ('${fmtNum(a.grade)}/${fmtNum(a.maxGrade)}', ratioColor(a.grade, a.maxGrade, cs));
  if (a.isSubmitted) return (s['submitted'], Brand.primary);
  if (a.deadline == null) return (s['notSubmitted'], cs.outline);
  final left = a.deadline!.difference(t);
  if (left.isNegative || a.expired) return (s['overdue'], Brand.danger);
  final c = left < const Duration(hours: 24)
      ? Brand.danger
      : left < const Duration(days: 3)
          ? Brand.warning
          : Brand.success;
  return (s.f('dueIn', {'t': fmtDuration(left, s.lang)}), c);
}

/// An assignment with its course colour, deadline and status.
class DeadlineCard extends StatelessWidget {
  const DeadlineCard({super.key, required this.a, this.onTap, this.showCourse = true});
  final Assignment a;
  final VoidCallback? onTap;
  final bool showCourse;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = context.watch<AppState>().snapshot;
    final color = courseColor(a.courseId, snap, name: a.courseName);
    final (label, labelColor) = deadlineLabel(a, s, cs);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        TintIcon(
          a.isGraded
              ? Icons.verified_rounded
              : a.isSubmitted
                  ? Icons.cloud_done_rounded
                  : Icons.assignment_outlined,
          color: color,
          size: 40,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.25)),
            const SizedBox(height: 3),
            Text(
              [
                if (showCourse) a.courseName,
                if (a.deadline != null) fmtDateTime(a.deadline!, s.lang),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Tag(label, color: labelColor),
      ]),
    );
  }
}
