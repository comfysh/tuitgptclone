import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/dom.dart';

import 'models.dart';
import 'parsers.dart';

class SessionExpiredException implements Exception {
  @override
  String toString() => 'LMS session expired. Please sign in again.';
}

class LmsException implements Exception {
  final String message;
  LmsException(this.message);
  @override
  String toString() => message;
}

/// HTTP client for lms.tuit.uz. It uses the session cookie captured from the
/// in-app login page, so it sees exactly what you see in the browser.
class LmsClient {
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
  static final lmsUri = Uri.parse(lmsBase);

  final PersistCookieJar cookieJar;
  late final Dio _dio;

  /// Bumped on sign-out. Responses to requests sent before that are dropped
  /// before the cookie manager sees them, so they can't save the old session
  /// back to disk.
  int get epoch => _epoch;
  int _epoch = 0;

  LmsClient(String cookieDir) : cookieJar = PersistCookieJar(storage: FileStorage(cookieDir)) {
    _dio = Dio(BaseOptions(
      baseUrl: lmsBase,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: false,
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'User-Agent': userAgent,
        'Accept-Language': 'uz,ru;q=0.9,en;q=0.8',
      },
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        o.extra['epoch'] = _epoch;
        h.next(o);
      },
      onResponse: (r, h) {
        if (r.requestOptions.extra['epoch'] != _epoch) {
          h.reject(DioException(requestOptions: r.requestOptions, message: 'Signed out'));
        } else {
          h.next(r);
        }
      },
      onError: (e, h) {
        if (e.requestOptions.extra['epoch'] != _epoch) {
          h.reject(DioException(requestOptions: e.requestOptions, message: 'Signed out'));
        } else {
          h.next(e);
        }
      },
    ));
    _dio.interceptors.add(CookieManager(cookieJar));
  }

  /// Stores cookies captured from the login WebView.
  /// Saving replaces cookies with the same name, so requests running at the
  /// same time never see an empty jar.
  Future<void> importCookies(List<Cookie> cookies) async {
    await cookieJar.saveFromResponse(lmsUri, cookies);
  }

  Future<bool> hasSession() async {
    final c = await cookieJar.loadForRequest(lmsUri);
    return c.any((e) => e.name.toLowerCase().contains('session'));
  }

  Future<List<Cookie>> currentCookies() => cookieJar.loadForRequest(lmsUri);

  Future<void> logout() async {
    _epoch++;
    try {
      await cookieJar.deleteAll();
    } catch (_) {}
  }

  bool _isLoginRedirect(Response r) {
    final loc = r.headers.value('location') ?? '';
    return (r.statusCode == 301 || r.statusCode == 302 || r.statusCode == 303) &&
        (loc.contains('/auth/login') || loc.endsWith('/login') || loc.contains('/login?'));
  }

  Future<Response<T>> _get<T>(String path, {ResponseType type = ResponseType.plain, bool json = false}) async {
    var url = path;
    for (var hop = 0; hop < 5; hop++) {
      final r = await _dio.get<T>(
        url,
        options: Options(
          responseType: type,
          headers: json
              ? {'Accept': 'application/json, text/javascript, */*; q=0.01', 'X-Requested-With': 'XMLHttpRequest'}
              : {'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8'},
        ),
      );
      final code = r.statusCode ?? 0;
      if (code == 401 || code == 419) throw SessionExpiredException();
      if (_isLoginRedirect(r)) throw SessionExpiredException();
      if (code >= 300 && code < 400) {
        final loc = r.headers.value('location');
        if (loc == null) break;
        url = loc;
        continue;
      }
      if (code >= 400) throw LmsException('LMS returned HTTP $code for $path');
      return r;
    }
    throw LmsException('Too many redirects for $path');
  }

  Future<Document> getHtml(String path) async {
    final r = await _get<String>(path);
    final body = r.data ?? '';
    if (isLoginPage(body)) throw SessionExpiredException();
    return parseHtml(body);
  }

  Future<dynamic> getJson(String path) async {
    final r = await _get<dynamic>(path, type: ResponseType.json, json: true);
    final data = r.data;
    if (data is String && isLoginPage(data)) throw SessionExpiredException();
    return data;
  }

  // ------------------------------------------------------------- endpoints

  /// Profile and tuition contract (same page).
  Future<(StudentInfo, List<ContractYear>)> info() async {
    final d = await getHtml('/student/info');
    return (parseInfo(d), _tryList(() => parseContracts(d)));
  }

  static List<T> _tryList<T>(List<T> Function() f) {
    try {
      return f();
    } catch (_) {
      return <T>[];
    }
  }

  Future<List<Semester>> semesters() async {
    for (final page in const ['/student/my-courses', '/student/finals', '/student/schedule']) {
      try {
        final list = parseSemesters(await getHtml(page));
        if (list.isNotEmpty) return list;
      } on SessionExpiredException {
        rethrow;
      } catch (_) {}
    }
    return const [];
  }

  Future<List<Course>> courses(int semesterId) async =>
      parseCourses(await getJson('/student/my-courses/data?semester_id=$semesterId'));

  Future<List<Absence>> absences(int semesterId) async =>
      parseAbsences(await getJson('/student/attendance/data?semester_id=$semesterId'));

  Future<List<ExamFinal>> finals(int semesterId) async =>
      parseFinals(await getJson('/student/finals/data?semester_id=$semesterId'));

  /// Timetable entries plus the LMS's own "this week is odd/even" marker.
  Future<(List<ScheduleItem>, (DateTime, WeekSide)?)> schedule(int semesterId) async {
    final json = await getJson('/student/schedule/load/$semesterId');
    return (parseSchedule(json), parseWeekInfo(json));
  }

  Future<CoursePage?> coursePage(Course c) async =>
      parseCoursePage(await getHtml('/student/my-courses/show/${c.id}'), c);

  Future<List<Lesson>> lessons(int courseId) async => parseLessons(await getHtml('/student/calendar/$courseId'));

  /// Subjects by semester plus the GPA badge.
  Future<(List<Discipline>, StudyPlanSummary)> studyPlan() async {
    final d = await getHtml('/student/study-plan');
    return (parseStudyPlan(d), parseStudyPlanSummary(d));
  }

  /// News from the list page; full text is fetched only for posts not seen before.
  Future<List<NewsItem>> news({int limit = 9, Map<String, NewsItem> known = const {}}) async {
    final list = parseNewsList(await getHtml('/dashboard/news')).take(limit).toList();
    final items = await Future.wait(list.map((n) async {
      final old = known[n.key];
      if (old?.body != null) return NewsItem(title: n.title, body: old!.body, date: n.date ?? old.date, url: n.url);
      try {
        final full = parseNewsPage(await getHtml(n.url!), n.url!);
        return full == null ? n : NewsItem(title: full.title, body: full.body, date: full.date ?? n.date, url: n.url);
      } on SessionExpiredException {
        rethrow;
      } catch (_) {
        return n;
      }
    }));
    return items;
  }

  /// Uploads an answer file for an assignment (LMS limit: 50 MB).
  Future<void> upload({required int uploadId, required int courseId, required String fileName, required Uint8List bytes}) async {
    final page = await getHtml('/student/my-courses/show/$courseId');
    final token = csrfToken(page);
    final form = FormData.fromMap({
      'id': uploadId.toString(),
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final r = await _dio.post(
      '/student/my-courses/upload',
      data: form,
      options: Options(headers: {
        if (token != null) 'X-CSRF-TOKEN': token,
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': '$lmsBase/student/my-courses/show/$courseId',
        'Origin': lmsBase,
      }),
    );
    if (_isLoginRedirect(r) || r.statusCode == 401 || r.statusCode == 419) throw SessionExpiredException();
    final code = r.statusCode ?? 0;
    if (code >= 400) {
      throw LmsException('Upload failed (HTTP $code). ${r.data is Map ? (r.data['message'] ?? '') : ''}');
    }
  }

  /// Downloads a file (teacher materials, your uploads) with your session.
  Future<Uint8List> download(String url, {void Function(int, int)? onProgress}) async {
    final r = await _dio.get<List<int>>(
      absoluteUrl(url),
      options: Options(responseType: ResponseType.bytes, followRedirects: true, maxRedirects: 5),
      onReceiveProgress: onProgress,
    );
    if (_isLoginRedirect(r)) throw SessionExpiredException();
    if ((r.statusCode ?? 0) >= 400) throw LmsException('Download failed (HTTP ${r.statusCode})');
    final ct = r.headers.value('content-type') ?? '';
    final bytes = Uint8List.fromList(r.data ?? const []);
    if (ct.contains('text/html') && isLoginPage(String.fromCharCodes(bytes.take(20000)))) {
      throw SessionExpiredException();
    }
    return bytes;
  }

  /// Best-effort filename from a download URL.
  static String fileNameFromUrl(String url, {String fallback = 'file'}) {
    final seg = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    if (seg.isEmpty) return fallback;
    final name = seg.last; // pathSegments are already percent-decoded
    return name.contains('.') ? name : fallback;
  }
}

/// Converts cookies captured by the WebView into dart:io cookies.
/// [expires] is milliseconds on Android but seconds on Windows (WebView2/CDP).
Cookie makeCookie(String name, String value, {String? domain, String? path, num? expires, bool? httpOnly, bool? secure}) {
  final c = Cookie(name, value);
  c.domain = domain;
  c.path = path ?? '/';
  if (expires != null && expires > 0) {
    final ms = expires < 100000000000 ? expires * 1000 : expires;
    c.expires = DateTime.fromMillisecondsSinceEpoch(ms.round());
  }
  c.httpOnly = httpOnly ?? false;
  c.secure = secure ?? true;
  return c;
}
