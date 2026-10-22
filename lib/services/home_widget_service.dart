import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../core/format.dart';
import '../core/insights.dart';
import '../core/settings.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/snapshot.dart';

/// Feeds the Android home-screen widget "TuitMate · Today"
/// (android/app/src/main/kotlin/uz/personal/tuitmate/TuitWidgetProvider.kt).
///
/// The widget has to stay right while the app is closed, so it gets a
/// schedule rather than a single answer: the class slots of the next [_days]
/// days and the deadlines of the open tasks. The Kotlin provider picks the
/// current / next class and counts the open tasks itself on every redraw
/// (at each class start / end, at midnight, every 30 minutes and after each
/// sync).
///
/// Saved values (SharedPreferences "HomeWidgetPreferences", both JSON strings):
/// * [_labelsKey]: texts in the user's language (not personal).
/// * [_dataKey]: `{"v", "at", "until", "slots": [{"s", "e", "t", "r", "k"}],
///   "tasks": [{"t", "d"}], "nbUsed", "nbLimit"}`, times in epoch ms
///   ("d" is 0 for a task without a deadline).
class HomeWidgetService {
  HomeWidgetService._();

  static const _provider = 'uz.personal.tuitmate.TuitWidgetProvider';
  static const _dataKey = 'tuitmate_widget_data';
  static const _labelsKey = 'tuitmate_widget_labels';

  /// Days of classes the widget gets. It trusts them for [_validDays] (then it
  /// asks to open the app); the extra week keeps "the next 7 days" complete
  /// until then.
  static const _days = 14;
  static const _validDays = 7;
  static const _maxTasks = 50;

  /// Runs the widget writes one after another, so a sign-out's [clear] always
  /// lands after an update that started before it.
  static Future<void> _queue = Future<void>.value();

  static Future<void> _run(Future<void> Function() job) => _queue = _queue.then((_) => job());

  /// Saves what the widget shows and redraws it. Android only; never throws.
  static Future<void> update(LmsSnapshot snap, Settings settings) => _run(() async {
        try {
          if (!Platform.isAndroid) return;
          final s = S(settings.language);
          await HomeWidget.saveWidgetData<String>(_labelsKey, jsonEncode(_labels(s)), deleteFile: false);
          await HomeWidget.saveWidgetData<String>(
            _dataKey,
            snap.isEmpty ? null : jsonEncode(_data(snap, settings, s, DateTime.now())),
            deleteFile: false,
          );
          await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
        } catch (_) {}
      });

  /// Removes the personal data (after sign-out): the widget then only asks to
  /// open the app. Android only; never throws.
  static Future<void> clear() => _run(() async {
        try {
          if (!Platform.isAndroid) return;
          await HomeWidget.saveWidgetData<String>(_dataKey, null, deleteFile: false);
          await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
        } catch (_) {}
      });

  static Map<String, Object> _data(LmsSnapshot snap, Settings settings, S s, DateTime now) {
    final today = dateOnly(now);
    final slots = <Map<String, Object>>[];
    for (var i = 0; i < _days; i++) {
      // Calendar days (not 24 h steps), so a DST change can't skip a day.
      final day = DateTime(today.year, today.month, today.day + i);
      for (final c in classesOn(day, settings, snap)) {
        slots.add({
          's': c.start.millisecondsSinceEpoch,
          'e': c.end.millisecondsSinceEpoch,
          't': c.item.displaySubject.trim(),
          'r': c.item.room?.trim() ?? '',
          'k': lessonTypeName(c.item.type, s),
        });
      }
    }

    // The same "open task" rule as every screen (tasks without a deadline count).
    final tasks = <({String title, DateTime? due})>[];
    for (final a in snap.assignments) {
      if (!isOpenTask(a)) continue;
      final course = a.courseName.trim();
      tasks.add((title: course.isEmpty ? a.title : '${a.title} · $course', due: a.deadline));
    }
    // Soonest first, tasks without a deadline last.
    tasks.sort((a, b) => a.due == null
        ? (b.due == null ? 0 : 1)
        : b.due == null
            ? -1
            : a.due!.compareTo(b.due!));

    final att = AttendanceSummary.from(snap, settings);
    return {
      'v': 1,
      'at': now.millisecondsSinceEpoch,
      'until': DateTime(today.year, today.month, today.day + _validDays).millisecondsSinceEpoch,
      'slots': slots,
      'tasks': [
        for (final t in tasks.take(_maxTasks)) {'t': t.title, 'd': t.due?.millisecondsSinceEpoch ?? 0},
      ],
      'nbUsed': att.hoursUsed,
      'nbLimit': att.limitHours,
    };
  }

  static Map<String, Object> _labels(S s) => {
        'lang': s.lang,
        'now': s['now'],
        'next': s['next'],
        'classes': s['wgClassesToday'],
        'tasks': s['wgOpenTasks'],
        'nb': s['wgNbHours'],
        'noMore': s['wgNoMore'],
        'free': s['wgFreeDay'],
        'tomorrowAt': s['wgTomorrowAt'],
        'noneWeek': s['wgNoneThisWeek'],
        'dueToday': s['wgDueToday'],
        'dueTomorrow': s['wgDueTomorrow'],
        'inDays': s['inDays'],
        'noTasks': s['wgNoTasks'],
        'openApp': s['wgOpenApp'],
        'sync': s['wgSync'],
        'wd': [for (final k in const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']) s[k]],
      };
}
