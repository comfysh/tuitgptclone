// Pure functions that turn LMS HTML/JSON into models.
// Selectors follow the current lms.tuit.uz markup. Each field is parsed
// defensively so one layout change doesn't break a whole screen.

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'models.dart';

const lmsBase = 'https://lms.tuit.uz';

String _clean(String? s) => (s ?? '')
    .replaceAll('&#039;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String? _nullIfEmpty(String? s) {
  final c = _clean(s);
  return c.isEmpty ? null : c;
}

T? _try<T>(T Function() f) {
  try {
    return f();
  } catch (_) {
    return null;
  }
}

/// Parses "dd-MM-yyyy", "dd.MM.yyyy", "yyyy-MM-dd", optionally followed by "H:m[:s]".
DateTime? parseLmsDate(String? raw) {
  if (raw == null) return null;
  final s = raw.replaceAll(RegExp(r'\(.*?\)'), ' ').trim();
  int h = 0, mi = 0, sec = 0;
  final t = RegExp(r'(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?').firstMatch(s);
  if (t != null) {
    h = int.parse(t[1]!);
    mi = int.parse(t[2]!);
    sec = int.tryParse(t[3] ?? '0') ?? 0;
  }
  var m = RegExp(r'(\d{1,2})[-./](\d{1,2})[-./](\d{4})').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!), h, mi, sec);
  }
  m = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), h, mi, sec);
  }
  return null;
}

double? _num(String? s) {
  if (s == null) return null;
  final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m[0]!.replaceAll(',', '.'));
}

String absoluteUrl(String href) {
  if (href.startsWith('http')) return href;
  if (href.startsWith('//')) return 'https:$href';
  return '$lmsBase${href.startsWith('/') ? '' : '/'}$href';
}

Document parseHtml(String body) => html_parser.parse(body);

/// True when the HTML is the login form (session expired).
bool isLoginPage(String body) =>
    body.contains('name="g-recaptcha-response"') ||
    (body.contains('name="password"') && body.contains('/auth/login'));

String? csrfToken(Document d) =>
    d.querySelector('meta[name="csrf-token"]')?.attributes['content'];

// ---------------------------------------------------------------- info

StudentInfo parseInfo(Document d) {
  final fieldValues = d.querySelectorAll('div.si-field span.si-field-value').map((e) => e.text).toList();
  final infoValues = d.querySelectorAll('div.si-info-item span.si-field-value').map((e) => e.text).toList();
  String? f(List<String> l, int i) => i < l.length ? _nullIfEmpty(l[i]) : null;

  var name = _nullIfEmpty(d.querySelector('div.si-student-name')?.text);
  name ??= _nullIfEmpty(d.querySelector('ul.dropdown-menu > li > div')?.text);

  return StudentInfo(
    fullName: name,
    studentId: _nullIfEmpty(d.querySelector('div.si-student-id')?.text),
    birthDate: f(fieldValues, 0),
    gender: f(fieldValues, 1),
    address: f(fieldValues, 2),
    specialization: f(infoValues, 0),
    studyLanguage: f(infoValues, 1),
    degree: f(infoValues, 2),
    studyForm: f(infoValues, 3),
    year: f(infoValues, 4),
    group: f(infoValues, 5),
    tutor: f(infoValues, 6),
    stipend: _nullIfEmpty(d.querySelector('div.si-info-item span span')?.text),
    photo: d.querySelector('div.si-avatar-wrap img')?.attributes['src'] ??
        d.querySelector('div.card.relative p.text-center img')?.attributes['src'],
  );
}

String? parseAccountName(Document d) => _nullIfEmpty(d.querySelector('ul.dropdown-menu > li > div')?.text);

// ---------------------------------------------------------------- semesters

List<Semester> parseSemesters(Document d) {
  final out = <Semester>[];
  for (final o in d.querySelectorAll('select.js-semester option, select[name="semester_id"] option, select#semester_id option')) {
    final id = int.tryParse(o.attributes['value'] ?? '');
    if (id == null) continue;
    if (out.any((s) => s.id == id)) continue;
    out.add(Semester(id, _clean(o.text), selected: o.attributes.containsKey('selected')));
  }
  return out;
}

// ---------------------------------------------------------------- JSON endpoints

List<dynamic> _dataList(dynamic json, [String key = 'data']) {
  if (json is String) json = jsonDecode(json);
  if (json is Map && json[key] is List) return json[key] as List;
  if (json is List) return json;
  return const [];
}

List<String> _splitHash(dynamic v) {
  final s = (v ?? '').toString();
  return s.isEmpty ? <String>[] : s.split('###').map(_clean).where((e) => e.isNotEmpty).toList();
}

List<Course> parseCourses(dynamic json) => _dataList(json)
    .map((e) => _try(() {
          final m = Map<String, dynamic>.from(e);
          return Course(
            id: (m['id'] as num).toInt(),
            subject: _clean(m['subject']?.toString()),
            subjectId: (m['subject_id'] as num?)?.toInt() ?? 0,
            absenceCount: int.tryParse('${m['attendance'] ?? 0}') ?? 0,
            streams: _splitHash(m['streams']),
            teachers: _splitHash(m['teachers']),
            failed: (m['failed'] ?? m['falied']) == true,
          );
        }))
    .whereType<Course>()
    .toList();

List<Absence> parseAbsences(dynamic json) => _dataList(json)
    .map((e) => _try(() {
          final m = Map<String, dynamic>.from(e);
          return Absence(
            subject: _clean(m['subject']?.toString()),
            subjectId: (m['subject_id'] as num?)?.toInt() ?? 0,
            date: parseLmsDate(m['date']?.toString()),
            lessonType: _nullIfEmpty(m['type']?.toString()),
            theme: _nullIfEmpty(m['calendar']?.toString()),
            themeNumber: int.tryParse('${m['theme_number'] ?? 0}') ?? 0,
          );
        }))
    .whereType<Absence>()
    .toList();

List<ExamFinal> parseFinals(dynamic json) => _dataList(json)
    .map((e) => _try(() {
          final m = Map<String, dynamic>.from(e);
          var info = m['final_info'];
          if (info is String && info.isNotEmpty) info = _try(() => jsonDecode(info));
          final points = (info is List ? info : const [])
              .map((p) => _try(() => TestPoint((p['number'] as num).toInt(), (p['point'] as num))))
              .whereType<TestPoint>()
              .toList();
          return ExamFinal(
            subject: _clean(m['subject']?.toString()),
            subjectId: (m['subject_id'] as num?)?.toInt() ?? 0,
            grade: int.tryParse('${m['f_grade']}'),
            stream: _nullIfEmpty(m['stream']?.toString()),
            room: _nullIfEmpty(m['room']?.toString()),
            date: parseLmsDate(m['date']?.toString()),
            from: _nullIfEmpty(m['from']?.toString()),
            to: _nullIfEmpty(m['to']?.toString()),
            timeLimit: int.tryParse('${m['final_limit']}'),
            testPoints: points,
          );
        }))
    .whereType<ExamFinal>()
    .toList();

final _lectureRe = RegExp(r'\d\d\d$');
final _labRe = RegExp(r'-\w\d$');

LessonType _typeFromStream(String s) {
  if (_lectureRe.hasMatch(s)) return LessonType.lecture;
  if (_labRe.hasMatch(s)) return LessonType.laboratory;
  return LessonType.practice;
}

List<ScheduleItem> parseSchedule(dynamic json) => _dataList(json, 'json')
    .map((e) => _try(() {
          final m = Map<String, dynamic>.from(e);
          final title = _clean((m['title'] ?? '').toString().replaceAll('/', ' ').replaceAll('\n', ' '));
          final start = DateTime.parse(m['start'].toString());
          final subject = RegExp(r'\)[^-]+-')
              .firstMatch(title)
              ?.group(0)
              ?.replaceAll(')', '')
              .replaceAll('-', '')
              .trim();
          final stream = RegExp(r'\D\D\D\d+-*\w*$').firstMatch(title)?.group(0)?.trim();
          final room = RegExp(r'\D-\d+').firstMatch(title)?.group(0)?.trim();
          return ScheduleItem(
            start: start,
            title: title,
            subject: (subject?.isEmpty ?? true) ? null : subject,
            stream: (stream?.isEmpty ?? true) ? null : stream,
            room: (room?.isEmpty ?? true) ? null : room,
            side: WeekSide.fromValue(int.tryParse('${m['type'] ?? 1}')),
            type: _typeFromStream(title),
          );
        }))
    .whereType<ScheduleItem>()
    .toList();

// ---------------------------------------------------------------- course page (assignments)

CoursePage? parseCoursePage(Document d, Course course) {
  if (d.querySelector('div.page-inner > div.panel') == null &&
      d.querySelector('table#simple-table1') == null) {
    return null;
  }
  final h4 = d.querySelectorAll('tbody tr td h4').map((e) => e.text).toList();
  final rating = CourseRating(
    achieved: h4.isNotEmpty ? _num(h4[0]) : null,
    max: h4.length > 1 ? _num(h4[1]) : null,
    ratingPercent: h4.length > 2 ? _num(h4[2]) : null,
    grade: h4.length > 3 ? _num(h4[3])?.toInt() : null,
  );

  final list = <Assignment>[];
  for (final tr in d.querySelectorAll('table#simple-table1 tbody tr:not(.criteria-row)')) {
    final a = _try(() => _parseAssignmentRow(tr, course));
    if (a != null) list.add(a);
  }
  return CoursePage(rating, list);
}

Assignment _parseAssignmentRow(Element tr, Course course) {
  final tds = tr.querySelectorAll('td');
  String td(int i) => i < tds.length ? tds[i].text : '';

  final buttons = tr.querySelectorAll('td.text-center div button');
  double? grade = buttons.isNotEmpty ? _num(buttons[0].text) : null;
  double? maxGrade = buttons.length > 1 ? _num(buttons[1].text) : null;

  LmsFile? taskFile;
  final taskA = tr.querySelector('td div a');
  if (taskA != null && _clean(taskA.text).isNotEmpty && taskA.attributes['href'] != null) {
    taskFile = LmsFile(_clean(taskA.text), absoluteUrl(taskA.attributes['href']!));
  }

  int? uploadId;
  LmsFile? uploaded;
  final directA = tr.querySelector('td > a');
  if (directA != null) {
    final href = directA.attributes['href'] ?? '#';
    if (href == '#') {
      uploadId = int.tryParse(directA.attributes['data-id'] ?? '');
    } else {
      uploaded = LmsFile(_clean(directA.text), absoluteUrl(href));
    }
  }
  uploadId ??= int.tryParse(tr.querySelector('button.js-btn-upload')?.attributes['data-id'] ?? '') ??
      int.tryParse(tr.querySelector('[data-id]')?.attributes['data-id'] ?? '');

  return Assignment(
    courseId: course.id,
    courseName: course.subject,
    taskType: _nullIfEmpty(td(0)),
    teacher: _nullIfEmpty(td(1)),
    name: _nullIfEmpty(tr.querySelector('td div p')?.text) ?? _nullIfEmpty(td(2)),
    taskFile: taskFile,
    deadline: parseLmsDate(td(3)),
    grade: grade,
    maxGrade: maxGrade,
    uploadId: uploadId,
    uploadedFile: uploaded,
    failed: tr.querySelector('td > span') != null,
  );
}

// ---------------------------------------------------------------- course calendar (lessons + files)

List<Lesson> parseLessons(Document d) {
  final out = <Lesson>[];
  const tabs = {'lecture': LessonType.lecture, 'practice': LessonType.practice, 'lab': LessonType.laboratory};
  tabs.forEach((id, type) {
    for (final tr in d.querySelectorAll('div#$id tbody > tr')) {
      final l = _try(() {
        final tds = tr.querySelectorAll('td');
        if (tds.isEmpty) return null;
        final files = tr
            .querySelectorAll('td a')
            .where((a) => (a.attributes['href'] ?? '#') != '#')
            .map((a) => LmsFile(_clean(a.text).isEmpty ? 'file' : _clean(a.text), absoluteUrl(a.attributes['href']!)))
            .toList();
        return Lesson(
          type: type,
          number: int.tryParse(_clean(tds[0].text)) ?? 0,
          theme: _nullIfEmpty(tr.querySelector('td p')?.text) ?? (tds.length > 1 ? _nullIfEmpty(tds[1].text) : null),
          date: tds.length > 2 ? parseLmsDate(tds[2].text) : null,
          files: files,
        );
      });
      if (l != null) out.add(l);
    }
  });
  return out;
}

// ---------------------------------------------------------------- study plan

List<Discipline> parseStudyPlan(Document d) {
  final out = <Discipline>[];
  for (final card in d.querySelectorAll('div.page-inner div.card')) {
    final semester = _nullIfEmpty(card.querySelector('div.card-body > p')?.text) ??
        _nullIfEmpty(card.querySelector('.card-title, .card-header')?.text);
    for (final tr in card.querySelectorAll('table tbody tr')) {
      final title = _nullIfEmpty(tr.querySelector('td')?.text);
      if (title == null) continue;
      out.add(Discipline(
        title: title,
        semester: semester,
        credits: _num(tr.querySelector('td.text-center')?.text)?.toInt(),
        grade: _num(tr.querySelector('td.text-right')?.text)?.toInt(),
      ));
    }
  }
  return out;
}

// ---------------------------------------------------------------- news

/// Returns the URLs of news items on the dashboard listing.
List<String> parseNewsLinks(Document d) => d
    .querySelectorAll('div.row div.col-md-4 div.card')
    .map((c) => c.querySelector('div.d-flex a')?.attributes['href'] ?? c.querySelector('a')?.attributes['href'])
    .whereType<String>()
    .map(absoluteUrl)
    .toSet()
    .toList();

NewsItem? parseNewsPage(Document d, String url) {
  final title = _nullIfEmpty(d.querySelector('h4.panel__title')?.text) ??
      _nullIfEmpty(d.querySelector('.panel-title, h4, h3')?.text);
  if (title == null) return null;
  return NewsItem(
    title: title,
    body: _nullIfEmpty(d.querySelector('div.panel-body blockquote div')?.text) ??
        _nullIfEmpty(d.querySelector('div.panel-body')?.text),
    date: parseLmsDate(d.querySelector('div.panel-body blockquote footer cite')?.text),
    url: url,
  );
}
