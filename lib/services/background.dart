import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';

import '../core/settings.dart';
import '../core/storage.dart';
import '../lms/lms_client.dart';
import '../lms/snapshot.dart';
import 'home_widget_service.dart';
import '../lms/changes.dart';
import 'automation.dart';
import 'background_login.dart';
import 'notifier.dart';

const _taskName = 'lms-check';

/// Entry point for Android WorkManager. Runs even when the app is closed.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      // This isolate is separate from the UI one, so date formats load again here.
      await initializeDateFormatting();
      await runLmsCheck();
    } catch (_) {
      // Offline or LMS down: Android runs the check again soon (backoff
      // below) instead of waiting for the next period.
      return false;
    }
    return true;
  });
}

/// One background check: download a snapshot (everything, when teacher files
/// and the rest are older than [fullSyncEvery]; otherwise the parts that
/// change during the day), compare, notify, and send automation events. When
/// LMS has ended the session it signs in again with the saved password first
/// (see BackgroundLogin).
Future<void> runLmsCheck() async {
  final settings = await Settings.load(reload: true);
  if (!settings.notifications && !Automation.active(settings)) return;
  final storage = await AppStorage.instance();
  final client = LmsClient(storage.cookieDir);
  final prev = await storage.loadSnapshot();
  // Signed out: sign-out deletes the snapshot and the saved password.
  if (prev == null && !await client.hasSession()) return;

  final full = prev == null || needsFullSync(prev, DateTime.now());
  Future<LmsSnapshot> fetch() => fetchSnapshot(client, previous: prev, semesterId: settings.semesterId, full: full);
  LmsSnapshot now;
  try {
    // The cookie jar drops the session cookie once it expires (LMS keeps it ~2 h).
    if (!await client.hasSession()) throw SessionExpiredException();
    now = await fetch();
  } on SessionExpiredException {
    if (!await BackgroundLogin.run(client, settings, storage)) {
      await Notifier.notifySessionExpired(settings, storage);
      return;
    }
    try {
      now = await fetch();
    } on SessionExpiredException {
      await Notifier.notifySessionExpired(settings, storage);
      return;
    }
  }
  await storage.saveSnapshot(now);
  await HomeWidgetService.update(now, settings); // never throws
  var changes = const <LmsChange>[];
  try {
    changes = await Notifier.processChanges(prev, now, settings, storage);
  } catch (_) {}
  await Automation.deliver(changes: changes, snap: now, settings: settings, storage: storage); // never throws
}

class Background {
  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().cancelByUniqueName(_taskName);
  }

  static Future<void> configure(Settings settings) async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(callbackDispatcher);
    if (!settings.notifications && !Automation.active(settings)) {
      await Workmanager().cancelByUniqueName(_taskName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: Duration(minutes: max(15, settings.checkMinutes)),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }
}
