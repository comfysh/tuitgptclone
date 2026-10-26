// Server tests. The database tests need a MySQL 8 server and an account that
// may create the database "tuitmate_test":
//   TUITMATE_TEST_DB_USER / TUITMATE_TEST_DB_PASSWORD (and _HOST, _PORT)
// Without them those tests are skipped.

import 'dart:convert';
import 'dart:io';

import 'package:mysql_client/mysql_client.dart';
import 'package:test/test.dart';
import 'package:tuitmate_lms/changes.dart';
import 'package:tuitmate_lms/lms_client.dart';
import 'package:tuitmate_lms/models.dart';
import 'package:tuitmate_lms/snapshot.dart';
import 'package:tuitmate_server/api.dart';
import 'package:tuitmate_server/config.dart';
import 'package:tuitmate_server/db.dart';
import 'package:tuitmate_server/fetcher.dart';
import 'package:tuitmate_server/schema.dart';
import 'package:tuitmate_server/secret_box.dart';
import 'package:tuitmate_server/store.dart';

final _env = Platform.environment;
final _dbUser = _env['TUITMATE_TEST_DB_USER'];

LmsSnapshot sample(DateTime now) {
  const courses = [
    Course(id: 30893, subject: 'Database', subjectId: 12, absenceCount: 1, teachers: ['Aliyeva D.'], streams: ['DBM402']),
    Course(id: 30655, subject: 'Discrete structures', subjectId: 13, teachers: ['Karimov A.', 'Qodirov S.'], streams: ['MTH402']),
  ];
  Assignment task(int c, String n, int days, {double? grade, bool up = false}) => Assignment(
        courseId: courses[c].id,
        courseName: courses[c].subject,
        taskType: 'Laboratoriya',
        teacher: courses[c].teachers.first,
        name: n,
        deadline: DateTime(now.year, now.month, now.day + days, 23, 59),
        grade: grade,
        maxGrade: 5,
        uploadId: 100 + n.length,
        activityId: 500 + n.length,
        uploadedFile: up ? const LmsFile('javob.docx', 'https://lms.tuit.uz/storage/a.docx') : null,
      );
  return LmsSnapshot(
    semesters: const [Semester(9, '2026-2027 First semester', selected: true)],
    semesterId: 9,
    courses: courses,
    coursePages: {
      30893: CoursePage(const CourseRating(achieved: 6, max: 50, ratingPercent: 13, grade: 2), [task(0, 'Lab 3', 2), task(0, "Lab 2: SQL so'rovlar", -5, grade: 5, up: true)]),
      30655: CoursePage(const CourseRating(), [task(1, 'Independent work 1', 9)]),
    },
    absences: [Absence(subject: 'Database', subjectId: 12, date: DateTime(now.year, now.month, now.day - 3), lessonType: 'Laboratoriya', theme: 'JOIN', themeNumber: 3)],
    finals: [ExamFinal(subject: 'Database', subjectId: 12, date: DateTime(now.year, now.month, now.day + 30), from: '09:00', to: '10:20', room: 'A-305')],
    schedule: [ScheduleItem(start: DateTime(now.year, now.month, now.day, 13), title: 't', subject: 'Discrete structures', room: 'B-209', type: LessonType.lecture, side: WeekSide.left)],
    news: [NewsItem(title: 'Yakuniy nazorat jadvali', body: 'Matn', date: DateTime(now.year, now.month, now.day - 1), url: 'https://lms.tuit.uz/news/77')],
    updatedAt: now,
    fullAt: now,
  );
}

void main() {
  test('SQL scripts split at semicolons outside quotes and comments', () {
    final parts = splitSql('''
-- a comment; with a semicolon
CREATE TABLE a (x INT COMMENT 'one; two', y VARCHAR(9) COMMENT 'it''s; fine');
INSERT INTO a VALUES (1, ";");
SELECT 1''');
    expect(parts, hasLength(3));
    expect(parts.first, contains("'one; two'"));
    expect(parts[1], 'INSERT INTO a VALUES (1, ";")');
  });

  test('the schema built into the server is sql/schema.sql', () {
    expect(schemaSql, File('sql/schema.sql').readAsStringSync(), reason: 'regenerate lib/schema.dart from sql/schema.sql');
    expect(splitSql(schemaSql).where((s) => s.startsWith('CREATE TABLE')), hasLength(13));
  });

  test('secrets: sealed values open only with the same key and context', () async {
    final vault = Vault(List<int>.generate(32, (i) => i));
    final sealed = await vault.seal('cookie value Ш', 'cookies:1');
    expect(sealed, isNot(contains('cookie')));
    expect(await vault.open(sealed, 'cookies:1'), 'cookie value Ш');
    expect(() => vault.open(sealed, 'cookies:2'), throwsA(anything));
    expect(() => Vault(List<int>.filled(32, 9)).open(sealed, 'cookies:1'), throwsA(anything));
    expect(() => Vault(const [1, 2, 3]), throwsArgumentError);
  });

  test('config file and connection code', () {
    final env = Config.parseEnv('# comment\nDB_USER=tuitmate\nDB_PASSWORD="p=a#ss"\n\nLISTEN_PORT=9443\n');
    final c = Config(env);
    expect((c.dbUser, c.dbPassword, c.port, c.fetchMinutes), ('tuitmate', 'p=a#ss', 9443, 5));
    final code = connectionCode('https://203.0.113.5:8443', 'tok', 'ab' * 32);
    expect(code, startsWith('tmsrv1.'));
    final payload = code.substring(7);
    final json = jsonDecode(utf8.decode(base64Url.decode(payload + '=' * ((4 - payload.length % 4) % 4))));
    expect(json, {'u': 'https://203.0.113.5:8443', 't': 'tok', 'f': 'ab' * 32});
  });

  group('with MySQL', skip: _dbUser == null ? 'set TUITMATE_TEST_DB_USER to run' : null, () {
    late Db db;
    late Store store;
    late Directory tmp;

    setUpAll(() async {
      final host = _env['TUITMATE_TEST_DB_HOST'] ?? '127.0.0.1';
      final port = int.parse(_env['TUITMATE_TEST_DB_PORT'] ?? '3306');
      final admin = await MySQLConnection.createConnection(
          host: host, port: port, userName: _dbUser!, password: _env['TUITMATE_TEST_DB_PASSWORD'] ?? '');
      await admin.connect();
      await admin.execute('DROP DATABASE IF EXISTS tuitmate_test');
      await admin.execute('CREATE DATABASE tuitmate_test CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci');
      await admin.close();
      db = await Db.open(Config({
        'DB_HOST': host,
        'DB_PORT': '$port',
        'DB_NAME': 'tuitmate_test',
        'DB_USER': _dbUser!,
        'DB_PASSWORD': _env['TUITMATE_TEST_DB_PASSWORD'] ?? '',
      }));
      store = Store(db, Vault(List<int>.generate(32, (i) => 255 - i)));
      tmp = Directory.systemTemp.createTempSync('tuitmate_server_test');
    });

    tearDownAll(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    test('schema applies twice; one account; tokens are stored as hashes', () async {
      await db.applySchema();
      await db.applySchema();
      final a = await store.ensureAccount(fetchMinutes: 7);
      expect(await store.ensureAccount(), a);
      expect(await store.fetchMinutes(a), 7);
      final token = await store.newToken(a, label: 'phone');
      expect(await store.accountForToken(token), a);
      expect(await store.accountForToken('${token}x'), isNull);
      final stored = await db.q('SELECT token_sha256 FROM api_tokens');
      expect(stored.rows.single.colByName('token_sha256'), isNot(contains(token)));
    });

    test('the session is stored encrypted, checked and ended', () async {
      final a = await store.ensureAccount();
      final cookie = makeCookie('tuitlms_session', 'abc123', path: '/', secure: true, httpOnly: true,
          expires: DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch);
      await store.saveSession(a, [cookie]);
      final raw = await db.q('SELECT cookies_enc FROM lms_sessions');
      expect(raw.rows.single.colByName('cookies_enc'), isNot(contains('abc123')));
      var s = (await store.session(a))!;
      expect((s.cookies.single.name, s.cookies.single.value, s.checkedAt, s.endedAt), ('tuitlms_session', 'abc123', null, null));
      await store.sessionChecked(a, [makeCookie('tuitlms_session', 'abc124')]);
      s = (await store.session(a))!;
      expect((s.cookies.single.value, s.checkedAt != null), ('abc124', true));
      await store.sessionEnded(a);
      expect((await store.session(a))!.endedAt, isNotNull);
      expect(await Fetcher(store, tmp.path).run(a), FetchOutcome.noSession); // waits for the app
    });

    test('snapshots, changes and the current-state tables', () async {
      final a = await store.ensureAccount();
      final now = DateTime.now();
      final first = sample(now.subtract(const Duration(minutes: 5)));
      await store.saveSnapshot(a, first, full: true);
      final second = sample(now);
      second.coursePages = {
        ...second.coursePages,
        30893: CoursePage(second.coursePages[30893]!.rating, [
          ...second.coursePages[30893]!.assignments,
          Assignment(courseId: 30893, courseName: 'Database', name: 'Lab 4', deadline: DateTime(now.year, now.month, now.day + 6, 23, 59), uploadId: 999, activityId: 999),
        ]),
      };
      final changes = diffSnapshots(first, second);
      expect(changes.map((c) => c.kind), [ChangeKind.newAssignment]);
      await store.saveSnapshot(a, second, full: false);
      await store.addChanges(a, changes, now);
      await store.writeCurrentState(a, second);

      final back = (await store.latestSnapshot(a))!;
      expect(back.assignments.map((x) => x.title), contains('Lab 4'));
      expect(back.updatedAt!.difference(now).inSeconds.abs(), lessThan(2));
      final list = await store.changesAfter(a, 0);
      expect(list.single['subject'], 'Database');
      expect(list.single['kind'], 'newAssignment');
      expect(await store.changesAfter(a, list.single['id'] as int), isEmpty);

      Future<int> count(String table) async =>
          int.parse((await db.q('SELECT COUNT(*) AS n FROM $table WHERE account_id = :a', {'a': a})).rows.single.colByName('n')!);
      expect(await count('courses'), 2);
      expect(await count('assignments'), 4);
      expect(await count('absences'), 1);
      expect(await count('exams'), 1);
      expect(await count('classes'), 1);
      expect(await count('news'), 1);
      final graded = await db.q("SELECT title, grade, status FROM assignments WHERE status = 'graded'");
      expect(graded.rows.single.colByName('title'), "Lab 2: SQL so'rovlar");
      final side = await db.q('SELECT week_side FROM classes');
      expect(side.rows.single.colByName('week_side'), 'odd');
      // Rewriting does not duplicate.
      await store.writeCurrentState(a, second);
      expect(await count('assignments'), 4);
    });

    test('only the newest snapshots are kept', () async {
      final a = await store.ensureAccount();
      for (var i = 0; i < 5; i++) {
        await store.saveSnapshot(a, sample(DateTime.now()), full: false, keep: 3);
      }
      final n = await db.q('SELECT COUNT(*) AS n FROM snapshots WHERE account_id = :a', {'a': a});
      expect(n.rows.single.colByName('n'), '3');
    });

    test('the API: token, status, snapshot, changes, session', () async {
      final a = await store.ensureAccount();
      final token = await store.newToken(a);
      // A throwaway self-signed certificate.
      final cert = '${tmp.path}/cert.pem', key = '${tmp.path}/key.pem';
      final r = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes', //
        '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=tuitmate-test',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final fingerprint = await certFingerprint(cert);
      expect(fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));

      final api = Api(store, Fetcher(store, tmp.path), log: (_) {});
      await api.start(address: '127.0.0.1', port: 0, tls: SecurityContext()..useCertificateChain(cert)..usePrivateKey(key));
      addTearDown(api.stop);
      final port = api.port!;
      final client = HttpClient()..badCertificateCallback = (c, _, _) => true;
      addTearDown(client.close);
      Future<(int, String)> call(String method, String path, {String? auth, Object? body}) async {
        final req = await client.openUrl(method, Uri.parse('https://127.0.0.1:$port$path'));
        if (auth != null) req.headers.set('Authorization', 'Bearer $auth');
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final res = await req.close();
        return (res.statusCode, await utf8.decodeStream(res));
      }

      expect((await call('GET', '/health')).$2, 'ok');
      expect((await call('GET', '/v1/status')).$1, 401);
      expect((await call('GET', '/v1/status', auth: 'not-a-token-not-a-token')).$1, 401);
      final status = await call('GET', '/v1/status', auth: token);
      expect(status.$1, 200);
      expect(jsonDecode(status.$2)['snapshot_at'], isNotNull);

      final snap = await call('GET', '/v1/snapshot', auth: token);
      expect(snap.$1, 200);
      final body = jsonDecode(snap.$2) as Map<String, dynamic>;
      final parsed = LmsSnapshot.fromJson(Map<String, dynamic>.from(body['snapshot']));
      expect(parsed.courses, hasLength(2));
      final at = DateTime.parse(body['fetched_at'] as String);
      expect((await call('GET', '/v1/snapshot?after=${Uri.encodeQueryComponent(at.toIso8601String())}', auth: token)).$1, 204);

      final changes = jsonDecode((await call('GET', '/v1/changes?after=0', auth: token)).$2)['changes'] as List;
      expect(changes, isNotEmpty);

      expect((await call('PUT', '/v1/session', auth: token, body: {'cookies': []})).$1, 400);
      expect((await call('PUT', '/v1/session', auth: token, body: {'cookies': [{'name': 'XSRF-TOKEN', 'value': 'x'}]})).$1, 400);
      expect((await call('DELETE', '/v1/session', auth: token)).$1, 200);
      expect(jsonDecode((await call('GET', '/v1/status', auth: token)).$2)['session']['state'], 'none');
      expect((await call('GET', '/v1/nothing', auth: token)).$1, 404);
    });
  });
}
