import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/storage.dart';
import '../lms/lms_client.dart';
import '../lms/snapshot.dart';

/// Your own TuitMate server (server/README.md): it keeps the LMS session the
/// app hands it alive and checks LMS every few minutes into MySQL; the app
/// takes the newest snapshot from it instead of going to LMS itself.
///
/// The connection code from `tuitmate-server new-token` holds the address,
/// the token and the SHA-256 of the server's self-signed certificate, which
/// is pinned: the app talks to that server only.
class ServerConfig {
  const ServerConfig(this.url, this.token, this.fingerprint);
  final String url;
  final String token;
  final String fingerprint;

  static const prefix = 'tmsrv1.';

  /// Reads a connection code ("tmsrv1.…"); null when it isn't one.
  static ServerConfig? parse(String code) {
    final c = code.trim();
    if (!c.startsWith(prefix)) return null;
    try {
      final p = c.substring(prefix.length);
      final j = jsonDecode(utf8.decode(base64Url.decode(p + '=' * ((4 - p.length % 4) % 4)))) as Map;
      final url = '${j['u']}', token = '${j['t']}', fp = '${j['f']}'.toLowerCase();
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
      if (token.length < 20 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fp)) return null;
      return ServerConfig(url.replaceFirst(RegExp(r'/+$'), ''), token, fp);
    } catch (_) {
      return null;
    }
  }

  String get host => Uri.parse(url).host;

  Map<String, dynamic> toJson() => {'u': url, 't': token, 'f': fingerprint};
}

/// What the server reports about itself.
class ServerStatus {
  const ServerStatus(this.json);
  final Map<String, dynamic> json;

  String get sessionState => '${(json['session'] as Map?)?['state'] ?? 'none'}';
  bool get sessionLive => sessionState == 'live';
  DateTime? get snapshotAt => DateTime.tryParse('${json['snapshot_at'] ?? ''}')?.toLocal();
  Map? get lastCheck => json['last_check'] as Map?;
  DateTime? get lastOkAt => DateTime.tryParse('${(json['last_ok_check'] as Map?)?['finished_at'] ?? ''}')?.toLocal();
  int get fetchMinutes => (json['fetch_minutes'] as num?)?.toInt() ?? 5;
  String get version => '${json['server_version'] ?? '?'}';
}

class ServerLink {
  ServerLink._();

  static ServerConfig? _cached;
  static bool _loaded = false;

  /// The saved connection, or null when the app isn't connected to a server.
  static Future<ServerConfig?> load() async {
    if (_loaded) return _cached;
    final raw = await Secrets.read(Secrets.server);
    ServerConfig? c;
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map;
        c = ServerConfig('${j['u']}', '${j['t']}', '${j['f']}');
      } catch (_) {}
    }
    _loaded = true;
    return _cached = c;
  }

  static Future<void> save(ServerConfig? c) async {
    await Secrets.write(Secrets.server, c == null ? null : jsonEncode(c.toJson()));
    _cached = c;
    _loaded = true;
  }

  /// Sign-out and tests: read the keystore again next time.
  static void forget() {
    _cached = null;
    _loaded = false;
  }

  static Dio _dio(ServerConfig c, {Duration receive = const Duration(seconds: 30)}) {
    final dio = Dio(BaseOptions(
      baseUrl: c.url,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: receive,
      headers: {'Authorization': 'Bearer ${c.token}'},
      validateStatus: (s) => s != null && s < 500,
    ));
    bool pinned(X509Certificate? cert) => cert != null && crypto.sha256.convert(cert.der).toString() == c.fingerprint;
    dio.httpClientAdapter = IOHttpClientAdapter(
      // The certificate is self-signed: accepted only when it is the pinned one.
      createHttpClient: () => HttpClient()..badCertificateCallback = (cert, host, port) => pinned(cert),
      // …and a CA-signed one must be the pinned one too.
      validateCertificate: (cert, host, port) => pinned(cert),
    );
    return dio;
  }

  static Map<String, dynamic> _map(Object? data) =>
      data is Map ? Map<String, dynamic>.from(data) : jsonDecode('$data') as Map<String, dynamic>;

  static Never _fail(Response r) => throw ServerException(r.statusCode ?? 0, '${r.data is Map ? r.data['error'] : r.data}');

  static Future<ServerStatus> status(ServerConfig c) async {
    final r = await _dio(c).get<Object>('/v1/status');
    if (r.statusCode != 200) _fail(r);
    return ServerStatus(_map(r.data));
  }

  /// Hands the app's LMS session to the server (after signing in).
  static Future<ServerStatus> sendSession(ServerConfig c, LmsClient client) async {
    final cookies = await client.currentCookies();
    if (!cookies.any((k) => k.name.toLowerCase().contains('session'))) throw const ServerException(0, 'no LMS session');
    final r = await _dio(c).put<Object>('/v1/session', data: {
      'cookies': [
        for (final k in cookies)
          {
            'name': k.name,
            'value': k.value,
            'path': k.path ?? '/',
            if (k.expires != null) 'expires': k.expires!.millisecondsSinceEpoch,
            'secure': k.secure,
            'httpOnly': k.httpOnly,
          },
      ],
    });
    if (r.statusCode != 202 && r.statusCode != 200) _fail(r);
    return ServerStatus(_map(r.data));
  }

  /// Takes the server's live session (same session, renewed expiry) into
  /// [client]. False when the server has none.
  static Future<bool> takeSession(ServerConfig c, LmsClient client) async {
    final r = await _dio(c).get<Object>('/v1/session');
    if (r.statusCode == 404) return false;
    if (r.statusCode != 200) _fail(r);
    final list = _map(r.data)['cookies'] as List? ?? const [];
    final cookies = [
      for (final j in list)
        makeCookie('${j['name']}', '${j['value']}',
            path: j['path'] as String?, expires: j['expires'] as num?, httpOnly: j['httpOnly'] as bool?, secure: j['secure'] as bool?),
    ];
    if (cookies.isEmpty) return false;
    await client.importCookies(cookies);
    return true;
  }

  /// The newest snapshot, or null when it isn't newer than [after].
  static Future<(DateTime, LmsSnapshot)?> snapshot(ServerConfig c, {DateTime? after}) async {
    final r = await _dio(c, receive: const Duration(seconds: 60)).get<Object>('/v1/snapshot',
        queryParameters: {if (after != null) 'after': after.toUtc().toIso8601String()});
    if (r.statusCode == 204) return null;
    if (r.statusCode != 200) _fail(r);
    final j = _map(r.data);
    return (DateTime.parse('${j['fetched_at']}').toLocal(), LmsSnapshot.fromJson(Map<String, dynamic>.from(j['snapshot'] as Map)));
  }

  /// Sign-out: the server forgets the session (best effort, a few seconds).
  static Future<void> dropSession() async {
    try {
      final c = await load();
      if (c != null) await _dio(c, receive: const Duration(seconds: 5)).delete<Object>('/v1/session');
    } catch (_) {}
  }

  /// Asks the server to check LMS now and waits for it (up to ~2 minutes).
  static Future<String> refreshNow(ServerConfig c, {bool full = false}) async {
    final r = await _dio(c, receive: const Duration(seconds: 130))
        .post<Object>('/v1/refresh', queryParameters: {if (full) 'full': '1'});
    if (r.statusCode != 200) _fail(r);
    return '${_map(r.data)['outcome']}';
  }
}

class ServerException implements Exception {
  const ServerException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => status == 0 ? message : 'server $status: $message';
}

/// How old the server's newest snapshot may be to use it (it checks every
/// few minutes; older means the server is off or its session ended).
const serverSnapshotMaxAge = Duration(minutes: 12);

/// One sync's data: from your server when it has a recent snapshot,
/// otherwise from LMS directly (as without a server). [askServerNow] (a
/// refresh you asked for) makes the server check LMS first. The record's
/// second field says whether it came from the server.
Future<(LmsSnapshot, bool)> fetchLatest(
  LmsClient client, {
  LmsSnapshot? previous,
  int? semesterId,
  bool full = false,
  bool askServerNow = false,
}) async {
  final server = await ServerLink.load();
  // The server follows LMS's current semester; a chosen older one comes from LMS.
  if (server != null && semesterId == null) {
    try {
      if (askServerNow) await ServerLink.refreshNow(server, full: full);
      final got = await ServerLink.snapshot(server);
      if (got != null) {
        final (at, snap) = got;
        final recent = DateTime.now().difference(at) < serverSnapshotMaxAge;
        final notOlder = previous?.updatedAt == null || !at.isBefore(previous!.updatedAt!);
        if (recent && notOlder) return (snap, true);
      }
    } catch (_) {
      // Server unreachable: LMS directly.
    }
  }
  // The cookie jar drops the session cookie once it expires (LMS keeps it ~2 h).
  if (!await client.hasSession()) throw SessionExpiredException();
  return (await fetchSnapshot(client, previous: previous, semesterId: semesterId, full: full), false);
}

/// The app has a working LMS session (it just signed in, or LMS answered it
/// directly): if the server has none, hand it over. Never throws.
Future<void> shareSessionIfNeeded(LmsClient client, {bool force = false}) async {
  try {
    final server = await ServerLink.load();
    if (server == null) return;
    if (!force && (await ServerLink.status(server)).sessionLive) return;
    await ServerLink.sendSession(server, client);
  } catch (_) {}
}

/// The app's session ended: take the server's (same session, kept alive by
/// its checks). True when that worked. Never throws.
Future<bool> adoptServerSession(LmsClient client) async {
  try {
    final server = await ServerLink.load();
    return server != null && await ServerLink.takeSession(server, client);
  } catch (_) {
    return false;
  }
}
