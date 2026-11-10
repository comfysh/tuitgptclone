// The LMS session must not end because of the device: cookies are kept until
// LMS replaces them, and "not signed in" answers don't overwrite the session.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/lms/lms_client.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('tuitmate_session'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Cookie session(String value, {Duration? expiresIn, int? maxAge}) => Cookie('tuitlms_session', value)
    ..path = '/'
    ..expires = expiresIn == null ? null : DateTime.now().add(expiresIn)
    ..maxAge = maxAge;

  test('a session cookie outlives its 2-hour expiry and a wrong device clock', () async {
    final client = LmsClient('${tmp.path}/jar/');
    // As LMS sends it; a device clock 5 hours ahead sees it as already expired.
    await client.importCookies([session('abc', expiresIn: const Duration(hours: -3), maxAge: 7200)]);
    expect(await client.hasSession(), isTrue);
    expect((await client.currentCookies()).single.value, 'abc');
    // Still there for a new start of the app.
    expect(await LmsClient('${tmp.path}/jar/').hasSession(), isTrue);
  });

  test('LMS can still delete a cookie', () async {
    final client = LmsClient('${tmp.path}/jar/');
    await client.importCookies([session('abc', maxAge: 7200)]);
    await client.importCookies([session('deleted', expiresIn: const Duration(days: -400), maxAge: 0)]);
    expect(await client.hasSession(), isFalse);
  });

  test('kept cookies carry no expiry', () {
    final kept = SessionCookieJar.keepUntilReplaced(session('abc', expiresIn: const Duration(hours: 2), maxAge: 7200)
      ..httpOnly = true
      ..secure = true);
    expect((kept.expires, kept.maxAge, kept.httpOnly, kept.secure, kept.path), (null, null, true, true, '/'));
  });

  test('cookies without a session are not a sign-in', () async {
    expect(await LmsClient.signedInWith([Cookie('XSRF-TOKEN', 'x')]), isFalse);
  });
}
