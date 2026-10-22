import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import 'attendance_screen.dart';
import 'chat_screen.dart';
import 'courses_screen.dart';
import 'deadlines_screen.dart';
import 'design.dart';
import 'exams_screen.dart';
import 'files_screen.dart';
import 'grades_screen.dart';
import 'lms_web_page.dart';
import 'nav.dart';
import 'news_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// Main layout: side rail on PC/tablets, bottom bar on phones.
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

  /// Keeps all tabs (and a running AI reply) alive when the layout switches
  /// between phone and PC width.
  final _stackKey = GlobalKey();

  static const _tabs = [
    Dest.today,
    Dest.schedule,
    Dest.deadlines,
    Dest.courses,
    Dest.grades,
    Dest.attendance,
    Dest.exams,
    Dest.files,
    Dest.news,
    Dest.assistant,
    Dest.profile,
  ];
  static const _bottom = [Dest.today, Dest.schedule, Dest.deadlines, Dest.assistant];
  static const _more = [Dest.courses, Dest.grades, Dest.attendance, Dest.exams, Dest.files, Dest.news, Dest.lms, Dest.profile];

  /// Sidebar groups on PC.
  static const _railGroups = [
    [Dest.today, Dest.schedule, Dest.deadlines],
    [Dest.courses, Dest.grades, Dest.attendance, Dest.exams],
    [Dest.files, Dest.news, Dest.assistant],
    [Dest.lms, Dest.profile],
  ];

  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app.addListener(_onApp);
    _nav = context.read<NavController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_app.loggedIn) {
        _app.configureBackground();
        _app.refreshWidget(); // cached data first, in case the sync fails
        _app.refresh();
      }
    });
  }

  @override
  void dispose() {
    _app.removeListener(_onApp);
    super.dispose();
  }

  /// When the LMS session expires and a password is saved, sign in again
  /// automatically through the real login page.
  Future<void> _onApp() async {
    if (!_app.sessionExpired || !_app.settings.autoLogin || _autoLoginOpen) return;
    final now = DateTime.now();
    if (_lastAutoLogin != null && now.difference(_lastAutoLogin!) < const Duration(minutes: 15)) return;
    _lastAutoLogin = now;
    final pass = await Secrets.read(Secrets.lmsPassword);
    if (pass == null || !mounted) return;
    _autoLoginOpen = true;
    try {
      await LmsWebPage.login(context);
    } finally {
      _autoLoginOpen = false;
    }
  }

  Widget _screen(Dest d) => switch (d) {
        Dest.today => const TodayScreen(),
        Dest.schedule => const ScheduleScreen(),
        Dest.deadlines => const DeadlinesScreen(),
        Dest.courses => const CoursesScreen(),
        Dest.grades => const GradesScreen(),
        Dest.attendance => const AttendanceScreen(),
        Dest.exams => const ExamsScreen(),
        Dest.files => const FilesScreen(),
        Dest.news => const NewsScreen(),
        Dest.assistant => const ChatScreen(),
        Dest.profile => const ProfileScreen(),
        Dest.lms => const SizedBox(),
      };

  void _select(Dest d) {
    if (d == Dest.lms) {
      LmsWebPage.open(context);
      return;
    }
    _nav.go(d);
  }

  String _label(Dest d, S s) => s[destInfo[d]!.key];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    context.watch<NavController>();
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final current = _nav.current;
    final stack = IndexedStack(
      key: _stackKey,
      index: _tabs.indexOf(current).clamp(0, _tabs.length - 1),
      children: [for (final d in _tabs) _screen(d)],
    );

    if (wide) {
      return Scaffold(
        body: Row(children: [
          _Sidebar(
            compact: width < 1180,
            groups: _railGroups,
            current: current,
            label: (d) => _label(d, s),
            onSelect: _select,
          ),
          Expanded(child: stack),
        ]),
      );
    }
    return Scaffold(
      body: stack,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bottom.contains(current) ? _bottom.indexOf(current) : _bottom.length,
        onDestinationSelected: (i) {
          if (i < _bottom.length) {
            _nav.go(_bottom[i]);
          } else {
            _showMore(context);
          }
        },
        destinations: [
          for (final d in _bottom)
            NavigationDestination(
              icon: Icon(destInfo[d]!.icon),
              selectedIcon: Icon(destInfo[d]!.selectedIcon),
              label: switch (d) {
                Dest.assistant => s['assistantShort'],
                Dest.schedule => s['scheduleShort'],
                Dest.deadlines => s['tasksShort'],
                _ => _label(d, s),
              },
            ),
          NavigationDestination(icon: const Icon(Icons.grid_view_rounded), label: s['more']),
        ],
      ),
    );
  }

  void _showMore(BuildContext context) {
    final s = S.read(context);
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.82,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final d in _more)
                InkWell(
                  borderRadius: BorderRadius.circular(radiusM),
                  onTap: () {
                    Navigator.pop(ctx);
                    _select(d);
                  },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TintIcon(_nav.current == d ? destInfo[d]!.selectedIcon : destInfo[d]!.icon,
                        color: _moreColor(d), size: 50),
                    const SizedBox(height: 8),
                    Text(_label(d, s),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _moreColor(Dest d) => switch (d) {
      Dest.courses => Brand.primary,
      Dest.grades => Brand.success,
      Dest.attendance => Brand.warning,
      Dest.exams => Brand.danger,
      Dest.files => Brand.violet,
      Dest.news => Brand.info,
      Dest.lms => const Color(0xFF64748B),
      _ => const Color(0xFF14B8A6),
    };

/// PC sidebar: brand, grouped destinations, compact (icons only) on narrower windows.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.groups,
    required this.current,
    required this.label,
    required this.onSelect,
  });
  final bool compact;
  final List<List<Dest>> groups;
  final Dest current;
  final String Function(Dest) label;
  final void Function(Dest) onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: compact ? 84 : 248,
      color: cs.surface,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 18, 12, 18), children: [
          Padding(
            padding: EdgeInsets.only(left: compact ? 0 : 8, bottom: 18),
            child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(gradient: Brand.hero, borderRadius: BorderRadius.circular(radiusS)),
                child: const Icon(Icons.school_rounded, color: Colors.white),
              ),
              if (!compact) ...[
                const SizedBox(width: 10),
                Text('TuitMate', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ]),
          ),
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Divider(color: cs.outlineVariant.withValues(alpha: 0.4))),
            for (final d in groups[g]) _item(context, d),
          ],
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, Dest d) {
    final cs = Theme.of(context).colorScheme;
    final selected = d == current;
    final fg = selected ? cs.primary : cs.onSurfaceVariant;
    final tile = Material(
      color: selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(radiusS),
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusS),
        onTap: () => onSelect(d),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 11),
          child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            Icon(selected ? destInfo[d]!.selectedIcon : destInfo[d]!.icon, color: fg, size: 22),
            if (!compact) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(label(d),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: selected ? cs.primary : cs.onSurface, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
              if (d == Dest.lms) Icon(Icons.open_in_new_rounded, size: 16, color: cs.outline),
            ],
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: compact ? Tooltip(message: label(d), child: tile) : tile,
    );
  }
}
