import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
import '../core/insights.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/changes.dart';
import '../lms/snapshot.dart';

/// Local notifications on Android and Windows.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'lms_updates',
    'LMS updates',
    channelDescription: 'New assignments, deadlines, grades, absences and news',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _remindChannel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Deadline and class reminders',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Used during quiet hours: shown in the list, no sound, no vibration, no pop-up.
  static const _quietChannel = AndroidNotificationDetails(
    'quiet',
    'Quiet hours',
    channelDescription: 'Notifications that arrive during your quiet hours',
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
  );

  static const _briefChannel = AndroidNotificationDetails(
    'brief',
    'Morning brief',
    channelDescription: 'One summary of the day: classes and what is due',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
        windows: WindowsInitializationSettings(
          appName: 'TuitMate',
          appUserModelId: 'Uz.Personal.TuitMate',
          guid: '6f1c3b0e-6a54-4d1e-9a3e-2f73c8a1b7d4',
        ),
      ),
    );
    _ready = true;
  }

  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// Removes shown and scheduled notifications (sign-out).
  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  static int _id(String key) => key.hashCode & 0x3fffffff;

  static Future<void> show(String key, String title, String body,
      {bool reminder = false, bool quiet = false, List<String>? lines}) async {
    await init();
    final base = quiet ? _quietChannel : (reminder ? _remindChannel : _channel);
    final android = lines == null
        ? base
        : AndroidNotificationDetails(
            base.channelId,
            base.channelName,
            channelDescription: base.channelDescription,
            importance: base.importance,
            priority: base.priority,
            playSound: base.playSound,
            enableVibration: base.enableVibration,
            styleInformation: InboxStyleInformation(lines, contentTitle: title, summaryText: body),
          );
    await _plugin.show(
      id: _id(key),
      title: title,
      body: lines == null ? body : '$body\n${lines.join('\n')}',
      notificationDetails: NotificationDetails(
        android: android,
        windows: quiet ? WindowsNotificationDetails(audio: WindowsNotificationAudio.silent()) : const WindowsNotificationDetails(),
      ),
    );
  }

  /// [now] is within the quiet hours [from]..[to] (minutes after midnight; may wrap past midnight).
  static bool isQuietTime(DateTime now, int from, int to) {
    if (from == to) return false;
    final m = now.hour * 60 + now.minute;
    return from < to ? (m >= from && m < to) : (m >= from || m < to);
  }

  static bool _quiet(Settings settings, DateTime at) =>
      settings.quietHours && isQuietTime(at, settings.quietFrom, settings.quietTo);

  static String _text(LmsChange c, S s) {
    final lang = s.lang;
    String when(DateTime? d) => d == null ? '' : fmtDateTime(d, lang);
    switch (c.kind) {
      case ChangeKind.newAssignment:
        return '${c.detail}${c.when != null ? ' · ${s['deadline']}: ${when(c.when)}' : ''}';
      case ChangeKind.deadlineChanged:
        return '${c.detail} → ${when(c.when)}';
      case ChangeKind.gradePosted:
        return '${c.detail}: ${fmtNum(c.value)}${c.max != null ? ' / ${fmtNum(c.max)}' : ''}';
      case ChangeKind.examGrade:
        return '${s['score']}: ${fmtNum(c.value)} / 100';
      case ChangeKind.examChanged:
        return '${when(c.when)}${c.detail.isNotEmpty ? ' · ${s['room']} ${c.detail}' : ''}';
      case ChangeKind.newAbsence:
        return '${s['nb']} · ${c.when != null ? fmtDate(c.when!, lang) : ''} ${c.detail}';
      case ChangeKind.news:
        return c.detail.length > 140 ? '${c.detail.substring(0, 140)}…' : c.detail;
      case ChangeKind.newFile:
        return c.detail;
      case ChangeKind.reminder:
        final left = c.when!.difference(DateTime.now());
        return '${c.detail} · ${s.f('dueIn', {'t': fmtDuration(left, lang)})}';
    }
  }

  static String _title(LmsChange c, S s) => '${_head(c.kind, s)} · ${c.subject}';

  static String _head(ChangeKind kind, S s) {
    final head = switch (kind) {
      ChangeKind.newAssignment => {'en': 'New assignment', 'uz': 'Yangi topshiriq', 'ru': 'Новое задание'},
      ChangeKind.deadlineChanged => {'en': 'Deadline changed', 'uz': "Muddat o'zgardi", 'ru': 'Дедлайн изменён'},
      ChangeKind.gradePosted => {'en': 'New grade', 'uz': 'Yangi baho', 'ru': 'Новая оценка'},
      ChangeKind.examGrade => {'en': 'Exam result', 'uz': 'Imtihon natijasi', 'ru': 'Результат экзамена'},
      ChangeKind.examChanged => {'en': 'Exam schedule', 'uz': 'Imtihon jadvali', 'ru': 'Расписание экзамена'},
      ChangeKind.newAbsence => {'en': 'Absence recorded', 'uz': 'NB qo‘yildi', 'ru': 'Отмечен пропуск'},
      ChangeKind.news => {'en': 'LMS news', 'uz': 'LMS yangiligi', 'ru': 'Новость LMS'},
      ChangeKind.reminder => {'en': 'Deadline soon', 'uz': 'Muddat yaqin', 'ru': 'Скоро дедлайн'},
      ChangeKind.newFile => {'en': 'New material', 'uz': 'Yangi material', 'ru': 'Новый материал'},
    };
    return head[s.lang] ?? head['en']!;
  }

  /// Compares the previous and new snapshot, shows notifications (unless the
  /// kind is muted; bundled when there are many; silent in quiet hours),
  /// remembers which reminders were already sent, and returns every change
  /// (also muted ones, for automation).
  static Future<List<LmsChange>> processChanges(LmsSnapshot? old, LmsSnapshot now, Settings settings, AppStorage storage) async {
    final state = await storage.readJson(storage.notifyStateFile);
    final sent = Set<String>.from(state['sent'] ?? const []);

    final changes = <LmsChange>[
      if (old != null) ...diffSnapshots(old, now),
      if (settings.remindDeadlines) ...dueReminders(now, sent, DateTime.now()),
    ];
    for (final c in changes) {
      if (c.kind == ChangeKind.reminder) sent.add(c.key);
    }
    if (settings.notifications) {
      try {
        await _notify(changes, settings);
      } catch (_) {}
    }
    // Forget reminders whose deadline is long gone, keep the newest 400 (insertion order).
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    sent.removeWhere((k) {
      final d = DateTime.tryParse(k.substring(k.lastIndexOf('|') + 1));
      return d != null && d.isBefore(cutoff);
    });
    final list = sent.toList();
    state['sent'] = list.length > 400 ? list.sublist(list.length - 400) : list;
    state['sessionNotified'] = false;
    await storage.writeJson(storage.notifyStateFile, state);
    await scheduleClassReminders(now, settings);
    await scheduleMorningBrief(now, settings);
    return changes;
  }

  /// Deadline reminders one by one; other updates one by one when there are
  /// one or two, otherwise a single notification listing them.
  static Future<void> _notify(List<LmsChange> changes, Settings settings) async {
    final s = S(settings.language);
    final muted = settings.mutedKinds;
    final quiet = _quiet(settings, DateTime.now());
    final visible = [for (final c in changes) if (!muted.contains(c.kind.name)) c];
    final reminders = [for (final c in visible) if (c.kind == ChangeKind.reminder) c];
    final updates = [for (final c in visible) if (c.kind != ChangeKind.reminder) c];
    for (final c in reminders.take(6)) {
      await show(c.key, _title(c, s), _text(c, s), reminder: true, quiet: quiet);
    }
    if (updates.length <= 2) {
      for (final c in updates) {
        await show(c.key, _title(c, s), _text(c, s), quiet: quiet);
      }
      return;
    }
    // "2 × New assignment · 1 × New grade" and one line per update.
    final counts = <ChangeKind, int>{};
    for (final c in updates) {
      counts[c.kind] = (counts[c.kind] ?? 0) + 1;
    }
    final summary = [for (final e in counts.entries) '${e.value} × ${_head(e.key, s)}'].join(' · ');
    final lines = [for (final c in updates.take(8)) '${_title(c, s)}: ${_text(c, s)}'];
    if (updates.length > 8) lines.add(s.f('nfMore', {'n': updates.length - 8}));
    await show('bundle|${DateTime.now().millisecondsSinceEpoch}', s.f('nfBundleTitle', {'n': updates.length}), summary,
        quiet: quiet, lines: lines);
  }

  static Future<void> notifySessionExpired(Settings settings, AppStorage storage) async {
    final state = await storage.readJson(storage.notifyStateFile);
    if (state['sessionNotified'] == true) return;
    final s = S(settings.language);
    await show('session', 'TuitMate', '${s['sessionExpired']} ${s['signInAgain']}.',
        quiet: _quiet(settings, DateTime.now()));
    state['sessionNotified'] = true;
    await storage.writeJson(storage.notifyStateFile, state);
  }

  static const _classBase = 900000;

  /// Schedules "class in 10 minutes" notifications for the next 7 days.
  static Future<void> scheduleClassReminders(LmsSnapshot snap, Settings settings) async {
    await init();
    for (var i = 0; i < 60; i++) {
      await _plugin.cancel(id: _classBase + i);
    }
    if (!settings.remindClasses || !settings.notifications) return;
    final s = S(settings.language);
    final now = DateTime.now();
    var n = 0;
    for (var d = 0; d < 7 && n < 60; d++) {
      for (final slot in classesOn(now.add(Duration(days: d)), settings, snap)) {
        final at = slot.start.subtract(const Duration(minutes: 10));
        if (!at.isAfter(now) || n >= 60) continue;
        final room = slot.item.room != null ? ' · ${s['room']} ${slot.item.room}' : '';
        try {
          await _plugin.zonedSchedule(
            id: _classBase + n,
            scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
            notificationDetails: const NotificationDetails(
              android: _remindChannel,
              windows: WindowsNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: '${fmtTime(slot.start)} · ${slot.item.displaySubject}',
            body: '${lessonTypeName(slot.item.type, s)}$room',
          );
          n++;
        } catch (_) {
          return;
        }
      }
    }
  }

  static const _briefBase = 910000;

  /// Schedules the morning brief for today (if its time hasn't passed) and
  /// tomorrow: the day's classes, what is due that day and exams. Days with
  /// nothing in them get no brief.
  static Future<void> scheduleMorningBrief(LmsSnapshot snap, Settings settings) async {
    await init();
    for (var i = 0; i < 2; i++) {
      await _plugin.cancel(id: _briefBase + i);
    }
    if (!settings.notifications || !settings.morningBrief || snap.isEmpty) return;
    final s = S(settings.language);
    final now = DateTime.now();
    for (var d = 0; d < 2; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final at = day.add(Duration(minutes: settings.briefAt));
      if (!at.isAfter(now)) continue;
      final b = morningBrief(snap, settings, day, at, s);
      if (b == null) continue;
      final quiet = _quiet(settings, at);
      try {
        await _plugin.zonedSchedule(
          id: _briefBase + d,
          scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              (quiet ? _quietChannel : _briefChannel).channelId,
              (quiet ? _quietChannel : _briefChannel).channelName,
              channelDescription: (quiet ? _quietChannel : _briefChannel).channelDescription,
              importance: quiet ? Importance.low : Importance.defaultImportance,
              priority: quiet ? Priority.low : Priority.defaultPriority,
              playSound: !quiet,
              enableVibration: !quiet,
              styleInformation: BigTextStyleInformation(b.$2, contentTitle: b.$1),
            ),
            windows: quiet ? WindowsNotificationDetails(audio: WindowsNotificationAudio.silent()) : const WindowsNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: b.$1,
          body: b.$2,
        );
      } catch (_) {
        return;
      }
    }
  }

  /// Title and text of the brief for [day] sent at [at], or null when the day
  /// has no classes, deadlines or exams.
  static (String, String)? morningBrief(LmsSnapshot snap, Settings settings, DateTime day, DateTime at, S s) {
    final end = DateTime(day.year, day.month, day.day + 1);
    final classes = classesOn(day, settings, snap);
    final due = [
      for (final a in snap.assignments)
        if (isOpenTask(a) && a.deadline != null && !a.deadline!.isBefore(at) && a.deadline!.isBefore(end)) a,
    ]..sort((a, b) => a.deadline!.compareTo(b.deadline!));
    final exams = [
      for (final f in snap.finals)
        if (f.startsAt != null && !f.startsAt!.isBefore(day) && f.startsAt!.isBefore(end)) f,
    ];
    if (classes.isEmpty && due.isEmpty && exams.isEmpty) return null;
    final head = [
      classes.isEmpty ? s['nfBriefFree'] : s.f('nfBriefClasses', {'n': classes.length, 'time': fmtTime(classes.first.start)}),
      if (due.isNotEmpty) s.f('nfBriefDue', {'n': due.length}),
      if (exams.isNotEmpty) s['nfBriefExam'],
    ].join(' · ');
    final lines = [
      for (final f in exams) '${s['nfExam']} ${f.from ?? fmtTime(f.startsAt!)} · ${f.subject}${f.room != null ? ' · ${f.room}' : ''}',
      for (final c in classes) '${fmtTime(c.start)} ${c.item.displaySubject}${c.item.room != null ? ' · ${c.item.room}' : ''}',
      for (final a in due.take(4)) '${s['deadline']} ${fmtTime(a.deadline!)} · ${a.title} (${a.courseName})',
    ];
    return (head, lines.join('\n'));
  }
}
