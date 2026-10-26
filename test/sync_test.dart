import 'package:flutter_test/flutter_test.dart';
import 'package:tuitmate/lms/snapshot.dart';
import 'package:tuitmate/services/background_login.dart';

void main() {
  test('a light check loads everything once teacher files etc. are an hour old', () {
    final now = DateTime(2026, 10, 26, 12);
    expect(needsFullSync(LmsSnapshot(updatedAt: now), now), isTrue); // never loaded in full
    expect(needsFullSync(LmsSnapshot(updatedAt: now, fullAt: now.subtract(const Duration(minutes: 30))), now), isFalse);
    expect(needsFullSync(LmsSnapshot(updatedAt: now, fullAt: now.subtract(fullSyncEvery)), now), isTrue);
    expect(needsFullSync(LmsSnapshot(updatedAt: now, fullAt: now.add(const Duration(hours: 2))), now), isTrue); // clock moved back
    // The time survives saving.
    final at = DateTime(2026, 10, 26, 11, 15);
    expect(LmsSnapshot.fromJson(LmsSnapshot(updatedAt: now, fullAt: at).toJson()).fullAt, at);
  });

  test('automatic sign-in waits longer after each failure, but never gives up', () {
    final t = DateTime(2026, 10, 26, 9);
    Map<String, dynamic> state(int failures) => {'loginFailures': failures, 'loginTriedAt': t.toIso8601String()};
    expect(BackgroundLogin.nextTry({}), isNull);
    expect(BackgroundLogin.nextTry(state(0)), isNull); // last one worked: any time
    expect(BackgroundLogin.nextTry(state(1)), t.add(const Duration(minutes: 20)));
    expect(BackgroundLogin.nextTry(state(2)), t.add(const Duration(hours: 1)));
    expect(BackgroundLogin.nextTry(state(3)), t.add(const Duration(hours: 3)));
    expect(BackgroundLogin.nextTry(state(4)), t.add(const Duration(hours: 6)));
    expect(BackgroundLogin.nextTry(state(40)), t.add(const Duration(hours: 6)));
  });
}
