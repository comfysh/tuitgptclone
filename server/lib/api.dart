import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'fetcher.dart';
import 'store.dart';

const serverVersion = '1.4.0';

/// The HTTPS API the app talks to. Every call (except /health) needs
/// `Authorization: Bearer <token>` (a token from `tuitmate-server new-token`).
///
///   GET    /health                 "ok" (no token)
///   GET    /v1/status              session, last check, schedule
///   PUT    /v1/session             {"cookies":[…]}: the app's LMS session after it signed in
///   GET    /v1/session             that session as LMS last renewed it (404 when not live)
///   DELETE /v1/session             forget the session
///   GET    /v1/snapshot?after=ISO  newest snapshot (204 when none newer than `after`)
///   POST   /v1/refresh?full=1      check LMS now and wait for it (max 2 min)
///   GET    /v1/changes?after=ID    what changed, oldest first
class Api {
  Api(this.store, this.fetcher, {this.log = _print});
  final Store store;
  final Fetcher fetcher;
  final void Function(String) log;

  HttpServer? _server;

  /// Failed token checks per client address, to slow down guessing.
  final _failures = <String, List<DateTime>>{};
  static const _maxFailures = 10;
  static const _failureWindow = Duration(minutes: 15);
  static const _maxBody = 256 * 1024;

  Future<void> start({required String address, required int port, required SecurityContext tls}) async {
    final server = _server = await HttpServer.bindSecure(address, port, tls);
    server.autoCompress = true; // snapshots are large JSON
    server.idleTimeout = const Duration(seconds: 30);
    log('API listening on https://$address:$port');
    server.listen((req) => unawaited(_handle(req)), onError: (Object e) => log('API: $e'));
  }

  Future<void> stop() async => _server?.close(force: true);

  /// The port it listens on (useful with port 0 in tests).
  int? get port => _server?.port;

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      res.headers.set('Cache-Control', 'no-store');
      final path = req.uri.path;
      if (path == '/health' && req.method == 'GET') return await _text(res, 200, 'ok');

      final ip = req.connectionInfo?.remoteAddress.address ?? '?';
      if (_blocked(ip)) return await _json(res, 429, {'error': 'too many wrong tokens, try again later'});
      final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
      final account = auth.startsWith('Bearer ') ? await store.accountForToken(auth.substring(7).trim()) : null;
      if (account == null) {
        _fail(ip);
        return await _json(res, 401, {'error': 'unknown token'});
      }

      switch ((req.method, path)) {
        case ('GET', '/v1/status'):
          return await _json(res, 200, await status(account));
        case ('PUT', '/v1/session'):
          final body = await _body(req);
          final list = body['cookies'];
          if (list is! List || list.isEmpty) return await _json(res, 400, {'error': 'cookies missing'});
          final cookies = [for (final c in list) cookieFromJson(Map<String, dynamic>.from(c as Map))];
          if (!cookies.any((c) => c.name.toLowerCase().contains('session'))) {
            return await _json(res, 400, {'error': 'no LMS session cookie'});
          }
          await store.saveSession(account, cookies);
          unawaited(fetcher.run(account, full: true)); // check it right away
          return await _json(res, 202, await status(account));
        case ('GET', '/v1/session'):
          // The live session with the expiry LMS last gave it, so the app's
          // copy (same session) stays valid without signing in again.
          final session = await store.session(account);
          if (session == null || session.endedAt != null || session.cookies.isEmpty) {
            return await _json(res, 404, {'error': 'no live session'});
          }
          return await _json(res, 200, {
            'cookies': [for (final c in session.cookies) cookieToJson(c)],
            if (session.checkedAt != null) 'checked_at': session.checkedAt!.toIso8601String(),
          });
        case ('DELETE', '/v1/session'):
          await store.forgetSession(account);
          return await _json(res, 200, await status(account));
        case ('GET', '/v1/snapshot'):
          final latest = await store.latestSnapshotJson(account);
          final after = DateTime.tryParse(req.uri.queryParameters['after'] ?? '');
          if (latest == null || (after != null && !latest.$1.isAfter(after.toUtc()))) {
            res.statusCode = 204;
            return await res.close();
          }
          // The stored JSON goes out as it is, without decoding it again.
          res.statusCode = 200;
          res.headers.contentType = ContentType.json;
          res.write('{"fetched_at":${jsonEncode(latest.$1.toIso8601String())},"snapshot":${latest.$2}}');
          return await res.close();
        case ('POST', '/v1/refresh'):
          final full = req.uri.queryParameters['full'] == '1';
          final outcome = await fetcher.run(account, full: full).timeout(const Duration(minutes: 2), onTimeout: () => FetchOutcome.failed);
          return await _json(res, 200, {...await status(account), 'outcome': outcome.name});
        case ('GET', '/v1/changes'):
          final after = int.tryParse(req.uri.queryParameters['after'] ?? '') ?? 0;
          return await _json(res, 200, {'changes': await store.changesAfter(account, after)});
        default:
          return await _json(res, 404, {'error': 'no such endpoint'});
      }
    } on FormatException {
      await _json(res, 400, {'error': 'bad request'});
    } catch (e) {
      log('API ${req.method} ${req.uri.path}: $e');
      try {
        await _json(res, 500, {'error': 'server error'});
      } catch (_) {}
    }
  }

  /// What the app shows in Profile › Sync and `tuitmate-server status` prints.
  Future<Map<String, dynamic>> status(int account) async {
    final session = await store.session(account);
    final last = await store.lastRun(account);
    final lastOk = await store.lastRun(account, okOnly: true);
    final latest = await store.latestSnapshotJson(account);
    return {
      'server_version': serverVersion,
      'account': account,
      'fetch_minutes': await store.fetchMinutes(account),
      'checking': fetcher.isRunning(account),
      'session': {
        'state': session == null ? 'none' : (session.endedAt != null ? 'ended' : 'live'),
        if (session != null) 'obtained_at': session.obtainedAt.toIso8601String(),
        if (session?.checkedAt != null) 'checked_at': session!.checkedAt!.toIso8601String(),
        if (session?.endedAt != null) 'ended_at': session!.endedAt!.toIso8601String(),
      },
      if (last != null) 'last_check': _run(last),
      if (lastOk != null) 'last_ok_check': _run(lastOk),
      if (latest != null) 'snapshot_at': latest.$1.toIso8601String(),
    };
  }

  static Map<String, dynamic> _run(RunInfo r) => {
        'started_at': r.startedAt.toIso8601String(),
        if (r.finishedAt != null) 'finished_at': r.finishedAt!.toIso8601String(),
        'full': r.full,
        'ok': r.ok,
        'changes': r.changes,
        if (r.failedParts.isNotEmpty) 'failed_parts': r.failedParts,
        if (r.error != null) 'error': r.error,
      };

  bool _blocked(String ip) {
    final list = _failures[ip];
    if (list == null) return false;
    final since = DateTime.now().subtract(_failureWindow);
    list.removeWhere((t) => t.isBefore(since));
    return list.length >= _maxFailures;
  }

  void _fail(String ip) {
    (_failures[ip] ??= []).add(DateTime.now());
    if (_failures.length > 10000) _failures.clear(); // never grows without end
  }

  static Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) throw const FormatException('body too large');
    }
    final v = jsonDecode(utf8.decode(bytes));
    if (v is! Map) throw const FormatException('JSON object expected');
    return Map<String, dynamic>.from(v);
  }

  static Future<void> _json(HttpResponse res, int code, Object body) async {
    res.statusCode = code;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  static Future<void> _text(HttpResponse res, int code, String body) async {
    res.statusCode = code;
    res.headers.contentType = ContentType.text;
    res.write(body);
    await res.close();
  }
}

/// SHA-256 of the first certificate in a PEM file, as hex: the app pins it,
/// so it talks only to this server (the certificate is self-signed).
Future<String> certFingerprint(String pemPath) async {
  final pem = await File(pemPath).readAsString();
  final m = RegExp(r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----').firstMatch(pem);
  if (m == null) throw FormatException('no certificate in $pemPath');
  final der = base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
  return sha256Hex(der);
}

/// One line the app takes in Profile › Sync › TuitMate server: the address,
/// the token and the certificate fingerprint.
String connectionCode(String url, String token, String fingerprint) =>
    'tmsrv1.${base64Url.encode(utf8.encode(jsonEncode({'u': url, 't': token, 'f': fingerprint}))).replaceAll('=', '')}';

void _print(String line) => stdout.writeln('${DateTime.now().toUtc().toIso8601String()} $line');
