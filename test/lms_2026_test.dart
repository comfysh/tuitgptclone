// Parsers against the lms.tuit.uz layout of the 2026 redesign.
// Fixtures copy the real page structure with made-up values.

import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/core/insights.dart';
import 'package:tuitmate/lms/models.dart';
import 'package:tuitmate/lms/parsers.dart';

const _course = Course(id: 30893, subject: 'Database', subjectId: 62);

const _coursePage = '''
<html><head><meta name="csrf-token" content="t0k"></head><body><div class="page-inner">
<div class="sc-page-header"><h3><span>Assignments /</span> Database</h3></div>
<div class="sc-summary">
  <div class="sc-summary-box"><div class="sc-box-label">Achieved points</div><div class="sc-box-value">5</div></div>
  <div class="sc-summary-box"><div class="sc-box-label">Max. points</div><div class="sc-box-value">40</div></div>
  <div class="sc-summary-box"><div class="sc-box-label">Rating</div><div class="sc-box-value">12.5<small>%</small></div></div>
  <div class="sc-summary-box"><div class="sc-box-label">Current grade</div><div class="sc-box-value sc-grade-2">2</div></div>
</div>
<div class="sc-card"><table class="sc-table" id="simple-table1"><tbody>
<tr>
  <td><span class="sc-badge">Practice</span></td>
  <td style="font-size:13px;">Teacher One</td>
  <td><div class="sc-activity-title">1 practical task</div>
      <a href="https://lms.tuit.uz/uploads/samples/KK/Kq/V3/1790614926.pdf" class="btn btn-default btn-xs"><i class="fa fa-download"></i> 1 practica...</a></td>
  <td><span class="sc-deadline"><i class="fa fa-calendar-o"></i>07-10-2026 23:59:59</span></td>
  <td><div class="sc-score"> 5 <span class="sc-max">/ 5</span></div>
      <div><button onclick="toggleCriteria(150095)" class="btn btn-default btn-xs"><i class="fa fa-list-ul"></i> Criteria</button></div></td>
  <td><a href="https://lms.tuit.uz/uploads/activities/KK/Sr/Vi/1791259300.docx" class="btn btn-default btn-sm"><i class="fa fa-file-o"></i> My answer...</a></td>
</tr>
<tr class="criteria-row sc-criteria-row" id="criteria-150095" style="display:none;"><td colspan="6"><div class="sc-criteria-list">
  <span>Criteria:</span>
  <div class="sc-criteria-item">Understanding the topic <strong>2</strong></div>
  <div class="sc-criteria-item">Defense of the task ( <strong>3</strong></div>
</div></td></tr>
<tr>
  <td><span class="sc-badge">Practice</span></td>
  <td>Teacher One</td>
  <td><div class="sc-activity-title">2-practical work</div>
      <a href="https://lms.tuit.uz/uploads/samples/KK/KP/Ha/1791650910.zip" class="btn btn-default btn-xs"><i class="fa fa-download"></i> 2-practica...</a></td>
  <td><span class="sc-deadline">28-10-2026 23:59:59</span></td>
  <td><div class="sc-score"><span style="color:#a0aec0">—</span><span class="sc-max">/ 5</span></div>
      <div><button onclick="toggleCriteria(153541)" class="btn btn-default btn-xs">Criteria</button></div></td>
  <td><a href="#" data-target="#uploadModal" data-toggle="modal" class="btn btn-primary btn-sm sc-btn-upload js-btn-upload" data-id="153541"><i class="fa fa-upload"></i> Upload assignment</a></td>
</tr>
<tr>
  <td><span class="sc-badge">Practice</span></td>
  <td>Teacher Two</td>
  <td><div class="sc-activity-title">1-practice</div></td>
  <td><span class="sc-deadline">25-10-2026 23:59:59</span></td>
  <td><div class="sc-score"><span>—</span><span class="sc-max">/ 5</span></div></td>
  <td><a href="https://lms.tuit.uz/uploads/activities/KK/cB/M2/1792586029.zip" class="btn btn-default btn-sm">My_file...</a>
      <div><button href="#" class="btn btn-default btn-xs js-btn-upload" data-id="155787">Resend</button></div></td>
</tr>
<tr>
  <td><span class="sc-badge">Lecture</span></td>
  <td>Teacher Two</td>
  <td><div class="sc-activity-title">Old task</div></td>
  <td><span class="sc-deadline">01-10-2026 23:59:59</span></td>
  <td><div class="sc-score"><span>—</span><span class="sc-max">/ 10</span></div></td>
  <td><span class="sc-expired"><i class="fa fa-clock-o"></i> Expired</span></td>
</tr>
</tbody></table></div></div></body></html>''';

const _calendar = '''
<div class="page-inner"><div class="cal-panel">
<ul class="cal-tabs" role="tablist">
  <li class="active"><a href="#lecture" data-toggle="tab">Lecture <span class="cal-count">2</span></a></li>
  <li><a href="#lab" data-toggle="tab">Laboratory <span class="cal-count">1</span></a></li>
</ul>
<div class="tab-content">
  <div role="tabpanel" class="tab-pane fade active in" id="lecture"><ul class="cal-list">
    <li class="cal-item"><div class="cal-row"><span class="cal-num">1</span>
      <span class="cal-body"><span class="cal-title">Introduction</span></span>
      <span class="cal-meta"><span class="cal-date">15.09.2026</span><span class="cal-toggle-spacer"></span></span></div></li>
    <li class="cal-item"><button type="button" class="cal-row" data-toggle="collapse" data-target="#cal-lecture-533690-1">
      <span class="cal-num">2</span><span class="cal-body"><span class="cal-title">Relational model</span></span>
      <span class="cal-meta"><span class="cal-date">17.09.2026</span><span class="cal-res-count"><i class="fa fa-paperclip"></i>2</span></span></button>
      <div class="collapse cal-collapse" id="cal-lecture-533690-1"><div class="cal-drawer">
        <a href="https://dl.tuit.uz/subject-resources/533690/aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7b.pptx" class="cal-res"><i class="fa fa-file-o"></i><span class="cal-res-name">2-Lecture</span><span class="cal-res-go">Download</span></a>
        <a href="https://dl.tuit.uz/subject-resources/533690/cD4eF6gH8iJ0kL2mN4oP6qR8sT0uV2wX4yZ6aB8c.pdf" class="cal-res"><span class="cal-res-name">Practice_9.1</span><span class="cal-res-go">Download</span></a>
      </div></div></li>
  </ul></div>
  <div role="tabpanel" class="tab-pane fade" id="lab"><ul class="cal-list">
    <li class="cal-item"><div class="cal-row"><span class="cal-num">1</span><span class="cal-body"><span class="cal-title">Lab setup</span></span>
      <span class="cal-meta"><span class="cal-date">19.09.2026</span></span></div></li>
  </ul></div>
</div></div></div>''';

const _studyPlan = '''
<div class="page-inner">
<div class="sp-header"><h3 class="sp-title">Individual study plan</h3>
  <div class="sp-header-right"><div class="gpa-badge">GPA: <span>3.60</span></div></div></div>
<div class="semester-grid">
  <div class="semester-card"><div class="semester-card-header"><span class="semester-num">I</span> <span class="semester-label">semester</span></div>
    <table class="plan-table"><tbody>
      <tr><td class="td-subject">Calculus 1</td><td class="td-credit">6</td><td class="td-grade"><span class="grade-badge grade-good">4</span></td></tr>
      <tr><td class="td-subject">Physics 1 (6 kr)</td><td class="td-credit">6</td><td class="td-grade"><span class="grade-badge grade-fail">2</span></td></tr>
    </tbody></table></div>
  <div class="semester-card"><div class="semester-card-header"><span class="semester-num">II</span> <span class="semester-label">semester</span></div>
    <table class="plan-table"><tbody>
      <tr><td class="td-subject">Database</td><td class="td-credit">4</td><td class="td-grade"><span class="grade-empty">—</span></td></tr>
    </tbody></table></div>
</div></div>''';

const _newsList = '''
<div class="page-inner"><div class="news-grid">
  <div class="news-card"><h5 class="news-card-title">Exam schedule published</h5><p class="news-card-excerpt">Exam schedule published</p>
    <div class="news-card-footer"><span class="news-card-date">10.06.2026</span><a class="news-card-link" href="https://lms.tuit.uz/dashboard/news/detailed/81">More</a></div></div>
  <div class="news-card"><h5 class="news-card-title"></h5><p class="news-card-excerpt"></p>
    <div class="news-card-footer"><span class="news-card-date">01.06.2026</span><a class="news-card-link" href="/dashboard/news/detailed/80">More</a></div></div>
</div></div>''';

const _newsDetail = '''
<div class="page-inner"><div class="news-article">
  <div class="news-article-header"><h1 class="news-article-title">Exam schedule published</h1><div class="news-article-meta">Published — 10.06.2026</div></div>
  <div class="news-article-body"><p>Dear students,</p><p>the schedule is <b>online</b>.</p><ul><li>Bring ID</li></ul></div>
</div></div>''';

const _info = '''
<div class="page-inner">
<div class="si-profile-card"><div class="si-avatar-wrap"><img src="data:image/png;base64,AAAA"></div>
  <div class="si-student-name">Familiya Ism Otasining (chet el fuqarosi)</div><div class="si-student-id">№ 12345-25</div>
  <div class="si-field"><span class="si-field-label">Birth date</span><span class="si-field-value">01-01-2007</span></div>
  <div class="si-field"><span class="si-field-label">Address(temporary)</span><span class="si-field-value">Dorm 4</span></div>
</div>
<div class="si-info-card">
  <div class="si-info-item"><span class="si-field-label">Group</span><span class="si-field-value">700-25 ABC</span></div>
  <div class="si-info-item"><span class="si-field-label">Year</span><span class="si-field-value">2</span></div>
  <div class="si-info-item"><span class="si-field-label">Stipend</span><span class="si-field-value"><span class="si-badge no"><i></i> Not</span></span></div>
</div>
<div class="si-card"><div class="si-contract-header"><span>Contract</span><span class="si-contract-badge">2026-2027</span></div>
  <div class="si-empty-contract">The contract has not been generated yet.</div></div>
<details class="si-acc-item"><summary>2025-2026 <span class="si-acc-sum">Fully paid</span></summary><div class="si-acc-body">
  <div class="si-stat-grid">
    <div class="si-stat total"><div class="si-stat-amount">10 000 000 <small>UZS</small></div></div>
    <div class="si-stat paid"><div class="si-stat-amount">10 000 000 <small>UZS</small></div></div>
    <div class="si-stat debt"><div class="si-stat-amount">0 <small>UZS</small></div></div>
  </div><div class="si-progress-pct">100%</div></div></details>
</div>''';

void main() {
  test('course page: rating, tasks, criteria and states', () {
    final page = parseCoursePage(parseHtml(_coursePage), _course)!;
    expect(page.rating.achieved, 5);
    expect(page.rating.max, 40);
    expect(page.rating.ratingPercent, 12.5);
    expect(page.rating.grade, 2);
    expect(page.assignments.length, 4);

    final graded = page.assignments[0];
    expect(graded.name, '1 practical task');
    expect(graded.grade, 5);
    expect(graded.maxGrade, 5);
    expect(graded.activityId, 150095);
    expect(graded.taskFile!.name, '1 practica….pdf');
    expect(graded.uploadedFile!.url, endsWith('1791259300.docx'));
    expect(graded.uploadId, isNull);
    expect(graded.criteria.map((c) => c.points), [2, 3]);
    expect(graded.criteria.last.text, 'Defense of the task');
    expect(graded.status, AssignmentStatus.graded);

    final open = page.assignments[1];
    expect(open.grade, isNull);
    expect(open.uploadId, 153541);
    expect(open.uploadedFile, isNull);
    expect(open.status, AssignmentStatus.notSubmitted);

    final resend = page.assignments[2];
    expect(resend.uploadId, 155787);
    expect(resend.uploadedFile, isNotNull);
    expect(resend.status, AssignmentStatus.submitted);

    final expired = page.assignments[3];
    expect(expired.expired, isTrue);
    expect(expired.isOverdue, isTrue);
    expect(expired.canUpload, isFalse);
  });

  test('empty course page means no tasks, not an error', () {
    final page = parseCoursePage(parseHtml('<div class="page-inner"><style>.x{}</style></div>'), _course);
    expect(page, isNotNull);
    expect(page!.assignments, isEmpty);
  });

  test('calendar: lessons by part with teacher files', () {
    final l = parseLessons(parseHtml(_calendar));
    expect(l.length, 3);
    expect(l[1].type, LessonType.lecture);
    expect(l[1].number, 2);
    expect(l[1].date, DateTime(2026, 9, 17));
    expect(l[1].files.map((f) => f.name), ['2-Lecture.pptx', 'Practice_9.1.pdf']);
    expect(l[2].type, LessonType.laboratory);
  });

  test('schedule entries and the current week', () {
    final json = {
      'view': '<div class="calendar-wrap"><div class="cal-week is-even"><span class="cal-week-range">19.10.2026 – 24.10.2026</span>'
          '<span class="cal-week-label">Even week</span></div></div>',
      'json': [
        {'title': '(D-312)\nLinear Algebra (6 credits)-LIA402-1', 'start': '2026-10-19T09:30:00', 'type': 1, 'className': 'bg-teal'},
        {'title': '(D/-312)\nLinear Algebra (6 credits)/-LIA402/', 'start': '2026-10-19T11:00:00', 'type': 2, 'className': 'bg-brown'},
        {'title': '(A-328)\nElectronics and circuits-ELC402-L1', 'start': '2026-10-21T11:00:00', 'type': 3},
      ],
    };
    final s = parseSchedule(json);
    expect(s[0].subject, 'Linear Algebra (6 credits)');
    expect(s[0].room, 'D-312');
    expect(s[0].stream, 'LIA402-1');
    expect(s[0].type, LessonType.practice);
    expect(s[1].room, 'D-312');
    expect(s[1].side, WeekSide.left);
    expect(s[1].type, LessonType.lecture);
    expect(s[2].type, LessonType.laboratory);
    expect(s[2].side, WeekSide.right);
    final week = parseWeekInfo(json)!;
    expect(week.$1, DateTime(2026, 10, 19));
    expect(week.$2, WeekSide.right);
  });

  test('study plan with GPA', () {
    final d = parseHtml(_studyPlan);
    final plan = parseStudyPlan(d);
    expect(plan.length, 3);
    expect(plan[0].semester, 'I semester');
    expect(plan[1].credits, 6); // not the "6" in the title
    expect(plan[2].grade, isNull);
    expect(parseStudyPlanSummary(d).gpa, 3.6);
    expect(estimatedGpa(plan), closeTo(2.0, 0.001)); // (6*4 + 6*0) / 12
  });

  test('news list and article', () {
    final list = parseNewsList(parseHtml(_newsList));
    expect(list.length, 1); // untitled post skipped
    expect(list.first.url, 'https://lms.tuit.uz/dashboard/news/detailed/81');
    expect(list.first.date, DateTime(2026, 6, 10));
    final n = parseNewsPage(parseHtml(_newsDetail), 'https://lms.tuit.uz/dashboard/news/detailed/81')!;
    expect(n.title, 'Exam schedule published');
    expect(n.body, 'Dear students,\nthe schedule is online.\n• Bring ID');
    expect(n.key, list.first.key);
  });

  test('profile by labels and tuition contract', () {
    final d = parseHtml(_info);
    final i = parseInfo(d);
    expect(i.fullName, 'Familiya Ism Otasining');
    expect(i.studentId, '12345-25');
    expect(i.tempAddress, 'Dorm 4');
    expect(i.group, '700-25 ABC');
    expect(i.stipend, 'Not');
    final c = parseContracts(d);
    expect(c.length, 2);
    expect(c[0].current, isTrue);
    expect(c[0].hasData, isFalse);
    expect(c[0].notice, isNotNull);
    expect(c[1].year, '2025-2026');
    expect(c[1].total, 10000000);
    expect(c[1].debt, 0);
    expect(c[1].status, 'Fully paid');
  });

  test('grade forecast', () {
    final page = parseCoursePage(parseHtml(_coursePage), _course)!;
    final f = forecastFor(page);
    expect(f.percent, closeTo(12.5, 0.01));
    expect(f.openPoints, 20); // 5 + 5 + 10 still ungraded
    final five = f.targets.firstWhere((t) => t.grade == 5);
    expect(five.pointsNeeded, closeTo(29.4, 0.01)); // 86% of 40 = 34.4, minus 5
    expect(five.reachable, isFalse); // only 20 points still open
    expect(f.targets.firstWhere((t) => t.grade == 3).reachable, isTrue); // needs 17
  });
}
