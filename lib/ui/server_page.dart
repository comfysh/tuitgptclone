import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../core/timetable.dart' show dateOnly;
import '../services/server_link.dart';
import 'widgets.dart';

const _guideUrl = 'https://github.com/comfysh/tuitgptclone/blob/main/server/README.md';

/// Profile › Sync › TuitMate server: connects with a code, or shows the
/// connected server.
Future<void> openServer(BuildContext context) async {
  final c = await ServerLink.load();
  if (!context.mounted) return;
  if (c == null) {
    await showServerConnect(context);
  } else {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServerPage()));
  }
}

/// Paste the connection code; the app checks the server (and its pinned
/// certificate) before saving, then hands over its LMS session.
Future<bool> showServerConnect(BuildContext context) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => const _ConnectDialog());
  return ok ?? false;
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog();

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final s = S.read(context);
    final app = context.read<AppState>();
    final config = ServerConfig.parse(_code.text);
    if (config == null) return setState(() => _error = s['srvBadCode']);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServerLink.status(config); // also proves the certificate is the pinned one
      await ServerLink.save(config);
      if (app.loggedIn) unawaited(shareSessionIfNeeded(app.client, force: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['srvOk'])));
      Navigator.pop(context, true);
      unawaited(app.refresh());
    } catch (e) {
      if (mounted) setState(() => _error = s.f('srvFailed', {'error': _short(e)}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(s['srvTitle']),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['srvPaste']),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(hintText: 'tmsrv1.…', errorText: _error, errorMaxLines: 3),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(_guideUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text(s['srvGuide']),
          ),
          Text(s['srvHow'], style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(s['cancel'])),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : Text(s['srvConnect']),
        ),
      ],
    );
  }
}

/// The connected server: its LMS session, its last check, actions.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  ServerConfig? _config;
  ServerStatus? _status;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ServerLink.load();
    if (c == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    try {
      final st = await ServerLink.status(c);
      if (mounted) {
        setState(() {
          _config = c;
          _status = st;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _config = c;
          _status = null;
          _error = _short(e);
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final s = S.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.f('srvFailed', {'error': _short(e)}))));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  String _when(DateTime? t, S s) {
    if (t == null) return s['srvNever'];
    final l = t.toLocal();
    return dateOnly(l) == dateOnly(DateTime.now()) ? fmtTime(l) : fmtDateTime(l, s.lang);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final st = _status;
    final session = st?.json['session'] as Map?;
    final checked = DateTime.tryParse('${session?['checked_at'] ?? ''}');
    final last = st?.lastCheck;
    final lastAt = DateTime.tryParse('${last?['finished_at'] ?? ''}');
    final sessionText = switch (st?.sessionState) {
      'live' => s.f('srvSessionLive', {'time': _when(checked, s)}),
      'ended' => s['srvSessionEnded'],
      _ => s['srvSessionNone'],
    };
    Widget row(IconData icon, Color color, String title, String? sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TintIcon(icon, color: color, size: 36, iconSize: 19),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        );
    return Scaffold(
      appBar: pageAppBar(context, title: s['srvTitle'], subtitle: _config == null ? null : s.f('srvConnectedTo', {'host': _config!.host})),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
        if (_error != null)
          AppCard(child: row(Icons.cloud_off_rounded, Brand.danger, s.f('srvFailed', {'error': _error}), null))
        else if (st == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else
          AppCard(
            child: Column(children: [
              row(st.sessionLive ? Icons.verified_user_outlined : Icons.error_outline_rounded,
                  st.sessionLive ? Brand.success : Brand.warning, s['srvSession'], sessionText),
              row(
                last == null || last['ok'] == true ? Icons.update_rounded : Icons.sync_problem_rounded,
                last == null || last['ok'] == true ? Brand.info : Brand.warning,
                s['srvLastCheck'],
                last == null ? s['srvNever'] : [_when(lastAt, s), if (last['ok'] != true && last['error'] != null) '${last['error']}'].join(' · '),
              ),
              row(Icons.timer_outlined, Brand.primary, s.f('srvEvery', {'n': st.fetchMinutes}), s.f('srvVersion', {'v': st.version})),
            ]),
          ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: _busy || _config == null
                ? null
                : () => _run(() async {
                      await ServerLink.refreshNow(_config!);
                      await app.refresh(full: false);
                    }),
            icon: const Icon(Icons.cloud_sync_rounded),
            label: Text(s['srvCheckNow']),
          ),
          OutlinedButton.icon(
            onPressed: _busy || _config == null || !app.loggedIn
                ? null
                : () => _run(() async => ServerLink.sendSession(_config!, app.client), done: s['srvSent']),
            icon: const Icon(Icons.key_rounded),
            label: Text(s['srvSendSession']),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _disconnect(context),
            icon: Icon(Icons.link_off_rounded, color: cs.error),
            label: Text(s['srvDisconnect'], style: TextStyle(color: cs.error)),
          ),
        ]),
        const SizedBox(height: 18),
        Text(s['srvHow'], style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        TextButton.icon(
          onPressed: () => launchUrl(Uri.parse(_guideUrl), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: Text(s['srvGuide']),
        ),
      ]),
    );
  }

  Future<void> _disconnect(BuildContext context) async {
    final s = S.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s['srvDisconnectQ']),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s['srvDisconnect'])),
        ],
      ),
    );
    if (ok != true) return;
    await ServerLink.dropSession();
    await ServerLink.save(null);
    if (context.mounted) Navigator.pop(context);
  }
}

String _short(Object e) {
  final t = e.toString().replaceFirst('DioException ', '').replaceFirst('Exception: ', '');
  return t.length > 160 ? '${t.substring(0, 160)}…' : t;
}
