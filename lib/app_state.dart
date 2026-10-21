import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'core/settings.dart';
import 'core/storage.dart';
import 'lms/lms_client.dart';
import 'lms/models.dart';
import 'lms/snapshot.dart';
import 'services/background.dart';
import 'services/notifier.dart';
import 'services/web_env.dart';

/// Global app state: settings, LMS session and the latest data snapshot.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.settings, this.storage, this.client, this.snapshot, this.loggedIn) {
    WidgetsBinding.instance.addObserver(this);
    _startDesktopTimer();
  }

  final Settings settings;
  final AppStorage storage;
  final LmsClient client;
  LmsSnapshot snapshot;
  bool loggedIn;

  bool syncing = false;
  bool sessionExpired = false;
  String? lastError;
  Timer? _timer;

  /// Completes when the running refresh finishes.
  Completer<void>? _sync;

  /// Set when something asked for a refresh while one was running.
  bool _refreshAgain = false;

  /// Running sign-out, if any.
  Future<void>? _loggingOut;

  /// True while sign-out is still deleting the WebView session and saved
  /// password; "Sign in" waits for it.
  bool wiping = false;

  static Future<AppState> create() async {
    final settings = await Settings.load();
    final storage = await AppStorage.instance();
    final client = LmsClient(storage.cookieDir);
    final snap = await storage.loadSnapshot() ?? LmsSnapshot();
    final loggedIn = await client.hasSession();
    return AppState(settings, storage, client, snap, loggedIn);
  }

  String get language => settings.language;
  ThemeMode get themeMode => settings.themeMode;

  void setLanguage(String v) {
    settings.language = v;
    notifyListeners();
  }

  void setThemeMode(ThemeMode v) {
    settings.themeMode = v;
    notifyListeners();
  }

  /// Call after changing any setting that affects what is shown.
  void touch() => notifyListeners();

  Future<void> configureBackground() async {
    try {
      await Background.configure(settings);
    } catch (_) {}
    _startDesktopTimer();
  }

  void _startDesktopTimer() {
    _timer?.cancel();
    if (Platform.isAndroid || !settings.notifications) return;
    _timer = Timer.periodic(Duration(minutes: settings.checkMinutes.clamp(5, 240)), (_) {
      if (loggedIn && !sessionExpired) refresh(full: false, silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && loggedIn) _onResumed();
  }

  Future<void> _onResumed() async {
    if (await _adoptDiskSnapshot()) notifyListeners();
    final age = DateTime.now().difference(snapshot.updatedAt ?? DateTime(2000));
    if (age > const Duration(minutes: 10)) await refresh(full: false, silent: true);
  }

  /// The Android background worker runs in another isolate and saves its own
  /// snapshot (and already notified its changes). Use it when it is newer, so
  /// the next diff doesn't announce the same changes again.
  Future<bool> _adoptDiskSnapshot() async {
    final disk = await storage.loadSnapshot();
    final diskAt = disk?.updatedAt;
    if (disk == null || diskAt == null) return false;
    if (snapshot.updatedAt != null && !diskAt.isAfter(snapshot.updatedAt!)) return false;
    snapshot = disk;
    return true;
  }

  /// Called by the login page with cookies captured from the WebView.
  Future<void> onLoggedIn(List<Cookie> cookies) async {
    if (_loggingOut != null) await _loggingOut;
    // From the Welcome screen the new HomeShell starts the first sync itself;
    // a re-login from inside the app has to start it here.
    final shellOpen = loggedIn;
    await client.importCookies(cookies);
    loggedIn = true;
    sessionExpired = false;
    notifyListeners();
    await Notifier.requestPermission();
    await configureBackground();
    _refreshAgain = false; // the sync below (or HomeShell's first one) covers anything queued earlier
    if (shellOpen) await refresh();
  }

  Future<void> refresh({bool full = true, bool silent = false}) async {
    if (!loggedIn) return;
    if (syncing) {
      if (!silent) _refreshAgain = true;
      return;
    }
    syncing = true;
    final done = _sync = Completer<void>();
    if (!silent) lastError = null;
    notifyListeners();
    final epoch = client.epoch;
    try {
      await _adoptDiskSnapshot();
      final old = snapshot;
      final fresh = await fetchSnapshot(client, previous: old, semesterId: settings.semesterId, full: full);
      if (!loggedIn || client.epoch != epoch) return; // signed out meanwhile: drop the result
      // The Android worker may have saved (and notified) while we fetched;
      // diff against the newest copy so nothing is announced twice.
      var base = old;
      final disk = await storage.loadSnapshot();
      if (disk?.updatedAt != null && (old.updatedAt == null || disk!.updatedAt!.isAfter(old.updatedAt!))) {
        base = disk!;
      }
      if (!loggedIn || client.epoch != epoch) return;
      snapshot = fresh;
      sessionExpired = false;
      lastError = null;
      try {
        await storage.saveSnapshot(fresh);
      } catch (_) {}
      if (!loggedIn || client.epoch != epoch) return;
      try {
        await Notifier.processChanges(base.isEmpty ? null : base, fresh, settings, storage);
      } catch (_) {}
    } on SessionExpiredException {
      if (loggedIn && client.epoch == epoch) sessionExpired = true;
    } catch (e) {
      if (loggedIn && client.epoch == epoch) lastError = e.toString();
    } finally {
      syncing = false;
      done.complete();
      notifyListeners();
    }
    if (_refreshAgain && loggedIn && !sessionExpired) {
      _refreshAgain = false;
      unawaited(refresh());
    }
  }

  /// [id] null means "follow the LMS's current semester".
  Future<void> changeSemester(int? id) async {
    settings.semesterId = id;
    if (syncing) {
      _refreshAgain = true; // reload with the new semester once the running sync ends
      return;
    }
    await refresh();
  }

  Future<void> upload(Assignment a, String fileName, Uint8List bytes) async {
    try {
      await client.upload(uploadId: a.uploadId!, courseId: a.courseId, fileName: fileName, bytes: bytes);
    } on SessionExpiredException {
      sessionExpired = true;
      notifyListeners();
      rethrow;
    }
    final course = snapshot.courseById(a.courseId);
    if (course != null) {
      try {
        // A running sync may hold the pre-upload page; let it land first.
        if (syncing) await _sync?.future;
        if (!loggedIn) return;
        final page = await client.coursePage(course);
        if (page != null && loggedIn) {
          snapshot.coursePages = {...snapshot.coursePages, course.id: page};
          await storage.saveSnapshot(snapshot);
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  Future<Uint8List> download(String url, {void Function(int, int)? onProgress}) async {
    try {
      return await client.download(url, onProgress: onProgress);
    } on SessionExpiredException {
      sessionExpired = true;
      notifyListeners();
      rethrow;
    }
  }

  /// Signs out and removes this account's data from the device: LMS session
  /// (app and WebView), cached data, chats, saved password and AI keys,
  /// scheduled notifications and background checks.
  Future<void> logout() => _loggingOut ??= _logout().whenComplete(() => _loggingOut = null);

  Future<void> _logout() async {
    wiping = true;
    final running = syncing ? _sync?.future : null;
    loggedIn = false; // stops new syncs; a running one discards its result
    _refreshAgain = false;
    snapshot = LmsSnapshot();
    sessionExpired = false;
    lastError = null;
    try {
      await client.logout(); // also makes late responses unable to save cookies
      notifyListeners(); // back to the Welcome screen right away ("Sign in" stays disabled)
      try {
        await Notifier.cancelAll();
      } catch (_) {}
      try {
        await Background.cancel();
      } catch (_) {}
      await WebEnv.clearCookies();
      await storage.clearAll();
      await Secrets.deleteAll();
    } finally {
      wiping = false;
      notifyListeners();
    }
    if (running != null) {
      // A sync started before sign-out may still be finishing; wipe again after it.
      await running;
      snapshot = LmsSnapshot();
      try {
        await Notifier.cancelAll();
      } catch (_) {}
      await client.logout();
      await storage.clearAll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
