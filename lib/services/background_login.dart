import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/settings.dart';
import '../core/storage.dart';
import '../lms/lms_client.dart';
import '../lms/parsers.dart';
import 'web_env.dart';

/// Signs in to LMS again without showing anything, so checks and notifications
/// keep working after LMS ends the session (it lasts about two hours).
///
/// It loads the real login page in an invisible browser, fills in the saved
/// login and password and presses the button, the same way the visible login
/// page does, so LMS's reCAPTCHA runs normally. Used by the Android background
/// check and by the app itself (also while it sits in the Windows tray).
class BackgroundLogin {
  BackgroundLogin._();

  static bool _running = false;

  /// Waits between tries after failures in a row (wrong password, reCAPTCHA
  /// refusing, no network): 20 min, 1 h, 3 h, then every 6 h. It never gives
  /// up for good; a manual sign-in or new saved password starts over.
  static const _backoff = [Duration(minutes: 20), Duration(hours: 1), Duration(hours: 3), Duration(hours: 6)];

  static Future<bool> canTry(Settings settings) async {
    if (!(io.Platform.isAndroid || io.Platform.isWindows)) return false;
    if (!settings.backgroundLogin || !settings.autoLogin) return false;
    return hasSavedLogin();
  }

  /// Login and password are saved on this device.
  static Future<bool> hasSavedLogin() async {
    final login = await Secrets.read(Secrets.lmsLogin);
    final pass = await Secrets.read(Secrets.lmsPassword);
    return login != null && login.isNotEmpty && pass != null && pass.isNotEmpty;
  }

  /// When the next automatic try may run, given the last one.
  static DateTime? nextTry(Map<String, dynamic> state) {
    final failures = (state['loginFailures'] as num?)?.toInt() ?? 0;
    final last = DateTime.tryParse('${state['loginTriedAt'] ?? ''}');
    if (last == null || failures == 0) return null;
    return last.add(_backoff[(failures - 1).clamp(0, _backoff.length - 1)]);
  }

  /// Signs in and stores the new session in [client]. True on success; never
  /// throws. [force] (the "try now" button) skips the wait after failures.
  static Future<bool> run(LmsClient client, Settings settings, AppStorage storage, {bool force = false}) async {
    if (_running || !await canTry(settings)) return false;
    final state = await storage.readJson(storage.notifyStateFile);
    final failures = (state['loginFailures'] as num?)?.toInt() ?? 0;
    final last = DateTime.tryParse('${state['loginTriedAt'] ?? ''}');
    final now = DateTime.now();
    if (!force) {
      final next = nextTry(state);
      if (next != null && now.isBefore(next)) return false;
      // Two checks at once (app and background): one try is enough.
      if (last != null && now.difference(last).abs() < const Duration(minutes: 2)) return false;
    }
    _running = true;
    state['loginTriedAt'] = now.toIso8601String();
    await storage.writeJson(storage.notifyStateFile, state);
    var result = LoginResult.error;
    try {
      result = await _signIn(client);
    } catch (_) {
      result = LoginResult.error;
    } finally {
      _running = false;
    }
    final ok = result == LoginResult.ok;
    final after = await storage.readJson(storage.notifyStateFile);
    after['loginFailures'] = ok ? 0 : failures + 1;
    after['loginResult'] = result.name;
    if (ok) {
      after['loginOkAt'] = DateTime.now().toIso8601String();
      after['sessionNotified'] = false;
    }
    await storage.writeJson(storage.notifyStateFile, after);
    return ok;
  }

  /// A manual sign-in or a new saved password starts over.
  static Future<void> reset(AppStorage storage) async {
    final state = await storage.readJson(storage.notifyStateFile);
    state.remove('loginFailures');
    state.remove('loginTriedAt');
    await storage.writeJson(storage.notifyStateFile, state);
  }

  /// How automatic sign-in went last: for the status line in Profile.
  static Future<LoginStatus> status(AppStorage storage) async {
    final state = await storage.readJson(storage.notifyStateFile);
    return LoginStatus(
      okAt: DateTime.tryParse('${state['loginOkAt'] ?? ''}'),
      triedAt: DateTime.tryParse('${state['loginTriedAt'] ?? ''}'),
      result: LoginResult.values.where((r) => r.name == state['loginResult']).firstOrNull,
      failures: (state['loginFailures'] as num?)?.toInt() ?? 0,
      nextTry: nextTry(state),
    );
  }

  static bool _isLoggedInPage(WebUri? url) {
    if (url == null || url.host != 'lms.tuit.uz') return false;
    final p = url.path;
    return !(p.startsWith('/auth') || p == '/login' || p.startsWith('/login/') || p == '/schedule');
  }

  static Future<LoginResult> _signIn(LmsClient client) async {
    final login = await Secrets.read(Secrets.lmsLogin);
    final pass = await Secrets.read(Secrets.lmsPassword);
    if (login == null || pass == null) return LoginResult.error;
    final done = Completer<LoginResult>();
    var submitted = false;

    Future<void> capture(InAppWebViewController c) async {
      if (done.isCompleted) return;
      final raw = await WebEnv.cookies.getCookies(url: WebUri(lmsBase), webViewController: c);
      final cookies = <io.Cookie>[];
      for (final k in raw) {
        try {
          cookies.add(makeCookie(k.name, '${k.value}',
              expires: k.expiresDate, httpOnly: k.isHttpOnly, secure: k.isSecure, path: k.path));
        } catch (_) {}
      }
      if (!cookies.any((k) => k.name.toLowerCase().contains('session'))) return;
      await client.importCookies(cookies);
      if (!done.isCompleted) done.complete(LoginResult.ok);
    }

    Future<void> onPage(InAppWebViewController c, WebUri? url) async {
      if (done.isCompleted || url == null) return;
      if (_isLoggedInPage(url)) {
        await capture(c);
        return;
      }
      if (url.host != 'lms.tuit.uz' || !url.path.startsWith('/auth/login')) return;
      final error = await c.evaluateJavascript(source: "!!document.querySelector('[role=alert], .alert-danger')");
      if (submitted) {
        // Back on the login page after pressing the button: refused.
        if (error == true && !done.isCompleted) done.complete(LoginResult.refused);
        return;
      }
      submitted = true;
      await c.evaluateJavascript(source: '''
(function(){
  var l = document.getElementById('login'), p = document.getElementById('password');
  if (l) l.value = ${jsonEncode(login)};
  if (p) p.value = ${jsonEncode(pass)};
  var n = 0; var t = setInterval(function(){ var b = document.getElementById('login-btn'); n++;
    if (b && !b.disabled) { clearInterval(t); b.click(); } if (n > 60) clearInterval(t); }, 250);
})();''');
    }

    final view = HeadlessInAppWebView(
      webViewEnvironment: WebEnv.env,
      initialUrlRequest: URLRequest(url: WebUri('$lmsBase/auth/login')),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true, thirdPartyCookiesEnabled: true),
      onLoadStop: onPage,
      onUpdateVisitedHistory: (c, url, _) {
        if (_isLoggedInPage(url)) capture(c);
      },
    );
    try {
      await view.run();
      return await done.future.timeout(const Duration(seconds: 75), onTimeout: () => LoginResult.timeout);
    } finally {
      try {
        await view.dispose();
      } catch (_) {}
    }
  }
}

/// How an automatic sign-in ended: signed in, LMS showed an error on the
/// login page (wrong password or reCAPTCHA), no answer in time, or another
/// problem (no network, no saved password).
enum LoginResult { ok, refused, timeout, error }

class LoginStatus {
  const LoginStatus({this.okAt, this.triedAt, this.result, this.failures = 0, this.nextTry});
  final DateTime? okAt;
  final DateTime? triedAt;
  final LoginResult? result;
  final int failures;
  final DateTime? nextTry;
}
