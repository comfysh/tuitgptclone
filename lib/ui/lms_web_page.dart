import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import '../lms/lms_client.dart';
import '../lms/parsers.dart';
import 'files.dart';

/// WebView2 on Windows needs a writable data folder; we keep it in app data.
class WebEnv {
  static WebViewEnvironment? env;

  static Future<void> init() async {
    if (!io.Platform.isWindows) return;
    try {
      final storage = await AppStorage.instance();
      env = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: '${storage.root.path}\\webview'),
      );
    } catch (_) {}
  }

  static CookieManager get cookies => CookieManager.instance(webViewEnvironment: env);
}

/// Shows the real lms.tuit.uz in an embedded browser.
/// In [loginMode] it captures the session cookie after you sign in
/// (login/password or OneID) and returns to the app.
class LmsWebPage extends StatefulWidget {
  const LmsWebPage({super.key, this.loginMode = false, this.path});
  final bool loginMode;
  final String? path;

  static Future<bool?> login(BuildContext context) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LmsWebPage(loginMode: true)));

  static Future<void> open(BuildContext context, [String? path]) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LmsWebPage(path: path)));

  @override
  State<LmsWebPage> createState() => _LmsWebPageState();
}

class _LmsWebPageState extends State<LmsWebPage> {
  InAppWebViewController? _c;
  double _progress = 0;
  bool _done = false;
  bool _autoSubmitted = false;
  String? _savedLogin;
  String? _savedPassword;

  @override
  void initState() {
    super.initState();
    _loadCreds();
  }

  Future<void> _loadCreds() async {
    _savedLogin = await Secrets.read(Secrets.lmsLogin);
    _savedPassword = await Secrets.read(Secrets.lmsPassword);
  }

  String get _startUrl {
    if (widget.loginMode) return '$lmsBase/auth/login';
    return absoluteUrl(widget.path ?? '/dashboard/news');
  }

  bool _isLmsLoggedInPage(WebUri? url) {
    if (url == null || url.host != 'lms.tuit.uz') return false;
    final p = url.path;
    return !(p.startsWith('/auth') || p == '/login' || p.startsWith('/login/') || p == '/schedule');
  }

  Future<void> _onLoadStop(InAppWebViewController c, WebUri? url) async {
    if (url == null) return;
    if (url.host == 'lms.tuit.uz' && url.path.startsWith('/auth/login')) {
      await _prepareLoginForm(c);
      return;
    }
    if (_isLmsLoggedInPage(url)) await _captureSession(c);
  }

  Future<void> _prepareLoginForm(InAppWebViewController c) async {
    final app = context.read<AppState>();
    await c.evaluateJavascript(source: '''
(function(){
  var f = document.querySelector('form[action*="auth/login"]');
  if (!f || f.__tm) return; f.__tm = true;
  f.addEventListener('submit', function(){
    var l = document.getElementById('login'), p = document.getElementById('password');
    if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('creds', l ? l.value : '', p ? p.value : '');
  }, true);
})();''');
    if (_savedLogin != null && _savedPassword != null) {
      await c.evaluateJavascript(source: '''
(function(){
  var l = document.getElementById('login'), p = document.getElementById('password');
  if (l && !l.value) l.value = ${jsonEncode(_savedLogin)};
  if (p && !p.value) p.value = ${jsonEncode(_savedPassword)};
})();''');
      final hasError = await c.evaluateJavascript(source: "!!document.querySelector('[role=alert], .alert-danger')");
      if (app.settings.autoLogin && !_autoSubmitted && hasError != true) {
        _autoSubmitted = true;
        await c.evaluateJavascript(source: '''
(function(){ var n=0; var t=setInterval(function(){ var b=document.getElementById('login-btn'); n++;
  if(b && !b.disabled){ clearInterval(t); b.click(); } if(n>40) clearInterval(t); }, 250); })();''');
      }
    }
  }

  Future<void> _captureSession(InAppWebViewController c) async {
    final app = context.read<AppState>();
    try {
      final raw = await WebEnv.cookies.getCookies(url: WebUri(lmsBase), webViewController: c);
      final cookies = <io.Cookie>[];
      for (final k in raw) {
        try {
          cookies.add(makeCookie(k.name, '${k.value}',
              expiresMs: k.expiresDate, httpOnly: k.isHttpOnly, secure: k.isSecure, path: k.path));
        } catch (_) {}
      }
      if (!cookies.any((k) => k.name.toLowerCase().contains('session'))) return;
      if (widget.loginMode) {
        if (_done) return;
        _done = true;
        if (mounted) Navigator.of(context).pop(true);
        await app.onLoggedIn(cookies);
      } else {
        await app.client.importCookies(cookies);
        if (app.sessionExpired) {
          app.sessionExpired = false;
          app.refresh(full: false, silent: true);
        }
      }
    } catch (_) {}
  }

  Future<DownloadStartResponse?> _onDownload(InAppWebViewController c, DownloadStartRequest req) async {
    final name = req.suggestedFilename ?? LmsClient.fileNameFromUrl(req.url.toString());
    if (mounted) await downloadAndOpen(context, req.url.toString(), name);
    return DownloadStartResponse(handled: true, action: DownloadStartResponseAction.CANCEL);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.loginMode ? s['signIn'] : s['lmsSite']),
        actions: [
          if (!widget.loginMode) ...[
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _c?.goBack()),
            IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _c?.goForward()),
          ],
          IconButton(icon: const Icon(Icons.refresh), tooltip: s['refresh'], onPressed: () => _c?.reload()),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 3),
              )
            : null,
      ),
      body: Column(
        children: [
          if (widget.loginMode) _LoginOptions(),
          Expanded(
            child: InAppWebView(
              webViewEnvironment: WebEnv.env,
              initialUrlRequest: URLRequest(url: WebUri(_startUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                useOnDownloadStart: true,
                supportZoom: true,
                builtInZoomControls: true,
                displayZoomControls: false,
              ),
              onWebViewCreated: (c) {
                _c = c;
                c.addJavaScriptHandler(
                  handlerName: 'creds',
                  callback: (List<dynamic> args) {
                    final app = context.read<AppState>();
                    if (args.length >= 2 && app.settings.rememberPassword) {
                      final l = '${args[0]}'.trim(), p = '${args[1]}';
                      if (l.isNotEmpty && p.isNotEmpty) {
                        Secrets.write(Secrets.lmsLogin, l);
                        Secrets.write(Secrets.lmsPassword, p);
                      }
                    }
                    return null;
                  },
                );
              },
              onProgressChanged: (c, p) => setState(() => _progress = p / 100),
              onLoadStop: _onLoadStop,
              onUpdateVisitedHistory: (c, url, _) {
                if (_isLmsLoggedInPage(url)) _captureSession(c);
              },
              onDownloadStarting: _onDownload,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginOptions extends StatefulWidget {
  @override
  State<_LoginOptions> createState() => _LoginOptionsState();
}

class _LoginOptionsState extends State<_LoginOptions> {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = context.read<AppState>();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s['loginHint'], style: Theme.of(context).textTheme.bodySmall),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: app.settings.rememberPassword,
              title: Text(s['rememberPassword']),
              onChanged: (v) {
                setState(() => app.settings.rememberPassword = v ?? true);
                if (v == false) Secrets.deleteLms();
              },
            ),
          ],
        ),
      ),
    );
  }
}
