import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:tuitmate_lms/changes.dart';
import 'package:tuitmate_lms/lms_client.dart';
import 'package:tuitmate_lms/models.dart';
import 'package:tuitmate_lms/snapshot.dart';

import 'db.dart';
import 'secret_box.dart';

/// Everything the server reads and writes in MySQL (sql/schema.sql).
class Store {
  Store(this.db, this.vault);
  final Db db;
  final Vault vault;

  // ------------------------------------------------------------ accounts

  /// The first account, created when there is none (one person per server).
  Future<int> ensureAccount({int fetchMinutes = 5}) async {
    final r = await db.q('SELECT id FROM accounts ORDER BY id LIMIT 1');
    if (r.rows.isNotEmpty) return int.parse(r.rows.first.colByName('id')!);
    final ins = await db.q("INSERT INTO accounts (label, fetch_minutes) VALUES ('me', :m)", {'m': fetchMinutes});
    return ins.lastInsertID.toInt();
  }

  Future<List<int>> accountIds() async {
    final r = await db.q('SELECT id FROM accounts ORDER BY id');
    return [for (final row in r.rows) int.parse(row.colByName('id')!)];
  }

  Future<int> fetchMinutes(int account) async {
    final r = await db.q('SELECT fetch_minutes FROM accounts WHERE id = :id', {'id': account});
    return r.rows.isEmpty ? 5 : int.parse(r.rows.first.colByName('fetch_minutes')!);
  }

  // ------------------------------------------------------------ app tokens

  /// A new random token for the app; only its SHA-256 is stored.
  Future<String> newToken(int account, {String label = 'app'}) async {
    final rnd = Random.secure();
    final token = base64Url.encode(List<int>.generate(32, (_) => rnd.nextInt(256))).replaceAll('=', '');
    await db.q('INSERT INTO api_tokens (account_id, token_sha256, label) VALUES (:a, :h, :l)', {
      'a': account,
      'h': await sha256Hex(utf8.encode(token)),
      'l': cut(label, 64),
    });
    return token;
  }

  /// The account a token belongs to (and notes that it was used).
  Future<int?> accountForToken(String token) async {
    if (token.length < 20 || token.length > 200) return null;
    final h = await sha256Hex(utf8.encode(token));
    final r = await db.q('SELECT id, account_id FROM api_tokens WHERE token_sha256 = :h', {'h': h});
    if (r.rows.isEmpty) return null;
    await db.q('UPDATE api_tokens SET last_used_at = :t WHERE id = :id',
        {'t': sqlTime(DateTime.now()), 'id': int.parse(r.rows.first.colByName('id')!)});
    return int.parse(r.rows.first.colByName('account_id')!);
  }

  Future<int> revokeTokens(int account) async =>
      (await db.q('DELETE FROM api_tokens WHERE account_id = :a', {'a': account})).affectedRows.toInt();

  // ------------------------------------------------------------ LMS session

  /// The session the app handed over after signing in to LMS.
  Future<void> saveSession(int account, List<Cookie> cookies) async {
    await db.q(
      'INSERT INTO lms_sessions (account_id, cookies_enc, obtained_at, checked_at, ended_at) '
      'VALUES (:a, :c, :t, NULL, NULL) '
      'ON DUPLICATE KEY UPDATE cookies_enc = VALUES(cookies_enc), obtained_at = VALUES(obtained_at), '
      'checked_at = NULL, ended_at = NULL',
      {'a': account, 'c': await _sealCookies(account, cookies), 't': sqlTime(DateTime.now())},
    );
  }

  /// LMS accepted the session: keep its cookies as LMS last sent them (the
  /// expiry moves forward with every request).
  Future<void> sessionChecked(int account, List<Cookie> cookies) async {
    await db.q(
      'UPDATE lms_sessions SET cookies_enc = :c, checked_at = :t, ended_at = NULL WHERE account_id = :a',
      {'a': account, 'c': await _sealCookies(account, cookies), 't': sqlTime(DateTime.now())},
    );
  }

  /// LMS no longer accepts the session.
  Future<void> sessionEnded(int account) => db.q(
      'UPDATE lms_sessions SET ended_at = :t WHERE account_id = :a AND ended_at IS NULL',
      {'a': account, 't': sqlTime(DateTime.now())});

  Future<SessionInfo?> session(int account) async {
    final r = await db.q(
        'SELECT cookies_enc, obtained_at, checked_at, ended_at FROM lms_sessions WHERE account_id = :a', {'a': account});
    if (r.rows.isEmpty) return null;
    final row = r.rows.first;
    List<Cookie> cookies;
    try {
      final list = jsonDecode(await vault.open(row.colByName('cookies_enc')!, 'cookies:$account')) as List;
      cookies = [for (final j in list) cookieFromJson(Map<String, dynamic>.from(j))];
    } catch (_) {
      cookies = const [];
    }
    return SessionInfo(
      cookies,
      fromSqlUtc(row.colByName('obtained_at'))!,
      fromSqlUtc(row.colByName('checked_at')),
      fromSqlUtc(row.colByName('ended_at')),
    );
  }

  Future<void> forgetSession(int account) => db.q('DELETE FROM lms_sessions WHERE account_id = :a', {'a': account});

  Future<String> _sealCookies(int account, List<Cookie> cookies) =>
      vault.seal(jsonEncode([for (final c in cookies) cookieToJson(c)]), 'cookies:$account');

  // ------------------------------------------------------------ fetch runs

  Future<int> startRun(int account, bool full) async {
    final r = await db.q('INSERT INTO fetch_runs (account_id, started_at, full_sync) VALUES (:a, :t, :f)',
        {'a': account, 't': sqlTime(DateTime.now()), 'f': full});
    return r.lastInsertID.toInt();
  }

  Future<void> finishRun(int run, {required bool ok, int changes = 0, List<String> failedParts = const [], String? error, required int ms}) =>
      db.q(
        'UPDATE fetch_runs SET finished_at = :t, ok = :ok, changes = :c, failed_parts = :fp, error = :e, duration_ms = :ms WHERE id = :id',
        {
          't': sqlTime(DateTime.now()),
          'ok': ok,
          'c': changes,
          'fp': failedParts.isEmpty ? null : cut(failedParts.join(','), 512),
          'e': error,
          'ms': ms,
          'id': run,
        },
      );

  Future<RunInfo?> lastRun(int account, {bool okOnly = false}) async {
    final r = await db.q(
      'SELECT started_at, finished_at, full_sync, ok, changes, failed_parts, error FROM fetch_runs '
      'WHERE account_id = :a ${okOnly ? 'AND ok = TRUE' : 'AND finished_at IS NOT NULL'} ORDER BY id DESC LIMIT 1',
      {'a': account},
    );
    if (r.rows.isEmpty) return null;
    final row = r.rows.first;
    return RunInfo(
      startedAt: fromSqlUtc(row.colByName('started_at'))!,
      finishedAt: fromSqlUtc(row.colByName('finished_at')),
      full: row.colByName('full_sync') == '1',
      ok: row.colByName('ok') == '1',
      changes: int.tryParse(row.colByName('changes') ?? '') ?? 0,
      failedParts: (row.colByName('failed_parts') ?? '').split(',').where((s) => s.isNotEmpty).toList(),
      error: row.colByName('error'),
    );
  }

  // ------------------------------------------------------------ snapshots

  Future<void> saveSnapshot(int account, LmsSnapshot s, {required bool full, int keep = 100}) async {
    await db.q('INSERT INTO snapshots (account_id, fetched_at, full_sync, data) VALUES (:a, :t, :f, :d)', {
      'a': account,
      't': sqlTime(s.updatedAt ?? DateTime.now()),
      'f': full,
      'd': jsonEncode(s.toJson()),
    });
    // Keep the newest [keep].
    await db.q(
      'DELETE FROM snapshots WHERE account_id = :a AND id < ('
      'SELECT min_id FROM (SELECT id AS min_id FROM snapshots WHERE account_id = :a ORDER BY id DESC LIMIT 1 OFFSET ${keep - 1}) t)',
      {'a': account},
    );
  }

  /// The newest snapshot's time and JSON text (as stored).
  Future<(DateTime, String)?> latestSnapshotJson(int account) async {
    final r = await db.q(
        'SELECT fetched_at, data FROM snapshots WHERE account_id = :a ORDER BY id DESC LIMIT 1', {'a': account});
    if (r.rows.isEmpty) return null;
    return (fromSqlUtc(r.rows.first.colByName('fetched_at'))!, r.rows.first.colByName('data')!);
  }

  Future<LmsSnapshot?> latestSnapshot(int account) async {
    final j = await latestSnapshotJson(account);
    if (j == null) return null;
    try {
      return LmsSnapshot.fromJson(Map<String, dynamic>.from(jsonDecode(j.$2)));
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ changes

  Future<void> addChanges(int account, List<LmsChange> changes, DateTime at) async {
    if (changes.isEmpty) return;
    final params = <String, dynamic>{'a': account, 't': sqlTime(at)};
    final rows = <String>[];
    for (final (i, c) in changes.indexed) {
      rows.add('(:a, :t, :k$i, :key$i, :s$i, :d$i, :w$i, :v$i, :m$i)');
      params.addAll({
        'k$i': c.kind.name,
        'key$i': cut(c.key, 700),
        's$i': cut(c.subject, 255),
        'd$i': c.detail,
        'w$i': c.when == null ? null : sqlTime(c.when!, utc: false),
        'v$i': c.value,
        'm$i': c.max,
      });
    }
    await db.q(
      'INSERT INTO changes (account_id, detected_at, kind, change_key, subject, detail, when_at, value, max_value) VALUES ${rows.join(', ')}',
      params,
    );
  }

  /// Changes after the one with id [after], oldest first.
  Future<List<Map<String, dynamic>>> changesAfter(int account, int after, {int limit = 200}) async {
    final r = await db.q(
      'SELECT id, detected_at, kind, change_key, subject, detail, when_at, value, max_value FROM changes '
      'WHERE account_id = :a AND id > :after ORDER BY id LIMIT $limit',
      {'a': account, 'after': after},
    );
    return [
      for (final row in r.rows)
        {
          'id': int.parse(row.colByName('id')!),
          'detected_at': fromSqlUtc(row.colByName('detected_at'))?.toIso8601String(),
          'kind': row.colByName('kind'),
          'key': row.colByName('change_key'),
          'subject': row.colByName('subject'),
          'detail': row.colByName('detail'),
          'when': row.colByName('when_at')?.replaceFirst(' ', 'T'),
          'value': double.tryParse(row.colByName('value') ?? ''),
          'max': double.tryParse(row.colByName('max_value') ?? ''),
        },
    ];
  }

  // ------------------------------------------------------------ current state

  /// Rewrites courses, assignments, absences, exams, classes and news from
  /// [s] in one transaction (readers never see half of it).
  Future<void> writeCurrentState(int account, LmsSnapshot s) async {
    await db.tx((c) async {
      for (final t in const ['courses', 'assignments', 'absences', 'exams', 'classes', 'news']) {
        await c.execute('DELETE FROM $t WHERE account_id = :a', {'a': account});
      }
      String? at(DateTime? d) => d == null ? null : sqlTime(d, utc: false);
      await _insert(c, 'courses', account, [
        for (final course in s.courses)
          {
            'course_id': course.id,
            'subject': cut(course.subject, 255),
            'teachers': cut(course.teachers.join(', '), 512),
            'streams': cut(course.streams.join(', '), 255),
            'absence_count': course.absenceCount,
            'rating_percent': s.coursePages[course.id]?.rating.ratingPercent,
            'points': s.coursePages[course.id]?.rating.achieved,
            'max_points': s.coursePages[course.id]?.rating.max,
            'grade': s.coursePages[course.id]?.rating.grade,
          },
      ]);
      await _insert(c, 'assignments', account, [
        for (final a in s.assignments)
          {
            'course_id': a.courseId,
            'title': cut(a.title, 500),
            'task_type': a.taskType == null ? null : cut(a.taskType!, 100),
            'teacher': a.teacher == null ? null : cut(a.teacher!, 255),
            'deadline': at(a.deadline),
            'status': a.isGraded ? 'graded' : (a.isSubmitted ? 'submitted' : 'notSubmitted'),
            'grade': a.grade,
            'max_grade': a.maxGrade,
            'your_file': a.uploadedFile == null ? null : cut(a.uploadedFile!.name, 500),
            'task_file': a.taskFile == null ? null : cut(a.taskFile!.url, 1000),
          },
      ]);
      await _insert(c, 'absences', account, [
        for (final a in s.absences)
          {
            'subject': cut(a.subject, 255),
            'subject_id': a.subjectId,
            'absent_on': a.date == null ? null : at(a.date)!.substring(0, 10),
            'lesson_type': a.lessonType == null ? null : cut(a.lessonType!, 64),
            'theme': a.theme == null ? null : cut(a.theme!, 500),
            'theme_number': a.themeNumber,
            'excused': a.excused,
          },
      ]);
      await _insert(c, 'exams', account, [
        for (final f in s.finals)
          {
            'subject': cut(f.subject, 255),
            'subject_id': f.subjectId,
            'starts_at': at(f.startsAt),
            'ends_at': f.to == null ? null : cut(f.to!, 8),
            'room': f.room == null ? null : cut(f.room!, 64),
            'stream': f.stream == null ? null : cut(f.stream!, 64),
            'grade': f.grade,
          },
      ]);
      await _insert(c, 'classes', account, [
        for (final i in s.schedule)
          {
            'starts_at': at(i.start),
            'subject': cut(i.subject ?? i.title, 255),
            'lesson_type': i.type.name,
            'room': i.room == null ? null : cut(i.room!, 64),
            'stream': i.stream == null ? null : cut(i.stream!, 64),
            'week_side': switch (i.side) { WeekSide.left => 'odd', WeekSide.right => 'even', WeekSide.full => 'both' },
          },
      ]);
      await _insert(c, 'news', account, [
        for (final n in s.news)
          {
            'title': cut(n.title, 500),
            'published': at(n.date),
            'url': n.url == null ? null : cut(n.url!, 1000),
            'body': n.body,
          },
      ]);
    });
  }

  /// One multi-row INSERT for [rows] (all with the same keys).
  static Future<void> _insert(MySQLConnection c, String table, int account, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final cols = rows.first.keys.toList();
    final params = <String, dynamic>{'acc': account};
    final values = <String>[];
    for (final (i, r) in rows.indexed) {
      values.add('(:acc, ${[for (final k in cols) ':${k}_$i'].join(', ')})');
      for (final k in cols) {
        params['${k}_$i'] = r[k];
      }
    }
    await c.execute('INSERT INTO $table (account_id, ${cols.join(', ')}) VALUES ${values.join(', ')}', params);
  }
}

class SessionInfo {
  const SessionInfo(this.cookies, this.obtainedAt, this.checkedAt, this.endedAt);
  final List<Cookie> cookies;
  final DateTime obtainedAt;
  final DateTime? checkedAt;
  final DateTime? endedAt;
}

class RunInfo {
  const RunInfo({
    required this.startedAt,
    this.finishedAt,
    required this.full,
    required this.ok,
    this.changes = 0,
    this.failedParts = const [],
    this.error,
  });
  final DateTime startedAt;
  final DateTime? finishedAt;
  final bool full, ok;
  final int changes;
  final List<String> failedParts;
  final String? error;
}

/// [s] shortened to [max] characters (MySQL refuses longer values).
String cut(String s, int max) => s.length <= max ? s : s.substring(0, max);

Future<String> sha256Hex(List<int> bytes) async {
  final h = await Sha256().hash(bytes);
  return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, dynamic> cookieToJson(Cookie c) => {
      'name': c.name,
      'value': c.value,
      if (c.domain != null) 'domain': c.domain,
      'path': c.path ?? '/',
      if (c.expires != null) 'expires': c.expires!.millisecondsSinceEpoch,
      'httpOnly': c.httpOnly,
      'secure': c.secure,
    };

Cookie cookieFromJson(Map<String, dynamic> j) => makeCookie(
      '${j['name']}',
      '${j['value']}',
      domain: j['domain'] as String?,
      path: j['path'] as String?,
      expires: j['expires'] as num?,
      httpOnly: j['httpOnly'] as bool?,
      secure: j['secure'] as bool?,
    );
