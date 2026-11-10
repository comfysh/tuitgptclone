import 'dart:io' show Cookie;

import '../core/settings.dart';
import '../core/storage.dart';
import '../lms/lms_client.dart';
import 'background_login.dart';
import 'server_link.dart';

/// LMS said the session is over: get a working one without asking the user.
///
/// 0. A newer session saved on this device by the app's other half.
/// 1. The session your TuitMate server keeps alive, if connected, checked
///    against LMS before it is trusted (the server may not have noticed yet
///    that the same session ended).
/// 2. Otherwise a silent sign-in with the saved login and password, and the
///    new session is handed to the server.
///
/// True when [client] holds a session LMS accepts. Never throws.
Future<bool> renewLmsSession(LmsClient client, Settings settings, AppStorage storage, {bool force = false}) async {
  // 0. The app and its Android background check each keep the cookies in
  //    memory: the other one may already have signed in again and saved it.
  try {
    String? session(List<Cookie> l) => l.where((c) => c.name.toLowerCase().contains('session')).map((c) => c.value).firstOrNull;
    final saved = await LmsClient(storage.cookieDir).currentCookies();
    final onDisk = session(saved);
    if (onDisk != null && onDisk != session(await client.currentCookies())) {
      await client.importCookies(saved);
      if (await client.isSignedIn()) return true;
    }
  } catch (_) {}
  try {
    if (await adoptServerSession(client) && await client.isSignedIn()) return true;
  } catch (_) {}
  try {
    if (await BackgroundLogin.run(client, settings, storage, force: force)) {
      await shareSessionIfNeeded(client, force: true);
      return true;
    }
  } catch (_) {}
  return false;
}
