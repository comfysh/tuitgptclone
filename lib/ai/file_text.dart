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
  final re = RegExp('<$textTag(?: [^>]*)?>([^<]*)</$textTag>|(\n)');
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

String? _xlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final shared = zip.findFile('xl/sharedStrings.xml');
  if (shared == null) return null;
  return _xmlText(utf8.decode(shared.content, allowMalformed: true), paragraphTag: 'si', textTag: 't');
}

int _num(String s) => int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(s)?.group(1) ?? '0') ?? 0;
