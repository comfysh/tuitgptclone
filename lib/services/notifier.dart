import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
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

  static Future<void> show(String key, String title, String body, {bool reminder = false}) async {
    await init();
    await _plugin.show(
      id: _id(key),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: reminder ? _remindChannel : _channel,
        windows: const WindowsNotificationDetails(),
      ),
    );
  }

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

  static String _title(LmsChange c, S s) {
    final head = switch (c.kind) {
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
    return '${head[s.lang] ?? head['en']} · ${c.subject}';
  }

  /// Compares the previous and new snapshot, shows notifications, and
  /// remembers which reminders were already sent.
  static Future<int> processChanges(LmsSnapshot? old, LmsSnapshot now, Settings settings, AppStorage storage) async {
    if (!settings.notifications) {
      await scheduleClassReminders(now, settings); // cancels pending class reminders
      return 0;
    }
    final s = S(settings.language);
    final state = await storage.readJson(storage.notifyStateFile);
    final sent = Set<String>.from(state['sent'] ?? const []);

    final changes = <LmsChange>[
      if (old != null) ...diffSnapshots(old, now),
      if (settings.remindDeadlines) ...dueReminders(now, sent, DateTime.now()),
    ];
    var shown = 0;
    for (final c in changes.take(12)) {
      try {
        await show(c.key, _title(c, s), _text(c, s), reminder: c.kind == ChangeKind.reminder);
        if (c.kind == ChangeKind.reminder) sent.add(c.key);
        shown++;
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
    return shown;
  }

  static Future<void> notifySessionExpired(Settings settings, AppStorage storage) async {
    final state = await storage.readJson(storage.notifyStateFile);
    if (state['sessionNotified'] == true) return;
    final s = S(settings.language);
    await show('session', 'TuitMate', '${s['sessionExpired']} ${s['signInAgain']}.');
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
}
