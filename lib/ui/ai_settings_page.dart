// AI provider, API key and model settings.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ai/ai_service.dart';
import '../app_state.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import 'widgets.dart';

// ---------------------------------------------------------------- AI settings

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
    final cs = Theme.of(context).colorScheme;
    final status = _status;

    void selectProvider(AiProvider p) {
      st.aiProvider = p;
      setState(() => _models = []);
      app.touch();
    }

    return Scaffold(
      appBar: AppBar(title: Text(s['aiSettings'])),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            // ---- provider
            SectionHeader(s['provider'], padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _ProviderTile(
                    selected: gemini,
                    icon: Icons.auto_awesome_rounded,
                    color: Brand.primary,
                    title: 'Gemini',
                    subtitle: 'Google · ${s['pfAiFree']}',
                    onTap: () => selectProvider(AiProvider.gemini),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProviderTile(
                    selected: !gemini,
                    icon: Icons.hub_rounded,
                    color: Brand.violet,
                    title: s['pfAiCompatible'],
                    subtitle: 'Groq · OpenRouter · OpenAI',
                    onTap: () => selectProvider(AiProvider.openai),
                  ),
                ),
              ]),
            ),

            // ---- key
            SectionHeader(s['apiKey']),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (gemini) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TintIcon(Icons.key_rounded, color: Brand.warning, size: 36),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s['aiSetupBody'], style: TextStyle(color: cs.onSurfaceVariant))),
                  ]),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(s['getKey']),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _geminiKey,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Gemini ${s['apiKey']}',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                    ),
                  ),
                ] else ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in _presets.entries)
                      ActionChip(
                        avatar: const Icon(Icons.bolt_rounded, size: 18),
                        label: Text(e.key),
                        onPressed: () => setState(() {
                          _openaiBase.text = e.value.$1;
                          _openaiModel.text = e.value.$2;
                        }),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _openaiBase,
                    decoration: InputDecoration(labelText: s['baseUrl'], prefixIcon: const Icon(Icons.link_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openaiKey,
                    obscureText: true,
                    decoration: InputDecoration(labelText: s['apiKey'], prefixIcon: const Icon(Icons.vpn_key_rounded)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, children: [
                    for (final e in _presets.entries)
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse(e.value.$3), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text('${e.key.split(' ').first}: ${s['getKey']}'),
                      ),
                  ]),
                ],
              ]),
            ),

            // ---- model
            SectionHeader(s['model']),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _models.isEmpty
                    ? TextField(
                        controller: modelCtl,
                        decoration: InputDecoration(labelText: s['model'], prefixIcon: const Icon(Icons.memory_rounded)),
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: _models.contains(modelCtl.text) ? modelCtl.text : null,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: s['model'], prefixIcon: const Icon(Icons.memory_rounded)),
                        items: [
                          for (final m in _models) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => modelCtl.text = v ?? modelCtl.text,
                      ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run((ai) async {
                              final m = await ai.listModels();
                              setState(() => _models = m.toSet().toList());
                            }),
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: Text(s['loadModels']),
                  ),
                ),
              ]),
            ),

            // ---- actions
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _persist();
                          if (context.mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(s['save']),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run((ai) async {
                            final r = await ai.test();
                            _status = '✓ ${s['keyWorks']} ($r)';
                          }),
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: Text(s['testKey']),
                ),
              ),
            ]),
            if (status != null) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final ok = status.startsWith('✓');
                final c = ok ? Brand.success : Brand.danger;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(radiusS)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded, color: c, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: SelectableText(status, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                );
              }),
            ],
            const SizedBox(height: 24),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s['chatGptNote'],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusL),
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: AppCard(
          onTap: onTap,
          radius: radiusL - 2,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TintIcon(icon, color: color, size: 36),
              const Spacer(),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? color : cs.outlineVariant,
                size: 22,
              ),
            ]),
            const SizedBox(height: 12),
            Text(title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(subtitle,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
