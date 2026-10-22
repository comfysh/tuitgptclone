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

/// Lower-case label without apostrophes and punctuation:
/// "Address(temporary)" -> "address temporary", "Ta'lim tili" -> "talim tili".
String _labelKey(String? s) => _clean(s)
    .toLowerCase()
    .replaceAll(RegExp(r"['‘’ʻʼ`]"), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// StudentInfo field named by a /student/info label (en / uz / ru), or null.
/// Order matters: temporary address before address, language ("Ta'lim tili")
/// before form ("Ta'lim shakli"), tutor/group before year.
String? _infoKey(String? label) {
  final l = _labelKey(label);
  if (l.isEmpty) return null;
  final words = l.split(' ');
  bool has(List<String> stems) => stems.any(l.contains);
  if (has(const ['birth', 'tugil', 'рожд'])) return 'birthDate';
  if (has(const ['gender', 'jins']) || words.contains('sex') || words.contains('пол')) return 'gender';
  if (has(const ['address', 'manzil', 'адрес'])) {
    return has(const ['temporar', 'vaqtin', 'времен', 'current', 'joriy', 'текущ']) ? 'tempAddress' : 'address';
  }
  if (has(const ['stipend', 'стипенд'])) return 'stipend';
  if (has(const ['tutor', 'tyutor', 'тьютор', 'kurator', 'curator', 'куратор'])) return 'tutor';
  if (has(const ['speciali', 'mutaxassis', 'yonalish', 'специальн', 'направлен'])) return 'specialization';
  if (has(const ['language', 'tili', 'язык'])) return 'studyLanguage';
  if (has(const ['degree', 'daraja', 'bosqich', 'степен', 'уровен'])) return 'degree';
  if (has(const ['type of study', 'form of', 'study form', 'education form', 'shakl', 'форма', 'вид обуч'])) {
    return 'studyForm';
  }
  if (has(const ['group', 'guruh', 'групп'])) return 'group';
  if (has(const ['admission', 'qabul', 'поступ'])) return null; // "year of admission" is not the study year
  if (has(const ['year', 'kurs', 'курс'])) return 'year';
  return null;
}

/// Text of a span.si-field-value. The stipend value is a badge
/// (<span class="si-badge yes|no"><i …></i> Not</span>); without text its class decides.
String? _infoValue(Element? v) {
  if (v == null) return null;
  final text = _clean(v.text);
  if (text.isNotEmpty && text != '-' && text != '—') return text;
  final badge = v.querySelector('.si-badge');
  if (badge == null) return null;
  if (badge.classes.contains('yes')) return 'Yes';
  if (badge.classes.contains('no')) return 'No';
  return null;
}

/// /student/info (2026 layout): .si-profile-card (.si-avatar-wrap img, .si-student-name,
/// .si-student-id, .si-field rows) and .si-info-card (.si-info-item rows); each row is
/// span.si-field-label + span.si-field-value.
StudentInfo parseInfo(Document d) {
  final values = <String, String>{};

  // Match each row by its label; rows with an unknown label (new wording or
  // language) fall back to their position in the current layout.
  void collect(String rowSelector, List<String> order) {
    final rows = d.querySelectorAll(rowSelector);
    final unknown = <int, String>{};
    for (var i = 0; i < rows.length; i++) {
      final value = _infoValue(rows[i].querySelector('.si-field-value'));
      if (value == null) continue;
      final key = _infoKey(rows[i].querySelector('.si-field-label')?.text);
      if (key != null) {
        values.putIfAbsent(key, () => value);
      } else {
        unknown[i] = value;
      }
    }
    unknown.forEach((i, value) {
      if (i < order.length) values.putIfAbsent(order[i], () => value);
    });
  }

  collect('.si-field', const ['birthDate', 'gender', 'address', 'tempAddress']);
  collect('.si-info-item',
      const ['specialization', 'studyLanguage', 'degree', 'studyForm', 'year', 'group', 'tutor', 'stipend']);

  var name = _nullIfEmpty(d.querySelector('.si-student-name')?.text);
  if (name != null) {
    // "Surname Name Patronymic (chet el fuqarosi)": the bracket is a status note, not the name.
    name = _nullIfEmpty(name.replaceFirst(RegExp(r'\s*\([^()]*\)$'), '')) ?? name;
  }
  final rawId = _nullIfEmpty(d.querySelector('.si-student-id')?.text);
  if (name == null && rawId == null && values.isEmpty) {
    // Layout changed or wrong page: fail so the sync keeps the cached copy.
    throw const FormatException('Student info: profile block (.si-student-name / .si-field) not found');
  }
  name ??= _nullIfEmpty(d.querySelector('ul.dropdown-menu > li > div')?.text); // header account name

  final studentId = rawId == null ? null : _nullIfEmpty(rawId.replaceFirst(RegExp(r'^(?:№|#|No\.)\s*'), ''));

  String? photo;
  for (final sel in const [
    '.si-avatar-wrap img', // profile card
    '.navbar-right a.dropdown-float img', // header avatar: same picture, on every page
  ]) {
    final src = d.querySelector(sel)?.attributes['src']?.trim();
    if (src == null || src.isEmpty) continue;
    photo = src.startsWith('data:') ? src.replaceAll(RegExp(r'\s+'), '') : absoluteUrl(src);
    break;
  }

  return StudentInfo(
    fullName: name,
    studentId: studentId,
    birthDate: values['birthDate'],
    gender: values['gender'],
    address: values['address'],
    tempAddress: values['tempAddress'],
    specialization: values['specialization'],
    studyLanguage: values['studyLanguage'],
    degree: values['degree'],
    studyForm: values['studyForm'],
    year: values['year'],
    group: values['group'],
    tutor: values['tutor'],
    stipend: values['stipend'],
    photo: photo,
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
            // The LMS lists a teacher once per class type (lecture, practice…).
            teachers: _splitHash(m['teachers']).toSet().toList(),
            failed: (m['failed'] ?? m['falied']) == true,
            questionsUrl: m['download_questions_url'] is String && (m['download_questions_url'] as String).isNotEmpty
                ? absoluteUrl(m['download_questions_url'] as String)
                : null,
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
            excused: '${m['has_reason'] ?? 0}' == '1' || m['has_reason'] == true,
          );
        }))
    .whereType<Absence>()
    .toList();

// ---------------------------------------------------------------- finals
// /student/finals renders an empty table#datatable and fills it from
// GET /student/finals/data?semester_id=N -> {draw, recordsTotal, recordsFiltered, data:[row]}.
// Columns: subject | stream ("Group") | date | from ("Start time") | room | f_grade ("Grade")
// | info button when final_info is truthy. Info modal: final_limit ("… N min.") and
// $.each(JSON.parse(final_info)) -> item.number / item.point. `to` and subject_id are no
// longer rendered but are still read. DataTables inserts cells as HTML, so strip markup.

/// Plain text of a JSON cell: null/false -> '', entities decoded, markup removed.
/// With [dropActions], embedded action buttons (.js-sign-btn, .js-appeal-show) are dropped first.
String _cellText(dynamic v, {bool dropActions = true}) {
  if (v == null || v == false) return '';
  final raw = v.toString();
  if (!raw.contains('<') && !raw.contains('&')) return _clean(raw);
  final text = _try(() {
    final f = html_parser.parseFragment(raw);
    if (dropActions) {
      for (final b in f.querySelectorAll('.js-sign-btn, .js-appeal-show')) {
        b.remove();
      }
    }
    return f.text;
  });
  return _clean(text ?? raw);
}

/// Like [_cellText] but null for empty cells and dash placeholders.
String? _cellOrNull(dynamic v) {
  final s = _cellText(v);
  return (s.isEmpty || s == '-' || s == '—' || s == '–' || s.toLowerCase() == 'null') ? null : s;
}

/// Numeric cell: a JSON number as-is, otherwise the first number in its text.
num? _numCell(dynamic v) => v is num ? v : _num(_cellText(v, dropActions: false));

/// "9:00", "09:00:00", "2026-12-20 09:00:00" -> "09:00"; text without a time is returned unchanged.
String? _hhmm(String? s) {
  if (s == null) return null;
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(s);
  return m == null ? s : '${m[1]!.padLeft(2, '0')}:${m[2]}';
}

dynamic _jsonOrNull(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

/// final_info: JSON string (or already-decoded list/map) of {number, point}.
/// The page walks it with $.each, so a map of such objects is accepted too.
List<TestPoint> _finalPoints(dynamic info) {
  final decoded = info is String ? (info.trim().isEmpty ? null : _jsonOrNull(info.trim())) : info;
  final Iterable<dynamic> items = decoded is List
      ? decoded
      : decoded is Map
          ? decoded.values
          : const <dynamic>[];
  final out = <TestPoint>[];
  var i = 0;
  for (final p in items) {
    i++;
    if (p is! Map) continue;
    final point = _numCell(p['point']);
    if (point == null) continue;
    out.add(TestPoint(_numCell(p['number'])?.toInt() ?? i, point));
  }
  return out;
}

ExamFinal? _finalRow(Map<String, dynamic> m) {
  final subject = _cellText(m['subject']);
  if (subject.isEmpty) return null;
  final dateText = _cellOrNull(m['date']);
  final fromText = _cellOrNull(m['from']);
  final sid = m['subject_id'];
  return ExamFinal(
    subject: subject,
    subjectId: sid is num ? sid.toInt() : int.tryParse(_cellText(sid)) ?? 0,
    grade: _numCell(m['f_grade'])?.round(), // null/""/"-" = not graded yet; 0 is a real grade
    stream: _cellOrNull(m['stream']),
    room: _cellOrNull(m['room']),
    date: parseLmsDate(dateText) ?? parseLmsDate(fromText),
    from: _hhmm(fromText) ?? (dateText != null && dateText.contains(':') ? _hhmm(dateText) : null),
    to: _hhmm(_cellOrNull(m['to'])),
    timeLimit: _numCell(m['final_limit'])?.round(), // minutes
    testPoints: _finalPoints(m['final_info']),
  );
}

List<ExamFinal> parseFinals(dynamic json) => _dataList(json)
    .map((e) => _try(() => _finalRow(Map<String, dynamic>.from(e))))
    .whereType<ExamFinal>()
    .toList();

final _lectureRe = RegExp(r'\d\d\d$');
final _labRe = RegExp(r'-\w\d$');

LessonType _typeFromStream(String s) {
  if (_lectureRe.hasMatch(s)) return LessonType.lecture;
  if (_labRe.hasMatch(s)) return LessonType.laboratory;
  return LessonType.practice;
}

/// Stream codes look like LIA402, LIA402-1, ELC402-L1, FIZ12-a1.
final _streamRe = RegExp(r'\s*-\s*([A-Za-z]{2,}\d+[A-Za-z0-9]*(?:-[A-Za-z0-9]+)*)$');

/// One timetable entry. Title format: "(ROOM)\nSUBJECT-STREAM"; entries for
/// odd/even weeks wrap parts in slashes: "(D/-312)\nSubject/-LIA402/".
ScheduleItem? parseScheduleEntry(Map<String, dynamic> m) {
  final raw = (m['title'] ?? '').toString();
  final start = DateTime.tryParse(m['start']?.toString() ?? '');
  if (start == null) return null;
  final title = _clean(raw.replaceAll('/', '').replaceAll('\n', ' '));
  String? room;
  var rest = title;
  final rm = RegExp(r'^\(([^)]*)\)\s*(.*)$').firstMatch(title);
  if (rm != null) {
    room = _nullIfEmpty(rm[1]);
    rest = rm[2]!.trim();
  }
  String? stream;
  var subject = rest;
  final sm = _streamRe.firstMatch(rest);
  if (sm != null) {
    stream = sm[1];
    subject = rest.substring(0, sm.start).trim();
  }
  return ScheduleItem(
    start: start,
    title: title,
    subject: _nullIfEmpty(subject),
    stream: stream,
    room: room,
    side: WeekSide.fromValue(int.tryParse('${m['type'] ?? 1}')),
    type: _typeFromStream(stream ?? rest),
    colorClass: _nullIfEmpty(m['className']?.toString()),
  );
}

List<ScheduleItem> parseSchedule(dynamic json) => _dataList(json, 'json')
    .map((e) => _try(() => parseScheduleEntry(Map<String, dynamic>.from(e))))
    .whereType<ScheduleItem>()
    .toList();

/// The schedule response also says which week it is now, e.g.
/// <div class="cal-week is-even"><span class="cal-week-range">19.10.2026 – 24.10.2026</span>.
/// Returns the Monday of that week and its side (odd/even).
(DateTime, WeekSide)? parseWeekInfo(dynamic json) {
  if (json is String) json = _try(() => jsonDecode(json));
  if (json is! Map) return null;
  final view = json['view'];
  if (view is! String || view.isEmpty) return null;
  final d = parseHtml(view);
  final week = d.querySelector('.cal-week');
  if (week == null) return null;
  final cls = week.classes;
  final side = cls.contains('is-odd')
      ? WeekSide.left
      : cls.contains('is-even')
          ? WeekSide.right
          : null;
  if (side == null) return null;
  final from = parseLmsDate(d.querySelector('.cal-week-range')?.text);
  if (from == null) return null;
  final monday = DateTime(from.year, from.month, from.day).subtract(Duration(days: from.weekday - 1));
  return (monday, side);
}

// ---------------------------------------------------------------- course page (assignments)

CoursePage? parseCoursePage(Document d, Course course) {
  final table = d.querySelector('table#simple-table1');
  final boxes = d.querySelectorAll('.sc-summary .sc-summary-box');
  if (boxes.isNotEmpty || table?.classes.contains('sc-table') == true) {
    return _parseCoursePageV2(d, course, table, boxes);
  }
  final legacy = _parseCoursePageLegacy(d, course);
  if (legacy != null) return legacy;
  // A course without tasks renders an empty page body.
  if (d.querySelector('div.page-inner') != null) return const CoursePage(CourseRating(), []);
  return null;
}

/// A link's file name: link texts are cut ("2-Topshiri..."), so prefer the URL's name.
LmsFile? _fileLink(Element? a) {
  final href = a?.attributes['href'];
  if (a == null || href == null || href == '#' || href.startsWith('javascript')) return null;
  final url = absoluteUrl(href);
  var name = _clean(a.text);
  final seg = Uri.tryParse(url)?.pathSegments.where((e) => e.isNotEmpty).lastOrNull ?? '';
  final ext = seg.contains('.') ? seg.substring(seg.lastIndexOf('.')) : '';
  if (name.isEmpty) {
    name = seg.isEmpty ? 'file' : seg;
  } else if (name.endsWith('...') || name.endsWith('…')) {
    // "2-Topshiri..." → "2-Topshiri….docx" (the URL's own name is just a number)
    name = '${name.replaceAll(RegExp(r'(\.\.\.|…)$'), '').trim()}…$ext';
  } else if (ext.isNotEmpty && !name.toLowerCase().endsWith(ext.toLowerCase())) {
    name = '$name$ext';
  }
  return LmsFile(name, url);
}

/// Text of [e] without the parts inside elements for which [skip] is true.
String _textWithout(Element e, bool Function(Element) skip) {
  final b = StringBuffer();
  for (final n in e.nodes) {
    if (n is Element) {
      if (skip(n)) continue;
      b.write(_textWithout(n, skip));
    } else {
      b.write(n.text);
    }
  }
  return b.toString();
}

/// Current markup (2026): summary boxes + .sc-table with optional criteria rows.
CoursePage _parseCoursePageV2(Document d, Course course, Element? table, List<Element> boxes) {
  double? box(List<String> words, int index) {
    for (final b in boxes) {
      final label = _clean(b.querySelector('.sc-box-label')?.text).toLowerCase();
      if (words.any(label.contains)) return _num(b.querySelector('.sc-box-value')?.text);
    }
    return index < boxes.length ? _num(boxes[index].querySelector('.sc-box-value')?.text) : null;
  }

  final rating = CourseRating(
    achieved: box(const ['achieved', "to'plangan", 'набран', 'olingan'], 0),
    max: box(const ['max'], 1),
    ratingPercent: box(const ['rating', 'reyting', 'рейтинг'], 2),
    grade: box(const ['grade', 'baho', 'оценк'], 3)?.toInt(),
  );

  final list = <Assignment>[];
  if (table != null) {
    for (final tr in table.querySelectorAll('tbody > tr')) {
      if (tr.classes.contains('criteria-row') || tr.classes.contains('sc-criteria-row')) continue;
      final a = _try(() => _parseTaskRowV2(d, tr, course));
      if (a != null) list.add(a);
    }
  }
  return CoursePage(rating, list);
}

Assignment? _parseTaskRowV2(Document d, Element tr, Course course) {
  final tds = tr.children.where((e) => e.localName == 'td').toList();
  if (tds.length < 5) return null;
  Element td(int i) => tds[i];

  final taskType = _nullIfEmpty(td(0).querySelector('.sc-badge')?.text) ?? _nullIfEmpty(td(0).text);
  final teacher = _nullIfEmpty(td(1).text);
  final name = _nullIfEmpty(td(2).querySelector('.sc-activity-title')?.text) ?? _nullIfEmpty(td(2).text);
  final taskFile = _fileLink(td(2).querySelector('a[href]'));
  final deadline = parseLmsDate(td(3).querySelector('.sc-deadline')?.text ?? td(3).text);

  final score = td(4).querySelector('.sc-score');
  double? grade, maxGrade;
  if (score != null) {
    grade = _num(_textWithout(score, (e) => e.classes.contains('sc-max'))); // "—" → null (not graded yet)
    maxGrade = _num(score.querySelector('.sc-max')?.text);
  } else {
    grade = _num(td(4).text);
  }

  // Task id: from toggleCriteria(id) or the upload button's data-id.
  int? activityId;
  final onclick = td(4).querySelector('[onclick*="toggleCriteria"]')?.attributes['onclick'];
  if (onclick != null) activityId = int.tryParse(RegExp(r'(\d+)').firstMatch(onclick)?.group(1) ?? '');

  final last = tds.length > 5 ? td(5) : null;
  final uploadBtn = last?.querySelector('.js-btn-upload[data-id]');
  final uploadId = int.tryParse(uploadBtn?.attributes['data-id'] ?? '');
  activityId ??= uploadId;
  LmsFile? uploaded;
  if (last != null) {
    for (final a in last.querySelectorAll('a[href]')) {
      if (a.classes.contains('js-btn-upload')) continue;
      uploaded = _fileLink(a);
      if (uploaded != null) break;
    }
  }

  final criteria = <Criterion>[];
  if (activityId != null) {
    final row = d.getElementById('criteria-$activityId');
    for (final item in row?.querySelectorAll('.sc-criteria-item') ?? const <Element>[]) {
      final text = _clean(_textWithout(item, (e) => e.localName == 'strong'));
      if (text.isEmpty) continue;
      criteria.add(Criterion(text.replaceAll(RegExp(r'[\s(]+$'), ''), _num(item.querySelector('strong')?.text)));
    }
  }

  return Assignment(
    courseId: course.id,
    courseName: course.subject,
    taskType: taskType,
    teacher: teacher,
    name: name,
    taskFile: taskFile,
    deadline: deadline,
    grade: grade,
    maxGrade: maxGrade,
    uploadId: uploadId,
    uploadedFile: uploaded,
    activityId: activityId,
    criteria: criteria,
    expired: last?.querySelector('.sc-expired') != null,
    midterm: last?.querySelector('.sc-midterm') != null,
  );
}

/// Markup before the 2026 redesign.
CoursePage? _parseCoursePageLegacy(Document d, Course course) {
  if (d.querySelector('div.page-inner > div.panel') == null && d.querySelector('table#simple-table1') == null) {
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
  if (grade == 0) grade = null; // old markup showed 0 for "not graded"
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
//
// /student/calendar/{courseId} ("Calendar plan", 2026 redesign):
//   div.page-inner div.cal-panel
//     ul.cal-tabs > li[.active] > a[href="#lecture"|"#practice"|"#lab"]  label + span.cal-count
//     div.tab-content > div.tab-pane#lecture|#practice|#lab
//       ul.cal-list > li.cal-item[.is-open][.is-holiday]
//         button.cal-row[data-target="#cal-{tab}-{calendarId}-{idx}"]   row with materials
//         div.cal-row                                                    row without materials
//           span.cal-num | span.cal-body > span.cal-title (+ span.cal-note)
//           span.cal-meta > span.cal-date (+ span.cal-res-count)
//         div.collapse.cal-collapse > div.cal-drawer > a.cal-res
//           i.fa + span.cal-res-name + span.cal-res-go ("Download")
//       or div.cal-empty when a part has no themes.
// Dates are the planned dates of the calendar plan. The old table layout
// (same pane ids, tbody > tr) is still accepted as a fallback.

/// Lesson type from a tab id or a (localized) type name: Lecture / Ma'ruza / Лекция …
LessonType? lessonTypeOfName(String? key) => _lessonTypeOf(key);

LessonType? _lessonTypeOf(String? key) {
  final k = _clean(key).toLowerCase();
  if (k.isEmpty) return null;
  if (k.contains('lab') || k.contains('лаб')) return LessonType.laboratory;
  if (k.contains('lect') || k.contains('lek') || k.contains('ruza') || k.contains('лекц') || k.contains('руза')) {
    return LessonType.lecture;
  }
  if (k.contains('pract') || k.contains('prakt') || k.contains('amaliy') || k.contains('semin') ||
      k.contains('практ') || k.contains('семин') || k.contains('амали')) {
    return LessonType.practice;
  }
  return null;
}

/// Last path segment of [url] (already percent-decoded), or ''.
String _urlFileName(String url) {
  final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const <String>[];
  return segs.isEmpty ? '' : segs.last;
}

/// ".pdf", ".pptx" ... from the URL path, or '' when there is none.
String _urlExt(String url) {
  final n = _urlFileName(url);
  final i = n.lastIndexOf('.');
  if (i <= 0 || i == n.length - 1 || n.length - i > 6) return '';
  return n.substring(i);
}

/// Laravel storage names ("Gy34YzVItH1Y...YIg.pdf") mean nothing to the user.
bool _isRandomStorageName(String n) => RegExp(r'^[A-Za-z0-9]{24,}\.\w{1,5}$').hasMatch(n);

LmsFile? _calendarFile(Element a) {
  final href = (a.attributes['href'] ?? '').trim();
  if (href.isEmpty || href.startsWith('#') || href.toLowerCase().startsWith('javascript:')) return null;
  final url = absoluteUrl(href);

  var label = _clean(a.querySelector('.cal-res-name')?.text);
  if (label.isEmpty) {
    label = _clean(a.text);
    final go = _clean(a.querySelector('.cal-res-go')?.text); // "Download" (localized)
    if (go.isNotEmpty) label = _clean(label.replaceAll(go, ''));
  }

  final fromUrl = _urlFileName(url);
  if (label.isEmpty || label.endsWith('...') || label.endsWith('…')) {
    if (fromUrl.contains('.') && !_isRandomStorageName(fromUrl)) {
      label = fromUrl;
    } else {
      label = label.replaceAll(RegExp(r'(\.\.\.|…)+$'), '').trim();
    }
  }
  if (label.isEmpty) return LmsFile(fromUrl.isNotEmpty ? fromUrl : 'file', url);

  // Display names come without an extension ("lec-1", "Practice_9.1"); add the real one
  // from the URL so saving/opening/AI upload get the right type.
  final ext = _urlExt(url);
  if (ext.isNotEmpty && !label.toLowerCase().endsWith(ext.toLowerCase())) label = '$label$ext';
  return LmsFile(label, url);
}

Lesson? _parseCalendarItem(Element li, LessonType type, int index) {
  final theme = _nullIfEmpty(li.querySelector('.cal-title')?.text) ??
      _nullIfEmpty(li.querySelector('.cal-body')?.text);
  final number = _num(li.querySelector('.cal-num')?.text)?.toInt() ?? index + 1;
  final date = parseLmsDate(li.querySelector('.cal-date')?.text);

  var anchors = li.querySelectorAll('a.cal-res');
  if (anchors.isEmpty) anchors = li.querySelectorAll('.cal-drawer a[href], .cal-collapse a[href]');
  final files = <LmsFile>[];
  final seen = <String>{};
  for (final a in anchors) {
    final f = _try(() => _calendarFile(a));
    if (f != null && seen.add(f.url)) files.add(f);
  }

  if (theme == null && date == null && files.isEmpty) return null;
  return Lesson(type: type, number: number, theme: theme, date: date, files: files);
}

/// Previous layout: div#lecture|#practice|#lab table rows (number | theme | date, links in cells).
Lesson? _parseLegacyLessonRow(Element tr, LessonType type) {
  final tds = tr.querySelectorAll('td');
  if (tds.isEmpty) return null;
  final files = <LmsFile>[];
  final seen = <String>{};
  for (final a in tr.querySelectorAll('td a')) {
    final f = _try(() => _calendarFile(a));
    if (f != null && seen.add(f.url)) files.add(f);
  }
  return Lesson(
    type: type,
    number: int.tryParse(_clean(tds[0].text)) ?? 0,
    theme: _nullIfEmpty(tr.querySelector('td p')?.text) ?? (tds.length > 1 ? _nullIfEmpty(tds[1].text) : null),
    date: tds.length > 2 ? parseLmsDate(tds[2].text) : null,
    files: files,
  );
}

List<Lesson> parseLessons(Document d) {
  final root = d.querySelector('div.page-inner') ?? d.body;
  if (root == null) return <Lesson>[];

  // Pane id -> tab label ("lab" -> "Laboratory 15"), used when the id alone is not a known key.
  final labels = <String, String>{};
  for (final a in root.querySelectorAll('ul.cal-tabs a[href], ul[role="tablist"] a[href]')) {
    final href = a.attributes['href'] ?? '';
    if (href.startsWith('#') && href.length > 1) labels.putIfAbsent(href.substring(1), () => a.text);
  }

  final out = <Lesson>[];
  var panes = root.querySelectorAll('div.tab-content > div.tab-pane');
  if (panes.isEmpty) panes = root.querySelectorAll('div.tab-pane');

  if (panes.isEmpty) {
    // Old layout without tab-content wrappers: div#lecture / #practice / #lab tables.
    for (final id in const ['lecture', 'practice', 'lab']) {
      for (final tr in root.querySelectorAll('div#$id tbody > tr')) {
        final l = _try(() => _parseLegacyLessonRow(tr, _lessonTypeOf(id)!));
        if (l != null) out.add(l);
      }
    }
    if (out.isNotEmpty) return out;
    // No tabs: take the part from the collapse target ("#cal-lab-533690-0").
    final items = root.querySelectorAll('li.cal-item');
    for (var i = 0; i < items.length; i++) {
      final target = items[i].querySelector('[data-target]')?.attributes['data-target'] ?? '';
      final key = RegExp(r'cal-([a-z]+)-').firstMatch(target)?.group(1);
      final l = _try(() => _parseCalendarItem(items[i], _lessonTypeOf(key) ?? LessonType.practice, i));
      if (l != null) out.add(l);
    }
    return out;
  }

  for (final pane in panes) {
    final id = pane.attributes['id'] ?? '';
    final type = _lessonTypeOf(id) ?? _lessonTypeOf(labels[id]);
    final items = pane.querySelectorAll('li.cal-item');
    if (items.isNotEmpty) {
      for (var i = 0; i < items.length; i++) {
        final l = _try(() => _parseCalendarItem(items[i], type ?? LessonType.practice, i));
        if (l != null) out.add(l);
      }
    } else if (type != null) {
      // div.cal-empty yields nothing here; old table markup still parses.
      for (final tr in pane.querySelectorAll('tbody > tr')) {
        final l = _try(() => _parseLegacyLessonRow(tr, type));
        if (l != null) out.add(l);
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------- study plan
//
// /student/study-plan (redesign). Everything lives in div.page-inner:
//   div.sp-header > h3.sp-title + div.sp-header-right
//       > div.gpa-badge "GPA: <span>x.xx</span>"            (overall)
//       > [div.gpa-badge.gpa-badge-current]                 (optional)
//   [div.sp-info > div.sp-info-body > .sp-info-title + .sp-info-text]  (optional notice)
//   div.semester-grid (2 cards per grid; the last may hold 1)
//     > div.semester-card
//         > div.semester-card-header > span.semester-num "I" + span.semester-label "semester"
//         > table.plan-table > tbody > tr > td.td-subject | td.td-credit | td.td-grade
//             td.td-grade > span.grade-badge.grade-(excellent|good|satisf|fail) "5|4|3|2"
//                        or span.grade-empty "—"  (not graded yet)

List<Discipline> parseStudyPlan(Document d) {
  final out = <Discipline>[];
  final root = d.querySelector('div.page-inner') ?? d.body;
  if (root == null) return out;

  var blocks = root.querySelectorAll('div.semester-card');
  // If the card wrapper is renamed, fall back to the tables themselves (semester label = null).
  if (blocks.isEmpty) blocks = root.querySelectorAll('table.plan-table');

  for (final block in blocks) {
    final semester = _try(() => _studyPlanSemesterLabel(block));
    for (final tr in block.querySelectorAll('tbody tr')) {
      final row = _try(() => _parseDisciplineRow(tr, semester));
      // No de-duplication: elective placeholders legitimately repeat within one semester.
      if (row != null) out.add(row);
    }
  }
  return out;
}

/// "I semester": Roman numeral + localized word, exactly as shown in the card header.
String? _studyPlanSemesterLabel(Element block) {
  final header = block.querySelector('div.semester-card-header');
  if (header == null) return null;
  final parts = [
    _clean(header.querySelector('.semester-num')?.text),
    _clean(header.querySelector('.semester-label')?.text),
  ].where((e) => e.isNotEmpty).toList();
  return parts.isNotEmpty ? parts.join(' ') : _nullIfEmpty(header.text);
}

Discipline? _parseDisciplineRow(Element tr, String? semester) {
  final tds = tr.querySelectorAll('td');
  final positional = tds.length >= 3; // Discipline | Credit | Grade
  final subjectTd = tr.querySelector('td.td-subject') ?? (positional ? tds[0] : null);
  if (subjectTd == null) return null; // header row or a "no data" colspan row
  final title = _nullIfEmpty(subjectTd.text);
  if (title == null) return null;

  final creditTd = tr.querySelector('td.td-credit') ?? (positional ? tds[1] : null);
  final gradeTd = tr.querySelector('td.td-grade') ?? (positional ? tds[2] : null);

  int? grade;
  if (gradeTd != null && gradeTd.querySelector('.grade-empty') == null) {
    final badge = gradeTd.querySelector('.grade-badge');
    grade = _num((badge ?? gradeTd).text)?.round(); // "—" -> null
  }

  return Discipline(
    title: title,
    semester: semester,
    // Always the Credit column: titles contain misleading digits ("Calculus 1", "(4 credits)").
    credits: _num(creditTd?.text)?.round(),
    grade: grade,
  );
}

/// Optional: header summary (overall GPA, optional "current" GPA badge, optional notice).
StudyPlanSummary parseStudyPlanSummary(Document d) {
  final root = d.querySelector('div.page-inner') ?? d.body;
  double? gpa, current;
  String? currentLabel;
  for (final b in root?.querySelectorAll('.gpa-badge') ?? const <Element>[]) {
    final span = b.querySelector('span');
    final value = _num(span?.text ?? b.text);
    if (b.classes.contains('gpa-badge-current')) {
      current ??= value;
      final label = span == null ? b.text : b.text.replaceFirst(span.text, '');
      currentLabel ??= _nullIfEmpty(label.replaceAll(':', ''));
    } else {
      gpa ??= value;
    }
  }
  String? notice;
  final info = root?.querySelector('.sp-info');
  if (info != null) {
    final parts = [
      _clean(info.querySelector('.sp-info-title')?.text),
      _clean(info.querySelector('.sp-info-text')?.text),
    ].where((e) => e.isNotEmpty).toList();
    notice = parts.isNotEmpty ? parts.join(' — ') : _nullIfEmpty(info.text);
  }
  return StudyPlanSummary(gpa: gpa, currentGpa: current, currentGpaLabel: currentLabel, notice: notice);
}

// ---------------------------------------------------------------- news
//
// /dashboard/news[?page=N] (also the page shown right after login); 9 cards per page, newest first:
//   div.page-inner > div.news-grid > div.news-card
//       h5.news-card-title        full title (2-line clamp is CSS only); may be empty
//       p.news-card-excerpt       so far always identical to the title; may be empty
//       div.news-card-footer > span.news-card-date "10.06.2026"
//                            > a.news-card-link[href=".../dashboard/news/detailed/81"] "More"
//   div.page-inner > div.news-pagination > div.pag-wrap > .pag-btn
//       a.pag-btn[href="...?page=N"] | span.pag-btn.pag-active | span.pag-btn.pag-disabled (←/→) | span.pag-btn.pag-dots
// /dashboard/news/detailed/{id}:
//   div.page-inner > a.news-back + div.news-article
//       > div.news-article-header > h1.news-article-title, div.news-article-meta "Published — 26.04.2025"
//       > div.news-article-body   (editor HTML: p, h2, h3, img, a, blockquote...; may be empty)

final _newsIdRe = RegExp(r'/news/detailed/(\d+)');
final _newsPageRe = RegExp(r'[?&]page=(\d+)');
final _newsWsRe = RegExp(r'\s+');
final _cutRe = RegExp(r'(\.\.\.|…)$');

/// Canonical detail URL, so a list card and its detail page share NewsItem.key.
String? _newsUrl(String? href) {
  final m = _newsIdRe.firstMatch(href ?? '');
  return m == null ? null : '$lmsBase/dashboard/news/detailed/${m[1]}';
}

/// [sel] inside div.page-inner, so the shared template never matches.
List<Element> _inPage(Document d, String sel) =>
    (d.querySelector('div.page-inner') ?? d.documentElement)?.querySelectorAll(sel) ?? const [];

/// Detail URLs on the news list, in page order (untitled posts included).
List<String> parseNewsLinks(Document d) {
  var anchors = _inPage(d, 'div.news-card a.news-card-link[href]');
  if (anchors.isEmpty) anchors = _inPage(d, 'a[href*="/news/detailed/"]');
  return {for (final a in anchors) _newsUrl(a.attributes['href'])}.whereType<String>().toList();
}

/// The list page's cards: title, date and URL, but no real body (the excerpt has
/// always repeated the title, so body is set only when it says something else).
/// Cards without title and excerpt are skipped: their detail page is empty too.
List<NewsItem> parseNewsList(Document d) {
  final out = <NewsItem>[];
  final seen = <String>{};
  for (final card in _inPage(d, 'div.news-card')) {
    final item = _try<NewsItem?>(() {
      final a = card.querySelector('a.news-card-link[href]') ?? card.querySelector('a[href*="/news/detailed/"]');
      final url = _newsUrl(a?.attributes['href']);
      if (url == null || !seen.add(url)) return null;
      final excerpt = _nullIfEmpty(card.querySelector('.news-card-excerpt')?.text);
      final title = _nullIfEmpty(card.querySelector('.news-card-title')?.text) ?? excerpt;
      if (title == null) return null;
      return NewsItem(
        title: title,
        body: excerpt == null || _repeats(excerpt, title) ? null : excerpt,
        date: parseLmsDate(card.querySelector('.news-card-date')?.text),
        url: url,
      );
    });
    if (item != null) out.add(item);
  }
  return out;
}

/// True when [excerpt] is [title], possibly cut with "..." / "…".
bool _repeats(String excerpt, String title) {
  if (excerpt == title) return true;
  final stem = excerpt.replaceFirst(_cutRe, '').trimRight();
  return stem.isNotEmpty && stem.length < excerpt.length && title.startsWith(stem);
}

/// A news detail page. Null when there is no article or it has no text at all.
NewsItem? parseNewsPage(Document d, String url) {
  final article = d.querySelector('div.news-article');
  if (article == null) return null;
  final body = _richText(article.querySelector('div.news-article-body'));
  var title = _nullIfEmpty(article.querySelector('.news-article-title')?.text);
  if (title == null && body != null) {
    // Untitled post that has text: use its first line.
    final first = body.split('\n').first;
    title = first.runes.length <= 90 ? first : '${String.fromCharCodes(first.runes.take(89)).trimRight()}…';
  }
  if (title == null) return null;
  return NewsItem(
    title: title,
    body: body,
    date: parseLmsDate(article.querySelector('.news-article-meta')?.text),
    url: _newsUrl(url) ?? url,
  );
}

/// Pagination under the news grid; null when there is none (single page).
({int current, int last, String? next})? parseNewsPagination(Document d) {
  final wrap = _inPage(d, 'div.news-pagination').firstOrNull;
  if (wrap == null) return null;
  final current = int.tryParse(_clean(wrap.querySelector('.pag-btn.pag-active')?.text)) ?? 1;
  var last = current;
  String? next;
  for (final b in wrap.querySelectorAll('.pag-btn')) {
    final href = b.localName == 'a' ? b.attributes['href'] : null;
    final m = href == null ? null : _newsPageRe.firstMatch(href);
    final linked = m == null ? null : int.parse(m[1]!);
    final n = int.tryParse(_clean(b.text)) ?? linked;
    if (n != null && n > last) last = n;
    if (linked == current + 1) next ??= absoluteUrl(href!);
  }
  return (current: current, last: last, next: next);
}

const _richSkip = {
  'script', 'style', 'noscript', 'template', 'xml', 'svg', 'img', 'iframe',
  'object', 'video', 'audio', 'button', 'input', 'select',
};
const _richBlocks = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'aside', 'blockquote', 'pre',
  'figure', 'figcaption', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li',
  'dl', 'dt', 'dd', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'hr', 'address', 'center',
};

/// Plain text of editor HTML: one line per paragraph / heading / list item / table
/// row, joined with '\n'; spaces (incl. &nbsp;) collapsed inside a line. Images,
/// scripts and comments are dropped. Null when there is no text.
/// Do not pass the result through _clean/_nullIfEmpty (they would remove the '\n').
String? _richText(Element? root) {
  if (root == null) return null;
  final b = StringBuffer();
  void walk(Node n, bool pre) {
    if (n is Text) {
      b.write(pre ? n.text : n.text.replaceAll(_newsWsRe, ' '));
      return;
    }
    if (n is! Element) return; // comments (Word "<!--[if gte mso]>" junk), etc.
    final tag = n.localName ?? '';
    if (_richSkip.contains(tag)) return;
    if (tag == 'br') {
      b.write('\n');
      return;
    }
    if (tag == 'a') {
      b.write(_newsLinkLabel(n));
      return;
    }
    final block = _richBlocks.contains(tag);
    if (block) b.write('\n');
    if (tag == 'li') {
      final p = n.parent;
      if (p != null && p.localName == 'ol') {
        b.write('${p.children.where((c) => c.localName == 'li').toList().indexOf(n) + 1}. ');
      } else {
        b.write('• ');
      }
    }
    for (final c in n.nodes) {
      walk(c, pre || tag == 'pre');
    }
    if (tag == 'td' || tag == 'th') b.write(' ');
    if (block) b.write('\n');
  }

  walk(root, false);
  final text = b.toString().split('\n').map(_clean).where((l) => l.isNotEmpty).join('\n');
  return text.isEmpty ? null : text;
}

/// Text for a link inside a news body. Editor link texts are often cut
/// ("Buyruq_20..."); then (or when the link has no text) the URL's file name is used.
String _newsLinkLabel(Element a) {
  final text = _clean(a.text);
  final cut = text.endsWith('...') || text.endsWith('…');
  if (text.isNotEmpty && !cut) return text;
  if (text.isEmpty && a.querySelector('img') != null) return ''; // image wrapped in a link
  final href = a.attributes['href']?.trim() ?? '';
  if (href.isEmpty ||
      href.startsWith('#') ||
      href.startsWith('javascript') ||
      href.startsWith('mailto:') ||
      href.startsWith('tel:')) {
    return text;
  }
  final seg = _try(() => Uri.parse(absoluteUrl(href)).pathSegments.where((s) => s.isNotEmpty).lastOrNull) ?? '';
  final dot = seg.lastIndexOf('.');
  final hasName = dot > 0 && dot < seg.length - 1;
  final numericName = hasName && RegExp(r'^\d+$').hasMatch(seg.substring(0, dot));
  if (hasName && !(cut && numericName)) return seg; // "Buyruq_2025.pdf"
  return cut ? (_fileLink(a)?.name ?? text) : text; // "2-Topshiri….docx" / keep text
}

// ---------------------------------------------------------------- tuition contract (on /student/info)

/// "17 866 395 <small>UZS</small>" -> 17866395 (spaces/NBSP group thousands).
double? _amount(Element? e) {
  if (e == null) return null;
  final t = _textWithout(e, (x) => x.localName == 'small')
      .replaceAll(RegExp(r'[\s  ]'), '')
      .replaceAll(RegExp(r',(?=\d{3}(?!\d))'), '');
  return _num(t);
}

bool _inDetails(Element e) {
  for (var p = e.parent; p != null; p = p.parent) {
    if (p.localName == 'details') return true;
  }
  return false;
}

ContractYear _contractYear(Element scope, String year, {required bool current, String? status}) {
  final grid = scope.querySelectorAll('.si-stat-grid').where((g) => !current || !_inDetails(g)).firstOrNull;
  double? stat(String cls) => _amount(grid?.querySelector('.si-stat.$cls .si-stat-amount'));
  return ContractYear(
    year: year,
    current: current,
    status: status,
    notice: _nullIfEmpty(scope.querySelector('.si-empty-contract')?.text),
    total: stat('total'),
    paid: stat('paid'),
    debt: stat('debt'),
    paidPercent: _num((grid?.parent ?? scope).querySelector('.si-progress-pct')?.text),
    currency: _nullIfEmpty(grid?.querySelector('.si-stat-amount small')?.text),
  );
}

/// Tuition contract by academic year: current year first, then the "Previous academic years" accordion.
List<ContractYear> parseContracts(Document d) {
  final yearRe = RegExp(r'\d{4}\s*[-–]\s*\d{4}');
  final out = <ContractYear>[];
  final header = d.querySelector('.si-contract-header');
  final card = header?.parent;
  if (header != null && card != null) {
    final year = _nullIfEmpty(header.querySelector('.si-contract-badge')?.text) ??
        yearRe.firstMatch(header.text)?.group(0) ??
        '';
    out.add(_contractYear(card, year, current: true));
  }
  for (final item in d.querySelectorAll('details.si-acc-item')) {
    final summary = item.querySelector('summary');
    final head = summary == null ? '' : _clean(_textWithout(summary, (e) => e.classes.contains('si-acc-sum')));
    final year = yearRe.firstMatch(head)?.group(0)?.replaceAll(RegExp(r'\s'), '') ?? head;
    out.add(_contractYear(item.querySelector('.si-acc-body') ?? item, year,
        current: false, status: _nullIfEmpty(item.querySelector('.si-acc-sum')?.text)));
  }
  return out;
}

/// Sidebar menu: (label, absolute URL) for each real link, including submenu items. Match by URL, not label.
List<(String, String)> parseMenu(Document d) {
  final out = <(String, String)>[];
  for (final a in d.querySelectorAll('ul#side-menu a[href], ul.accordion-menu a[href]')) {
    final href = (a.attributes['href'] ?? '').trim();
    if (href.isEmpty || href == '#' || href.startsWith('javascript')) continue;
    final url = absoluteUrl(href);
    final label = _nullIfEmpty(a.querySelector('span')?.text) ?? _clean(a.text);
    if (label.isEmpty || out.any((e) => e.$2 == url)) continue;
    out.add((label, url));
  }
  return out;
}
