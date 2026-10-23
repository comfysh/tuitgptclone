// AI provider presets: where each API lives, its models and what it can read.
//
// Checked against the providers' docs in October 2026. Model names change
// often, so the settings page can also load the live list from `/models`.

import 'package:flutter/material.dart';

/// How a provider is called.
enum AiKind {
  /// Google's own Gemini API (`streamGenerateContent`, `x-goog-api-key`).
  gemini,

  /// The OpenAI chat-completions format: POST `{base}/chat/completions` with
  /// a Bearer key, streamed as server-sent events.
  openai,
}

class AiPreset {
  const AiPreset({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    required this.defaultModel,
    required this.noteKey,
    required this.icon,
    this.nameKey,
    this.urlAliases = const [],
    this.models = const [],
    this.retiredModels = const [],
    this.keyUrl,
    this.needsKey = true,
    this.free = false,
    this.images = true,
    this.visionHints = const [],
    this.imageTypes = openaiImageTypes,
    this.nativePdf = false,
    this.pdfOptions,
    this.editableUrl = false,
    this.runsLocally = false,
    this.publicModels = false,
    this.urlSuggestions = const {},
  });

  /// Stable id, used in settings keys and the secure store (`ai_key_<id>`).
  final String id;

  /// Display name (a brand name, not translated unless [nameKey] is set).
  final String name;

  /// String key for a translated name (Custom).
  final String? nameKey;

  final AiKind kind;

  /// API root; for [editableUrl] presets only the starting value.
  final String baseUrl;

  /// Other spellings of [baseUrl] (used to recognise 1.0 settings).
  final List<String> urlAliases;

  /// Used until the student picks another one. Empty = load from `/models`.
  final String defaultModel;

  /// Suggested models, shown first in the picker.
  final List<String> models;

  /// Names the API no longer accepts; a saved one falls back to [defaultModel].
  final List<String> retiredModels;

  /// Where to create a key (or download the app for local servers).
  final String? keyUrl;

  /// Without a key nothing works. Otherwise the key is optional.
  final bool needsKey;

  /// Has a free tier or free models.
  final bool free;

  /// String key (lib/core/strings/ai.dart) of a short note: price, speed…
  final String noteKey;

  final IconData icon;

  /// Accepts images in chat (see [supportsImages]).
  final bool images;

  /// When not empty, only models whose id contains one of these (lower case)
  /// can see images; the others get a note instead of the picture.
  final List<String> visionHints;

  /// Image types sent inline; others are described instead.
  final Set<String> imageTypes;

  /// Reads PDF files itself (Gemini inlineData, OpenAI-style `file` parts).
  final bool nativePdf;

  /// Extra request fields when a PDF is attached (OpenRouter's free parser).
  final Map<String, Object>? pdfOptions;

  /// The student types the server address (local servers, Custom).
  final bool editableUrl;

  /// Runs on the student's own computer (no internet needed, no key).
  final bool runsLocally;

  /// `/models` answers without a key.
  final bool publicModels;

  /// Quick fills for the address field: label → URL.
  final Map<String, String> urlSuggestions;

  static const openaiImageTypes = {'image/png', 'image/jpeg', 'image/webp', 'image/gif'};
  static const geminiImageTypes = {'image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif'};

  bool get isGemini => kind == AiKind.gemini;

  /// Name in the UI language; [tr] looks up a string key.
  String displayName(String Function(String key) tr) => nameKey == null ? name : tr(nameKey!);

  /// Whether [model] of this provider can look at pictures.
  bool supportsImages(String model) {
    if (!images) return false;
    if (visionHints.isEmpty) return true;
    final m = model.toLowerCase();
    return visionHints.any(m.contains);
  }

  static const gemini = AiPreset(
    id: 'gemini',
    name: 'Google Gemini',
    kind: AiKind.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModel: 'gemini-flash-latest',
    models: ['gemini-flash-latest', 'gemini-flash-lite-latest', 'gemini-3.8-flash', 'gemini-3.5-flash-lite'],
    keyUrl: 'https://aistudio.google.com/apikey',
    free: true,
    noteKey: 'aiNoteGemini',
    icon: Icons.auto_awesome_rounded,
    imageTypes: geminiImageTypes,
    nativePdf: true,
  );

  static const deepseek = AiPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    kind: AiKind.openai,
    baseUrl: 'https://api.deepseek.com',
    urlAliases: ['https://api.deepseek.com/v1'],
    defaultModel: 'deepseek-flash',
    models: ['deepseek-flash', 'deepseek-v4-pro'],
    // Retired on 24 Jul 2026 (still in many tutorials).
    retiredModels: ['deepseek-chat', 'deepseek-reasoner'],
    keyUrl: 'https://platform.deepseek.com/api_keys',
    noteKey: 'aiNoteDeepseek',
    icon: Icons.waves_rounded,
    // deepseek-flash has vision, deepseek-v4-pro does not.
    visionHints: ['flash'],
  );

  static const openai = AiPreset(
    id: 'openai',
    name: 'OpenAI',
    kind: AiKind.openai,
    baseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-6-luna',
    models: ['gpt-6-luna', 'gpt-6.1-sol', 'gpt-6-astra'],
    keyUrl: 'https://platform.openai.com/api-keys',
    noteKey: 'aiNoteOpenai',
    icon: Icons.blur_on_rounded,
    nativePdf: true,
  );

  static const openrouter = AiPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    kind: AiKind.openai,
    baseUrl: 'https://openrouter.ai/api/v1',
    // Picks a free model for each request (and one with vision for pictures).
    defaultModel: 'openrouter/free',
    models: ['openrouter/free', 'openrouter/auto'],
    keyUrl: 'https://openrouter.ai/keys',
    free: true,
    noteKey: 'aiNoteOpenrouter',
    icon: Icons.alt_route_rounded,
    nativePdf: true,
    // Without this, PDFs for models that can't read them go to a paid OCR.
    pdfOptions: {
      'plugins': [
        {
          'id': 'file-parser',
          'pdf': {'engine': 'cloudflare-ai'},
        },
      ],
    },
    publicModels: true,
  );

  static const groq = AiPreset(
    id: 'groq',
    name: 'Groq',
    kind: AiKind.openai,
    baseUrl: 'https://api.groq.com/openai/v1',
    defaultModel: 'llama-3.3-70b-versatile',
    models: ['llama-3.3-70b-versatile', 'openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'qwen/qwen3.8-27b', 'llama-3.1-8b-instant'],
    keyUrl: 'https://console.groq.com/keys',
    free: true,
    noteKey: 'aiNoteGroq',
    icon: Icons.bolt_rounded,
    visionHints: ['qwen3.8-27b', 'muse-spark', 'llama-4', 'vision'],
  );

  static const mistral = AiPreset(
    id: 'mistral',
    name: 'Mistral AI',
    kind: AiKind.openai,
    baseUrl: 'https://api.mistral.ai/v1',
    defaultModel: 'mistral-small-latest',
    models: ['mistral-small-latest', 'mistral-medium-latest'],
    keyUrl: 'https://console.mistral.ai/api-keys',
    free: true,
    noteKey: 'aiNoteMistral',
    icon: Icons.air_rounded,
    visionHints: ['small', 'medium', 'large', 'ministral', 'pixtral'],
  );

  static const together = AiPreset(
    id: 'together',
    name: 'Together AI',
    kind: AiKind.openai,
    baseUrl: 'https://api.together.ai/v1',
    urlAliases: ['https://api.together.xyz/v1'],
    defaultModel: 'openai/gpt-oss-120b',
    models: ['openai/gpt-oss-120b', 'deepseek-ai/DeepSeek-V4.1-Flash', 'Qwen/Qwen3.8-Flash', 'MiniMaxAI/MiniMax-M3'],
    keyUrl: 'https://api.together.ai/settings/api-keys',
    noteKey: 'aiNoteTogether',
    icon: Icons.hub_rounded,
    visionHints: ['minimax-m3', 'kimi-k3', '-vl', 'vision', 'qwen3.5-9b'],
  );

  static const xai = AiPreset(
    id: 'xai',
    name: 'xAI Grok',
    kind: AiKind.openai,
    baseUrl: 'https://api.x.ai/v1',
    defaultModel: 'grok-4.7',
    models: ['grok-4.7'],
    keyUrl: 'https://console.x.ai',
    noteKey: 'aiNoteXai',
    icon: Icons.rocket_launch_rounded,
    imageTypes: {'image/png', 'image/jpeg'},
  );

  static const local = AiPreset(
    id: 'local',
    name: 'Ollama / LM Studio',
    kind: AiKind.openai,
    baseUrl: 'http://localhost:11434/v1',
    defaultModel: '', // whatever is installed: loaded from /models
    keyUrl: 'https://ollama.com/download',
    needsKey: false,
    free: true,
    noteKey: 'aiNoteLocal',
    icon: Icons.computer_rounded,
    editableUrl: true,
    runsLocally: true,
    urlSuggestions: {'Ollama': 'http://localhost:11434/v1', 'LM Studio': 'http://localhost:1234/v1'},
  );

  static const custom = AiPreset(
    id: 'custom',
    name: 'Custom',
    nameKey: 'aiCustomName',
    kind: AiKind.openai,
    baseUrl: '',
    defaultModel: '',
    needsKey: false,
    noteKey: 'aiNoteCustom',
    icon: Icons.tune_rounded,
    editableUrl: true,
  );

  /// In the order the settings page lists them.
  static const all = [gemini, deepseek, openrouter, groq, mistral, openai, together, xai, local, custom];

  static AiPreset? byId(String? id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static AiPreset of(String? id) => byId(id) ?? gemini;

  static String _norm(String url) => url.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

  /// The preset an OpenAI-compatible address belongs to (1.0 settings):
  /// a known provider, a local server, or Custom.
  static AiPreset forUrl(String url) {
    final u = _norm(url);
    for (final p in all) {
      if (p.editableUrl) continue;
      if (_norm(p.baseUrl) == u || p.urlAliases.any((a) => _norm(a) == u)) return p;
    }
    return isLocalUrl(u) ? local : custom;
  }

  /// localhost or a private network address (a PC at home).
  static bool isLocalUrl(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.local') || host == '0.0.0.0' || host == '::1') return true;
    final ip = host.split('.').map(int.tryParse).toList();
    if (ip.length != 4 || ip.any((e) => e == null)) return false;
    final a = ip[0]!, b = ip[1]!;
    return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }
}
