// Automation (owner only): webhook to n8n or any URL, encrypted with the
// owner's AES-256 key, and a guide for AI assistants. See docs/AUTOMATION.md.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import '../services/automation.dart';
import 'widgets.dart';

/// Asks for the owner's key; unlocks admin mode when it matches the fingerprint
/// built into the app. Returns true when unlocked.
Future<bool> showAdminUnlock(BuildContext context) async {
  final s = S.read(context);
  final app = context.read<AppState>();
  final text = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(s['auUnlockTitle']),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['auUnlockBody']),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            autofocus: true,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 13, fontFeatures: tabular),
            decoration: InputDecoration(
              hintText: s['auKeyHint'],
              errorText: error,
              suffixIcon: IconButton(
                tooltip: s['auPaste'],
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (d?.text != null) text.text = d!.text!.trim();
                },
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
          FilledButton(
            onPressed: () async {
              if (await AutomationKey.isOwnerKey(text.text)) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                setState(() => error = s['auWrongKey']);
              }
            },
            child: Text(s['auUnlock']),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  final key = AutomationKey.parse(text.text)!;
  await Secrets.write(Secrets.adminKey, base64.encode(key));
  app.settings.adminUnlocked = true;
  app.touch();
  return true;
}

class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AutomationPage()));

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  late final TextEditingController _url;
  String? _fingerprint;
  int _pending = 0;
  String? _lastSuccess;
  bool _busy = false;
  String? _result;
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppState>().settings.webhookUrl ?? '');
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final key = await AutomationKey.load();
    final f = key == null ? null : await AutomationKey.fingerprint(key);
    final pending = await Automation.pending(app.storage);
    final state = await app.storage.readJson(app.storage.automationFile);
    if (!mounted) return;
    setState(() {
      _fingerprint = f;
      _pending = pending;
      _lastSuccess = state['lastSuccess'] as String?;
    });
  }

  Future<void> _saveUrl() async {
    final app = context.read<AppState>();
    final s = S.read(context);
    final v = _url.text.trim();
    final uri = Uri.tryParse(v);
    if (v.isNotEmpty && (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty)) {
      setState(() {
        _result = s['auBadUrl'];
        _resultOk = false;
      });
      return;
    }
    app.settings.webhookUrl = v;
    app.touch();
    await app.configureBackground(); // the background check also runs for automation
    setState(() {
      _result = v.isEmpty ? null : s['auSaved'];
      _resultOk = true;
    });
  }

  Future<void> _run(Future<String?> Function() job) async {
    final s = S.read(context);
    setState(() {
      _busy = true;
      _result = null;
    });
    final err = await job();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _resultOk = err == null;
      _result = err == null ? s['auDelivered'] : s.f('auFailed', {'e': err});
    });
    await _load();
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.settings;
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final enabledTypes = st.webhookEvents;
    final f = _fingerprint;

    return Scaffold(
      appBar: AppBar(title: Text(s['auTitle'])),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['auIntro'], style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Tag(s['auAdmin'], icon: Icons.verified_user_outlined, color: cs.primary),
                  if (f != null) Tag('AES-256 · ${f.substring(0, 8)}…${f.substring(f.length - 6)}', color: cs.onSurfaceVariant),
                  if (_pending > 0) Tag(s.f('auPending', {'n': _pending}), color: Brand.warning),
                  if (_lastSuccess != null)
                    Tag(s.f('auLastOk', {'t': fmtAgo(DateTime.tryParse(_lastSuccess!)?.toLocal(), s)}), color: Brand.success),
                ]),
              ]),
            ),

            SectionHeader(s['auWebhook']),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s['auUrl'],
                    hintText: 'https://n8n.example.com/webhook/tuitmate',
                  ),
                  onSubmitted: (_) => _saveUrl(),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text(s['auUrlHelp'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _saveUrl, child: Text(s['save'])),
                ]),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['auEncrypt']),
                  subtitle: Text(s['auEncryptSub']),
                  value: st.webhookEncrypt,
                  onChanged: (v) {
                    st.webhookEncrypt = v;
                    app.touch();
                  },
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy || (st.webhookUrl ?? '').isEmpty ? null : () => _run(() => Automation.sendTest(st)),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text(s['auTest']),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || (st.webhookUrl ?? '').isEmpty || app.snapshot.isEmpty
                        ? null
                        : () => _run(() => Automation.sendNow(app.snapshot, st)),
                    icon: const Icon(Icons.today_rounded, size: 18),
                    label: Text(s['auSendSummary']),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || (st.webhookUrl ?? '').isEmpty || app.snapshot.isEmpty
                        ? null
                        : () => _run(() => Automation.sendNow(app.snapshot, st, full: true)),
                    icon: const Icon(Icons.dataset_outlined, size: 18),
                    label: Text(s['auSendAll']),
                  ),
                ]),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(_resultOk ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                          size: 18, color: _resultOk ? Brand.success : Brand.danger),
                      const SizedBox(width: 8),
                      Expanded(child: SelectableText(_result!, style: const TextStyle(fontSize: 13))),
                    ]),
                  ),
              ]),
            ),

            SectionHeader(s['auEvents']),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (final type in Automation.eventTypes.where((t) => t != 'snapshot.full'))
                  CheckboxListTile(
                    dense: true,
                    title: Text(s['auEv_${type.replaceAll('.', '_')}']),
                    subtitle: Text(type, style: const TextStyle(fontSize: 12, letterSpacing: 0.2)),
                    value: enabledTypes?.contains(type) ?? true,
                    onChanged: (v) {
                      final set = {...(enabledTypes ?? Automation.eventTypes.toSet())};
                      v == true ? set.add(type) : set.remove(type);
                      st.webhookEvents = set;
                      app.touch();
                    },
                  ),
                const Divider(),
                SwitchListTile(
                  title: Text(s['auSnapshot']),
                  subtitle: Text(s['auSnapshotSub']),
                  value: st.webhookSnapshot,
                  onChanged: (v) {
                    st.webhookSnapshot = v;
                    app.touch();
                  },
                ),
              ]),
            ),

            SectionHeader(s['auForAi']),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s['auForAiSub'], style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: () async => _copy(await rootBundle.loadString('docs/AUTOMATION.md'), s['auCopiedGuide']),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(s['auCopyGuide']),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async => _copy(await rootBundle.loadString('docs/automation/n8n-workflow.json'), s['auCopiedWorkflow']),
                    icon: const Icon(Icons.account_tree_outlined, size: 18),
                    label: Text(s['auCopyWorkflow']),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          icon: const Icon(Icons.key_rounded),
                          content: Text(s['auCopyKeyWarn']),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s['auCopyKey'])),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      final key = await AutomationKey.load();
                      if (key != null) await _copy(base64.encode(key), s['auCopiedKey']);
                    },
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: Text(s['auCopyKey']),
                  ),
                ]),
              ]),
            ),

            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cs.error),
              onPressed: () async {
                await Secrets.write(Secrets.adminKey, null);
                st.adminUnlocked = false;
                app.touch();
                await app.configureBackground();
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(s['auLock']),
            ),
          ]),
        ),
      ),
    );
  }
}
