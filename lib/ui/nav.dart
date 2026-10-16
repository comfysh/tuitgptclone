import 'package:flutter/material.dart';

enum Dest { today, schedule, deadlines, courses, attendance, exams, news, assistant, lms, profile }

class DestInfo {
  final String key;
  final IconData icon;
  final IconData selectedIcon;
  const DestInfo(this.key, this.icon, this.selectedIcon);
}

const destInfo = {
  Dest.today: DestInfo('today', Icons.home_outlined, Icons.home),
  Dest.schedule: DestInfo('schedule', Icons.calendar_month_outlined, Icons.calendar_month),
  Dest.deadlines: DestInfo('deadlines', Icons.assignment_outlined, Icons.assignment),
  Dest.courses: DestInfo('courses', Icons.school_outlined, Icons.school),
  Dest.attendance: DestInfo('attendance', Icons.event_busy_outlined, Icons.event_busy),
  Dest.exams: DestInfo('exams', Icons.fact_check_outlined, Icons.fact_check),
  Dest.news: DestInfo('news', Icons.campaign_outlined, Icons.campaign),
  Dest.assistant: DestInfo('assistant', Icons.auto_awesome_outlined, Icons.auto_awesome),
  Dest.lms: DestInfo('lmsSite', Icons.public_outlined, Icons.public),
  Dest.profile: DestInfo('profile', Icons.person_outline, Icons.person),
};

/// Lets any screen switch the current tab.
class NavController extends ChangeNotifier {
  Dest current = Dest.today;

  /// Optional payload for the destination, e.g. a prompt for the AI chat.
  Object? payload;

  void go(Dest d, {Object? payload}) {
    current = d;
    this.payload = payload;
    notifyListeners();
  }

  Object? takePayload() {
    final p = payload;
    payload = null;
    return p;
  }
}
