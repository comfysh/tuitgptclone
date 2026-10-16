import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_service.dart';
import '../ai/chat_models.dart';
import '../ai/lms_context.dart';
import '../app_state.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import 'nav.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  List<Conversation> _chats = [];
  Conversation _chat = Conversation.create();
  final List<ChatAttachment> _pending = [];
  StreamSubscription<String>? _sub;
  CancelToken? _cancel;
  bool _streaming = false;
  bool _hasKey = true;
  NavController? _nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.read<NavController>();
    if (_nav != nav) {
      _nav?.removeListener(_checkLaunch);
      _nav = nav..addListener(_checkLaunch);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkLaunch());
    }
  }

  @override
  void dispose() {
    _nav?.removeListener(_checkLaunch);
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ai = AiService(context.read<AppState>().settings);
    final chats = await ChatStore.load();
    final key = await ai.apiKey();
    if (!mounted) return;
    setState(() {
      _chats = chats;
      _hasKey = key != null && key.isNotEmpty;
    });
  }

  Future<void> _checkLaunch() async {
    final nav = _nav;
    if (nav == null || nav.current != Dest.assistant || nav.payload is! ChatLaunch) return;
    final launch = nav.takePayload() as ChatLaunch;
    _newChat();
    _input.text = launch.prompt;
    if (launch.bytes != null && launch.fileName != null) {
      final att = await ChatAttachment.save(launch.fileName!, launch.bytes!);
      if (mounted) setState(() => _pending.add(att));
    }
    _focus.requestFocus();
  }

  void _newChat() {
    _stop();
    setState(() {
      _chat = Conversation.create();
      _pending.clear();
    });
  }

  Future<void> _save() async {
    if (_chat.messages.isEmpty) return;
    _chat.updatedAt = DateTime.now();
    if (!_chats.contains(_chat)) _chats.insert(0, _chat);
    _chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await ChatStore.save(_chats);
  }

  Future<void> _attach() async {
    final s = S.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final files = await FilePicker.pickFiles(dialogTitle: s['attach']);
    for (final f in files) {
      final size = await f.length() ?? 0;
      if (size > 20 * 1024 * 1024) {
        messenger.showSnackBar(SnackBar(content: Text('${f.name}: ${s['fileTooBigAi']}')));
        continue;
      }
      final att = await ChatAttachment.save(f.name, await f.readAsBytes());
      if (!mounted) return;
      final settings = context.read<AppState>().settings;
      if (att.isPdf && settings.aiProvider != AiProvider.gemini) {
        messenger.showSnackBar(SnackBar(content: Text(s['pdfOnlyGemini'])));
      }
      setState(() => _pending.add(att));
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty && _pending.isEmpty) return;
    if (_streaming) return;
    final app = context.read<AppState>();
    final s = S.read(context);
    final ai = AiService(app.settings);
    final key = await ai.apiKey();
    if (key == null || key.isEmpty) {
      setState(() => _hasKey = false);
      return;
    }
    final user = ChatMessage('user', text, attachments: [..._pending]);
    final reply = ChatMessage('assistant', '');
    setState(() {
      _chat.messages.addAll([user, reply]);
      if (_chat.title.isEmpty) {
        final t = text.isEmpty ? user.attachments.first.name : text;
        _chat.title = t.length > 48 ? '${t.substring(0, 48)}…' : t;
      }
      _pending.clear();
      _input.clear();
      _streaming = true;
    });
    _scrollDown();

    final system = buildSystemPrompt(app.snapshot, app.settings, includeLms: app.settings.aiUseLmsContext);
    final history = _chat.messages.sublist(0, _chat.messages.length - 1);
    _cancel = CancelToken();
    final done = Completer<void>();
    var lastPaint = DateTime.now();
    _sub = ai.stream(system: system, history: history, cancel: _cancel).listen(
      (t) {
        reply.text += t;
        if (DateTime.now().difference(lastPaint).inMilliseconds > 60) {
          lastPaint = DateTime.now();
          if (mounted) setState(() {});
          _scrollDown();
        }
      },
      onError: (Object e) {
        reply.error = true;
        reply.text = e is AiException && e.message == 'NO_KEY'
            ? s['aiNoKey']
            : (e is DioException && CancelToken.isCancel(e) ? reply.text : '${s['error']}: $e');
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
    if (!mounted) return;
    setState(() => _streaming = false);
    _scrollDown();
    await _save();
  }

  void _stop() {
    _cancel?.cancel();
    _sub?.cancel();
    _sub = null;
    if (_streaming) setState(() => _streaming = false);
    _save();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _askChatGpt() async {
    final app = context.read<AppState>();
    final s = S.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final question = _input.text.trim();
    final context0 = buildSystemPrompt(app.snapshot, app.settings, includeLms: app.settings.aiUseLmsContext);
    final files = _pending.map((a) => a.name).toList();
    final prompt = StringBuffer()
      ..writeln(context0)
      ..writeln('---')
      ..writeln(question.isEmpty ? '(my question)' : question);
    if (files.isNotEmpty) prompt.writeln('\n(I will attach: ${files.join(', ')})');
    await Clipboard.setData(ClipboardData(text: prompt.toString()));
    final short = prompt.length < 6000;
    final uri = Uri.parse(short ? 'https://chatgpt.com/?q=${Uri.encodeComponent(prompt.toString())}' : 'https://chatgpt.com/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    messenger.showSnackBar(SnackBar(content: Text(s['chatGptCopied']), duration: const Duration(seconds: 6)));
  }

  void _openChat(Conversation c) {
    _stop();
    setState(() {
      _chat = c;
      _pending.clear();
    });
    _scrollDown();
  }

  Future<void> _deleteChat(Conversation c) async {
    await ChatStore.deleteFiles(c);
    setState(() {
      _chats.remove(c);
      if (_chat == c) _chat = Conversation.create();
    });
    await ChatStore.save(_chats);
  }

  Widget _chatList({bool inDrawer = false}) {
    final s = S.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () {
              _newChat();
              if (inDrawer) Navigator.pop(context);
            },
            icon: const Icon(Icons.add),
            label: Text(s['newChat']),
          ),
        ),
      ),
      Expanded(
        child: ListView(children: [
          for (final c in _chats)
            ListTile(
              dense: true,
              selected: c == _chat,
              title: Text(c.title.isEmpty ? '…' : c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                _openChat(c);
                if (inDrawer) Navigator.pop(context);
              },
              trailing: IconButton(
                tooltip: s['deleteChat'],
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _deleteChat(c),
              ),
            ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final settings = app.settings;

    final body = Column(children: [
      Expanded(
        child: _chat.messages.isEmpty
            ? _Welcome(hasKey: _hasKey, onPrompt: (p) => _send(p), onKeySaved: _load)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: _chat.messages.length,
                itemBuilder: (_, i) => _Bubble(
                  m: _chat.messages[i],
                  streaming: _streaming && i == _chat.messages.length - 1,
                ),
              ),
      ),
      if (_pending.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in _pending)
              InputChip(
                avatar: Icon(a.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 18),
                label: Text(a.name, overflow: TextOverflow.ellipsis),
                onDeleted: () => setState(() => _pending.remove(a)),
              ),
          ]),
        ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(tooltip: s['attach'], icon: const Icon(Icons.attach_file), onPressed: _streaming ? null : _attach),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () => _send(),
                },
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: Platform.isAndroid ? TextInputAction.newline : TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: s['typeMessage'],
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _streaming
                ? IconButton.filledTonal(tooltip: s['stop'], icon: const Icon(Icons.stop), onPressed: _stop)
                : IconButton.filled(tooltip: 'Send', icon: const Icon(Icons.send), onPressed: () => _send()),
          ]),
        ),
      ),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(_chat.title.isEmpty ? s['assistant'] : _chat.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: s['askChatGpt'],
            icon: const Icon(Icons.open_in_new),
            onPressed: _askChatGpt,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'ctx') {
                settings.aiUseLmsContext = !settings.aiUseLmsContext;
                app.touch();
              } else if (v == 'settings') {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsPage()));
                _load();
              } else if (v == 'new') {
                _newChat();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'new', child: Text(s['newChat'])),
              CheckedPopupMenuItem(value: 'ctx', checked: settings.aiUseLmsContext, child: Text(s['useLmsData'])),
              PopupMenuItem(value: 'settings', child: Text(s['aiSettings'])),
            ],
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _chatList(inDrawer: true))),
      body: wide
          ? Row(children: [
              SizedBox(width: 260, child: _chatList()),
              const VerticalDivider(width: 1),
              Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: body))),
            ])
          : body,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.streaming});
  final ChatMessage m;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    final isUser = m.role == 'user';
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: isUser ? 560 : 860),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? cs.primaryContainer : (m.error ? cs.errorContainer : cs.surfaceContainerHighest.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in m.attachments)
                a.isImage && File(a.path).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(a.path), height: 120, fit: BoxFit.cover),
                      )
                    : Chip(
                        avatar: const Icon(Icons.insert_drive_file_outlined, size: 16),
                        label: Text(a.name, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      ),
            ]),
          ),
        if (isUser)
          SelectableText(m.text)
        else if (m.text.isEmpty && streaming)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(s['thinking']),
          ])
        else
          SelectionArea(
            child: GptMarkdown(
              m.text,
              onLinkTap: (url, _) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
          ),
        if (!isUser && !streaming && m.text.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: s['copy'],
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: m.text));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['copied'])));
              },
            ),
          ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(radius: 14, backgroundColor: cs.primary, child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white)),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.hasKey, required this.onPrompt, required this.onKeySaved});
  final bool hasKey;
  final void Function(String) onPrompt;
  final VoidCallback onKeySaved;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(
        child: CircleAvatar(
          radius: 32,
          backgroundColor: cs.primary,
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 30),
        ),
      ),
      const SizedBox(height: 14),
      Text(s['aiWelcome'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 18),
      if (!hasKey) _KeySetupCard(onSaved: onKeySaved),
      if (hasKey)
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final k in ['qpPlanWeek', 'qpAbsences', 'qpExplain', 'qpQuiz'])
            ActionChip(label: Text(s[k]), onPressed: () => onPrompt(s[k])),
        ]),
      const SizedBox(height: 18),
      Text(s['chatGptNote'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _KeySetupCard extends StatefulWidget {
  const _KeySetupCard({required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_KeySetupCard> createState() => _KeySetupCardState();
}

class _KeySetupCardState extends State<_KeySetupCard> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['aiSetupTitle'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text(s['aiSetupBody']),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.key),
            label: Text(s['getKey']),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Gemini ${s['apiKey']}', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () async {
              final app = context.read<AppState>();
              await Secrets.write(Secrets.geminiKey, _key.text.trim());
              app.settings.aiProvider = AiProvider.gemini;
              widget.onSaved();
            },
            child: Text(s['save']),
          ),
        ]),
      ),
    );
  }
}

