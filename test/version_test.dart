import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/core/version.dart';

void main() {
  test('app version matches pubspec.yaml (releases are named after it)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull);
    expect(appVersion, m!.group(1));

    final changelog = File('CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## [$appVersion]'), reason: 'CHANGELOG.md needs a section for the release notes');
  });
}
