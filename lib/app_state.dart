import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'core/settings.dart';
import 'core/storage.dart';
import 'lms/changes.dart';
import 'lms/lms_client.dart';
import 'lms/models.dart';
import 'lms/snapshot.dart';
import 'services/automation.dart';
import 'services/background.dart';
import 'services/background_login.dart';
import 'services/home_widget_service.dart';
import 'services/inbox.dart';
import 'services/notifier.dart';
import 'services/web_env.dart';
import 'ui/themes.dart';

/// Global app state: settings, LMS session and the latest data snapshot.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.settings, this.storage, this.client, this.snapshot, this.loggedIn) {
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  /// How often the app checks LMS while it is open (on PC also while it sits
  /// in the tray). Closed, Android's background checks take over.
  static const openCheckMinutes = 10;

  /// Retries after a sync that could not load everything.
  static const _retryDelays = [Duration(seconds: 30), Duration(seconds: 90), Duration(minutes: 5)];

  final Settings settings;
  final AppStorage storage;
  final LmsClient client;
  LmsSnapshot snapshot;
  bool loggedIn;

  /// What changed in LMS, newest first (the Inbox).
  List<InboxItem> inbox = const [];
  int get unread => inbox.where((i) => !i.read).length;

  bool syncing = false;
  bool sessionExpired = false;
  String? lastError;
  Timer? _timer;
  Timer? _retryTimer;
  int _retries = 0;
  AppLifecycleState _life = AppLifecycleState.resumed;

  /// Parts of the last sync that still failed after the automatic retries
  /// (keys of [LmsSnapshot.errors]); the saved copy is shown for them.
  List<String> get failedParts => _retries >= _retryDelays.length ? snapshot.errors.keys.toList() : const [];

  /// Completes when the running refresh finishes.
  Completer<void>? _sync;

  /// Set when something asked for a refresh while one was running.
  bool _refreshAgain = false;

  /// A background re-login just happened; don't loop if LMS refuses again.
  bool _reloggedIn = false;

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
    return AppState(settings, storage, client, snap, loggedIn)..inbox = loggedIn ? await Inbox.load(storage) : const [];
  }

  /// Marks Inbox items read ([ids] null: every item shown now, not ones the
  /// background check added since). The screen updates at once.
  Future<void> markInboxRead({Set<String>? ids}) async {
    final target = ids ?? {for (final i in inbox) if (!i.read) i.id};
    if (!inbox.any((i) => !i.read && target.contains(i.id))) return;
    inbox = [for (final i in inbox) target.contains(i.id) ? i.copyWith(read: true) : i];
    notifyListeners();
    final saved = await Inbox.markRead(storage, ids: target);
    if (saved.isNotEmpty && loggedIn) {
      inbox = saved; // also picks up what the background check added
      notifyListeners();
    }
  }

  /// Picks up what the Android background check added.
  Future<bool> _reloadInbox() async {
    if (!loggedIn) return false;
    final items = await Inbox.load(storage);
    final changed = items.length != inbox.length || items.indexed.any((e) => e.$2.id != inbox[e.$1].id || e.$2.read != inbox[e.$1].read);
    if (changed) inbox = items;
    return changed;
  }

  String get language => settings.language;
  ThemeMode get themeMode => settings.themeMode;

  void setLanguage(String v) {
    settings.language = v;
    notifyListeners();
    // The home-screen widget shows its texts in the app language.
    refreshWidget();
  }

  void setThemeMode(ThemeMode v) {
    settings.themeMode = v;
    notifyListeners();
  }

  AppStyle get style => styleById(settings.themeStyle);

  void setStyle(AppStyle v) {
    settings.themeStyle = v.name;
    notifyListeners();
  }

  void setPureBlack(bool v) {
    settings.pureBlack = v;
    notifyListeners();
  }

  /// Call after changing any setting that affects what is shown.
  void touch() {
    notifyListeners();
    // Week parity, lesson length and NB limits change what the widget shows.
    refreshWidget();
  }

  /// Rewrites the Android home-screen widget from the current data.
  void refreshWidget() {
    if (loggedIn && !snapshot.isEmpty) unawaited(HomeWidgetService.update(snapshot, settings));
  }

  Future<void> configureBackground() async {
    try {
      await Background.configure(settings);
    } catch (_) {}
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final every = Duration(minutes: min(settings.checkMinutes, openCheckMinutes).clamp(5, 240));
    _timer = Timer.periodic(every, (_) {
      if (!loggedIn) return;
      // On Android, once the app is in the background its own checks run.
      if (Platform.isAndroid && _life != AppLifecycleState.resumed) return;
      // An ended session is retried only when the app may sign in by itself.
      if (sessionExpired && !(settings.autoLogin && settings.backgroundLogin)) return;
      refresh(full: false, silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _life = state;
    if (state == AppLifecycleState.resumed && loggedIn) _onResumed();
  }

  Future<void> _onResumed() async {
    final adopted = await _adoptDiskSnapshot();
    if (await _reloadInbox() || adopted) notifyListeners();
    final age = DateTime.now().difference(snapshot.updatedAt ?? DateTime(2000));
    if (age > const Duration(minutes: 2)) await refresh(full: false, silent: true);
  }

  /// After a sync that missed parts (or failed), tries again a few times.
  void _scheduleRetry({required bool full}) {
    _retryTimer?.cancel();
    if (!loggedIn || sessionExpired || _retries >= _retryDelays.length) return;
    _retryTimer = Timer(_retryDelays[_retries++], () {
      if (loggedIn && !sessionExpired) refresh(full: full, silent: true);
    });
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
    unawaited(BackgroundLogin.reset(storage)); // signed in by hand: background re-login may try again
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
    if (!silent) {
      lastError = null;
      _retries = 0; // asked by hand: retry failed parts again
    }
    notifyListeners();
    final epoch = client.epoch;
    var retry = false, retryFull = false;
    try {
      await _adoptDiskSnapshot();
      final old = snapshot;
      // A light check loads everything when teacher files etc. are an hour old.
      final everything = full || needsFullSync(old, DateTime.now());
      final fresh = await fetchSnapshot(client, previous: old, semesterId: settings.semesterId, full: everything);
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
      if (fresh.errors.isEmpty) {
        _retries = 0;
        _retryTimer?.cancel();
      } else {
        retry = true;
        retryFull = fresh.errors.keys.any((k) => k == 'info' || k == 'studyPlan' || k.startsWith('lessons:'));
      }
      try {
        await storage.saveSnapshot(fresh);
      } catch (_) {}
      if (!loggedIn || client.epoch != epoch) return;
      var changes = const <LmsChange>[];
      try {
        changes = await Notifier.processChanges(base.isEmpty ? null : base, fresh, settings, storage);
      } catch (_) {}
      if (loggedIn && client.epoch == epoch) await _reloadInbox();
      if (loggedIn && client.epoch == epoch) {
        unawaited(HomeWidgetService.update(fresh, settings));
        unawaited(Automation.deliver(changes: changes, snap: fresh, settings: settings, storage: storage));
      }
    } on SessionExpiredException {
      if (loggedIn && client.epoch == epoch) {
        // Sign in again without asking (invisible login page), then sync once more.
        if (!_reloggedIn && await BackgroundLogin.run(client, settings, storage) && loggedIn && client.epoch == epoch) {
          _reloggedIn = true;
          _refreshAgain = true;
        } else {
          sessionExpired = true;
          // On Windows the window may be hidden in the tray: say so once.
          if (silent && !Platform.isAndroid && settings.notifications) {
            unawaited(Notifier.notifySessionExpired(settings, storage).catchError((_) {}));
          }
        }
      }
    } catch (e) {
      if (loggedIn && client.epoch == epoch) {
        lastError = e.toString();
        retry = true;
        retryFull = full;
      }
    } finally {
      syncing = false;
      done.complete();
      notifyListeners();
    }
    if (_refreshAgain && loggedIn && !sessionExpired) {
      _refreshAgain = false;
      unawaited(refresh());
    } else {
      _reloggedIn = false;
      if (retry) _scheduleRetry(full: retryFull);
    }
  }

  /// Saves the LMS login and password for automatic sign-in (an empty
  /// [password] keeps the saved one).
  Future<void> saveLogin(String login, String? password) async {
    await Secrets.write(Secrets.lmsLogin, login.trim());
    if (password != null && password.isNotEmpty) await Secrets.write(Secrets.lmsPassword, password);
    settings.rememberPassword = true;
    await BackgroundLogin.reset(storage);
    notifyListeners();
  }

  /// Deletes the saved login and password; automatic sign-in stops.
  Future<void> forgetLogin() async {
    await Secrets.deleteLms();
    settings.rememberPassword = false;
    notifyListeners();
  }

  /// Signs in right now with the saved password ("Try now" in Profile).
  Future<bool> signInNow() async {
    if (!loggedIn) return false;
    final ok = await BackgroundLogin.run(client, settings, storage, force: true);
    if (ok && loggedIn) {
      sessionExpired = false;
      unawaited(refresh());
    }
    notifyListeners();
    return ok;
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
          refreshWidget(); // the submitted task is no longer open
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
    inbox = const [];
    _retryTimer?.cancel();
    _retries = 0;
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
      await HomeWidgetService.clear(); // nothing personal on the home screen
      await WebEnv.clearCookies();
      await storage.clearAll();
      await Secrets.deleteAll();
      settings.adminUnlocked = false; // the automation key went with the other secrets
    } finally {
      wiping = false;
      notifyListeners();
    }
    if (running != null) {
      // A sync started before sign-out may still be finishing; wipe again after it.
      await running;
      snapshot = LmsSnapshot();
      inbox = const [];
      try {
        await Notifier.cancelAll();
      } catch (_) {}
      await HomeWidgetService.clear();
      await client.logout();
      await storage.clearAll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
