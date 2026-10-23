import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../lms/snapshot.dart';

/// File locations and small persistence helpers shared by the UI and the
/// background worker.
class AppStorage {
  AppStorage._(this.root);
  final Directory root;

  static AppStorage? _instance;

  /// Uses [dir] instead of the platform folder (tests).
  static AppStorage useDirectory(Directory dir) => _instance = AppStorage._(dir);

  static Future<AppStorage> instance() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}tuitmate');
    await dir.create(recursive: true);
    return _instance = AppStorage._(dir);
  }

  String _p(String name) => '${root.path}${Platform.pathSeparator}$name';

  String get cookieDir => _p('cookies${Platform.pathSeparator}');
  File get snapshotFile => File(_p('snapshot.json'));
  File get notifyStateFile => File(_p('notify_state.json'));
  File get chatsFile => File(_p('chats.json'));

  /// Everything that changed in LMS, for the Inbox (lib/services/inbox.dart).
  File get inboxFile => File(_p('inbox.json'));

  /// Webhook delivery state and the queue of events not delivered yet (automation).
  File get automationFile => File(_p('automation.json'));
  Directory get chatFilesDir => Directory(_p('chat_files'));

  Future<Directory> downloadsDir() async {
    Directory? base;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      base = await getDownloadsDirectory();
    }
    base ??= await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}TuitMate');
    await d.create(recursive: true);
    return d;
  }

  Future<LmsSnapshot?> loadSnapshot() async {
    try {
      if (!await snapshotFile.exists()) return null;
      return LmsSnapshot.fromJson(jsonDecode(await snapshotFile.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSnapshot(LmsSnapshot s) => _atomicWrite(snapshotFile, jsonEncode(s.toJson()));

  static final _rand = Random();

  /// Writes via a temp file unique to this write: the UI and the Android
  /// background worker (another isolate) may save at the same moment.
  Future<void> _atomicWrite(File f, String data) async {
    final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}-${_rand.nextInt(1 << 30)}.tmp');
    try {
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<Map<String, dynamic>> readJson(File f) async {
    try {
      if (!await f.exists()) return {};
      return Map<String, dynamic>.from(jsonDecode(await f.readAsString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> writeJson(File f, Object data) => _atomicWrite(f, jsonEncode(data));

  /// Removes everything tied to the signed-in account.
  Future<void> clearAll() async {
    for (final f in [snapshotFile, notifyStateFile, chatsFile, automationFile, inboxFile]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    for (final d in [Directory(cookieDir), chatFilesDir]) {
      try {
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
    // Temp files left by an interrupted write.
    try {
      await for (final e in root.list()) {
        if (e is File && e.path.endsWith('.tmp')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

/// Secrets (LMS password, AI keys) live in the OS keystore.
class Secrets {
  static const _s = FlutterSecureStorage();

  static const lmsLogin = 'lms_login';
  static const lmsPassword = 'lms_password';
  static const geminiKey = 'gemini_key';
  static const openaiKey = 'openai_key';

  /// The owner's AES-256 automation key (base64), after admin unlock.
  static const adminKey = 'admin_key';

  static Future<String?> read(String k) async {
    try {
      return await _s.read(key: k);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String k, String? v) async {
    try {
      if (v == null || v.isEmpty) {
        await _s.delete(key: k);
      } else {
        await _s.write(key: k, value: v);
      }
    } catch (_) {}
  }

  static Future<void> deleteLms() async {
    await write(lmsLogin, null);
    await write(lmsPassword, null);
  }

  /// Sign-out: every secret (LMS, all AI provider keys, the automation key).
  static Future<void> deleteAll() async {
    await deleteLms();
    await write(geminiKey, null);
    await write(openaiKey, null);
    await write(adminKey, null);
    try {
      await _s.deleteAll();
    } catch (_) {}
  }
}
