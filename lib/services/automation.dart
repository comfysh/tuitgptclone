// Automation for the owner: TuitMate sends LMS events to a webhook (n8n, Make,
// a script…) encrypted with the owner's AES-256 key.
//
// The wire format is documented in docs/AUTOMATION.md; test/automation_test.dart
// checks it against independent Node.js and Python implementations. Keep all
// three in sync.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

import '../core/insights.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/timetable.dart';
import '../core/version.dart';
import '../lms/changes.dart';
import '../lms/models.dart';
import '../lms/snapshot.dart';

/// SHA-256 of `"tuitmate-admin-v1:" + key` for the owner's key. Only the holder
/// of that key can turn on admin features in any copy of the app; the key
/// itself is never in the source code.
const adminKeyFingerprint = 'fc09d9702c32a5aab55fb688cec2dd057c8b63c63923ca0bc301669cbf2b1e35';

class AutomationKey {
  AutomationKey._();

  /// 32 key bytes from base64 (standard or URL-safe, padding optional) or 64 hex
  /// characters; null for anything else.
  static List<int>? parse(String? text) {
    final t = (text ?? '').replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(t)) {
      return [for (var i = 0; i < 64; i += 2) int.parse(t.substring(i, i + 2), radix: 16)];
    }
    try {
      var b = t.replaceAll('-', '+').replaceAll('_', '/');
      while (b.length % 4 != 0) {
        b += '=';
      }
      final bytes = base64.decode(b);
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> fingerprint(List<int> key) async {
    final h = await Sha256().hash([...utf8.encode('tuitmate-admin-v1:'), ...key]);
    return _hex(h.bytes);
  }

  /// True when [text] is the owner's key.
  static Future<bool> isOwnerKey(String? text) async {
    final key = parse(text);
    if (key == null) return false;
    final f = await fingerprint(key);
    // Compare every character (no early exit).
    var diff = f.length ^ adminKeyFingerprint.length;
    for (var i = 0; i < f.length && i < adminKeyFingerprint.length; i++) {
      diff |= f.codeUnitAt(i) ^ adminKeyFingerprint.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// The unlocked key from the keystore, or null.
  static Future<List<int>?> load() async => parse(await Secrets.read(Secrets.adminKey));
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// One event before it is sealed.
class AutomationEvent {
  final String type;
  final String id;
  final DateTime sentAt; // UTC
  final Map<String, dynamic> payload;
  AutomationEvent(this.type, this.payload, {String? id, DateTime? sentAt})
      : id = id ?? _newId(),
        sentAt = (sentAt ?? DateTime.now()).toUtc();

  static final _random = Random.secure();
  static String _newId() => 'evt_${_hex([for (var i = 0; i < 16; i++) _random.nextInt(256)])}';

  String get sentAtText => sentAt.toIso8601String();
}

class Automation {
  Automation._();

  /// Every event type, in the order shown in settings.
  static const eventTypes = [
    'task.new',
    'task.deadline_changed',
    'task.graded',
    'task.deadline_soon',
    'exam.changed',
    'exam.result',
    'absence.new',
    'file.new',
    'news.new',
    'summary.daily',
    'snapshot.full',
  ];

  static const _maxQueue = 100;
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    // Any status is a response; delivery decides what counts as success.
    validateStatus: (_) => true,
  ));

  /// Admin unlocked and a webhook set: events are produced and sent.
  static bool active(Settings s) => s.adminUnlocked && (s.webhookUrl ?? '').isNotEmpty;

  static bool enabled(Settings s, String type) {
    if (type == 'snapshot.full') return s.webhookSnapshot;
    return s.webhookEvents?.contains(type) ?? true;
  }

  // ------------------------------------------------------------ sealing

  /// Additional data bound to the ciphertext: the readable envelope fields.
  static List<int> aad(String id, String type, String sentAt) => utf8.encode('tuitmate.v1|$id|$type|$sentAt');

  /// The JSON body that is POSTed. With [encrypt] the payload is sealed with
  /// AES-256-GCM (12-byte random IV, 16-byte tag appended to the ciphertext).
  static Future<String> seal(AutomationEvent e, List<int> key, {bool encrypt = true, String? source}) async {
    final clear = {'v': 1, 'id': e.id, 'event': e.type, 'sent_at': e.sentAtText, 'payload': e.payload};
    final envelope = <String, dynamic>{
      'v': 1,
      'id': e.id,
      'event': e.type,
      'sent_at': e.sentAtText,
      'source': source ?? Platform.operatingSystem,
      'app_version': appVersion,
    };
    if (encrypt) {
      final aes = AesGcm.with256bits();
      final box = await aes.encrypt(
        utf8.encode(jsonEncode(clear)),
        secretKey: SecretKey(key),
        nonce: aes.newNonce(),
        aad: aad(e.id, e.type, e.sentAtText),
      );
      envelope['enc'] = 'A256GCM';
      envelope['iv'] = base64.encode(box.nonce);
      envelope['data'] = base64.encode([...box.cipherText, ...box.mac.bytes]);
    } else {
      envelope['enc'] = 'none';
      envelope['payload'] = e.payload;
    }
    return jsonEncode(envelope);
  }

  /// `sha256=<hex>`: HMAC-SHA256 of the exact body bytes with the same key.
  static Future<String> signature(String body, List<int> key) async {
    final mac = await Hmac.sha256().calculateMac(utf8.encode(body), secretKey: SecretKey(key));
    return 'sha256=${_hex(mac.bytes)}';
  }

  /// Opens a body made by [seal] (used by tests and the in-app self-check).
  static Future<Map<String, dynamic>> open(String body, List<int> key) async {
    final env = jsonDecode(body) as Map<String, dynamic>;
    if (env['enc'] == 'none') return {'v': 1, 'id': env['id'], 'event': env['event'], 'sent_at': env['sent_at'], 'payload': env['payload']};
    final data = base64.decode(env['data'] as String);
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(data.sublist(0, data.length - 16), nonce: base64.decode(env['iv'] as String), mac: Mac(data.sublist(data.length - 16))),
      secretKey: SecretKey(key),
      aad: aad(env['id'] as String, env['event'] as String, env['sent_at'] as String),
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------ events

  static String? _iso(DateTime? d) => d?.toIso8601String();

  static Map<String, dynamic> taskJson(Assignment a) => {
        'course': a.courseName,
        'course_id': a.courseId,
        'title': a.title,
        'type': a.taskType,
        'teacher': a.teacher,
        'deadline': _iso(a.deadline),
        'status': a.status.name,
        'submitted': a.isSubmitted,
        'grade': a.grade,
        'max_grade': a.maxGrade,
        'open': isOpenTask(a),
        'midterm': a.midterm,
        if (a.taskFile != null) 'task_file': {'name': a.taskFile!.name, 'url': a.taskFile!.url},
        if (a.uploadedFile != null) 'your_file': {'name': a.uploadedFile!.name, 'url': a.uploadedFile!.url},
        if (a.criteria.isNotEmpty) 'criteria': [for (final c in a.criteria) {'text': c.text, 'points': c.points}],
      };

  static Map<String, dynamic> _examJson(ExamFinal f) => {
        'subject': f.subject,
        'starts_at': _iso(f.startsAt),
        'from': f.from,
        'to': f.to,
        'room': f.room,
        'stream': f.stream,
        'time_limit_min': f.timeLimit,
        'grade': f.grade,
        'test_points': [for (final p in f.testPoints) {'n': p.number, 'points': p.point}],
      };

  static Map<String, dynamic> _absenceJson(Absence a) => {
        'subject': a.subject,
        'date': _iso(a.date),
        'lesson_type': a.lessonType,
        'theme': a.theme,
        'theme_number': a.themeNumber,
        'excused': a.excused,
      };

  static Map<String, dynamic> _attendanceJson(LmsSnapshot snap, Settings settings) {
    final att = AttendanceSummary.from(snap, settings);
    return {'nb': att.absences, 'hours_used': att.hoursUsed, 'hours_limit': att.limitHours, 'hours_left': att.hoursLeft};
  }

  static String _type(ChangeKind k) => switch (k) {
        ChangeKind.newAssignment => 'task.new',
        ChangeKind.deadlineChanged => 'task.deadline_changed',
        ChangeKind.gradePosted => 'task.graded',
        ChangeKind.reminder => 'task.deadline_soon',
        ChangeKind.examChanged => 'exam.changed',
        ChangeKind.examGrade => 'exam.result',
        ChangeKind.newAbsence => 'absence.new',
        ChangeKind.newFile => 'file.new',
        ChangeKind.news => 'news.new',
      };

  /// Events for the changes of one sync, with the full objects from [snap].
  static List<AutomationEvent> eventsFor(List<LmsChange> changes, LmsSnapshot snap, Settings settings) {
    Assignment? task(String key) {
      for (final a in snap.assignments) {
        if (a.key == key || key.startsWith('${a.key}|')) return a;
      }
      return null;
    }

    final out = <AutomationEvent>[];
    for (final c in changes) {
      final type = _type(c.kind);
      final base = <String, dynamic>{'subject': c.subject, 'title': c.detail, 'when': _iso(c.when), 'key': c.key};
      final Map<String, dynamic> payload;
      switch (c.kind) {
        case ChangeKind.newAssignment || ChangeKind.deadlineChanged || ChangeKind.gradePosted:
          final a = task(c.key);
          payload = {...base, if (a != null) 'task': taskJson(a)};
        case ChangeKind.reminder:
          // "rem<h>|<task key>|<upload id>|<deadline>" (lib/lms/changes.dart dueReminders).
          final parts = c.key.split('|');
          final a = parts.length > 3 ? task(parts.sublist(1, parts.length - 2).join('|')) : null;
          payload = {...base, 'hours_before': c.value, if (a != null) 'task': taskJson(a)};
        case ChangeKind.examChanged || ChangeKind.examGrade:
          final f = snap.finals.where((f) => f.key == c.key).firstOrNull;
          payload = {...base, if (f != null) 'exam': _examJson(f)};
        case ChangeKind.newAbsence:
          final a = snap.absences.where((a) => a.key == c.key).firstOrNull;
          payload = {...base, if (a != null) 'absence': _absenceJson(a), 'attendance': _attendanceJson(snap, settings)};
        case ChangeKind.newFile:
          payload = {...base, 'file': {'name': c.detail, 'url': c.key.startsWith('file|') ? c.key.substring(5) : null}};
        case ChangeKind.news:
          final n = snap.news.where((n) => n.key == c.key).firstOrNull;
          payload = {...base, if (n != null) 'news': {'title': n.title, 'date': _iso(n.date), 'url': n.url, 'body': n.body}};
      }
      out.add(AutomationEvent(type, payload));
    }
    return out;
  }

  /// The day at a glance: classes, what is due in 48 hours, attendance, GPA.
  static Map<String, dynamic> dailySummary(LmsSnapshot snap, Settings settings, DateTime now) {
    final today = dateOnly(now);
    final due = snap.assignments
        .where((a) => isOpenTask(a) && a.deadline != null && a.deadline!.isBefore(now.add(const Duration(hours: 48))))
        .toList()
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
    return {
      'date': _iso(today)!.substring(0, 10),
      'week': weekSideFor(today, settings, snap) == WeekSide.right ? 'even' : 'odd',
      'classes': [
        for (final c in classesOn(today, settings, snap))
          {
            'start': _iso(c.start),
            'end': _iso(c.end),
            'subject': c.item.displaySubject,
            'room': c.item.room,
            'type': c.item.type.name,
            'topic': c.topic,
          },
      ],
      'due_48h': [for (final a in due) taskJson(a)],
      'open_tasks': snap.assignments.where(isOpenTask).length,
      'attendance': _attendanceJson(snap, settings),
      'gpa': snap.planSummary?.gpa ?? estimatedGpa(snap.studyPlan),
    };
  }

  /// The whole snapshot as JSON (without the profile photo).
  static Map<String, dynamic> snapshotJson(LmsSnapshot snap) {
    final j = jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>;
    final info = j['info'];
    if (info is Map) info.remove('photo');
    return j;
  }

  // ------------------------------------------------------------ delivery

  /// Deliveries run one after another, so two syncs never send the queue twice.
  static Future<void> _chain = Future.value();

  /// Seals and sends the events of one sync, plus the daily summary when it is
  /// due, plus anything that failed earlier. Never throws.
  static Future<void> deliver({
    required List<LmsChange> changes,
    required LmsSnapshot snap,
    required Settings settings,
    required AppStorage storage,
    DateTime? now,
  }) =>
      _chain = _chain.then((_) => _deliver(changes, snap, settings, storage, now));

  static Future<void> _deliver(
      List<LmsChange> changes, LmsSnapshot snap, Settings settings, AppStorage storage, DateTime? now) async {
    try {
      if (!active(settings) || snap.isEmpty) return;
      final key = await AutomationKey.load();
      if (key == null) return;
      final t = now ?? DateTime.now();
      final state = await storage.readJson(storage.automationFile);
      final queue = [for (final b in (state['queue'] as List? ?? const [])) '$b'];

      final events = [
        ...eventsFor(changes, snap, settings),
        if (_dailyDue(state, settings, t)) AutomationEvent('summary.daily', dailySummary(snap, settings, t)),
        if (settings.webhookSnapshot) AutomationEvent('snapshot.full', snapshotJson(snap)),
      ];
      if (events.any((e) => e.type == 'summary.daily')) state['lastDaily'] = _day(t);
      // Only the newest full snapshot is worth sending; drop older unsent ones.
      if (events.any((e) => e.type == 'snapshot.full' && enabled(settings, e.type))) {
        queue.removeWhere((b) => _eventOf(b) == 'snapshot.full');
      }
      for (final e in events) {
        if (!enabled(settings, e.type)) continue;
        queue.add(await seal(e, key, encrypt: settings.webhookEncrypt));
      }

      final left = <String>[];
      var failed = false;
      for (final body in queue) {
        // After one failure keep the rest for the next sync (likely offline).
        if (failed || !await _post(settings.webhookUrl!, body, key)) {
          failed = true;
          left.add(body);
        }
      }
      state['queue'] = left.length > _maxQueue ? left.sublist(left.length - _maxQueue) : left;
      state['lastAttempt'] = t.toUtc().toIso8601String();
      if (!failed && queue.isNotEmpty) state['lastSuccess'] = t.toUtc().toIso8601String();
      await storage.writeJson(storage.automationFile, state);
    } catch (_) {}
  }

  static String? _eventOf(String body) {
    try {
      return (jsonDecode(body) as Map)['event'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String _day(DateTime t) => _iso(dateOnly(t))!.substring(0, 10);

  static bool _dailyDue(Map<String, dynamic> state, Settings settings, DateTime t) {
    if (!enabled(settings, 'summary.daily')) return false;
    final at = dateOnly(t).add(Duration(minutes: settings.briefAt));
    return !t.isBefore(at) && state['lastDaily'] != _day(t);
  }

  static Future<bool> _post(String url, String body, List<int> key) async {
    try {
      final env = jsonDecode(body) as Map<String, dynamic>;
      final r = await _dio.post<dynamic>(
        url,
        data: body,
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'TuitMate/$appVersion',
            'X-TuitMate-Event': env['event'],
            'X-TuitMate-Id': env['id'],
            'X-TuitMate-Signature': await signature(body, key),
          },
        ),
      );
      final code = r.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }

  /// Sends a `test.ping` now. Returns null on success, otherwise what went wrong.
  static Future<String?> sendTest(Settings settings) async {
    final key = await AutomationKey.load();
    final url = settings.webhookUrl;
    if (key == null) return 'no key';
    if (url == null || url.isEmpty) return 'no webhook URL';
    final e = AutomationEvent('test.ping', {'message': 'Hello from TuitMate', 'app_version': appVersion});
    final body = await seal(e, key, encrypt: settings.webhookEncrypt);
    try {
      final r = await _dio.post<dynamic>(
        url,
        data: body,
        options: Options(contentType: 'application/json', responseType: ResponseType.plain, headers: {
          'User-Agent': 'TuitMate/$appVersion',
          'X-TuitMate-Event': e.type,
          'X-TuitMate-Id': e.id,
          'X-TuitMate-Signature': await signature(body, key),
        }),
      );
      final code = r.statusCode ?? 0;
      if (code >= 200 && code < 300) return null;
      final text = '${r.data ?? ''}'.trim();
      return 'HTTP $code${text.isEmpty ? '' : ': ${text.length > 160 ? '${text.substring(0, 160)}…' : text}'}';
    } on DioException catch (e) {
      return e.message ?? e.type.name;
    } catch (e) {
      return '$e';
    }
  }

  /// Sends the summary (and the snapshot when [full]) right now.
  static Future<String?> sendNow(LmsSnapshot snap, Settings settings, {bool full = false}) async {
    final key = await AutomationKey.load();
    final url = settings.webhookUrl;
    if (key == null) return 'no key';
    if (url == null || url.isEmpty) return 'no webhook URL';
    final e = full
        ? AutomationEvent('snapshot.full', snapshotJson(snap))
        : AutomationEvent('summary.daily', dailySummary(snap, settings, DateTime.now()));
    return await _post(url, await seal(e, key, encrypt: settings.webhookEncrypt), key) ? null : 'not delivered';
  }

  /// Events waiting to be delivered.
  static Future<int> pending(AppStorage storage) async {
    final state = await storage.readJson(storage.automationFile);
    return (state['queue'] as List?)?.length ?? 0;
  }
}
