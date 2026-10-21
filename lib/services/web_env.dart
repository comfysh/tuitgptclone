import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/storage.dart';

/// Shared WebView setup. WebView2 on Windows needs a writable data folder,
/// so we keep it in the app's data directory.
class WebEnv {
  static WebViewEnvironment? env;

  static Future<void> init() async {
    if (!Platform.isWindows) return;
    try {
      final storage = await AppStorage.instance();
      env = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: '${storage.root.path}\\webview'),
      );
    } catch (_) {}
  }

  static CookieManager get cookies => CookieManager.instance(webViewEnvironment: env);

  /// Forgets the LMS session kept by the embedded browser.
  static Future<void> clearCookies() async {
    try {
      await cookies.deleteAllCookies();
    } catch (_) {}
  }
}
