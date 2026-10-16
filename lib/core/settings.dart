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
