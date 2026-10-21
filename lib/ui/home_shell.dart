import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import 'attendance_screen.dart';
import 'chat_screen.dart';
import 'courses_screen.dart';
import 'deadlines_screen.dart';
import 'exams_screen.dart';
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
    Dest.attendance,
    Dest.exams,
    Dest.news,
    Dest.assistant,
    Dest.profile,
  ];
  static const _bottom = [Dest.today, Dest.schedule, Dest.deadlines, Dest.assistant];

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
        Dest.attendance => const AttendanceScreen(),
        Dest.exams => const ExamsScreen(),
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

    return Builder(
      builder: (_) => wide
          ? Scaffold(
              body: Row(children: [
                SafeArea(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - 24),
                      child: IntrinsicHeight(
                        child: NavigationRail(
                          extended: width >= 1200,
                          minExtendedWidth: 220,
                          selectedIndex: [..._tabs, Dest.lms].indexOf(current),
                          onDestinationSelected: (i) => _select([..._tabs, Dest.lms][i]),
                          leading: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: width >= 1200
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.school, size: 28),
                                    const SizedBox(width: 8),
                                    Text('TuitMate', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                                  ])
                                : const Icon(Icons.school, size: 28),
                          ),
                          labelType: width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                          destinations: [
                            for (final d in [..._tabs, Dest.lms])
                              NavigationRailDestination(
                                icon: Icon(destInfo[d]!.icon),
                                selectedIcon: Icon(destInfo[d]!.selectedIcon),
                                label: Text(width >= 1200
                                    ? s[destInfo[d]!.key]
                                    : s[d == Dest.courses
                                        ? 'coursesShort'
                                        : d == Dest.assistant
                                            ? 'assistantShort'
                                            : d == Dest.profile
                                                ? 'settings'
                                                : destInfo[d]!.key]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: stack),
              ]),
            )
          : Scaffold(
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
                      label: s[d == Dest.assistant ? 'assistantShort' : destInfo[d]!.key],
                    ),
                  NavigationDestination(icon: const Icon(Icons.apps), label: s['more']),
                ],
              ),
            ),
    );
  }

  void _showMore(BuildContext context) {
    final s = S.read(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final d in const [Dest.courses, Dest.attendance, Dest.exams, Dest.news, Dest.lms, Dest.profile])
            ListTile(
              leading: Icon(destInfo[d]!.icon),
              title: Text(s[destInfo[d]!.key]),
              selected: _nav.current == d,
              onTap: () {
                Navigator.pop(ctx);
                _select(d);
              },
            ),
        ]),
      ),
    );
  }
}
