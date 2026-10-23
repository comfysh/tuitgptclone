import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuitmate/core/settings.dart';
import 'package:tuitmate/core/strings.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/snapshot.dart';
import 'package:tuitmate/services/notifier.dart';

void main() {
  test('quiet hours, also across midnight', () {
    DateTime at(int h, int m) => DateTime(2026, 10, 23, h, m);
    const from = 22 * 60 + 30, to = 7 * 60;
    expect(Notifier.isQuietTime(at(23, 0), from, to), isTrue);
    expect(Notifier.isQuietTime(at(2, 0), from, to), isTrue);
    expect(Notifier.isQuietTime(at(6, 59), from, to), isTrue);
    expect(Notifier.isQuietTime(at(7, 0), from, to), isFalse);
    expect(Notifier.isQuietTime(at(12, 0), from, to), isFalse);
    expect(Notifier.isQuietTime(at(22, 29), from, to), isFalse);
    // Same-day range and an empty range.
    expect(Notifier.isQuietTime(at(13, 30), 13 * 60, 14 * 60), isTrue);
    expect(Notifier.isQuietTime(at(14, 0), 13 * 60, 14 * 60), isFalse);
    expect(Notifier.isQuietTime(at(3, 0), 600, 600), isFalse);
  });

  test('morning brief lists the day, and skips empty days', () async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    final settings = await Settings.load();
    const s = S('en');
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day + 1);
    final at = day.add(const Duration(hours: 7, minutes: 30));
    final snap = LmsSnapshot(
      schedule: [
        ScheduleItem(start: day.add(const Duration(hours: 9, minutes: 30)), title: 't', subject: 'Database', room: 'D-104', type: LessonType.practice),
        ScheduleItem(start: day.add(const Duration(hours: 11)), title: 't', subject: 'Electronics', type: LessonType.lecture),
      ],
      coursePages: {
        1: CoursePage(const CourseRating(), [
          Assignment(courseId: 1, courseName: 'Database', name: 'Lab 3', deadline: day.add(const Duration(hours: 23, minutes: 59)), maxGrade: 5),
          Assignment(courseId: 1, courseName: 'Database', name: 'Later', deadline: day.add(const Duration(days: 3)), maxGrade: 5),
        ]),
      },
      updatedAt: now,
    );
    final b = Notifier.morningBrief(snap, settings, day, at, s)!;
    expect(b.$1, '2 classes from 09:30 · 1 due today');
    expect(b.$2.split('\n'), ['09:30 Database · D-104', '11:00 Electronics', 'Deadline 23:59 · Lab 3 (Database)']);

    final empty = Notifier.morningBrief(snap, settings, day.add(const Duration(days: 1)), at.add(const Duration(days: 1)), s);
    expect(empty, isNull);
  });
}
