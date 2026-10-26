// Every text of every screen area exists in English, Uzbek and Russian (a
// missing one would silently show the English text).

import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/core/strings/today.dart';
import 'package:tuitmate/core/strings/schedule.dart';
import 'package:tuitmate/core/strings/tasks.dart';
import 'package:tuitmate/core/strings/courses.dart';
import 'package:tuitmate/core/strings/attendance.dart';
import 'package:tuitmate/core/strings/exams.dart';
import 'package:tuitmate/core/strings/grades.dart';
import 'package:tuitmate/core/strings/profile.dart';
import 'package:tuitmate/core/strings/files.dart';
import 'package:tuitmate/core/strings/news.dart';
import 'package:tuitmate/core/strings/chat.dart';
import 'package:tuitmate/core/strings/welcome.dart';
import 'package:tuitmate/core/strings/widget.dart';
import 'package:tuitmate/core/strings/ai.dart';
import 'package:tuitmate/core/strings/desktop.dart';
import 'package:tuitmate/core/strings/notify.dart';
import 'package:tuitmate/core/strings/automation.dart';
import 'package:tuitmate/core/strings/hub.dart';
import 'package:tuitmate/core/strings/sync.dart';
import 'package:tuitmate/core/strings/look.dart';

void main() {
  test('every area has the same keys in en, uz and ru', () {
    final areas = {'today': todayStrings, 'schedule': scheduleStrings, 'tasks': tasksStrings, 'courses': coursesStrings, 'attendance': attendanceStrings, 'exams': examsStrings, 'grades': gradesStrings, 'profile': profileStrings, 'files': filesStrings, 'news': newsStrings, 'chat': chatStrings, 'welcome': welcomeStrings, 'widget': widgetStrings, 'ai': aiStrings, 'desktop': desktopStrings, 'notify': notifyStrings, 'automation': automationStrings, 'hub': hubStrings, 'sync': syncStrings, 'look': lookStrings};
    areas.forEach((name, t) {
      final en = t['en']!.keys.toSet();
      for (final lang in ['uz', 'ru']) {
        final keys = t[lang]!.keys.toSet();
        expect(en.difference(keys), isEmpty, reason: '$name: missing in $lang');
        expect(keys.difference(en), isEmpty, reason: '$name: only in $lang');
      }
      for (final lang in ['en', 'uz', 'ru']) {
        for (final e in t[lang]!.entries) {
          // Placeholders like {n} must be the same in every language.
          final want = RegExp(r'\{(\w+)\}').allMatches(t['en']![e.key]!).map((m) => m[1]).toSet();
          final got = RegExp(r'\{(\w+)\}').allMatches(e.value).map((m) => m[1]).toSet();
          expect(got, want, reason: '$name/$lang/${e.key}');
        }
      }
    });
  });
}
