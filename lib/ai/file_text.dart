import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pulls readable text out of common study files so any AI model can use them.
/// Returns null for formats we can't read (PDF and images go to the model as-is).
String? extractText(String name, String mime, Uint8List bytes) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  try {
    if (mime.startsWith('text/') ||
        const {'txt', 'md', 'csv', 'json', 'xml', 'py', 'java', 'c', 'cpp', 'h', 'cs', 'js', 'ts', 'dart', 'kt', 'go', 'sql', 'html', 'css', 'log'}
            .contains(ext)) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (ext == 'docx') return _docx(bytes);
    if (ext == 'pptx') return _pptx(bytes);
    if (ext == 'xlsx') return _xlsx(bytes);
  } catch (_) {}
  return null;
}

String _xmlText(String xml, {String paragraphTag = 'w:p', String textTag = 'w:t'}) {
  final withBreaks = xml
      .replaceAll(RegExp('</$paragraphTag>'), '\n')
      .replaceAll(RegExp(r'<w:tab/>'), '\t')
      .replaceAll(RegExp(r'<w:br/>'), '\n');
  final buf = StringBuffer();
  final re = RegExp('<$textTag(?: [^>]*)?>([^<]*)</$textTag>|(\n|\t)');
  for (final m in re.allMatches(withBreaks)) {
    buf.write(m[1] ?? m[2]);
  }
  return _unescape(buf.toString()).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String? _docx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final doc = zip.findFile('word/document.xml');
  if (doc == null) return null;
  return _xmlText(utf8.decode(doc.content, allowMalformed: true));
}

String? _pptx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final slides = zip.files.where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList()
    ..sort((a, b) => _num(a.name).compareTo(_num(b.name)));
  if (slides.isEmpty) return null;
  final buf = StringBuffer();
  for (var i = 0; i < slides.length; i++) {
    buf.writeln('--- Slide ${i + 1} ---');
    buf.writeln(_xmlText(utf8.decode(slides[i].content, allowMalformed: true), paragraphTag: 'a:p', textTag: 'a:t'));
  }
  return buf.toString().trim();
}

/// Only this much text is sent to the AI (same as AiService.maxTextChars).
const _maxChars = 200000;

/// Every sheet as tab-separated rows (text cells resolved from the
/// shared-strings table, numbers and inline strings kept as they are).
String? _xlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final tRe = RegExp(r'<t(?: [^>]*)?>([^<]*)</t>');
  final shared = <String>[];
  const maxPart = 32 << 20; // skip parts that would inflate beyond 32 MB
  final ss = zip.findFile('xl/sharedStrings.xml');
  if (ss != null && ss.size <= maxPart) {
    final xml = utf8.decode(ss.content, allowMalformed: true);
    for (final si in RegExp(r'<si>([\s\S]*?)</si>').allMatches(xml)) {
      shared.add(_unescape(tRe.allMatches(si[1]!).map((m) => m[1]).join()));
    }
  }
  final sheets = zip.files.where((f) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)).toList()
    ..sort((a, b) => _num(a.name).compareTo(_num(b.name)));
  if (sheets.isEmpty) return shared.isEmpty ? null : shared.join('\n');
  final cellRe = RegExp(r'<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)');
  final vRe = RegExp(r'<v>([^<]*)</v>');
  final buf = StringBuffer();
  for (var i = 0; i < sheets.length && buf.length < _maxChars; i++) {
    buf.writeln('--- Sheet ${i + 1} ---');
    if (sheets[i].size > maxPart) {
      buf.writeln('(sheet too large to read)');
      continue;
    }
    // Don't decode more XML than can end up in the text (a cut row just won't match).
    final raw = sheets[i].content;
    final xml = utf8.decode(raw.length > _maxChars * 20 ? Uint8List.sublistView(raw, 0, _maxChars * 20) : raw,
        allowMalformed: true);
    for (final row in RegExp(r'<row\b[^>]*>([\s\S]*?)</row>').allMatches(xml)) {
      if (buf.length >= _maxChars) break;
      final cells = <String>[];
      for (final c in cellRe.allMatches(row[1]!)) {
        final attrs = c[1]!, inner = c[2] ?? '';
        final v = vRe.firstMatch(inner)?[1];
        if (attrs.contains('t="s"')) {
          final idx = int.tryParse(v ?? '') ?? -1;
          cells.add(idx >= 0 && idx < shared.length ? shared[idx] : '');
        } else if (attrs.contains('t="inlineStr"')) {
          cells.add(_unescape(tRe.allMatches(inner).map((m) => m[1]).join()));
        } else {
          cells.add(_unescape(v ?? ''));
        }
      }
      if (cells.any((e) => e.isNotEmpty)) buf.writeln(cells.join('\t'));
    }
  }
  return buf.toString().trim();
}

int _num(String s) => int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(s)?.group(1) ?? '0') ?? 0;
