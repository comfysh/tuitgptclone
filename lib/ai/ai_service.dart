import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/settings.dart';
import '../core/storage.dart';
import 'chat_models.dart';
import 'file_text.dart';

class AiException implements Exception {
  final String message;

  /// The API rejected the request itself (bad input, too large, blocked).
  /// Resending the same turn would fail again.
  final bool badRequest;
  AiException(this.message, {this.badRequest = false});
  @override
  String toString() => message;
}

/// Talks to Google Gemini (free tier) or any OpenAI-compatible API
/// (OpenAI, Groq, OpenRouter, …). Replies are streamed token by token.
class AiService {
  AiService(this.settings);
  final Settings settings;

  static const geminiBase = 'https://generativelanguage.googleapis.com/v1beta';
  static const maxInlineBytes = 18 * 1024 * 1024;
  static const maxTextChars = 200000;

  // Image types each API accepts inline; others (svg, bmp, tiff…) are rejected.
  static const _geminiImages = {'image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif'};
  static const _openaiImages = {'image/png', 'image/jpeg', 'image/webp', 'image/gif'};

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
    validateStatus: (_) => true,
  ));

  Future<String?> apiKey() =>
      Secrets.read(settings.aiProvider == AiProvider.gemini ? Secrets.geminiKey : Secrets.openaiKey);

  // ------------------------------------------------------------ parts

  Future<List<Map<String, dynamic>>> _geminiParts(ChatMessage m) async {
    final parts = <Map<String, dynamic>>[];
    for (final a in m.attachments) {
      final bytes = await _read(a);
      if (bytes == null) continue;
      final text = extractText(a.name, a.mime, bytes);
      if (text != null) {
        parts.add({'text': _fileBlock(a.name, text)});
      } else if (bytes.length <= maxInlineBytes &&
          (a.isPdf || _geminiImages.contains(a.mime) || a.mime.startsWith('audio/') || a.mime.startsWith('video/'))) {
        parts.add({
          'inlineData': {'mimeType': a.mime, 'data': base64Encode(bytes)}
        });
      } else {
        parts.add({'text': '[Attached file "${a.name}" (${a.mime}) could not be read.]'});
      }
    }
    if (m.text.trim().isNotEmpty) parts.add({'text': m.text});
    if (parts.isEmpty) parts.add({'text': '…'});
    return parts;
  }

  Future<dynamic> _openaiContent(ChatMessage m) async {
    if (m.attachments.isEmpty) return m.text;
    final parts = <Map<String, dynamic>>[];
    for (final a in m.attachments) {
      final bytes = await _read(a);
      if (bytes == null) continue;
      final text = extractText(a.name, a.mime, bytes);
      if (text != null) {
        parts.add({'type': 'text', 'text': _fileBlock(a.name, text)});
      } else if (_openaiImages.contains(a.mime) && bytes.length <= maxInlineBytes) {
        parts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:${a.mime};base64,${base64Encode(bytes)}'}
        });
      } else {
        parts.add({'type': 'text', 'text': '[Attached file "${a.name}" (${a.mime}) could not be read by this model.]'});
      }
    }
    parts.add({'type': 'text', 'text': m.text.trim().isEmpty ? '…' : m.text});
    return parts;
  }

  String _fileBlock(String name, String text) {
    final t = text.length > maxTextChars ? '${text.substring(0, maxTextChars)}\n…(truncated)' : text;
    return 'Attached file "$name":\n"""\n$t\n"""';
  }

  Future<Uint8List?> _read(ChatAttachment a) async {
    try {
      return await File(a.path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ streaming

  /// Streams the assistant reply for [history] (last item is the new user message).
  Stream<String> stream({required String system, required List<ChatMessage> history, CancelToken? cancel}) async* {
    final key = await apiKey();
    if (key == null || key.isEmpty) throw AiException('NO_KEY');
    if (settings.aiProvider == AiProvider.gemini) {
      yield* _gemini(key, system, history, cancel);
    } else {
      yield* _openai(key, system, history, cancel);
    }
  }

  Stream<String> _gemini(String key, String system, List<ChatMessage> history, CancelToken? cancel) async* {
    final contents = <Map<String, dynamic>>[];
    for (final m in history) {
      if (m.error) continue;
      contents.add({'role': m.role == 'assistant' ? 'model' : 'user', 'parts': await _geminiParts(m)});
    }
    final model = settings.geminiModel.replaceFirst('models/', '');
    final r = await _dio.post<ResponseBody>(
      '$geminiBase/models/$model:streamGenerateContent?alt=sse',
      data: {
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
        'contents': contents,
      },
      options: Options(responseType: ResponseType.stream, headers: {'x-goog-api-key': key}),
      cancelToken: cancel,
    );
    yield* _sse(r, (j) {
      final cand = (j['candidates'] as List?)?.firstOrNull;
      final parts = cand?['content']?['parts'] as List?;
      final text = parts == null ? '' : parts.where((p) => p['thought'] != true).map((p) => p['text'] ?? '').join();
      // A blocked prompt is an error: the turn is then not sent again.
      final block = j['promptFeedback']?['blockReason'];
      if (block != null) throw AiException('Gemini blocked this request ($block).', badRequest: true);
      // Explain why an answer stopped early instead of leaving an empty bubble.
      final reason = cand?['finishReason'];
      final note =
          reason != null && reason != 'STOP' && reason != 'FINISH_REASON_UNSPECIFIED' ? '\n\n[stopped: $reason]' : '';
      final out = '$text$note';
      return out.isEmpty ? null : out;
    });
  }

  Stream<String> _openai(String key, String system, List<ChatMessage> history, CancelToken? cancel) async* {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
    ];
    for (final m in history) {
      if (m.error) continue;
      messages.add({'role': m.role, 'content': await _openaiContent(m)});
    }
    final base = settings.openaiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final r = await _dio.post<ResponseBody>(
      '$base/chat/completions',
      data: {'model': settings.openaiModel, 'stream': true, 'messages': messages},
      options: Options(responseType: ResponseType.stream, headers: {'Authorization': 'Bearer $key'}),
      cancelToken: cancel,
    );
    yield* _sse(r, (j) => (j['choices'] as List?)?.firstOrNull?['delta']?['content'] as String?);
  }

  Stream<String> _sse(Response<ResponseBody> r, String? Function(Map<String, dynamic>) pick) async* {
    final body = r.data;
    if (body == null) throw AiException('Empty response');
    final lines = body.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    if ((r.statusCode ?? 0) >= 400) {
      final text = await lines.join('\n');
      final code = r.statusCode ?? 0;
      throw AiException(_errorText(r.statusCode, text), badRequest: code == 400 || code == 413 || code == 422);
    }
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      try {
        final j = jsonDecode(data);
        if (j is Map<String, dynamic>) {
          if (j['error'] != null) throw AiException(_errorText(r.statusCode, data));
          final t = pick(j);
          if (t != null && t.isNotEmpty) yield t;
        }
      } on FormatException {
        continue;
      }
    }
  }

  String _errorText(int? code, String body) {
    try {
      final j = jsonDecode(body);
      final e = j is List ? j.first['error'] : j['error'];
      final msg = e is Map ? (e['message'] ?? e.toString()) : e.toString();
      return 'HTTP $code: $msg';
    } catch (_) {
      return 'HTTP $code: ${body.length > 300 ? body.substring(0, 300) : body}';
    }
  }

  // ------------------------------------------------------------ helpers

  Future<List<String>> listModels() async {
    final key = await apiKey();
    if (key == null || key.isEmpty) throw AiException('NO_KEY');
    if (settings.aiProvider == AiProvider.gemini) {
      final r = await _dio.get('$geminiBase/models?pageSize=200', options: Options(headers: {'x-goog-api-key': key}));
      if ((r.statusCode ?? 0) >= 400) throw AiException(_errorText(r.statusCode, jsonEncode(r.data)));
      final models = ((r.data['models'] as List?) ?? const [])
          .where((m) => ((m['supportedGenerationMethods'] as List?) ?? const []).contains('generateContent'))
          .map((m) => (m['name'] as String).replaceFirst('models/', ''))
          .where((n) => n.startsWith('gemini'))
          .toList();
      models.sort();
      return ['gemini-flash-latest', 'gemini-flash-lite-latest', ...models.reversed];
    }
    final base = settings.openaiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final r = await _dio.get('$base/models', options: Options(headers: {'Authorization': 'Bearer $key'}));
    if ((r.statusCode ?? 0) >= 400) throw AiException(_errorText(r.statusCode, jsonEncode(r.data)));
    final ids = ((r.data['data'] as List?) ?? const []).map((m) => m['id'].toString()).toList()..sort();
    return ids;
  }

  /// Sends a tiny request to check the key and model.
  Future<String> test() async {
    final buf = StringBuffer();
    await for (final t in stream(system: 'Reply with one short word.', history: [ChatMessage('user', 'Say OK')])) {
      buf.write(t);
      if (buf.length > 40) break;
    }
    return buf.toString().trim();
  }
}
