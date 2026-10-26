import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/providers.dart';
import '../lms/models.dart';

enum AiProvider { gemini, openai }

class Settings {
  Settings(this._p);
  final SharedPreferences _p;

  static Future<Settings> load({bool reload = false}) async {
    final p = await SharedPreferences.getInstance();
    if (reload) await p.reload();
    return Settings(p);
  }

  // ---- general
  String get language {
    final v = _p.getString('language');
    if (v != null) return v;
    final sys = ui.PlatformDispatcher.instance.locale.languageCode;
    return sys == 'uz' || sys == 'ru' ? sys : 'en';
  }

  set language(String v) => _p.setString('language', v);

  ThemeMode get themeMode => ThemeMode.values[_p.getInt('themeMode') ?? 0];
  set themeMode(ThemeMode v) => _p.setInt('themeMode', v.index);

  /// Theme name (lib/ui/themes.dart AppStyle), e.g. "paper", "ocean".
  String get themeStyle => _p.getString('themeStyle') ?? 'paper';
  set themeStyle(String v) => _p.setString('themeStyle', v);

  /// True-black backgrounds in dark mode (OLED screens).
  bool get pureBlack => _p.getBool('pureBlack') ?? false;
  set pureBlack(bool v) => _p.setBool('pureBlack', v);

  /// Today's sections in the order shown; hidden ones are kept with a "-"
  /// in front. Null: the default layout (lib/ui/today_layout.dart).
  List<String>? get todayLayout => _p.getStringList('todayLayout');
  set todayLayout(List<String>? v) => v == null ? _p.remove('todayLayout') : _p.setStringList('todayLayout', v);

  /// The place the app opens on: "today", "plan", "inbox" or "study".
  String get startHub => _p.getString('startHub') ?? 'today';
  set startHub(String v) => _p.setString('startHub', v);

  int? get semesterId => _p.getInt('semesterId');
  set semesterId(int? v) => v == null ? _p.remove('semesterId') : _p.setInt('semesterId', v);

  // ---- timetable
  /// When set, the user told us which side the week starting on this Monday is.
  DateTime? get weekAnchorMonday {
    final s = _p.getString('weekAnchorMonday');
    return s == null ? null : DateTime.tryParse(s);
  }

  WeekSide? get weekAnchorSide {
    final v = _p.getInt('weekAnchorSide');
    return v == null ? null : WeekSide.fromValue(v);
  }

  void setWeekAnchor(DateTime? monday, WeekSide? side) {
    if (monday == null || side == null) {
      _p.remove('weekAnchorMonday');
      _p.remove('weekAnchorSide');
    } else {
      _p.setString('weekAnchorMonday', monday.toIso8601String());
      _p.setInt('weekAnchorSide', side.value);
    }
  }

  int get lessonMinutes => _p.getInt('lessonMinutes') ?? 80;
  set lessonMinutes(int v) => _p.setInt('lessonMinutes', v);

  // ---- attendance
  int get absenceLimitHours => _p.getInt('absenceLimitHours') ?? 74;
  set absenceLimitHours(int v) => _p.setInt('absenceLimitHours', v);

  int get hoursPerAbsence => _p.getInt('hoursPerAbsence') ?? 2;
  set hoursPerAbsence(int v) => _p.setInt('hoursPerAbsence', v);

  // ---- notifications
  bool get notifications => _p.getBool('notifications') ?? true;
  set notifications(bool v) => _p.setBool('notifications', v);

  int get checkMinutes => _p.getInt('checkMinutes') ?? 15;
  set checkMinutes(int v) => _p.setInt('checkMinutes', v);

  bool get remindDeadlines => _p.getBool('remindDeadlines') ?? true;
  set remindDeadlines(bool v) => _p.setBool('remindDeadlines', v);

  bool get remindClasses => _p.getBool('remindClasses') ?? false;
  set remindClasses(bool v) => _p.setBool('remindClasses', v);

  /// Quiet hours: notifications still arrive, but without sound or vibration.
  bool get quietHours => _p.getBool('quietHours') ?? true;
  set quietHours(bool v) => _p.setBool('quietHours', v);

  /// Minutes after midnight.
  int get quietFrom => _p.getInt('quietFrom') ?? 22 * 60 + 30;
  set quietFrom(int v) => _p.setInt('quietFrom', v);

  int get quietTo => _p.getInt('quietTo') ?? 7 * 60;
  set quietTo(int v) => _p.setInt('quietTo', v);

  /// One morning summary of the day (classes and what is due).
  bool get morningBrief => _p.getBool('morningBrief') ?? true;
  set morningBrief(bool v) => _p.setBool('morningBrief', v);

  int get briefAt => _p.getInt('briefAt') ?? 7 * 60 + 30;
  set briefAt(int v) => _p.setInt('briefAt', v);

  /// Change kinds (ChangeKind.name) the user turned off. New teacher files are
  /// frequent, so they start off.
  Set<String> get mutedKinds => (_p.getStringList('mutedKinds') ?? const ['newFile']).toSet();
  set mutedKinds(Set<String> v) => _p.setStringList('mutedKinds', v.toList()..sort());

  // ---- staying signed in
  /// Sign in again with the saved password when LMS ends the session, also in
  /// the background (Android) or while the app sits in the tray (Windows).
  bool get backgroundLogin => _p.getBool('backgroundLogin') ?? true;
  set backgroundLogin(bool v) => _p.setBool('backgroundLogin', v);

  /// Windows: closing the window keeps TuitMate running in the system tray.
  bool get closeToTray => _p.getBool('closeToTray') ?? true;
  set closeToTray(bool v) => _p.setBool('closeToTray', v);

  // ---- automation (admin only, see lib/services/automation.dart)
  bool get adminUnlocked => _p.getBool('adminUnlocked') ?? false;
  set adminUnlocked(bool v) => _p.setBool('adminUnlocked', v);

  String? get webhookUrl => _p.getString('webhookUrl');
  set webhookUrl(String? v) => v == null || v.trim().isEmpty ? _p.remove('webhookUrl') : _p.setString('webhookUrl', v.trim());

  /// Event types (e.g. "task.new") sent to the webhook; null = all of them.
  Set<String>? get webhookEvents => _p.getStringList('webhookEvents')?.toSet();
  set webhookEvents(Set<String>? v) =>
      v == null ? _p.remove('webhookEvents') : _p.setStringList('webhookEvents', v.toList()..sort());

  /// Encrypt webhook payloads with AES-256-GCM (off = plain JSON, still signed).
  bool get webhookEncrypt => _p.getBool('webhookEncrypt') ?? true;
  set webhookEncrypt(bool v) => _p.setBool('webhookEncrypt', v);

  /// Also send the whole snapshot after every sync (large; off by default).
  bool get webhookSnapshot => _p.getBool('webhookSnapshot') ?? false;
  set webhookSnapshot(bool v) => _p.setBool('webhookSnapshot', v);

  // ---- login
  bool get rememberPassword => _p.getBool('rememberPassword') ?? true;
  set rememberPassword(bool v) => _p.setBool('rememberPassword', v);

  bool get autoLogin => _p.getBool('autoLogin') ?? true;
  set autoLogin(bool v) => _p.setBool('autoLogin', v);

  // ---- AI
  // Provider presets: lib/ai/providers.dart. API keys are in the secure store
  // (AiKeys in lib/ai/ai_service.dart), one per provider.

  /// Id of the selected provider preset.
  String get aiProviderId {
    _migrateAi();
    return AiPreset.of(_p.getString('aiProviderId')).id;
  }

  set aiProviderId(String v) => _p.setString('aiProviderId', AiPreset.of(v).id);

  AiPreset get aiPreset => AiPreset.of(aiProviderId);

  /// Model picked for provider [id] (its default until one is picked;
  /// empty for local servers and Custom until the student chooses).
  String aiModelFor(String id) {
    _migrateAi();
    final p = AiPreset.of(id);
    final v = _p.getString('aiModel.$id')?.trim() ?? '';
    final m = v.isEmpty || p.retiredModels.contains(v) ? p.defaultModel : v;
    return p.isGemini ? m.replaceFirst('models/', '') : m;
  }

  void setAiModelFor(String id, String? model) {
    final v = model?.trim() ?? '';
    v.isEmpty ? _p.remove('aiModel.$id') : _p.setString('aiModel.$id', v);
  }

  String get aiModel => aiModelFor(aiProviderId);

  /// API address of provider [id]; only local servers and Custom can change it.
  String aiBaseUrlFor(String id) {
    final p = AiPreset.of(id);
    if (!p.editableUrl) return p.baseUrl;
    _migrateAi();
    final v = _p.getString('aiBaseUrl.$id')?.trim() ?? '';
    return v.isEmpty ? p.baseUrl : v;
  }

  void setAiBaseUrlFor(String id, String? url) {
    final v = (url ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    v.isEmpty ? _p.remove('aiBaseUrl.$id') : _p.setString('aiBaseUrl.$id', v);
  }

  String get aiBaseUrl => aiBaseUrlFor(aiProviderId);

  /// For the UI: "DeepSeek · deepseek-flash".
  String get aiSummary {
    final p = aiPreset, m = aiModel;
    return m.isEmpty ? p.name : '${p.name} · $m';
  }

  /// The provider that inherits the 1.0 "OpenAI-compatible" key.
  String get aiLegacyKeyProvider {
    _migrateAi();
    return _p.getString('aiLegacyKeyTo') ?? AiPreset.groq.id;
  }

  /// 1.0 had Gemini or one OpenAI-compatible address (Groq by default). Their
  /// model and address move to the matching preset once, so nobody loses
  /// their setup. Keys follow in AiKeys.read.
  void _migrateAi() {
    if (_p.containsKey('aiProviderId')) return;
    final oldUrl = _p.getString('openaiBaseUrl')?.trim() ?? '';
    final compat = AiPreset.forUrl(oldUrl.isEmpty ? AiPreset.groq.baseUrl : oldUrl);
    if (compat.editableUrl && oldUrl.isNotEmpty) setAiBaseUrlFor(compat.id, oldUrl);
    final oldModel = _p.getString('openaiModel')?.trim() ?? '';
    if (oldModel.isNotEmpty) _p.setString('aiModel.${compat.id}', oldModel);
    final oldGemini = (_p.getString('geminiModel') ?? '').trim().replaceFirst('models/', '');
    if (oldGemini.isNotEmpty) _p.setString('aiModel.${AiPreset.gemini.id}', oldGemini);
    _p.setString('aiLegacyKeyTo', compat.id);
    final wasCompat = _p.getInt('aiProvider') == AiProvider.openai.index;
    _p.setString('aiProviderId', wasCompat ? compat.id : AiPreset.gemini.id);
  }

  // 1.0 names, still read by older screens.
  AiProvider get aiProvider => aiPreset.isGemini ? AiProvider.gemini : AiProvider.openai;
  String get geminiModel => aiModelFor(AiPreset.gemini.id);
  String get openaiBaseUrl => aiBaseUrl;
  String get openaiModel => aiModel;

  bool get aiUseLmsContext => _p.getBool('aiUseLmsContext') ?? true;
  set aiUseLmsContext(bool v) => _p.setBool('aiUseLmsContext', v);
}
