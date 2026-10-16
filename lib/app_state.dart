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
    if (state == AppLifecycleState.resumed && loggedIn) {
      final age = DateTime.now().difference(snapshot.updatedAt ?? DateTime(2000));
      if (age > const Duration(minutes: 10)) refresh(full: false, silent: true);
    }
  }

  /// Called by the login page with cookies captured from the WebView.
  Future<void> onLoggedIn(List<Cookie> cookies) async {
    await client.importCookies(cookies);
    loggedIn = true;
    sessionExpired = false;
    notifyListeners();
    await Notifier.requestPermission();
    await configureBackground();
    await refresh();
  }

  Future<void> refresh({bool full = true, bool silent = false}) async {
    if (syncing || !loggedIn) return;
    syncing = true;
    if (!silent) lastError = null;
    notifyListeners();
    final old = snapshot;
    try {
      final fresh = await fetchSnapshot(client, previous: old, semesterId: settings.semesterId, full: full);
      snapshot = fresh;
      sessionExpired = false;
      lastError = null;
      await storage.saveSnapshot(fresh);
      try {
        await Notifier.processChanges(old.isEmpty ? null : old, fresh, settings, storage);
      } catch (_) {}
    } on SessionExpiredException {
      sessionExpired = true;
    } catch (e) {
      lastError = e.toString();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> changeSemester(int? id) async {
    settings.semesterId = id;
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
        final page = await client.coursePage(course);
        if (page != null) {
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

  Future<void> logout() async {
    await client.logout();
    await storage.clearAll();
    await Secrets.deleteLms();
    snapshot = LmsSnapshot();
    loggedIn = false;
    sessionExpired = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
