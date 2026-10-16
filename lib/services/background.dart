import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/settings.dart';
import '../core/storage.dart';
import '../lms/lms_client.dart';
import '../lms/snapshot.dart';
import 'notifier.dart';

const _taskName = 'lms-check';

/// Entry point for Android WorkManager. Runs even when the app is closed.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await runLmsCheck();
    } catch (_) {}
    return true;
  });
}

/// One background check: download a light snapshot, compare, notify.
Future<void> runLmsCheck() async {
  final settings = await Settings.load(reload: true);
  if (!settings.notifications) return;
  final storage = await AppStorage.instance();
  final client = LmsClient(storage.cookieDir);
  if (!await client.hasSession()) return;
  final prev = await storage.loadSnapshot();
  try {
    final now = await fetchSnapshot(client, previous: prev, semesterId: settings.semesterId, full: false);
    await storage.saveSnapshot(now);
    try {
      await Notifier.processChanges(prev, now, settings, storage);
    } catch (_) {}
  } on SessionExpiredException {
    await Notifier.notifySessionExpired(settings, storage);
  }
}

class Background {
  static Future<void> configure(Settings settings) async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(callbackDispatcher);
    if (!settings.notifications) {
      await Workmanager().cancelByUniqueName(_taskName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: Duration(minutes: max(15, settings.checkMinutes)),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}
