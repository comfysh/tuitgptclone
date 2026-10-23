import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart';

import '../core/storage.dart';

/// A request to open the AI chat with a prepared prompt (and maybe a file).
class ChatLaunch {
  final String prompt;
  final String? fileName;
  final Uint8List? bytes;

  /// Send the prompt right away (asked from the Ask palette) instead of
  /// leaving it in the box to edit.
  final bool send;
  const ChatLaunch(this.prompt, {this.fileName, this.bytes, this.send = false});
}

class ChatAttachment {
  final String name;
  final String mime;
  final String path; // copy inside the app's chat_files folder
  final int size;
  const ChatAttachment({required this.name, required this.mime, required this.path, required this.size});

  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  Map<String, dynamic> toJson() => {'name': name, 'mime': mime, 'path': path, 'size': size};
  factory ChatAttachment.fromJson(Map<String, dynamic> j) =>
      ChatAttachment(name: j['name'] ?? 'file', mime: j['mime'] ?? 'application/octet-stream', path: j['path'] ?? '', size: j['size'] ?? 0);

  /// Saves [bytes] into the app folder so the chat can resend it later.
  static Future<ChatAttachment> save(String name, Uint8List bytes) async {
    final storage = await AppStorage.instance();
    final dir = storage.chatFilesDir;
    await dir.create(recursive: true);
    final id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final f = File('${dir.path}${Platform.pathSeparator}${id}_$safe');
    await f.writeAsBytes(bytes);
    final mime = lookupMimeType(name, headerBytes: bytes.take(32).toList()) ?? _guessMime(name);
    return ChatAttachment(name: name, mime: mime, path: f.path, size: bytes.length);
  }

  static String _guessMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'md' || 'txt' || 'csv' || 'log' => 'text/plain',
      'py' || 'java' || 'c' || 'cpp' || 'cs' || 'js' || 'ts' || 'dart' || 'kt' || 'go' || 'sql' || 'html' || 'css' =>
        'text/plain',
      _ => 'application/octet-stream',
    };
  }
}

class ChatMessage {
  final String role; // 'user' | 'assistant'
  String text;
  final List<ChatAttachment> attachments;
  final DateTime time;
  bool error;

  ChatMessage(this.role, this.text, {this.attachments = const [], DateTime? time, this.error = false})
      : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'time': time.toIso8601String(),
        'error': error,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        j['role'] ?? 'user',
        j['text'] ?? '',
        attachments: ((j['attachments'] as List?) ?? const [])
            .map((e) => ChatAttachment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        time: DateTime.tryParse(j['time'] ?? ''),
        error: j['error'] == true,
      );
}

class Conversation {
  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updatedAt;

  Conversation({required this.id, this.title = '', List<ChatMessage>? messages, DateTime? updatedAt})
      : messages = messages ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  factory Conversation.create() => Conversation(id: DateTime.now().microsecondsSinceEpoch.toString());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        messages: ((j['messages'] as List?) ?? const [])
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? ''),
      );
}

class ChatStore {
  static const maxChats = 100;

  static Future<void> deleteAttachment(ChatAttachment a) async {
    try {
      await File(a.path).delete();
    } catch (_) {}
  }

  static Future<List<Conversation>> load() async {
    final storage = await AppStorage.instance();
    final j = await storage.readJson(storage.chatsFile);
    final list = ((j['chats'] as List?) ?? const [])
        .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // Version 1.0.0 could save a chat twice; keep the newest copy.
    final seen = <String>{};
    list.retainWhere((c) => seen.add(c.id));
    return list;
  }

  static Future<void> save(List<Conversation> chats) async {
    final storage = await AppStorage.instance();
    await storage.writeJson(storage.chatsFile, {'chats': chats.take(maxChats).map((e) => e.toJson()).toList()});
  }

  /// Deletes files in chat_files/ that no saved message uses (left behind
  /// when the app was closed with unsent attachments). Recent files are kept
  /// in case they are being attached right now.
  static Future<void> sweepOrphans(List<Conversation> chats) async {
    final storage = await AppStorage.instance();
    final dir = storage.chatFilesDir;
    if (!await dir.exists()) return;
    final used = {
      for (final c in chats)
        for (final m in c.messages)
          for (final a in m.attachments) a.path,
    };
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    await for (final e in dir.list()) {
      if (e is! File || used.contains(e.path)) continue;
      try {
        if ((await e.lastModified()).isBefore(cutoff)) await e.delete();
      } catch (_) {}
    }
  }

  static Future<void> deleteFiles(Conversation c) async {
    for (final m in c.messages) {
      for (final a in m.attachments) {
        try {
          await File(a.path).delete();
        } catch (_) {}
      }
    }
  }
}
