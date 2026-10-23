// The webhook format must match docs/AUTOMATION.md and the reference decoders
// in docs/automation/examples (Node.js and Python), which n8n and other tools use.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/lms/changes.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/snapshot.dart';
import 'package:tuitmate/core/settings.dart';
import 'package:tuitmate/core/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuitmate/services/automation.dart';

// A fixed TEST key (bytes 0..31), not the owner's key.
const testKeyB64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
final testKey = List<int>.generate(32, (i) => i);

Future<ProcessResult?> runIfAvailable(String exe, List<String> args, {Map<String, String>? env}) async {
  try {
    return await Process.run(exe, args, environment: env);
  } on ProcessException {
    return null; // tool not installed
  }
}

void main() {
  test('keys: base64, URL-safe base64 and hex; wrong length rejected', () async {
    expect(AutomationKey.parse(testKeyB64), testKey);
    expect(AutomationKey.parse(testKeyB64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')), testKey);
    expect(AutomationKey.parse(testKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()), testKey);
    expect(AutomationKey.parse(' $testKeyB64\n'), testKey);
    expect(AutomationKey.parse('AAEC'), isNull);
    expect(AutomationKey.parse('not a key'), isNull);
    expect(AutomationKey.parse(null), isNull);
    // Fingerprint computed independently with Python's hashlib.
    expect(await AutomationKey.fingerprint(testKey), 'c55a182a8f30a2117abef3bee69380833d146849481735e72663188133b11ddd');
    expect(await AutomationKey.isOwnerKey(testKeyB64), isFalse);
    expect(adminKeyFingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('sealed events open again; any change to the envelope is rejected', () async {
    final e = AutomationEvent('task.new', {'title': 'Lab 3', 'n': 1, 'uz': 'Oʻzbekcha'});
    final body = await Automation.seal(e, testKey, source: 'test');
    final env = jsonDecode(body) as Map<String, dynamic>;
    expect(env['enc'], 'A256GCM');
    expect(base64.decode(env['iv']).length, 12);
    expect(env.containsKey('payload'), isFalse); // nothing readable but the routing fields
    expect(body.contains('Lab 3'), isFalse);

    final opened = await Automation.open(body, testKey);
    expect(opened['event'], 'task.new');
    expect(opened['id'], e.id);
    expect(opened['payload'], {'title': 'Lab 3', 'n': 1, 'uz': 'Oʻzbekcha'});

    // Changing a readable field breaks the authentication (it is bound as AAD).
    final forged = jsonEncode({...env, 'event': 'task.graded'});
    expect(() => Automation.open(forged, testKey), throwsA(anything));
    expect(() => Automation.open(body, List<int>.filled(32, 7)), throwsA(anything));

    final plain = await Automation.seal(e, testKey, encrypt: false, source: 'test');
    expect((jsonDecode(plain) as Map)['payload'], {'title': 'Lab 3', 'n': 1, 'uz': 'Oʻzbekcha'});
    expect((await Automation.open(plain, testKey))['event'], 'task.new');
  });

  test('Node.js and Python reference decoders open what the app sends', () async {
    final tmp = Directory.systemTemp.createTempSync('tuitmate_auto');
    final e = AutomationEvent('summary.daily', {'date': '2026-10-23', 'classes': [], 'uz': 'Oʻqituvchi', 'ru': 'Пары'});
    final body = await Automation.seal(e, testKey, source: 'test');
    final sig = await Automation.signature(body, testKey);
    final file = File('${tmp.path}/body.json')..writeAsStringSync(body);
    final env = {...Platform.environment, 'TUITMATE_KEY': testKeyB64};

    final node = await runIfAvailable('node', ['docs/automation/examples/open-event.js', file.path, sig], env: env);
    if (node == null) {
      markTestSkipped('node not installed');
    } else {
      expect(node.exitCode, 0, reason: '${node.stderr}');
      final out = jsonDecode(node.stdout as String) as Map<String, dynamic>;
      expect(out['payload'], e.payload);
      expect(out['event'], 'summary.daily');
      // A wrong signature is refused.
      final bad = await runIfAvailable('node', ['docs/automation/examples/open-event.js', file.path, 'sha256=00'], env: env);
      expect(bad!.exitCode, isNot(0));
    }

    final py = await runIfAvailable('python3', ['-I', 'docs/automation/examples/open_event.py', file.path, sig], env: env);
    if (py == null || '${py.stderr}'.contains("No module named 'cryptography'")) {
      markTestSkipped('python3 with cryptography not installed');
    } else {
      expect(py.exitCode, 0, reason: '${py.stderr}');
      expect((jsonDecode(py.stdout as String) as Map)['payload'], e.payload);
    }

    // The n8n Code node snippet gives the same result (run with a stand-in for n8n's $input).
    final n8n = File('docs/automation/n8n-code-node.js').readAsStringSync();
    final harness = File('${tmp.path}/harness.js')
      ..writeAsStringSync('''
const \$input = { all: () => [{ json: { headers: { 'x-tuitmate-signature': ${jsonEncode(sig)} }, body: ${jsonEncode(jsonDecode(body))} } }] };
const \$env = { TUITMATE_KEY: ${jsonEncode(testKeyB64)} };
const result = (function () { $n8n })();
process.stdout.write(JSON.stringify(result));
''');
    final run = await runIfAvailable('node', [harness.path]);
    if (run != null) {
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final items = jsonDecode(run.stdout as String) as List;
      expect(items.single['json']['event'], 'summary.daily');
      expect(items.single['json']['payload'], e.payload);
    }
    tmp.deleteSync(recursive: true);
  });

  test('changes become events with the full task, exam and absence', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    final deadline = DateTime(2026, 10, 25, 23, 59);
    final task = Assignment(courseId: 1, courseName: 'Database', name: 'Lab 3', maxGrade: 5, deadline: deadline, uploadId: 9, activityId: 77);
    const absence = Absence(subject: 'Database', subjectId: 3, themeNumber: 6, lessonType: 'Amaliy');
    final snap = LmsSnapshot(
      courses: const [Course(id: 1, subject: 'Database', subjectId: 3)],
      coursePages: {1: CoursePage(const CourseRating(), [task])},
      absences: const [absence],
      updatedAt: DateTime(2026, 10, 23),
    );
    final events = Automation.eventsFor([
      LmsChange(ChangeKind.newAssignment, task.key, 'Database', 'Lab 3', when: deadline),
      LmsChange(ChangeKind.reminder, 'rem3|${task.key}|9|${deadline.toIso8601String()}', 'Database', 'Lab 3', when: deadline, value: 3),
      LmsChange(ChangeKind.newAbsence, absence.key, 'Database', 'Amaliy'),
      const LmsChange(ChangeKind.newFile, 'file|https://dl.tuit.uz/f/1.pdf', 'Database', '1.pdf'),
    ], snap, settings);
    expect(events.map((e) => e.type), ['task.new', 'task.deadline_soon', 'absence.new', 'file.new']);
    expect(events[0].payload['task']['title'], 'Lab 3');
    expect(events[0].payload['task']['open'], isTrue);
    expect(events[1].payload['task']['title'], 'Lab 3'); // reminder key resolved to the task
    expect(events[1].payload['hours_before'], 3);
    expect(events[2].payload['attendance']['hours_used'], 2);
    expect(events[3].payload['file']['url'], 'https://dl.tuit.uz/f/1.pdf');
    // Every event survives sealing (JSON-encodable).
    for (final e in events) {
      expect((await Automation.open(await Automation.seal(e, testKey, source: 'test'), testKey))['payload'], isNotNull);
    }
  });

  test('delivery: signed posts, offline queue in order, one daily summary, newest snapshot only', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // flutter_test answers every request with 400 otherwise
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'read' && (call.arguments as Map)['key'] == Secrets.adminKey ? testKeyB64 : null);

    var up = false;
    final got = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      if (up) {
        expect(req.headers.value('x-tuitmate-signature'), await Automation.signature(body, testKey));
        final opened = await Automation.open(body, testKey);
        expect(req.headers.value('x-tuitmate-event'), opened['event']);
        got.add(opened);
      }
      req.response.statusCode = up ? 200 : 503;
      await req.response.close();
    });

    SharedPreferences.setMockInitialValues({
      'adminUnlocked': true,
      'webhookUrl': 'http://127.0.0.1:${server.port}/hook',
      'webhookSnapshot': true,
    });
    final settings = await Settings.load();
    final tmp = Directory.systemTemp.createTempSync('tuitmate_deliver');
    final storage = AppStorage.useDirectory(tmp);
    final task = Assignment(courseId: 1, courseName: 'Database', name: 'Lab 3', maxGrade: 5, deadline: DateTime(2026, 10, 25, 23, 59));
    final snap = LmsSnapshot(
      courses: const [Course(id: 1, subject: 'Database', subjectId: 3)],
      coursePages: {1: CoursePage(const CourseRating(), [task])},
      updatedAt: DateTime(2026, 10, 23, 6),
    );
    final change = LmsChange(ChangeKind.newAssignment, task.key, 'Database', 'Lab 3', when: task.deadline);
    Future<List> queued() async => (await storage.readJson(storage.automationFile))['queue'] as List;

    // Offline twice before the morning-brief time (07:30): events wait, one snapshot kept.
    await Automation.deliver(changes: [change], snap: snap, settings: settings, storage: storage, now: DateTime(2026, 10, 23, 6));
    expect(await queued(), hasLength(2));
    await Automation.deliver(changes: const [], snap: snap, settings: settings, storage: storage, now: DateTime(2026, 10, 23, 7));
    expect(await queued(), hasLength(2));
    expect(got, isEmpty);

    // Back online after 07:30: the queue first, then the daily summary and the newest snapshot.
    up = true;
    await Automation.deliver(changes: const [], snap: snap, settings: settings, storage: storage, now: DateTime(2026, 10, 23, 8));
    expect(got.map((e) => e['event']), ['task.new', 'summary.daily', 'snapshot.full']);
    expect(got.first['payload']['task']['title'], 'Lab 3');
    expect(await queued(), isEmpty);

    // Later the same day: no second summary.
    settings.webhookSnapshot = false;
    await Automation.deliver(changes: const [], snap: snap, settings: settings, storage: storage, now: DateTime(2026, 10, 23, 9));
    expect(got, hasLength(3));

    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  test('docs, n8n workflow and app agree', () {
    final wf = jsonDecode(File('docs/automation/n8n-workflow.json').readAsStringSync()) as Map<String, dynamic>;
    final code = (wf['nodes'] as List).firstWhere((n) => n['type'] == 'n8n-nodes-base.code')['parameters']['jsCode'];
    expect(code, File('docs/automation/n8n-code-node.js').readAsStringSync(), reason: 'regenerate the workflow from n8n-code-node.js');
    final hook = (wf['nodes'] as List).firstWhere((n) => n['type'] == 'n8n-nodes-base.webhook');
    expect(hook['parameters']['httpMethod'], 'POST');
    final guide = File('docs/AUTOMATION.md').readAsStringSync();
    for (final type in [...Automation.eventTypes, 'test.ping']) {
      expect(guide, contains('`$type`'), reason: 'AUTOMATION.md must document $type');
    }
    expect(guide, contains('tuitmate.v1|<id>|<event>|<sent_at>'));
  });
}
