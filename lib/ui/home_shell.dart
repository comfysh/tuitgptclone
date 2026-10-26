import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/insights.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import '../core/timetable.dart';
import '../lms/changes.dart';
import '../services/desktop_tray.dart';
import '../services/notifier.dart';
import 'ask_palette.dart';
import 'attendance_screen.dart';
import 'chat_screen.dart';
import 'courses_screen.dart';
import 'deadlines_screen.dart';
import 'widgets.dart';
import 'exams_screen.dart';
import 'files_screen.dart';
import 'grades_screen.dart';
import 'inbox_screen.dart';
import 'lms_web_page.dart';
import 'nav.dart';
import 'news_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// Main layout: four places (Today, Plan, Inbox, Study) and Ask. A sidebar
/// on PC and tablets, a bottom bar with the Ask button in the middle on phones.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final NavController _nav;
  /// Last automatic re-login; at most one every 15 minutes so a session
  /// that keeps failing can't trap you in a login loop.
  DateTime? _lastAutoLogin;
  bool _autoLoginOpen = false;

  /// The login page was already shown for the session that ended last; the
  /// next time only after a sign-in worked (the banner stays meanwhile).
  bool _shownForThisExpiry = false;

  /// Keeps all tabs (and a running AI reply) alive when the layout switches
  /// between phone and PC width.
  final _stackKey = GlobalKey();

  /// Every page, kept alive in one stack (also a running AI reply).
  static const _tabs = [
    Dest.today,
    Dest.schedule,
    Dest.deadlines,
    Dest.exams,
    Dest.inbox,
    Dest.news,
    Dest.courses,
    Dest.grades,
    Dest.attendance,
    Dest.files,
    Dest.assistant,
    Dest.profile,
  ];

  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app.addListener(_onApp);
    _nav = context.read<NavController>();
    // The place chosen in "Customize Today" (Today unless changed).
    final start = Hub.values.where((h) => h.name == _app.settings.startHub).firstOrNull;
    if (start != null && start != Hub.today && _nav.current == Dest.today) _nav.current = hubInfo[start]!.sections.first;
    Notifier.onTap = _openRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_app.loggedIn) {
        _app.configureBackground();
        _app.refreshWidget(); // cached data first, in case the sync fails
        _app.refresh();
      }
      final launched = await Notifier.takeLaunchRoute();
      if (launched != null) _openRoute(launched);
    });
  }

  @override
  void dispose() {
    _app.removeListener(_onApp);
    if (Notifier.onTap == _openRoute) Notifier.onTap = null;
    super.dispose();
  }

  /// A tapped notification: updates open the Inbox, deadline reminders the
  /// task list (and on Windows the window comes out of the tray).
  void _openRoute(String route) {
    if (!mounted) return;
    final dest = switch (route) {
      'inbox' => Dest.inbox,
      'deadlines' => Dest.deadlines,
      _ => null,
    };
    if (dest == null) return;
    unawaited(DesktopTray.bringToFront());
    _nav.go(dest);
  }

  /// When the LMS session expires and a password is saved, sign in again
  /// automatically through the real login page.
  /// When LMS ended the session and the invisible sign-in could not renew it,
  /// opens the real login page once, filled in and submitted by itself.
  Future<void> _onApp() async {
    if (!_app.sessionExpired) {
      _shownForThisExpiry = false;
      return;
    }
    if (!_app.settings.autoLogin || _autoLoginOpen || _shownForThisExpiry) return;
    final now = DateTime.now();
    if (_lastAutoLogin != null && now.difference(_lastAutoLogin!) < const Duration(minutes: 15)) return;
    _lastAutoLogin = now;
    _shownForThisExpiry = true;
    final pass = await Secrets.read(Secrets.lmsPassword);
    if (pass == null || !mounted) return;
    _autoLoginOpen = true;
    try {
      await LmsWebPage.login(context);
    } finally {
      _autoLoginOpen = false;
    }
  }

  Widget _screen(Dest d) => HubSection(
        dest: d,
        child: switch (d) {
          Dest.today => const TodayScreen(),
          Dest.schedule => const ScheduleScreen(),
          Dest.deadlines => const DeadlinesScreen(),
          Dest.exams => const ExamsScreen(),
          Dest.inbox => const InboxScreen(),
          Dest.news => const NewsScreen(),
          Dest.courses => const CoursesScreen(),
          Dest.grades => const GradesScreen(),
          Dest.attendance => const AttendanceScreen(),
          Dest.files => const FilesScreen(),
          Dest.assistant => const ChatScreen(),
          Dest.profile => const ProfileScreen(),
          Dest.lms => const SizedBox(),
        },
      );

  void _select(Dest d) {
    if (d == Dest.lms) {
      LmsWebPage.open(context);
      return;
    }
    _nav.go(d);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    context.watch<NavController>();
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final current = _nav.current;
    final stack = IndexedStack(
      key: _stackKey,
      index: _tabs.indexOf(current).clamp(0, _tabs.length - 1),
      children: [for (final d in _tabs) _screen(d)],
    );

    final Widget page;
    if (wide) {
      page = Scaffold(
        body: Row(children: [
          _Sidebar(
            compact: width < 1180,
            current: current,
            unread: app.unread,
            onHub: _nav.goHub,
            onSelect: _select,
            onAsk: () => AskPalette.open(context),
          ),
          Expanded(child: stack),
        ]),
      );
    } else {
      page = Scaffold(
        body: stack,
        bottomNavigationBar: _BottomBar(
          current: current,
          unread: app.unread,
          onHub: _nav.goHub,
          onAsk: () => AskPalette.open(context),
        ),
      );
    }
    // Ctrl+K (Cmd+K on a Mac keyboard) opens Ask from anywhere in the app.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => AskPalette.open(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => AskPalette.open(context),
      },
      child: Focus(autofocus: true, child: page),
    );
  }
}

/// Phone: four places and the Ask button in the middle. The open place gets
/// an ink tab mark on the top edge.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current, required this.unread, required this.onHub, required this.onAsk});
  final Dest current;
  final int unread;
  final void Function(Hub) onHub;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final hub = hubOf(current);

    Widget item(Hub h) {
      final selected = hub == h;
      final info = hubInfo[h]!;
      final color = selected ? cs.onSurface : cs.onSurfaceVariant;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          label: s[info.key],
          excludeSemantics: true,
          child: InkWell(
            onTap: () => onHub(h),
            child: Column(children: [
              Container(
                width: 28,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? cs.onSurface : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                ),
              ),
              const SizedBox(height: 9),
              Stack(clipBehavior: Clip.none, children: [
                Icon(selected ? info.selectedIcon : info.icon, color: color, size: 24),
                if (h == Hub.inbox && unread > 0) Positioned(right: -12, top: -6, child: CountBadge(unread)),
              ]),
              const SizedBox(height: 4),
              Text(s[info.key],
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
            ]),
          ),
        ),
      );
    }

    final asking = current == Dest.assistant;
    final ask = Expanded(
      child: Semantics(
        button: true,
        label: s['askShort'],
        excludeSemantics: true,
        child: InkWell(
          onTap: onAsk,
          child: Column(children: [
            const SizedBox(height: 7),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.onSurface,
                shape: BoxShape.circle,
                border: asking ? Border.all(color: cs.primary, width: 3) : null,
              ),
              child: Icon(Icons.auto_awesome_rounded, color: cs.surface, size: 22),
            ),
            const SizedBox(height: 3),
            Text(s['askShort'],
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ]),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 74,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            item(Hub.today),
            item(Hub.plan),
            ask,
            item(Hub.inbox),
            item(Hub.study),
          ]),
        ),
      ),
    );
  }
}

/// PC sidebar: brand, the Ask box (Ctrl+K), the four places, what is on now
/// or next, and the AI chat, LMS website and profile at the bottom. Icons
/// only on narrower windows.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.current,
    required this.unread,
    required this.onHub,
    required this.onSelect,
    required this.onAsk,
  });
  final bool compact;
  final Dest current;
  final int unread;
  final void Function(Hub) onHub;
  final void Function(Dest) onSelect;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final hub = hubOf(current);
    return Container(
      width: compact ? 84 : 248,
      decoration: BoxDecoration(color: cs.surface, border: Border(right: BorderSide(color: cs.outlineVariant))),
      child: SafeArea(
        child: CustomScrollView(slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _brand(cs),
                const SizedBox(height: 16),
                _AskField(compact: compact, onTap: onAsk),
                const SizedBox(height: 14),
                for (final h in Hub.values)
                  _item(
                    context,
                    icon: hub == h ? hubInfo[h]!.selectedIcon : hubInfo[h]!.icon,
                    label: s[hubInfo[h]!.key],
                    selected: hub == h,
                    badge: h == Hub.inbox ? unread : 0,
                    onTap: () => onHub(h),
                  ),
                const Spacer(),
                if (!compact) const Padding(padding: EdgeInsets.only(bottom: 10), child: _NowCard()),
                Divider(color: cs.outlineVariant.withValues(alpha: 0.6), height: 12),
                for (final d in const [Dest.assistant, Dest.lms, Dest.profile])
                  _item(
                    context,
                    icon: destInfo[d]!.icon,
                    label: s[destInfo[d]!.key],
                    selected: current == d,
                    external: d == Dest.lms,
                    onTap: () => onSelect(d),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _brand(ColorScheme cs) => Padding(
        padding: EdgeInsets.only(left: compact ? 0 : 8),
        child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.onSurface, borderRadius: BorderRadius.circular(radiusS)),
            child: Text('T',
                style: TextStyle(fontFamily: brandFont, fontSize: 22, fontWeight: FontWeight.w700, color: cs.surface, height: 1)),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text('TuitMate',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontFamily: brandFont, fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
            ),
            Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(left: 3, top: 10),
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
          ],
        ]),
      );

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int badge = 0,
    bool external = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;
    final tile = Material(
      color: selected ? cs.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(radiusS),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusS),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 11),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon, color: fg, size: 22),
              if (compact && badge > 0)
                Positioned(right: -6, top: -6, child: Container(width: 9, height: 9, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle))),
            ]),
            if (!compact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
              if (badge > 0) CountBadge(badge),
              if (external) Icon(Icons.open_in_new_rounded, size: 16, color: cs.outline),
            ],
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: compact ? Tooltip(message: label, child: tile) : tile,
    );
  }
}

/// The search-box-looking button at the top of the sidebar.
class _AskField extends StatelessWidget {
  const _AskField({required this.compact, required this.onTap});
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final box = Material(
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS), side: BorderSide(color: cs.outlineVariant)),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusS),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
            if (!compact) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(s['askField'],
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(5)),
                child: Text('Ctrl K', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              ),
            ],
          ]),
        ),
      ),
    );
    return compact ? Tooltip(message: '${s['askField']} (Ctrl+K)', child: box) : box;
  }
}

/// Sidebar card: the class on now, else the next class today, else the
/// nearest open deadline in the coming week.
class _NowCard extends StatefulWidget {
  const _NowCard();

  @override
  State<_NowCard> createState() => _NowCardState();
}

class _NowCardState extends State<_NowCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final snap = app.snapshot;
    if (snap.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final slots = classesOn(dateOnly(now), app.settings, snap);
    final cur = slots.where((c) => c.isNow(now)).firstOrNull;
    final next = slots.where((c) => c.start.isAfter(now)).firstOrNull;
    final slot = cur ?? next;

    final String label, title;
    final String? line;
    final VoidCallback onTap;
    if (slot != null) {
      label = '${cur != null ? s['sbNow'] : s['sbNext']} · ${fmtTime(slot.start)}–${fmtTime(slot.end)}';
      title = slot.item.displaySubject;
      line = slot.item.room;
      onTap = () => context.read<NavController>().go(Dest.schedule);
    } else {
      final task = snap.assignments
          .where((a) => isOpenTask(a) && a.deadline != null && a.deadline!.isAfter(now) && a.deadline!.difference(now).inDays < 7)
          .toList()
          .sortedByDeadline()
          .firstOrNull;
      if (task == null) return const SizedBox.shrink();
      label = '${s['sbDue']} · ${fmtDateTime(task.deadline!, s.lang)}';
      title = task.title;
      line = task.courseName;
      onTap = () => showAssignmentSheet(context, task);
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusM),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: cur != null ? Brand.danger : cs.onSurfaceVariant,
                  fontFeatures: tabular,
                )),
            const SizedBox(height: 4),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (line != null && line.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
      ),
    );
  }
}
