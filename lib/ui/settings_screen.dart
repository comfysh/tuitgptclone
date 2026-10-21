import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_service.dart';
import '../app_state.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import '../services/notifier.dart';
import 'widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final st = app.settings;
    final i = app.snapshot.info;
    final cs = Theme.of(context).colorScheme;

    ImageProvider? photo;
    final p = i?.photo;
    if (p != null && p.startsWith('data:image')) {
      try {
        photo = MemoryImage(base64Decode(p.substring(p.indexOf(',') + 1)));
      } catch (_) {}
    } else if (p != null && p.startsWith('http')) {
      photo = NetworkImage(p);
    }

    return PageScaffold(
      title: s['profile'],
      lmsPath: '/student/info',
      children: [
        if (i != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundImage: photo,
                    child: photo == null ? const Icon(Icons.person, size: 34) : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.fullName ?? s['student'],
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (i.group != null) Text('${s['group']}: ${i.group}', style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                InfoRow(s['studentId'], i.studentId),
                InfoRow(s['specialization'], i.specialization),
                InfoRow(s['year'], i.year),
                InfoRow(s['studyForm'], i.studyForm),
                InfoRow(s['studyLanguage'], i.studyLanguage),
                InfoRow(s['degree'], i.degree),
                InfoRow(s['tutor'], i.tutor),
                InfoRow(s['stipend'], i.stipend),
                InfoRow(s['birthDate'], i.birthDate),
              ]),
            ),
          ),
        SectionTitle(s['settings']),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(s['language']),
              trailing: DropdownButton<String>(
                value: st.language,
                underline: const SizedBox(),
                items: [for (final e in S.languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => app.setLanguage(v!),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: Text(s['theme']),
              trailing: DropdownButton<ThemeMode>(
                value: st.themeMode,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: ThemeMode.system, child: Text(s['themeSystem'])),
                  DropdownMenuItem(value: ThemeMode.light, child: Text(s['themeLight'])),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text(s['themeDark'])),
                ],
                onChanged: (v) => app.setThemeMode(v!),
              ),
            ),
            if (app.snapshot.semesters.length > 1)
              ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(s['semester']),
                subtitle: DropdownButton<int>(
                  isExpanded: true,
                  value: app.snapshot.semesterId,
                  underline: const SizedBox(),
                  items: [
                    for (final sem in app.snapshot.semesters)
                      DropdownMenuItem(value: sem.id, child: Text(sem.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    // Picking the LMS's current semester means "follow the LMS", not "pin this one".
                    final current = app.snapshot.semesters.where((x) => x.selected).map((x) => x.id).firstOrNull;
                    app.changeSemester(v == current ? null : v);
                  },
                ),
              ),
          ]),
        ),
        SectionTitle(s['notifications']),
        Card(
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(s['notifications']),
              subtitle: Text('${s['notificationsSub']}${Platform.isAndroid ? '' : '\n${s['desktopNote']}'}'),
              value: st.notifications,
              onChanged: (v) async {
                st.notifications = v;
                app.touch();
                if (v) await Notifier.requestPermission();
                await app.configureBackground();
                await Notifier.scheduleClassReminders(app.snapshot, st); // cancels them when off
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(s['checkEvery']),
              trailing: DropdownButton<int>(
                value: st.checkMinutes,
                underline: const SizedBox(),
                items: [
                  for (final m in const [15, 30, 60, 120]) DropdownMenuItem(value: m, child: Text('$m ${s['minutes']}')),
                ],
                onChanged: (v) async {
                  st.checkMinutes = v!;
                  app.touch();
                  await app.configureBackground();
                },
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.alarm),
              title: Text(s['remindDeadlines']),
              value: st.remindDeadlines,
              onChanged: (v) {
                st.remindDeadlines = v;
                app.touch();
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.class_outlined),
              title: Text(s['remindClasses']),
              value: st.remindClasses,
              onChanged: (v) async {
                st.remindClasses = v;
                app.touch();
                await Notifier.scheduleClassReminders(app.snapshot, st);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notification_add_outlined),
              title: Text(s['testNotification']),
              onTap: () async {
                await Notifier.requestPermission();
                await Notifier.show('test', 'TuitMate', s['testNotificationBody']);
              },
            ),
          ]),
        ),
        SectionTitle('${s['schedule']} · ${s['attendance']}'),
        Card(
          child: Column(children: [
            _NumberTile(
              icon: Icons.av_timer,
              title: s['lessonLength'],
              value: st.lessonMinutes,
              suffix: s['minutes'],
              options: const [45, 50, 80, 90],
              onChanged: (v) {
                st.lessonMinutes = v;
                app.touch();
              },
            ),
            _NumberTile(
              icon: Icons.event_busy,
              title: s['absenceLimit'],
              value: st.absenceLimitHours,
              options: const [36, 48, 60, 74, 80, 100],
              onChanged: (v) {
                st.absenceLimitHours = v;
                app.touch();
              },
            ),
            _NumberTile(
              icon: Icons.looks_two_outlined,
              title: s['hoursPerNb'],
              value: st.hoursPerAbsence,
              options: const [1, 2, 3, 4],
              onChanged: (v) {
                st.hoursPerAbsence = v;
                app.touch();
              },
            ),
          ]),
        ),
        SectionTitle(s['assistant']),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: Text(s['aiSettings']),
            subtitle: Text(st.aiProvider == AiProvider.gemini ? 'Google Gemini · ${st.geminiModel}' : '${st.openaiBaseUrl} · ${st.openaiModel}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsPage())),
          ),
        ),
        SectionTitle(s['signIn']),
        Card(
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.password),
              title: Text(s['rememberPassword']),
              value: st.rememberPassword,
              onChanged: (v) {
                st.rememberPassword = v;
                if (!v) Secrets.deleteLms();
                app.touch();
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.login),
              title: Text(s['autoLogin']),
              value: st.autoLogin,
              onChanged: (v) {
                st.autoLogin = v;
                app.touch();
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: cs.error),
              title: Text(s['logout'], style: TextStyle(color: cs.error)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: Text(s['logoutConfirm']),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s['logout'])),
                    ],
                  ),
                );
                if (ok == true) await app.logout();
              },
            ),
          ]),
        ),
        SectionTitle(s['about']),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${s['aboutBody']}\n\n${s['unofficial']}', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.suffix,
  });
  final IconData icon;
  final String title;
  final int value;
  final List<int> options;
  final String? suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final opts = {...options, value}.toList()..sort();
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox(),
        items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(suffix == null ? '$o' : '$o $suffix'))],
        onChanged: (v) => onChanged(v!),
      ),
    );
  }
}

/// AI provider, key and model.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _geminiKey = TextEditingController();
  final _openaiKey = TextEditingController();
  final _geminiModel = TextEditingController();
  final _openaiModel = TextEditingController();
  final _openaiBase = TextEditingController();
  List<String> _models = [];
  String? _status;
  bool _busy = false;

  static const _presets = {
    'Groq (free tier)': ('https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile', 'https://console.groq.com/keys'),
    'OpenRouter': ('https://openrouter.ai/api/v1', 'openrouter/auto', 'https://openrouter.ai/keys'),
    'OpenAI': ('https://api.openai.com/v1', 'gpt-4o-mini', 'https://platform.openai.com/api-keys'),
  };

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>().settings;
    _geminiModel.text = st.geminiModel;
    _openaiModel.text = st.openaiModel;
    _openaiBase.text = st.openaiBaseUrl;
    Secrets.read(Secrets.geminiKey).then((v) => _geminiKey.text = v ?? '');
    Secrets.read(Secrets.openaiKey).then((v) => _openaiKey.text = v ?? '');
  }

  @override
  void dispose() {
    for (final c in [_geminiKey, _openaiKey, _geminiModel, _openaiModel, _openaiBase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _persist() async {
    final st = context.read<AppState>().settings;
    await Secrets.write(Secrets.geminiKey, _geminiKey.text.trim());
    await Secrets.write(Secrets.openaiKey, _openaiKey.text.trim());
    if (_geminiModel.text.trim().isNotEmpty) st.geminiModel = _geminiModel.text.trim();
    if (_openaiModel.text.trim().isNotEmpty) st.openaiModel = _openaiModel.text.trim();
    if (_openaiBase.text.trim().isNotEmpty) st.openaiBaseUrl = _openaiBase.text.trim();
  }

  Future<void> _run(Future<void> Function(AiService ai) f) async {
    await _persist();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await f(AiService(context.read<AppState>().settings));
    } catch (e) {
      _status = '✗ $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = context.watch<AppState>();
    final st = app.settings;
    final gemini = st.aiProvider == AiProvider.gemini;
    final modelCtl = gemini ? _geminiModel : _openaiModel;

    return Scaffold(
      appBar: AppBar(title: Text(s['aiSettings'])),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<AiProvider>(
          segments: const [
            ButtonSegment(value: AiProvider.gemini, label: Text('Gemini (free)'), icon: Icon(Icons.auto_awesome)),
            ButtonSegment(value: AiProvider.openai, label: Text('OpenAI-compatible'), icon: Icon(Icons.hub_outlined)),
          ],
          selected: {st.aiProvider},
          onSelectionChanged: (v) {
            st.aiProvider = v.first;
            setState(() => _models = []);
            app.touch();
          },
        ),
        const SizedBox(height: 16),
        if (gemini) ...[
          Text(s['aiSetupBody']),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.key),
              label: Text(s['getKey']),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _geminiKey,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Gemini ${s['apiKey']}', border: const OutlineInputBorder()),
          ),
        ] else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _presets.entries)
              ActionChip(
                label: Text(e.key),
                onPressed: () => setState(() {
                  _openaiBase.text = e.value.$1;
                  _openaiModel.text = e.value.$2;
                }),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _openaiBase,
            decoration: InputDecoration(labelText: s['baseUrl'], border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _openaiKey,
            obscureText: true,
            decoration: InputDecoration(labelText: s['apiKey'], border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: [
            for (final e in _presets.entries)
              TextButton(
                onPressed: () => launchUrl(Uri.parse(e.value.$3), mode: LaunchMode.externalApplication),
                child: Text('${e.key.split(' ').first}: ${s['getKey']}'),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _models.isEmpty
                ? TextField(
                    controller: modelCtl,
                    decoration: InputDecoration(labelText: s['model'], border: const OutlineInputBorder()),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: _models.contains(modelCtl.text) ? modelCtl.text : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: s['model'], border: const OutlineInputBorder()),
                    items: [for (final m in _models) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => modelCtl.text = v ?? modelCtl.text,
                  ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run((ai) async {
                      final m = await ai.listModels();
                      setState(() => _models = m.toSet().toList());
                    }),
            child: Text(s['loadModels']),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    await _persist();
                    if (context.mounted) Navigator.pop(context);
                  },
            child: Text(s['save']),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run((ai) async {
                      final r = await ai.test();
                      _status = '✓ ${s['keyWorks']} ($r)';
                    }),
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s['testKey']),
          ),
        ]),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText(_status!)),
        const SizedBox(height: 24),
        Text(s['chatGptNote'], style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
