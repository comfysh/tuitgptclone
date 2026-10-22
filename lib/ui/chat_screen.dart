import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import '../core/format.dart';
import '../core/insights.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import 'nav.dart';
import 'settings_screen.dart';
import 'widgets.dart';

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

  /// Max width of the message column on PC.
  static const _maxColumn = 860.0;

  @override
  void initState() {
    super.initState();
    _load(sweep: true);
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

  Future<void> _load({bool sweep = false}) async {
    final ai = AiService(context.read<AppState>().settings);
    final chats = await ChatStore.load();
    if (sweep) unawaited(ChatStore.sweepOrphans(chats));
    final key = await ai.apiKey();
    if (!mounted) return;
    setState(() {
      // Keep the open (maybe streaming) conversation object instead of its disk copy.
      final i = chats.indexWhere((c) => c.id == _chat.id);
      if (i >= 0) chats[i] = _chat;
      _chats = chats;
      _hasKey = key != null && key.isNotEmpty;
    });
  }

  Future<void> _checkLaunch() async {
    final nav = _nav;
    if (nav == null || nav.current != Dest.assistant) return;
    if (!_hasKey) unawaited(_recheckKey()); // maybe saved in Profile › AI settings
    if (nav.payload is! ChatLaunch) return;
    final launch = nav.takePayload() as ChatLaunch;
    _newChat();
    _input.text = launch.prompt;
    final name = launch.fileName, bytes = launch.bytes;
    if (bytes != null && name != null) {
      final att = await ChatAttachment.save(name, bytes);
      if (mounted) setState(() => _pending.add(att));
    }
    _focus.requestFocus();
  }

  void _newChat() {
    _stop();
    setState(() {
      _chat = Conversation.create();
      _discardPending();
    });
  }

  /// Deletes copies of attachments that were never sent.
  void _discardPending() {
    for (final a in _pending) {
      ChatStore.deleteAttachment(a);
    }
    _pending.clear();
  }

  Future<void> _save() async {
    if (_chat.messages.isEmpty) return;
    _chat.updatedAt = DateTime.now();
    if (!_chats.any((c) => identical(c, _chat))) {
      _chats.removeWhere((c) => c.id == _chat.id);
      _chats.insert(0, _chat);
    }
    _chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_chats.length > ChatStore.maxChats) {
      for (final c in _chats.sublist(ChatStore.maxChats)) {
        ChatStore.deleteFiles(c);
      }
      _chats.removeRange(ChatStore.maxChats, _chats.length);
    }
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

  Future<void> _recheckKey() async {
    final key = await AiService(context.read<AppState>().settings).apiKey();
    if (mounted && key != null && key.isNotEmpty && !_hasKey) setState(() => _hasKey = true);
  }

  /// Returns true when an API key is saved; otherwise explains what to do.
  Future<bool> _ensureKey() async {
    final ai = AiService(context.read<AppState>().settings);
    final key = await ai.apiKey();
    if (key != null && key.isNotEmpty) {
      // A key may have been saved from Profile › AI settings meanwhile.
      if (!_hasKey && mounted) setState(() => _hasKey = true);
      return true;
    }
    if (!mounted) return false;
    setState(() => _hasKey = false);
    // The setup card is only on the empty chat; in a running chat say it here.
    if (_chat.messages.isNotEmpty) {
      final s = S.read(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s['aiNoKey']),
        action: SnackBarAction(label: s['aiSettings'], onPressed: _openSettings),
      ));
    }
    return false;
  }

  Future<void> _send([String? preset]) async {
    var text = (preset ?? _input.text).trim();
    if (preset != null) {
      // A suggestion tapped after "Ask AI" on another screen: keep the task or
      // lesson details that came with it (the box holds "<prompt>\n\n<details>").
      final typed = _input.text.trim();
      final cut = typed.indexOf('\n\n');
      final extra = cut < 0 ? typed : typed.substring(cut + 2).trim();
      if (extra.isNotEmpty) text = '$text\n\n$extra';
    }
    if (text.isEmpty && _pending.isEmpty) return;
    if (_streaming) return;
    // Checked again after the await: a second Enter in that gap must not
    // send the question twice.
    if (!await _ensureKey() || !mounted || _streaming) return;
    final user = ChatMessage('user', text, attachments: [..._pending]);
    setState(() {
      _chat.messages.add(user);
      if (_chat.title.isEmpty) {
        final t = text.isEmpty ? user.attachments.first.name : text;
        _chat.title = t.length > 48 ? '${t.substring(0, 48)}…' : t;
      }
      _pending.clear();
      _input.clear();
    });
    await _reply();
  }

  /// The last reply failed with a temporary error: ask the same question again.
  bool get _canRetry {
    final m = _chat.messages;
    if (_streaming || m.length < 2) return false;
    final last = m[m.length - 1], user = m[m.length - 2];
    return last.role == 'assistant' && last.error && user.role == 'user' && !user.error;
  }

  Future<void> _retry() async {
    if (!_canRetry) return;
    if (!await _ensureKey() || !mounted || !_canRetry) return;
    setState(() => _chat.messages.removeLast());
    await _reply();
  }

  /// Streams the assistant's answer to the conversation so far.
  Future<void> _reply() async {
    final app = context.read<AppState>();
    final s = S.read(context);
    final ai = AiService(app.settings);
    final user = _chat.messages.last;
    final reply = ChatMessage('assistant', '');
    setState(() {
      _chat.messages.add(reply);
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
        // A request the API rejected (bad file, too large, blocked) is not resent;
        // after a temporary error (429, 503, timeout) "try again" still has the question.
        if (e is AiException && e.badRequest) user.error = true;
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsPage()));
    _load();
  }

  void _toggleLmsContext(bool v) {
    final app = context.read<AppState>();
    app.settings.aiUseLmsContext = v;
    app.touch();
  }

  void _openChat(Conversation c) {
    _stop();
    setState(() {
      _chat = c;
      _discardPending();
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

  void _removePending(ChatAttachment a) {
    setState(() => _pending.remove(a));
    ChatStore.deleteAttachment(a);
  }

  // ------------------------------------------------------------ suggestions

  /// Prompts for the empty chat: about the attached file, the student's own
  /// LMS data (sent to the model as context), or general study help.
  List<_Suggestion> _suggestions(AppState app) {
    if (_pending.isNotEmpty) {
      return const [
        _Suggestion(Icons.lightbulb_outline_rounded, Brand.warning, 'chSugFileExplain', 'qpExplain'),
        _Suggestion(Icons.format_list_bulleted_rounded, Brand.primary, 'chSugFileSummary', 'qpSummarize'),
        _Suggestion(Icons.quiz_outlined, Brand.violet, 'chSugFileQuiz', 'qpQuiz'),
        _Suggestion(Icons.style_outlined, Brand.success, 'chSugFileCards', 'chSugFileCardsQ'),
      ];
    }
    final snap = app.snapshot;
    if (app.settings.aiUseLmsContext && !snap.isEmpty) {
      final now = DateTime.now();
      final hasExam = snap.finals.any((f) {
        final t = f.startsAt;
        return t != null && t.isAfter(now);
      });
      return [
        const _Suggestion(Icons.assignment_late_outlined, Brand.warning, 'chSugDue', 'chSugDueQ'),
        const _Suggestion(Icons.calendar_month_outlined, Brand.primary, 'chSugTomorrow', 'chSugTomorrowQ'),
        const _Suggestion(Icons.event_busy_outlined, Brand.danger, 'qpAbsences', 'qpAbsences'),
        if (hasExam) const _Suggestion(Icons.fact_check_outlined, Brand.violet, 'chSugExam', 'chSugExamQ'),
        const _Suggestion(Icons.insights_rounded, Brand.success, 'chSugGrades', 'chSugGradesQ'),
        const _Suggestion(Icons.view_week_outlined, Brand.info, 'chSugWeek', 'qpPlanWeek'),
      ];
    }
    return const [
      _Suggestion(Icons.lightbulb_outline_rounded, Brand.warning, 'chSugExplain', 'chSugExplainQ'),
      _Suggestion(Icons.quiz_outlined, Brand.violet, 'chSugQuiz', 'chSugQuizQ'),
      _Suggestion(Icons.description_outlined, Brand.primary, 'chSugReport', 'chSugReportQ'),
      _Suggestion(Icons.code_rounded, Brand.success, 'chSugCode', 'chSugCodeQ'),
    ];
  }

  // ------------------------------------------------------------ pieces

  Widget _chatList(BuildContext context, {bool inDrawer = false}) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Row(children: [
          Expanded(
            child: Text(s['chats'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (_chats.isNotEmpty) Tag('${_chats.length}', color: cs.onSurfaceVariant),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: FilledButton.tonalIcon(
          onPressed: () {
            _newChat();
            if (inDrawer) Navigator.pop(context);
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(s['newChat']),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _chats.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(children: [
                  Icon(Icons.forum_outlined, size: 32, color: cs.outline),
                  const SizedBox(height: 8),
                  Text(s['chNoChats'], textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                itemCount: _chats.length,
                itemBuilder: (_, i) {
                  final c = _chats[i];
                  return _ChatTile(
                    chat: c,
                    selected: c == _chat,
                    onTap: () {
                      _openChat(c);
                      if (inDrawer) Navigator.pop(context);
                    },
                    onDelete: () => _deleteChat(c),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _header(BuildContext context, {required bool wide, required bool narrow}) {
    final s = S.of(context);
    final settings = context.read<AppState>().settings;
    final cs = Theme.of(context).colorScheme;
    final gemini = settings.aiProvider == AiProvider.gemini;
    final model = gemini ? settings.geminiModel.replaceFirst('models/', '') : settings.openaiModel;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 4, 10, 8, 10),
      child: Row(children: [
        if (!wide)
          Builder(
            builder: (ctx) => IconButton(
              tooltip: s['chats'],
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        if (!narrow) ...[
          const _AiMark(size: 40),
          const SizedBox(width: 12),
        ] else
          const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_chat.title.isEmpty ? s['assistant'] : _chat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(
                child: Tooltip(
                  message: s['aiSettings'],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _openSettings,
                    child: _hasKey
                        ? Tag(model, icon: gemini ? Icons.auto_awesome_rounded : Icons.hub_rounded, color: Brand.violet)
                        : Tag(s['chNoKey'], icon: Icons.key_off_rounded, color: Brand.warning),
                  ),
                ),
              ),
              if (settings.aiUseLmsContext) ...[
                const SizedBox(width: 6),
                // On phones only the icon, so the model name stays readable.
                if (narrow)
                  Tooltip(
                    message: s['chLmsTag'],
                    child: const Icon(Icons.link_rounded, size: 18, color: Brand.success),
                  )
                else
                  Flexible(child: Tag(s['chLmsTag'], icon: Icons.link_rounded, color: Brand.success)),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        if (!wide) HeaderButton(icon: Icons.add_comment_outlined, tooltip: s['newChat'], onPressed: _newChat),
        HeaderButton(icon: Icons.open_in_new_rounded, tooltip: s['askChatGpt'], onPressed: _askChatGpt),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          style: IconButton.styleFrom(backgroundColor: cs.surface, fixedSize: const Size(40, 40)),
          onSelected: (v) {
            if (v == 'ctx') {
              _toggleLmsContext(!settings.aiUseLmsContext);
            } else if (v == 'settings') {
              _openSettings();
            } else if (v == 'new') {
              _newChat();
            } else if (v == 'delete') {
              _deleteChat(_chat);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'new', child: _MenuRow(Icons.add_comment_outlined, s['newChat'])),
            CheckedPopupMenuItem(value: 'ctx', checked: settings.aiUseLmsContext, child: Text(s['useLmsData'])),
            PopupMenuItem(value: 'settings', child: _MenuRow(Icons.tune_rounded, s['aiSettings'])),
            if (_chats.contains(_chat))
              PopupMenuItem(value: 'delete', child: _MenuRow(Icons.delete_outline_rounded, s['deleteChat'])),
          ],
        ),
      ]),
    );
  }

  Widget _messages() {
    return LayoutBuilder(builder: (context, c) {
      final side = math.max(12.0, (c.maxWidth - _maxColumn) / 2);
      final n = _chat.messages.length;
      final retry = _canRetry;
      return ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(side, 16, side, 12),
        itemCount: n,
        itemBuilder: (_, i) => _Bubble(
          m: _chat.messages[i],
          streaming: _streaming && i == n - 1,
          onRetry: retry && i == n - 1 ? _retry : null,
        ),
      );
    });
  }

  Widget _composer(BuildContext context, {required bool wide}) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, wide ? 8 : 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxColumn - 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.55)),
                  boxShadow: dark
                      ? null
                      : [BoxShadow(color: const Color(0xFF1B2559).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (_pending.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final a in _pending) _PendingChip(a: a, onRemove: () => _removePending(a)),
                      ]),
                    ),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(
                      tooltip: s['attach'],
                      icon: const Icon(Icons.attach_file_rounded),
                      color: cs.onSurfaceVariant,
                      onPressed: _streaming ? null : _attach,
                    ),
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
                            filled: false,
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (_streaming)
                      IconButton.filled(
                        tooltip: s['stop'],
                        style: IconButton.styleFrom(backgroundColor: cs.onSurface, foregroundColor: cs.surface),
                        icon: const Icon(Icons.stop_rounded),
                        onPressed: _stop,
                      )
                    else
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _input,
                        builder: (_, v, _) {
                          final ready = v.text.trim().isNotEmpty || _pending.isNotEmpty;
                          return IconButton.filled(
                            tooltip: s['chSend'],
                            style: IconButton.styleFrom(
                              backgroundColor: Brand.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.08),
                              disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
                            ),
                            icon: const Icon(Icons.arrow_upward_rounded),
                            onPressed: ready ? () => _send() : null,
                          );
                        },
                      ),
                  ]),
                ]),
              ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s['chMistakes'],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline, fontSize: 11)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final screenNarrow = MediaQuery.sizeOf(context).width < 480;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 960;
      final main = Column(children: [
        _header(context, wide: wide, narrow: screenNarrow),
        if (_chat.messages.isNotEmpty) const Divider(height: 1),
        Expanded(
          child: _chat.messages.isEmpty
              ? _Welcome(
                  hasKey: _hasKey,
                  suggestions: _suggestions(app),
                  useLms: app.settings.aiUseLmsContext,
                  onPrompt: (p) => _send(p),
                  onKeySaved: _load,
                  onOpenSettings: _openSettings,
                  onChatGpt: _askChatGpt,
                  onToggleLms: _toggleLmsContext,
                )
              : _messages(),
        ),
        _composer(context, wide: wide),
      ]);
      return Scaffold(
        drawer: wide
            ? null
            : Drawer(backgroundColor: cs.surface, child: SafeArea(child: _chatList(context, inDrawer: true))),
        body: SafeArea(
          bottom: false,
          child: wide
              ? Row(children: [
                  Container(
                    width: 280,
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(
                        left: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                        right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                      ),
                    ),
                    child: _chatList(context),
                  ),
                  Expanded(child: main),
                ])
              : main,
        ),
      );
    });
  }
}

// ---------------------------------------------------------------- messages

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.streaming, this.onRetry});
  final ChatMessage m;
  final bool streaming;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: m.role == 'user' ? _userBubble(context) : _assistantBubble(context),
    );
  }

  Widget _userBubble(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final max = math.min(560.0, c.maxWidth * 0.85);
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: Brand.primary,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              if (m.attachments.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: m.text.isEmpty ? 0 : 8),
                  child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: [
                    for (final a in m.attachments) _SentAttachment(a),
                  ]),
                ),
              if (m.text.isNotEmpty)
                TextSelectionTheme(
                  data: TextSelectionThemeData(
                    selectionColor: Colors.white.withValues(alpha: 0.35),
                    cursorColor: Colors.white,
                  ),
                  child: SelectableText(m.text, style: const TextStyle(color: Colors.white, height: 1.4)),
                ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _assistantBubble(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = TextStyle(color: cs.onSurfaceVariant);

    final Widget content;
    if (m.text.isEmpty && streaming) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        _TypingDots(color: cs.primary),
        const SizedBox(width: 10),
        Text(s['thinking'], style: muted),
      ]);
    } else if (m.error) {
      content = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline_rounded, size: 18, color: Brand.danger),
        ),
        const SizedBox(width: 8),
        Flexible(child: SelectableText(m.text, style: TextStyle(color: cs.onSurface, height: 1.4))),
      ]);
    } else if (m.text.isEmpty) {
      content = Text(s['chStopped'], style: muted.copyWith(fontStyle: FontStyle.italic));
    } else {
      content = SelectionArea(
        child: GptMarkdown(
          m.text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          onLinkTap: (url, _) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
      );
    }

    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: m.error ? Color.alphaBlend(Brand.danger.withValues(alpha: 0.07), cs.surface) : cs.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        border: m.error
            ? Border.all(color: Brand.danger.withValues(alpha: 0.25))
            : (dark ? Border.all(color: Colors.white.withValues(alpha: 0.06)) : null),
        boxShadow: dark
            ? null
            : [BoxShadow(color: const Color(0xFF1B2559).withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (m.attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in m.attachments) _SentAttachment(a, onCard: true),
            ]),
          ),
        content,
      ]),
    );

    final showActions = !streaming && (m.text.isNotEmpty || onRetry != null);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _AiMark(size: 30),
      const SizedBox(width: 10),
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            card,
            if (showActions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 4, children: [
                  if (m.text.isNotEmpty)
                    _MiniAction(
                      icon: Icons.content_copy_rounded,
                      label: s['copy'],
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: m.text));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['copied'])));
                      },
                    ),
                  if (onRetry != null) _MiniAction(icon: Icons.refresh_rounded, label: s['retry'], onTap: onRetry),
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// A file inside a sent message: thumbnail for images, kind icon + name otherwise.
class _SentAttachment extends StatelessWidget {
  const _SentAttachment(this.a, {this.onCard = false});
  final ChatAttachment a;
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (a.isImage && File(a.path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(a.path),
          height: 140,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(width: 60, height: 60, child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }
    final kind = a.isImage ? FileKind.image : fileKind(a.name);
    final fg = onCard ? cs.onSurface : Colors.white;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: onCard ? fileKindColor(kind).withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(fileKindIcon(kind), size: 18, color: onCard ? fileKindColor(kind) : Colors.white),
        const SizedBox(width: 6),
        Flexible(
          child: Text(a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// A file waiting in the composer.
class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.a, required this.onRemove});
  final ChatAttachment a;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    final kind = a.isImage ? FileKind.image : fileKind(a.name);
    final color = fileKindColor(kind);
    final thumb = a.isImage && File(a.path).existsSync();
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radiusS),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        thumb
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(a.path),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => TintIcon(fileKindIcon(kind), color: color, size: 32),
                ),
              )
            : TintIcon(fileKindIcon(kind), color: color, size: 32),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            Text(_fmtSize(a.size), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
        IconButton(
          tooltip: s['delete'],
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          icon: const Icon(Icons.close_rounded),
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Small text action under an assistant reply.
class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// Gradient rounded square with the sparkle: the assistant's avatar.
class _AiMark extends StatelessWidget {
  const _AiMark({required this.size, this.glow = false});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: Brand.heroFor(context),
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: glow
            ? [BoxShadow(color: Brand.primary.withValues(alpha: 0.32), blurRadius: 28, offset: const Offset(0, 10))]
            : null,
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.52),
    );
  }
}

/// Three pulsing dots while the reply is on its way.
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _level(int i) {
    final t = (_c.value - i * 0.2) % 1.0;
    return t < 0.5 ? t * 2 : (1 - t) * 2;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.25 + 0.75 * _level(i)),
            ),
          ),
      ]),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ]);
}

// ---------------------------------------------------------------- chat list

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.selected, required this.onTap, required this.onDelete});
  final Conversation chat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(radiusS),
        child: InkWell(
          borderRadius: BorderRadius.circular(radiusS),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
            child: Row(children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 18, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(chat.title.isEmpty ? '…' : chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: selected ? cs.primary : cs.onSurface,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  Text(fmtAgo(chat.updatedAt, s), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                ]),
              ),
              IconButton(
                tooltip: s['deleteChat'],
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded, size: 19, color: cs.onSurfaceVariant),
                onPressed: onDelete,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- empty chat

class _Suggestion {
  const _Suggestion(this.icon, this.color, this.label, this.prompt);
  final IconData icon;
  final Color color;

  /// String keys: the short label on the card and the prompt that is sent.
  final String label;
  final String prompt;
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.hasKey,
    required this.suggestions,
    required this.useLms,
    required this.onPrompt,
    required this.onKeySaved,
    required this.onOpenSettings,
    required this.onChatGpt,
    required this.onToggleLms,
  });
  final bool hasKey;
  final List<_Suggestion> suggestions;
  final bool useLms;
  final void Function(String) onPrompt;
  final VoidCallback onKeySaved;
  final VoidCallback onOpenSettings;
  final VoidCallback onChatGpt;
  final ValueChanged<bool> onToggleLms;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final side = math.max(16.0, (c.maxWidth - 760) / 2);
      return ListView(padding: EdgeInsets.fromLTRB(side, 28, side, 16), children: [
        const Center(child: _AiMark(size: 68, glow: true)),
        const SizedBox(height: 18),
        Text(s['chHeroTitle'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(s['aiWelcome'], textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        ),
        const SizedBox(height: 24),
        if (!hasKey) ...[
          _KeySetupCard(onSaved: onKeySaved, onOpenSettings: onOpenSettings),
          const SizedBox(height: 12),
        ] else ...[
          SectionHeader(s['chTryAsking'], padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
          ResponsiveGrid(
            minItemWidth: 300,
            spacing: 10,
            children: [
              for (final g in suggestions) _SuggestionCard(g: g, onTap: () => onPrompt(s[g.prompt])),
            ],
          ),
          const SizedBox(height: 4),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(children: [
              const TintIcon(Icons.link_rounded, color: Brand.success, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['useLmsData'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(s['chCtxSub'], style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              Switch(value: useLms, onChanged: onToggleLms),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        AppCard(
          onTap: onChatGpt,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const TintIcon(Icons.open_in_new_rounded, color: Brand.info, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['askChatGpt'], style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(s['chatGptNote'], style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outline),
          ]),
        ),
      ]);
    });
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.g, required this.onTap});
  final _Suggestion g;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: radiusM,
      child: Row(children: [
        TintIcon(g.icon, color: g.color, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(s[g.label],
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 6),
        Icon(Icons.north_east_rounded, size: 16, color: Theme.of(context).colorScheme.outline),
      ]),
    );
  }
}

class _KeySetupCard extends StatefulWidget {
  const _KeySetupCard({required this.onSaved, required this.onOpenSettings});
  final VoidCallback onSaved;
  final VoidCallback onOpenSettings;

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
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const TintIcon(Icons.key_rounded, color: Brand.warning),
          const SizedBox(width: 12),
          Expanded(child: Text(s['aiSetupTitle'], style: Theme.of(context).textTheme.titleMedium)),
          const Tag('Gemini', icon: Icons.auto_awesome_rounded, color: Brand.violet),
        ]),
        const SizedBox(height: 12),
        Text(s['aiSetupBody'], style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () =>
                launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(s['getKey']),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Gemini ${s['apiKey']}',
            prefixIcon: const Icon(Icons.vpn_key_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: () async {
              final app = context.read<AppState>();
              await Secrets.write(Secrets.geminiKey, _key.text.trim());
              app.settings.aiProvider = AiProvider.gemini;
              widget.onSaved();
            },
            icon: const Icon(Icons.check_rounded),
            label: Text(s['save']),
          ),
          TextButton(onPressed: widget.onOpenSettings, child: Text(s['chOtherProvider'])),
        ]),
      ]),
    );
  }
}
