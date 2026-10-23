import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  int get checkMinutes => _p.getInt('checkMinutes') ?? 30;
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
  AiProvider get aiProvider => AiProvider.values[_p.getInt('aiProvider') ?? 0];
  set aiProvider(AiProvider v) => _p.setInt('aiProvider', v.index);

  String get geminiModel => _p.getString('geminiModel') ?? 'gemini-flash-latest';
  set geminiModel(String v) => _p.setString('geminiModel', v);

  String get openaiBaseUrl => _p.getString('openaiBaseUrl') ?? 'https://api.groq.com/openai/v1';
  set openaiBaseUrl(String v) => _p.setString('openaiBaseUrl', v);

  String get openaiModel => _p.getString('openaiModel') ?? 'llama-3.3-70b-versatile';
  set openaiModel(String v) => _p.setString('openaiModel', v);

  bool get aiUseLmsContext => _p.getBool('aiUseLmsContext') ?? true;
  set aiUseLmsContext(bool v) => _p.setBool('aiUseLmsContext', v);
}
