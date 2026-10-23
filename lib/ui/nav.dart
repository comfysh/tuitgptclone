import 'package:flutter/material.dart';

/// Every page of the app.
enum Dest { today, schedule, deadlines, exams, inbox, news, courses, grades, attendance, files, assistant, lms, profile }

/// The four places of the app, grouped by what you want to do rather than by
/// LMS menu: today; plan what is coming; see what changed; study.
enum Hub { today, plan, inbox, study }

class HubInfo {
  final String key;
  final IconData icon;
  final IconData selectedIcon;
  final List<Dest> sections;
  const HubInfo(this.key, this.icon, this.selectedIcon, this.sections);
}

const hubInfo = {
  Hub.today: HubInfo('today', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, [Dest.today]),
  Hub.plan: HubInfo('hubPlan', Icons.view_week_outlined, Icons.view_week_rounded, [Dest.schedule, Dest.deadlines, Dest.exams]),
  Hub.inbox: HubInfo('hubInbox', Icons.inbox_outlined, Icons.inbox_rounded, [Dest.inbox, Dest.news]),
  Hub.study: HubInfo('hubStudy', Icons.auto_stories_outlined, Icons.auto_stories_rounded,
      [Dest.courses, Dest.grades, Dest.attendance, Dest.files]),
};

/// The hub a page belongs to (none for the AI chat, LMS website and profile).
Hub? hubOf(Dest d) {
  for (final e in hubInfo.entries) {
    if (e.value.sections.contains(d)) return e.key;
  }
  return null;
}

class DestInfo {
  /// Full name (page lists, search); [tab] is the short name on section tabs.
  final String key;
  final String tab;
  final IconData icon;
  const DestInfo(this.key, this.tab, this.icon);
}

const destInfo = {
  Dest.today: DestInfo('today', 'today', Icons.wb_sunny_outlined),
  Dest.schedule: DestInfo('schedule', 'scheduleShort', Icons.calendar_month_outlined),
  Dest.deadlines: DestInfo('deadlines', 'deadlines', Icons.assignment_outlined),
  Dest.exams: DestInfo('exams', 'exams', Icons.fact_check_outlined),
  Dest.inbox: DestInfo('ibUpdates', 'ibUpdates', Icons.inbox_outlined),
  Dest.news: DestInfo('news', 'news', Icons.campaign_outlined),
  Dest.courses: DestInfo('coursesShort', 'coursesShort', Icons.school_outlined),
  Dest.grades: DestInfo('navGrades', 'gradesShort', Icons.workspace_premium_outlined),
  Dest.attendance: DestInfo('attendance', 'attendance', Icons.event_busy_outlined),
  Dest.files: DestInfo('navFiles', 'navFiles', Icons.folder_copy_outlined),
  Dest.assistant: DestInfo('assistant', 'assistant', Icons.auto_awesome_outlined),
  Dest.lms: DestInfo('lmsSite', 'lmsSite', Icons.public_outlined),
  Dest.profile: DestInfo('profile', 'profile', Icons.person_outline),
};

/// Lets any screen switch the current page.
class NavController extends ChangeNotifier {
  Dest current = Dest.today;

  /// Optional payload for the destination, e.g. a prompt for the AI chat.
  Object? payload;

  /// The section last open in each hub, so a hub opens where you left it.
  final _last = <Hub, Dest>{};

  void go(Dest d, {Object? payload}) {
    current = d;
    this.payload = payload;
    final hub = hubOf(d);
    if (hub != null) _last[hub] = d;
    notifyListeners();
  }

  void goHub(Hub hub) => go(_last[hub] ?? hubInfo[hub]!.sections.first);

  Hub? get hub => hubOf(current);

  Object? takePayload() {
    final p = payload;
    payload = null;
    return p;
  }
}

/// Tells a page which destination it is shown as, so its header can show the
/// hub's name and section tabs. Pages opened on their own (pushed routes,
/// tests) have none and show their own title.
class HubSection extends InheritedWidget {
  const HubSection({super.key, required this.dest, required super.child});
  final Dest dest;

  static Dest? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HubSection>()?.dest;

  @override
  bool updateShouldNotify(HubSection old) => old.dest != dest;
}
