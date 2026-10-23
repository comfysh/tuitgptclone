// Windows: keeps TuitMate running in the system tray, so the periodic LMS
// checks and notifications (AppState's desktop timer) go on while the window
// is closed.
//
// - Tray icon "TuitMate" with Open TuitMate / Refresh now / Quit in the app
//   language (rebuilt when the language changes). A left click or a double
//   click opens the window, a right click shows the menu.
// - The close button hides the window to the tray when settings.closeToTray
//   is on, otherwise it quits.
// - Launched with --minimized (the installer's "Start with Windows" entry) the
//   window stays hidden and only the tray icon appears: the runner skips its
//   first-frame Show() for that flag (windows/runner/flutter_window.cpp).
// - A second launch brings this window to the front
//   (windows/runner/main.cpp).
//
// Does nothing on other platforms (no plugin calls) and never throws.

import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart' show Menu, MenuItem, TrayListener, trayManager;
import 'package:window_manager/window_manager.dart' show WindowListener, windowManager;

import '../app_state.dart';
import '../core/strings.dart';

class DesktopTray with TrayListener, WindowListener {
  DesktopTray._(this._app, this._onRefresh);

  /// Launch argument for a hidden start (only the tray icon).
  static const minimizedArg = '--minimized';

  /// Registered in pubspec.yaml; tray_manager resolves it under data/flutter_assets.
  static const _iconAsset = 'assets/tray/tray_icon.ico';

  static const _open = 'open';
  static const _refresh = 'refresh';
  static const _quit = 'quit';

  static DesktopTray? _instance;

  final AppState _app;
  final Future<void> Function() _onRefresh;

  /// The tray icon is shown, so a hidden window can be reached again.
  bool _trayReady = false;

  /// window_manager is set up and intercepts the close button.
  bool _windowReady = false;

  bool _quitting = false;
  String? _menuLang;

  /// Sets up the tray icon and the close-to-tray behaviour on Windows. Call
  /// once from main() before runApp, with main's [args]. [onRefresh] is what
  /// "Refresh now" runs (default: [AppState.refresh]).
  static Future<void> init(
    AppState app, {
    List<String> args = const [],
    Future<void> Function()? onRefresh,
  }) async {
    if (!Platform.isWindows || _instance != null) return;
    final tray = _instance = DesktopTray._(app, onRefresh ?? () => app.refresh());
    try {
      await tray._start(startHidden: args.contains(minimizedArg));
    } catch (_) {}
  }

  Future<void> _start({required bool startHidden}) async {
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      // onWindowClose decides between hiding to the tray and quitting.
      await windowManager.setPreventClose(true);
      _windowReady = true;
    } catch (_) {}

    try {
      // tray_manager gives no error for a missing icon file; without an icon
      // hiding the window would leave TuitMate unreachable.
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final icon = File('$exeDir\\data\\flutter_assets\\${_iconAsset.replaceAll('/', '\\')}');
      if (await icon.exists()) {
        trayManager.addListener(this);
        await trayManager.setIcon(_iconAsset);
        _trayReady = true;
        await trayManager.setToolTip('TuitMate');
      }
    } catch (_) {}
    await _buildMenu();
    _app.addListener(_onAppChanged);

    // Without a tray icon a hidden window could not be opened again.
    if (startHidden && !_trayReady) await _show();
  }

  Future<void> _buildMenu() async {
    if (!_trayReady) return;
    final lang = _app.language;
    _menuLang = lang;
    final s = S(lang);
    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: _open, label: s['dkTrayOpen']),
        MenuItem(key: _refresh, label: s['dkTrayRefresh']),
        MenuItem.separator(),
        MenuItem(key: _quit, label: s['dkTrayQuit']),
      ]));
    } catch (_) {}
  }

  void _onAppChanged() {
    if (_app.language != _menuLang) unawaited(_buildMenu());
  }

  /// Shows the window if it is hidden in the tray (a tapped notification).
  static Future<void> bringToFront() async => _instance?._show();

  Future<void> _show() async {
    if (!_windowReady) return;
    try {
      await windowManager.show();
      await windowManager.focus(); // also restores a minimized window
    } catch (_) {}
  }

  Future<void> _refreshNow() async {
    try {
      if (!_app.loggedIn) {
        await _show(); // signing in happens in the window
        return;
      }
      await _onRefresh();
    } catch (_) {}
  }

  Future<void> _exit() async {
    if (_quitting) return;
    _quitting = true;
    // The runner's teardown doesn't pass WM_DESTROY to the plugin, so remove
    // the icon now or it lingers in the tray until the mouse passes over it.
    if (_trayReady) {
      try {
        await trayManager.destroy();
      } catch (_) {}
    }
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  Future<void> _onClose() async {
    try {
      if (_trayReady && !_quitting && _app.settings.closeToTray) {
        await windowManager.hide();
      } else {
        await _exit();
      }
    } catch (_) {}
  }

  // ---- WindowListener

  @override
  void onWindowClose() {
    // Without setPreventClose the window is already closing natively.
    if (_windowReady) unawaited(_onClose());
  }

  // ---- TrayListener (on Windows "mouse down" fires on button release)

  @override
  void onTrayIconMouseDown() => unawaited(_show());

  @override
  void onTrayIconRightMouseDown() => unawaited(_popUpMenu());

  Future<void> _popUpMenu() async {
    try {
      // Windows only closes a tray menu on an outside click when the app is the
      // foreground window; bringAppToFront makes it so before the menu opens.
      // ignore: deprecated_member_use
      await trayManager.popUpContextMenu(bringAppToFront: true);
    } catch (_) {}
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _open:
        unawaited(_show());
      case _refresh:
        unawaited(_refreshNow());
      case _quit:
        unawaited(_exit());
    }
  }
}
