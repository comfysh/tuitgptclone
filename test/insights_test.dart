import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/core/insights.dart';
import 'package:tuitmate/lms/models.dart';

Assignment task(String name, {double? grade, double max = 10, int dueInDays = 3, bool submitted = false, bool midterm = false, bool noDeadline = false}) =>
    Assignment(
      courseId: 1,
      courseName: 'Math',
      name: name,
      grade: grade,
      maxGrade: max,
      deadline: noDeadline ? null : DateTime.now().add(Duration(days: dueInDays)),
      uploadedFile: submitted ? const LmsFile('a.pdf', 'https://x/a.pdf') : null,
      midterm: midterm,
    );

void main() {
  test('open task rule: not submitted, not graded, deadline not passed (none counts)', () {
    expect(isOpenTask(task('a')), isTrue);
    expect(isOpenTask(task('b', noDeadline: true)), isTrue);
    expect(isOpenTask(task('c', submitted: true)), isFalse);
    expect(isOpenTask(task('d', grade: 5)), isFalse);
    expect(isOpenTask(task('e', dueInDays: -1)), isFalse);
  });

  test('standing ignores tasks that are still open (unlike the LMS rating)', () {
    // Real case: 4/8 graded, a 6-point task not due yet. LMS: 4/14 = 28.6 % (grade 2).
    final page = CoursePage(const CourseRating(achieved: 4, max: 14, ratingPercent: 28.6, grade: 2), [
      task('graded', grade: 4, max: 8, dueInDays: -4),
      task('open', max: 6),
    ]);
    final st = standingFor(page);
    expect(st.percent, 50);
    expect(st.grade, 2);

    final good = CoursePage(const CourseRating(achieved: 5, max: 40), [
      task('p1', grade: 5, max: 5, dueInDays: -10),
      for (var i = 0; i < 5; i++) task('open $i', max: 5, dueInDays: 5 + i),
    ]);
    expect(standingFor(good).grade, 5); // 12.5 % on the LMS, 100 % of the graded work

    // Nothing graded or missed yet: no expected grade at all.
    expect(standingFor(CoursePage(const CourseRating(), [task('x')])).grade, isNull);
    expect(standingFor(null).grade, isNull);
  });

  test('standing counts a missed task as zero, but not a midterm', () {
    final page = CoursePage(const CourseRating(), [
      task('done', grade: 9, max: 10, dueInDays: -9),
      task('missed', max: 10, dueInDays: -1),
      task('midterm', max: 10, dueInDays: -1, midterm: true),
    ]);
    expect(standingFor(page).percent, 45);
  });

  test('forecast does not count points of missed tasks as still open', () {
    final page = CoursePage(const CourseRating(achieved: 9, max: 30), [
      task('done', grade: 9, max: 10, dueInDays: -9),
      task('missed', max: 10, dueInDays: -1),
      task('open', max: 10),
    ]);
    final f = forecastFor(page);
    expect(f.openPoints, 10);
    expect(f.bestPercent, closeTo(63.3, 0.1));
  });
}
