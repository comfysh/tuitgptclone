// AI provider, API key and model settings.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ai/ai_service.dart';
import '../app_state.dart';
import '../core/settings.dart';
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
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _url = TextEditingController();

  /// Provider whose fields are shown.
  late String _id;

  /// Models loaded from the provider's API for [_id].
  List<String> _loaded = [];
  String? _status;
  bool _busy = false;

  /// The saved key of [_id] has been read into [_key] (until then it must
  /// not be overwritten with the empty field).
  bool _keyReady = false;
  int _gen = 0;

  Settings get _settings => context.read<AppState>().settings;
  AiPreset get _preset => AiPreset.of(_id);

  @override
  void initState() {
    super.initState();
    _id = _settings.aiProviderId;
    _loadFields();
  }

  @override
  void dispose() {
    for (final c in [_key, _model, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the fields with what is saved for [_id].
  void _loadFields() {
    final st = _settings;
    final gen = ++_gen;
    _model.text = st.aiModelFor(_id);
    _url.text = st.aiBaseUrlFor(_id);
    _key.text = '';
    _keyReady = false;
    _loaded = [];
    _status = null;
    AiKeys.read(st, _id).then((v) {
      if (!mounted || gen != _gen) return;
      setState(() {
        if (_key.text.isEmpty) _key.text = v ?? '';
        _keyReady = true;
      });
    });
  }

  Future<void> _persist() async {
    final st = _settings, id = _id, p = _preset;
    st.setAiModelFor(id, _model.text);
    if (p.editableUrl) st.setAiBaseUrlFor(id, _url.text);
    if (_keyReady || _key.text.trim().isNotEmpty) await AiKeys.write(st, id, _key.text);
  }

  Future<void> _select(AiPreset p) async {
    if (p.id == _id || _busy) return;
    await _persist(); // keep what was typed for the previous provider
    if (!mounted) return;
    final app = context.read<AppState>();
    app.settings.aiProviderId = p.id;
    setState(() {
      _id = p.id;
      _loadFields();
    });
    app.touch();
  }

  Future<void> _run(Future<void> Function(AiService ai) f) async {
    await _persist();
    if (!mounted) return;
    final s = S.read(context);
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await f(AiService(_settings));
    } catch (e) {
      _status = '✗ ${e is AiException && e.message == 'NO_KEY' ? s['aiErrNoKey'] : e}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadModels() async {
    final id = _id;
    await _run((ai) async {
      final m = await ai.listModels();
      if (!mounted || id != _id) return;
      _loaded = m;
      if (m.isEmpty) _status = '✗ ${S.read(context)['aiNoModelsFound']}';
    });
    if (mounted && id == _id && _loaded.isNotEmpty) await _pickModel();
  }

  Future<void> _chooseModel() async {
    if (_loaded.isEmpty) {
      await _loadModels();
    } else {
      await _pickModel();
    }
  }

  Future<void> _pickModel() async {
    final p = _preset;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ModelPicker(
        suggested: p.models,
        models: _loaded.where((m) => !p.models.contains(m)).toList(),
        current: _model.text.trim(),
      ),
    );
    if (picked != null && mounted) setState(() => _model.text = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final p = _preset;
    final name = p.displayName((k) => s[k]);
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: Text(s['aiSettings'])),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            // ---- provider
            SectionHeader(s['provider'], padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
            _ProviderGrid(selected: p.id, onSelect: _busy ? null : _select),

            // ---- key and address
            SectionHeader(name),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TintIcon(p.editableUrl ? Icons.dns_rounded : Icons.key_rounded, color: Brand.warning, size: 36),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_help(s, p, name), style: TextStyle(color: cs.onSurfaceVariant))),
                ]),
                if (p.keyUrl != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(p.keyUrl!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(p.needsKey ? (p.free ? s['getKey'] : s['aiGetKey']) : s['aiGetApp']),
                  ),
                ],
                if (p.editableUrl) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: s['baseUrl'],
                      hintText: p.baseUrl.isEmpty ? 'https://…/v1' : p.baseUrl,
                      prefixIcon: const Icon(Icons.link_rounded),
                    ),
                  ),
                  if (p.urlSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final e in p.urlSuggestions.entries)
                        ActionChip(
                          avatar: const Icon(Icons.bolt_rounded, size: 18),
                          label: Text(e.key),
                          onPressed: () => setState(() => _url.text = e.value),
                        ),
                    ]),
                  ],
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: p.needsKey ? s.f('aiKeyFor', {'name': name}) : s['aiKeyOptional'],
                    prefixIcon: const Icon(Icons.vpn_key_rounded),
                  ),
                ),
              ]),
            ),

            // ---- model
            SectionHeader(s['model']),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s['model'],
                    hintText: p.defaultModel.isEmpty ? null : p.defaultModel,
                    prefixIcon: const Icon(Icons.memory_rounded),
                    suffixIcon: IconButton(
                      tooltip: s['aiChooseModel'],
                      icon: const Icon(Icons.list_rounded),
                      onPressed: _busy ? null : _chooseModel,
                    ),
                  ),
                ),
                if (p.models.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _model,
                    builder: (context, v, _) => Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final m in p.models)
                        ChoiceChip(
                          label: Text(m),
                          selected: v.text.trim() == m,
                          onSelected: (_) => _model.text = m,
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _loadModels,
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
                          final app = context.read<AppState>();
                          await _persist();
                          app.touch();
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
                            // A local server without a model picked uses its first one.
                            if (_model.text.trim().isEmpty) _model.text = ai.settings.aiModelFor(ai.preset.id);
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
                final c = ok ? Brand.success : cs.error;
                return AppCard(
                  color: c.withValues(alpha: 0.10),
                  padding: const EdgeInsets.all(12),
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

  static String _help(S s, AiPreset p, String name) {
    if (p.isGemini) return s['aiSetupBody'];
    if (p.runsLocally) return s['aiLocalHelp'];
    if (p.editableUrl) return s['aiCustomHelp'];
    final help = s.f('aiKeyHelp', {'name': name});
    return p.free ? help : '$help ${s['aiPaidHint']}';
  }
}

/// Tint for a provider's icon.
Color _tint(AiPreset p) {
  final palette = [Brand.primary, Brand.info, Brand.violet, Brand.warning, Brand.success];
  final i = AiPreset.all.indexOf(p);
  return palette[(i < 0 ? 0 : i) % palette.length];
}

/// All providers as cards, two or three per row.
class _ProviderGrid extends StatelessWidget {
  const _ProviderGrid({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<AiPreset>? onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 560 ? 3 : 2;
      const all = AiPreset.all;
      return Column(children: [
        for (var r = 0; r < all.length; r += cols)
          Padding(
            padding: EdgeInsets.only(top: r == 0 ? 0 : 10),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = r; i < r + cols; i++) ...[
                  if (i > r) const SizedBox(width: 10),
                  Expanded(
                    child: i < all.length
                        ? _ProviderTile(
                            preset: all[i],
                            selected: all[i].id == selected,
                            onTap: onSelect == null ? null : () => onSelect!(all[i]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ]),
            ),
          ),
      ]);
    });
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.preset, required this.selected, required this.onTap});
  final AiPreset preset;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final p = preset;
    return Semantics(
      button: true,
      selected: selected,
      child: AppCard(
        onTap: onTap,
        color: selected ? cs.primary.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            TintIcon(p.icon, color: _tint(p), size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: p.free
                  ? Align(alignment: Alignment.centerRight, child: Tag(s['pfAiFree'], color: Brand.success))
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 6),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? cs.primary : cs.outlineVariant,
              size: 20,
            ),
          ]),
          const SizedBox(height: 10),
          Text(p.displayName((k) => s[k]),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 2),
          Text(s[p.noteKey],
              maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Searchable list: the preset's suggestions first, then what the API lists.
class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.suggested, required this.models, required this.current});
  final List<String> suggested;
  final List<String> models;
  final String current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final q = _q.text.trim().toLowerCase();
    bool hit(String m) => q.isEmpty || m.toLowerCase().contains(q);
    final sug = widget.suggested.where(hit).toList();
    final rest = widget.models.where(hit).toList();
    // (text, isHeader)
    final items = <(String, bool)>[
      if (sug.isNotEmpty) (s['aiSuggested'], true),
      for (final m in sug) (m, false),
      if (rest.isNotEmpty) (s['aiAllModels'], true),
      for (final m in rest) (m, false),
    ];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text(s['aiChooseModel'], style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: s['aiSearchModels'], prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s['aiNoModelsFound'], textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final (text, header) = items[i];
                      if (header) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Text(text,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                        );
                      }
                      final free = text.endsWith(':free') || text == 'openrouter/free';
                      return ListTile(
                        dense: true,
                        title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: text == widget.current
                            ? Icon(Icons.check_rounded, color: cs.primary)
                            : (free ? Tag(s['pfAiFree'], color: Brand.success) : null),
                        onTap: () => Navigator.pop(context, text),
                      );
                    },
                  ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(onPressed: () => Navigator.pop(context), child: Text(s['cancel'])),
            ),
          ),
        ]),
      ),
    );
  }
}
