import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/core/insights.dart';
import 'package:tuitmate/core/storage.dart';
import 'package:tuitmate/core/strings.dart';
import 'package:tuitmate/core/strings/hub.dart';
import 'package:tuitmate/lms/changes.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/snapshot.dart';
import 'package:tuitmate/services/inbox.dart';

void main() {
  late Directory tmp;
  late AppStorage storage;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tuitmate_inbox');
    storage = AppStorage.useDirectory(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('changes are kept newest first; the same change again replaces the old one', () async {
    final t0 = DateTime(2026, 10, 20, 9);
    await Inbox.record([
      LmsChange(ChangeKind.newAssignment, '1|#5', 'Database', 'Lab 3', when: DateTime(2026, 10, 25)),
      const LmsChange(ChangeKind.newFile, 'file|https://x/1.pdf', 'Database', '1.pdf'),
      LmsChange(ChangeKind.reminder, 'rem3|1|#5|9|x', 'Database', 'Lab 3', when: DateTime(2026, 10, 25), value: 3),
    ], storage, now: t0);
    var items = await Inbox.load(storage);
    expect(items.map((i) => i.kind), [ChangeKind.newAssignment, ChangeKind.newFile]); // reminders are not kept
    expect(items.every((i) => !i.read), isTrue);

    await Inbox.markRead(storage, ids: {items.first.id});
    await Inbox.record([
      LmsChange(ChangeKind.deadlineChanged, '1|#5', 'Database', 'Lab 3', when: DateTime(2026, 10, 27)),
      const LmsChange(ChangeKind.newFile, 'file|https://x/1.pdf', 'Database', '1.pdf'),
    ], storage, now: t0.add(const Duration(hours: 2)));
    items = await Inbox.load(storage);
    expect(items.map((i) => i.kind), [ChangeKind.deadlineChanged, ChangeKind.newFile, ChangeKind.newAssignment]);
    expect(items[0].when, DateTime(2026, 10, 27));
    expect(items[1].at, t0.add(const Duration(hours: 2))); // moved up, unread again
    expect(items[2].read, isTrue);
    expect(items.where((i) => i.kind == ChangeKind.newFile), hasLength(1));
  });

  test('the inbox keeps at most 300 items and survives a broken file', () async {
    await Inbox.record([for (var i = 0; i < 320; i++) LmsChange(ChangeKind.news, 'n$i', 'News $i', '')], storage);
    expect(await Inbox.load(storage), hasLength(Inbox.maxItems));
    storage.inboxFile.writeAsStringSync('{not json');
    expect(await Inbox.load(storage), isEmpty);
    expect(await Inbox.markRead(storage), isEmpty); // nothing to mark, nothing overwritten
    expect(storage.inboxFile.readAsStringSync(), '{not json');
  });

  test('first run: the latest news, already read; never again after that', () async {
    final now = DateTime(2026, 10, 23);
    final snap = LmsSnapshot(
      news: [
        for (var i = 0; i < 7; i++) NewsItem(title: 'N$i', date: now.subtract(Duration(days: i)), url: 'https://lms/n/$i'),
      ],
      updatedAt: now,
    );
    await Inbox.seed(snap, storage);
    final items = await Inbox.load(storage);
    expect(items.map((i) => i.subject), ['N0', 'N1', 'N2', 'N3', 'N4']);
    expect(items.every((i) => i.read), isTrue);
    await Inbox.record([const LmsChange(ChangeKind.newAbsence, 'a', 'Physics', 'Lab')], storage);
    await Inbox.seed(snap, storage);
    expect(await Inbox.load(storage), hasLength(6));
  });

  test('workload: open tasks and exams per week, from this week on', () {
    final now = DateTime(2026, 10, 21, 12); // Wednesday
    Assignment task(DateTime due, {bool done = false}) => Assignment(
          courseId: 1,
          courseName: 'DB',
          name: 'T${due.day}',
          deadline: due,
          uploadId: due.day,
          uploadedFile: done ? const LmsFile('a.docx', 'https://x/a.docx') : null,
        );
    final snap = LmsSnapshot(
      coursePages: {
        1: CoursePage(const CourseRating(), [
          task(DateTime(2026, 10, 20, 23, 59)), // Tuesday: already past
          task(DateTime(2026, 10, 24, 23, 59)),
          task(DateTime(2026, 10, 26, 23, 59)),
          task(DateTime(2026, 10, 28, 23, 59), done: true), // submitted: not open
          task(DateTime(2026, 11, 1, 23, 59)),
        ]),
      },
      finals: [ExamFinal(subject: 'DB', subjectId: 1, date: DateTime(2026, 11, 3), from: '09:00')],
      updatedAt: now,
    );
    final weeks = workload(snap, now, weeks: 3);
    expect(weeks.map((w) => w.monday), [DateTime(2026, 10, 19), DateTime(2026, 10, 26), DateTime(2026, 11, 2)]);
    expect(weeks.map((w) => (w.tasks, w.exams)), [(1, 0), (2, 0), (0, 1)]);
    expect(busiestWeek(weeks)!.monday, DateTime(2026, 11, 2)); // an exam weighs as much as three tasks
    expect(busiestWeek(workload(LmsSnapshot(updatedAt: now), now)), isNull);
  });

  test('the navigation texts exist in every language', () {
    for (final lang in ['uz', 'ru']) {
      for (final key in hubStrings['en']!.keys) {
        expect(hubStrings[lang]!.containsKey(key), isTrue, reason: '$lang is missing $key');
      }
      expect(hubStrings[lang]!.keys.toSet().difference(hubStrings['en']!.keys.toSet()), isEmpty);
    }
    // Every key the navigation uses resolves to a real text.
    for (final key in ['hubPlan', 'hubInbox', 'hubStudy', 'gradesShort', 'ibUpdates', 'scheduleShort', 'deadlines', 'navFiles']) {
      for (final lang in ['en', 'uz', 'ru']) {
        expect(S(lang)[key], isNot(key), reason: '$lang: $key');
      }
    }
  });
}
