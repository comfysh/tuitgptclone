import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import '../lms/lms_client.dart';

String safeFileName(String name) {
  final n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return n.isEmpty ? 'file' : (n.length > 120 ? n.substring(n.length - 120) : n);
}

/// File name from a Content-Disposition header value (WebView2 on Windows
/// reports the raw header as the "suggested file name").
String? fileNameFromDisposition(String? cd) {
  if (cd == null || cd.isEmpty || !cd.toLowerCase().contains('filename')) return null;
  final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false).firstMatch(cd);
  if (star != null) {
    try {
      return Uri.decodeComponent(star.group(1)!.trim());
    } catch (_) {}
  }
  final m = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false).firstMatch(cd);
  final n = m?.group(1)?.trim();
  return (n == null || n.isEmpty) ? null : n;
}

/// Picks a name with the right extension: prefers the URL's filename
/// when the link text has no extension.
String bestFileName(String url, String label) {
  final fromUrl = LmsClient.fileNameFromUrl(url, fallback: '');
  final ext = fromUrl.contains('.') ? fromUrl.substring(fromUrl.lastIndexOf('.')) : '';
  if (label.isEmpty) return fromUrl.isEmpty ? 'file' : fromUrl;
  // "Practice_9.1" has a dot but no extension: check against the URL's real one.
  if (ext.isEmpty || label.toLowerCase().endsWith(ext.toLowerCase())) return label;
  return '$label$ext';
}

/// Shows progress/result text somewhere other than a SnackBar (e.g. inside a
/// bottom sheet, which would hide the SnackBar). null clears it.
typedef StatusCallback = void Function(String? message, {bool busy, bool error});

/// Downloads a file from LMS using your session and opens it.
Future<void> downloadAndOpen(BuildContext context, String url, String label, {StatusCallback? onStatus}) async {
  final app = context.read<AppState>();
  final s = S.read(context);
  final messenger = ScaffoldMessenger.of(context);
  if (onStatus != null) {
    onStatus(s['downloading'], busy: true);
  } else {
    messenger.showSnackBar(SnackBar(content: Text(s['downloading']), duration: const Duration(seconds: 30)));
  }
  try {
    final bytes = await app.download(url);
    final dir = await app.storage.downloadsDir();
    final file = File('${dir.path}${Platform.pathSeparator}${safeFileName(bestFileName(url, label))}');
    await file.writeAsBytes(bytes);
    if (onStatus != null) {
      onStatus(s.f('downloaded', {'path': file.path}));
    } else {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(s.f('downloaded', {'path': file.path})),
        action: SnackBarAction(label: s['open'], onPressed: () => OpenFilex.open(file.path)),
      ));
    }
    await OpenFilex.open(file.path);
  } catch (e) {
    if (onStatus != null) {
      onStatus('${s['error']}: $e', error: true);
    } else {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('${s['error']}: $e')));
    }
  }
}

/// Downloads a file into memory (used to give LMS files to the AI).
Future<(String, Uint8List)?> fetchForAi(BuildContext context, String url, String label, {StatusCallback? onStatus}) async {
  final app = context.read<AppState>();
  final s = S.read(context);
  final messenger = ScaffoldMessenger.of(context);
  if (onStatus != null) {
    onStatus(s['downloading'], busy: true);
  } else {
    messenger.showSnackBar(SnackBar(content: Text(s['downloading'])));
  }
  try {
    final bytes = await app.download(url);
    if (onStatus != null) {
      onStatus(null);
    } else {
      messenger.hideCurrentSnackBar();
    }
    return (bestFileName(url, label), bytes);
  } catch (e) {
    if (onStatus != null) {
      onStatus('${s['error']}: $e', error: true);
    } else {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('${s['error']}: $e')));
    }
    return null;
  }
}
