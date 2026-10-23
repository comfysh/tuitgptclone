import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/settings.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import 'chat_models.dart';
import 'file_text.dart';
import 'providers.dart';

export 'providers.dart';

class AiException implements Exception {
  final String message;

  /// The API rejected the request itself (bad input, too large, blocked).
  /// Resending the same turn would fail again.
  final bool badRequest;
  AiException(this.message, {this.badRequest = false});
  @override
  String toString() => message;
}

/// API keys in the OS keystore, one per provider (`ai_key_<id>`).
class AiKeys {
  static String name(String providerId) => 'ai_key_$providerId';

  /// 1.0 kept one Gemini key and one "OpenAI-compatible" key.
  static String? _legacyName(Settings st, String providerId) {
    if (providerId == AiPreset.gemini.id) return Secrets.geminiKey;
    if (providerId == st.aiLegacyKeyProvider) return Secrets.openaiKey;
    return null;
  }

  /// The saved key of [providerId]; a 1.0 key is moved over on first read.
  static Future<String?> read(Settings st, String providerId) async {
    final v = await Secrets.read(name(providerId));
    if (v != null && v.isNotEmpty) return v;
    final old = _legacyName(st, providerId);
    if (old == null) return null;
    final o = await Secrets.read(old);
    if (o == null || o.isEmpty) return null;
    await Secrets.write(name(providerId), o);
    // Keep the old copy if the new one could not be stored.
    if (await Secrets.read(name(providerId)) == o) await Secrets.write(old, null);
    return o;
  }

  /// Saves (or with an empty [key] removes) the key of [providerId].
  static Future<void> write(Settings st, String providerId, String? key) async {
    await Secrets.write(name(providerId), key?.trim());
    final old = _legacyName(st, providerId);
    if (old != null) await Secrets.write(old, null);
  }
}

/// Talks to the provider chosen in settings (lib/ai/providers.dart): Google
/// Gemini through its own API, everything else through the OpenAI
/// chat-completions format. Replies are streamed token by token.
class AiService {
  AiService(this.settings);
  final Settings settings;

  static const geminiBase = 'https://generativelanguage.googleapis.com/v1beta';
  static const maxInlineBytes = 18 * 1024 * 1024;
  static const maxTextChars = 200000;

  /// What [apiKey] returns for a provider that works without a key (local
  /// servers, Custom) when none is saved, so callers treat it as set up.
  static const noKey = 'no-key-needed';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
    validateStatus: (_) => true,
  ));

  AiPreset get preset => settings.aiPreset;
  S get _s => S(settings.language);
  String get _name => preset.displayName((k) => _s[k]);

  /// The selected provider's key, [noKey] when it needs none, or null.
  Future<String?> apiKey() async {
    final p = preset;
    final k = await AiKeys.read(settings, p.id);
    if (k != null && k.isNotEmpty) return k;
    return p.needsKey ? null : noKey;
  }

  Map<String, String> _auth(String key) => key.isEmpty || key == noKey ? const {} : {'Authorization': 'Bearer $key'};

  String _base() {
    final b = settings.aiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (b.isEmpty) throw AiException(_s['aiErrNoUrl']);
    return b;
  }

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
          (a.isPdf ||
              AiPreset.geminiImageTypes.contains(a.mime) ||
              a.mime.startsWith('audio/') ||
              a.mime.startsWith('video/'))) {
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

  /// OpenAI-style content: a plain string unless a picture or PDF goes along
  /// (several APIs, DeepSeek among them, refuse arrays for text-only turns).
  /// Pictures the model can't see are replaced by a short note.
  Future<({Object content, bool pdf})> _openaiContent(ChatMessage m, AiPreset p, String model) async {
    if (m.attachments.isEmpty) return (content: m.text, pdf: false);
    final images = p.supportsImages(model);
    final parts = <Map<String, dynamic>>[];
    var rich = false, pdf = false;
    void note(String t) => parts.add({'type': 'text', 'text': t});
    for (final a in m.attachments) {
      final bytes = await _read(a);
      if (bytes == null) {
        note('[Attached file "${a.name}" could not be opened.]');
        continue;
      }
      final text = extractText(a.name, a.mime, bytes);
      if (text != null) {
        note(_fileBlock(a.name, text));
      } else if (a.isImage && images && p.imageTypes.contains(a.mime) && bytes.length <= maxInlineBytes) {
        parts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:${a.mime};base64,${base64Encode(bytes)}'}
        });
        rich = true;
      } else if (a.isPdf && p.nativePdf && bytes.length <= maxInlineBytes) {
        parts.add({
          'type': 'file',
          'file': {'filename': a.name, 'file_data': 'data:application/pdf;base64,${base64Encode(bytes)}'}
        });
        rich = pdf = true;
      } else if (a.isImage && !images) {
        note('[The student attached the image "${a.name}", but this model cannot see images, so it was not sent.]');
      } else {
        note('[Attached file "${a.name}" (${a.mime}) could not be read by this model.]');
      }
    }
    note(m.text.trim().isEmpty ? '…' : m.text);
    if (!rich) return (content: parts.map((e) => e['text'] as String).join('\n\n'), pdf: false);
    return (content: parts, pdf: pdf);
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

  /// Streams the assistant reply for [history] (last item is the new user
  /// message): only answer text, never a reasoning model's thinking.
  /// Errors are [AiException]s with a message in the UI language; a
  /// cancelled request ends with Dio's cancel exception.
  Stream<String> stream({required String system, required List<ChatMessage> history, CancelToken? cancel}) async* {
    final key = await apiKey();
    if (key == null || key.isEmpty) throw AiException('NO_KEY');
    final reply = preset.isGemini ? _gemini(key, system, history, cancel) : _openai(key, system, history, cancel);
    try {
      await for (final t in reply) {
        yield t;
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _netError(e);
    } on IOException catch (e) {
      throw _netError(e);
    } on TimeoutException catch (e) {
      throw _netError(e);
    }
  }

  Stream<String> _gemini(String key, String system, List<ChatMessage> history, CancelToken? cancel) async* {
    final contents = <Map<String, dynamic>>[];
    for (final m in history) {
      if (m.error) continue;
      contents.add({'role': m.role == 'assistant' ? 'model' : 'user', 'parts': await _geminiParts(m)});
    }
    final model = settings.aiModel;
    if (model.isEmpty) throw AiException(_s['aiErrNoModel']);
    final r = await _dio.post<ResponseBody>(
      '${_base()}/models/$model:streamGenerateContent?alt=sse',
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
    await for (final j in _sse(r)) {
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
      if (out.isNotEmpty) yield out;
    }
  }

  /// finish_reason values worth telling the student about.
  static const _stopNotes = {'length', 'content_filter', 'insufficient_system_resource'};

  Stream<String> _openai(String key, String system, List<ChatMessage> history, CancelToken? cancel) async* {
    final p = preset;
    final base = _base();
    var model = settings.aiModel;
    // A local server or Custom with no model picked yet: use the first one it has.
    if (model.isEmpty && p.editableUrl) model = await _firstModel(key);
    if (model.isEmpty) throw AiException(_s['aiErrNoModel']);
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
    ];
    var pdf = false;
    for (final m in history) {
      if (m.error) continue;
      // An empty answer (stopped before the first word) is refused by some APIs.
      if (m.role == 'assistant' && m.text.trim().isEmpty) continue;
      final c = await _openaiContent(m, p, model);
      pdf = pdf || c.pdf;
      messages.add({'role': m.role, 'content': c.content});
    }
    final r = await _dio.post<ResponseBody>(
      '$base/chat/completions',
      data: {
        'model': model,
        'stream': true,
        'messages': messages,
        if (pdf) ...?p.pdfOptions,
      },
      options: Options(responseType: ResponseType.stream, headers: _auth(key)),
      cancelToken: cancel,
    );
    final think = _ThinkFilter();
    await for (final j in _sse(r)) {
      final choice = (j['choices'] as List?)?.firstOrNull;
      if (choice is! Map) continue;
      // Reasoning models stream their thinking in other fields (DeepSeek
      // `reasoning_content`, OpenRouter/Groq `reasoning`): only `content` is the answer.
      final t = think.add(_deltaText(choice['delta']?['content']));
      if (t.isNotEmpty) yield t;
      final reason = choice['finish_reason'];
      if (reason is String && _stopNotes.contains(reason)) yield '\n\n[stopped: $reason]';
    }
    final rest = think.close();
    if (rest.isNotEmpty) yield rest;
  }

  /// `content` is usually a string; Mistral's reasoning models send a list
  /// of chunks where only the "text" ones are the answer.
  static String _deltaText(Object? c) {
    if (c is String) return c;
    if (c is List) {
      return c.whereType<Map>().where((e) => e['type'] == 'text').map((e) => e['text'] ?? '').join();
    }
    return '';
  }

  /// Server-sent events as JSON objects; HTTP and in-stream errors throw.
  Stream<Map<String, dynamic>> _sse(Response<ResponseBody> r) async* {
    final body = r.data;
    if (body == null) throw AiException('Empty response');
    final lines = body.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    final code = r.statusCode ?? 0;
    if (code >= 400) throw _httpError(code, await lines.join('\n'));
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      Object? j;
      try {
        j = jsonDecode(data);
      } on FormatException {
        continue;
      }
      if (j is! Map<String, dynamic>) continue;
      if (j['error'] != null) throw _httpError(code, data);
      yield j;
    }
  }

  // ------------------------------------------------------------ errors

  /// Turns an API error into a clear message in the UI language, with the
  /// provider's own words in brackets.
  AiException _httpError(int status, String body) {
    final s = _s, name = _name;
    final j = _json(body);
    var code = status;
    // Errors sent inside a 200 stream carry their own code.
    if (code < 400) {
      final e = j is Map ? j['error'] : null;
      final c = e is Map ? e['code'] : null;
      code = c is int ? c : int.tryParse('$c') ?? 500;
    }
    final low = body.toLowerCase();
    final detail = _detail(j, body);
    final region = low.contains('location is not supported') ||
        low.contains('unsupported_country') ||
        low.contains('not available in your region') ||
        low.contains('region, or territory not supported');
    // Gemini answers a wrong key with 400; that turn works once the key is fixed.
    final keyProblem = !region &&
        (code == 401 ||
            low.contains('api_key_invalid') ||
            low.contains('api key not valid') ||
            low.contains('api key expired') ||
            low.contains('invalid api key') ||
            low.contains('incorrect api key') ||
            (code == 403 && (low.contains('key') || low.contains('auth') || low.contains('permission'))));
    final balance = code == 402 ||
        low.contains('insufficient balance') ||
        low.contains('insufficient_quota') ||
        low.contains('insufficient credits');
    final noModel = code == 404 ||
        low.contains('model not exist') ||
        low.contains('model_not_found') ||
        low.contains('no such model') ||
        low.contains('invalid model');
    final String msg;
    if (region) {
      msg = s.f('aiErrRegion', {'name': name});
    } else if (keyProblem) {
      msg = s.f('aiErrKey', {'name': name});
    } else if (balance) {
      msg = s.f('aiErrBalance', {'name': name});
    } else if (code == 429) {
      msg = s.f('aiErrRate', {'name': name});
    } else if (noModel) {
      msg = s.f('aiErrModel', {'name': name, 'model': settings.aiModel});
    } else if (code >= 500) {
      msg = s.f('aiErrServer', {'name': name, 'code': code});
    } else {
      return AiException(detail.isEmpty ? 'HTTP $code' : 'HTTP $code: $detail',
          badRequest: code == 400 || code == 413 || code == 422);
    }
    return AiException(detail.isEmpty ? msg : '$msg\n($detail)', badRequest: code == 413 || code == 422);
  }

  static Object? _json(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// The provider's own error text, short.
  static String _detail(Object? j, String body) {
    Object? msg;
    final e = j is List && j.isNotEmpty && j.first is Map ? j.first['error'] : (j is Map ? j['error'] : null);
    if (e is Map) {
      msg = e['message'] ?? e['msg'] ?? e;
    } else if (e != null) {
      msg = e;
    } else if (j is Map) {
      msg = j['message'] ?? j['detail'] ?? j;
    } else {
      // An HTML error page says nothing useful.
      msg = body.trimLeft().startsWith('<') ? '' : body;
    }
    final t = '$msg'.trim();
    return t.length > 300 ? '${t.substring(0, 300)}…' : t;
  }

  AiException _netError(Object e) {
    final url = settings.aiBaseUrl;
    if (preset.runsLocally || AiPreset.isLocalUrl(url)) return AiException(_s.f('aiErrLocal', {'url': url}));
    final timeout = e is TimeoutException ||
        (e is DioException &&
            (e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.sendTimeout));
    return AiException(_s.f(timeout ? 'aiErrTimeout' : 'aiErrNetwork', {'name': _name}));
  }

  static String _bodyText(Object? data) {
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return '$data';
    }
  }

  // ------------------------------------------------------------ helpers

  /// Model ids the selected provider offers (sorted; OpenRouter: free first).
  Future<List<String>> listModels() async {
    final p = preset;
    final key = await apiKey();
    if ((key == null || key.isEmpty) && !p.publicModels) throw AiException('NO_KEY');
    try {
      return p.isGemini ? await _geminiModels(key!) : await _openaiModels(key ?? noKey);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _netError(e);
    } on IOException catch (e) {
      throw _netError(e);
    }
  }

  Future<List<String>> _geminiModels(String key) async {
    final r = await _dio.get('${_base()}/models?pageSize=200', options: Options(headers: {'x-goog-api-key': key}));
    if ((r.statusCode ?? 0) >= 400) throw _httpError(r.statusCode ?? 0, _bodyText(r.data));
    final models = ((r.data['models'] as List?) ?? const [])
        .where((m) => ((m['supportedGenerationMethods'] as List?) ?? const []).contains('generateContent'))
        .map((m) => (m['name'] as String).replaceFirst('models/', ''))
        .where((n) => n.startsWith('gemini'))
        .toList();
    models.sort();
    return {'gemini-flash-latest', 'gemini-flash-lite-latest', ...models.reversed}.toList();
  }

  /// Not for chat: embeddings, speech, images, moderation…
  static final _nonChat = RegExp(
      r'embed|tts|whisper|dall-e|moderation|transcri|realtime|audio|speech|rerank|guard|orpheus|imagine|gpt-image|sora|ocr|-image');

  /// Item `type`s (Together) that are not chat models.
  static const _nonChatTypes = {'image', 'embedding', 'moderation', 'rerank', 'audio', 'transcribe', 'tts', 'video'};

  Future<List<String>> _openaiModels(String key) async {
    final r = await _dio.get('${_base()}/models', options: Options(headers: _auth(key)));
    if ((r.statusCode ?? 0) >= 400) throw _httpError(r.statusCode ?? 0, _bodyText(r.data));
    var data = r.data;
    if (data is String) data = _json(data);
    // OpenAI style {data: [...]}; Together answers with a bare list.
    final list = data is List ? data : (data is Map ? (data['data'] ?? data['models']) : null);
    final ids = <String>{};
    for (final m in list is List ? list : const []) {
      final id = (m is Map ? (m['id'] ?? m['name']) : m)?.toString() ?? '';
      if (id.isEmpty || _nonChat.hasMatch(id.toLowerCase())) continue;
      if (m is Map) {
        if (_nonChatTypes.contains(m['type'])) continue;
        final caps = m['capabilities'];
        if (caps is Map && caps['completion_chat'] == false) continue; // Mistral
      }
      ids.add(id);
    }
    bool free(String id) => id.endsWith(':free') || id == 'openrouter/free';
    return ids.toList()
      ..sort((a, b) {
        final fa = free(a), fb = free(b);
        if (fa != fb) return fa ? -1 : 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
  }

  /// First model of a local server / Custom; remembered for next time.
  Future<String> _firstModel(String key) async {
    final ms = await _openaiModels(key);
    if (ms.isEmpty) return '';
    settings.setAiModelFor(preset.id, ms.first);
    return ms.first;
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

/// Hides a leading `<think>…</think>` block that some open models (Ollama,
/// LM Studio) write into the answer text itself.
class _ThinkFilter {
  int _state = 0; // 0 = not sure yet, 1 = inside <think>, 2 = answer
  final _buf = StringBuffer();

  String add(String t) {
    if (t.isEmpty) return '';
    if (_state == 2) return t;
    _buf.write(t);
    final s = _buf.toString();
    if (_state == 0) {
      final lead = s.trimLeft();
      if (lead.isEmpty || (lead.length < 7 && '<think>'.startsWith(lead))) return '';
      if (!lead.startsWith('<think>')) {
        _state = 2;
        _buf.clear();
        return s;
      }
      _state = 1;
    }
    final end = s.indexOf('</think>');
    if (end < 0) return '';
    _state = 2;
    _buf.clear();
    return s.substring(end + 8).trimLeft();
  }

  /// End of the stream: whatever is still held back (an unclosed thought is
  /// shown rather than an empty answer).
  String close() {
    final s = _buf.toString();
    _buf.clear();
    return _state == 1 ? s.replaceFirst('<think>', '').trim() : s;
  }
}
