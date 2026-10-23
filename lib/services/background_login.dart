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

  /// At most one try per 20 minutes, and none after 3 failures in a row
  /// (wrong password, reCAPTCHA refusing): then the user signs in by hand.
  static const _minGap = Duration(minutes: 20);
  static const _maxFailures = 3;

  static Future<bool> canTry(Settings settings) async {
    if (!(io.Platform.isAndroid || io.Platform.isWindows)) return false;
    if (!settings.backgroundLogin || !settings.autoLogin) return false;
    final login = await Secrets.read(Secrets.lmsLogin);
    final pass = await Secrets.read(Secrets.lmsPassword);
    return login != null && login.isNotEmpty && pass != null && pass.isNotEmpty;
  }

  /// Signs in and stores the new session in [client]. True on success; never throws.
  static Future<bool> run(LmsClient client, Settings settings, AppStorage storage) async {
    if (_running || !await canTry(settings)) return false;
    final state = await storage.readJson(storage.notifyStateFile);
    final failures = (state['loginFailures'] as num?)?.toInt() ?? 0;
    final last = DateTime.tryParse('${state['loginTriedAt'] ?? ''}');
    if (failures >= _maxFailures) return false;
    if (last != null && DateTime.now().difference(last) < _minGap) return false;
    _running = true;
    state['loginTriedAt'] = DateTime.now().toIso8601String();
    await storage.writeJson(storage.notifyStateFile, state);
    var ok = false;
    try {
      ok = await _signIn(client);
    } catch (_) {
      ok = false;
    } finally {
      _running = false;
    }
    final after = await storage.readJson(storage.notifyStateFile);
    after['loginFailures'] = ok ? 0 : failures + 1;
    if (ok) after['sessionNotified'] = false;
    await storage.writeJson(storage.notifyStateFile, after);
    return ok;
  }

  /// A manual sign-in resets the failure counter.
  static Future<void> reset(AppStorage storage) async {
    final state = await storage.readJson(storage.notifyStateFile);
    state.remove('loginFailures');
    state.remove('loginTriedAt');
    await storage.writeJson(storage.notifyStateFile, state);
  }

  static bool _isLoggedInPage(WebUri? url) {
    if (url == null || url.host != 'lms.tuit.uz') return false;
    final p = url.path;
    return !(p.startsWith('/auth') || p == '/login' || p.startsWith('/login/') || p == '/schedule');
  }

  static Future<bool> _signIn(LmsClient client) async {
    final login = await Secrets.read(Secrets.lmsLogin);
    final pass = await Secrets.read(Secrets.lmsPassword);
    if (login == null || pass == null) return false;
    final done = Completer<bool>();
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
      if (!done.isCompleted) done.complete(true);
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
        if (error == true && !done.isCompleted) done.complete(false);
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
      return await done.future.timeout(const Duration(seconds: 75), onTimeout: () => false);
    } finally {
      try {
        await view.dispose();
      } catch (_) {}
    }
  }
}
