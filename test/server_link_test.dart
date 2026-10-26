// The app's side of the TuitMate server: connection codes, certificate
// pinning, taking snapshots from the server and handing sessions over.
// A small stand-in server (HTTPS, self-signed certificate from openssl)
// answers like server/lib/api.dart.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/lms/lms_client.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/snapshot.dart';
import 'package:tuitmate/services/server_link.dart';

String code(String url, String token, String fp) =>
    'tmsrv1.${base64Url.encode(utf8.encode(jsonEncode({'u': url, 't': token, 'f': fp}))).replaceAll('=', '')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // real sockets to the local stand-in server

  late Directory tmp;
  late HttpServer server;
  late String fingerprint;
  const token = 'test-token-0123456789abcdef';
  var snapshotAge = Duration.zero;
  List<dynamic>? receivedCookies;
  final secrets = <String, String>{};

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = Map<String, dynamic>.from(call.arguments ?? const {});
        switch (call.method) {
          case 'read':
            return secrets[args['key']];
          case 'write':
            secrets[args['key'] as String] = args['value'] as String;
          case 'delete':
            secrets.remove(args['key']);
        }
        return null;
      },
    );
    tmp = Directory.systemTemp.createTempSync('tuitmate_server_link');
    final cert = '${tmp.path}/cert.pem', key = '${tmp.path}/key.pem';
    final r = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes', //
      '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=tuitmate-test', '-addext', 'subjectAltName=IP:127.0.0.1',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final pem = File(cert).readAsStringSync();
    final der = base64.decode(RegExp(r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END').firstMatch(pem)!.group(1)!.replaceAll(RegExp(r'\s'), ''));
    fingerprint = crypto.sha256.convert(der).toString();

    server = await HttpServer.bindSecure('127.0.0.1', 0, SecurityContext()..useCertificateChain(cert)..usePrivateKey(key));
    server.listen((req) async {
      final res = req.response..headers.contentType = ContentType.json;
      if (req.headers.value('authorization') != 'Bearer $token') {
        res.statusCode = 401;
        res.write('{"error":"unknown token"}');
        return res.close();
      }
      switch ((req.method, req.uri.path)) {
        case ('GET', '/v1/status'):
          res.write(jsonEncode({'server_version': '1.4.0', 'fetch_minutes': 5, 'session': {'state': receivedCookies == null ? 'none' : 'live'}}));
        case ('GET', '/v1/snapshot'):
          final at = DateTime.now().subtract(snapshotAge);
          final snap = LmsSnapshot(
            courses: const [Course(id: 1, subject: 'Database', subjectId: 12)],
            updatedAt: at,
          );
          res.write('{"fetched_at":"${at.toUtc().toIso8601String()}","snapshot":${jsonEncode(snap.toJson())}}');
        case ('PUT', '/v1/session'):
          receivedCookies = (jsonDecode(await utf8.decodeStream(req)) as Map)['cookies'] as List;
          res.statusCode = 202;
          res.write(jsonEncode({'session': {'state': 'live'}}));
        case ('GET', '/v1/session'):
          if (receivedCookies == null) {
            res.statusCode = 404;
            res.write('{"error":"no live session"}');
          } else {
            res.write(jsonEncode({'cookies': receivedCookies}));
          }
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  setUp(() {
    secrets.clear();
    ServerLink.forget();
    snapshotAge = Duration.zero;
    receivedCookies = null;
  });

  String url() => 'https://127.0.0.1:${server.port}';

  test('connection codes', () {
    final c = ServerConfig.parse('  ${code('${url()}/', token, fingerprint.toUpperCase())}\n')!;
    expect((c.url, c.token, c.fingerprint, c.host), (url(), token, fingerprint, '127.0.0.1'));
    expect(ServerConfig.parse('tmsrv2.abc'), isNull);
    expect(ServerConfig.parse(code('http://127.0.0.1:1', token, fingerprint)), isNull); // HTTPS only
    expect(ServerConfig.parse(code(url(), 'short', fingerprint)), isNull);
    expect(ServerConfig.parse(code(url(), token, 'abc')), isNull);
    expect(ServerConfig.parse('tmsrv1.%%%'), isNull);
  });

  test('the server certificate is pinned', () async {
    final good = ServerConfig.parse(code(url(), token, fingerprint))!;
    final status = await ServerLink.status(good);
    expect((status.version, status.fetchMinutes, status.sessionLive), ('1.4.0', 5, false));
    final wrongCert = ServerConfig.parse(code(url(), token, 'ab' * 32))!;
    await expectLater(ServerLink.status(wrongCert), throwsA(anything));
    final wrongToken = ServerConfig.parse(code(url(), '${token}x', fingerprint))!;
    await expectLater(ServerLink.status(wrongToken), throwsA(isA<ServerException>().having((e) => e.status, 'status', 401)));
  });

  test('a recent server snapshot is used; an old one sends the app to LMS', () async {
    await ServerLink.save(ServerConfig.parse(code(url(), token, fingerprint)));
    final client = LmsClient('${tmp.path}/jar1/');
    final (snap, viaServer) = await fetchLatest(client, previous: LmsSnapshot(updatedAt: DateTime.now().subtract(const Duration(hours: 1))));
    expect(viaServer, isTrue);
    expect(snap.courses.single.subject, 'Database');
    // A chosen older semester always comes from LMS.
    await expectLater(fetchLatest(client, semesterId: 7), throwsA(isA<SessionExpiredException>()));
    // Stale server data: LMS directly (this jar has no session, so: session expired).
    snapshotAge = const Duration(hours: 2);
    await expectLater(fetchLatest(client), throwsA(isA<SessionExpiredException>()));
    // Not connected: LMS directly.
    await ServerLink.save(null);
    snapshotAge = Duration.zero;
    await expectLater(fetchLatest(client), throwsA(isA<SessionExpiredException>()));
  });

  test('sessions are handed over and taken back', () async {
    await ServerLink.save(ServerConfig.parse(code(url(), token, fingerprint)));
    final phone = LmsClient('${tmp.path}/jar2/');
    expect(await adoptServerSession(phone), isFalse); // the server has none yet
    await phone.importCookies([
      makeCookie('tuitlms_session', 'live-session', path: '/', secure: true, httpOnly: true,
          expires: DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch),
    ]);
    await shareSessionIfNeeded(phone);
    expect(receivedCookies!.single['name'], 'tuitlms_session');
    expect(receivedCookies!.single['value'], 'live-session');
    // Another install (or the same app after its cookie expired) takes it back.
    final laptop = LmsClient('${tmp.path}/jar3/');
    expect(await laptop.hasSession(), isFalse);
    expect(await adoptServerSession(laptop), isTrue);
    expect((await laptop.currentCookies()).single.value, 'live-session');
  });
}
