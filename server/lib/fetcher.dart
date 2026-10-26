import 'dart:async';
import 'dart:io';

import 'package:tuitmate_lms/changes.dart';
import 'package:tuitmate_lms/lms_client.dart';
import 'package:tuitmate_lms/snapshot.dart';

import 'store.dart';

enum FetchOutcome {
  ok,

  /// No session yet, or LMS ended it: waiting for the app to send one.
  noSession,

  /// LMS answered that the session is over (it is marked ended).
  sessionEnded,

  /// Network or LMS problem; tried again at the next run.
  failed,
}

/// Checks LMS for one account with the session the app handed over: the same
/// download and change detection as the app (package tuitmate_lms), saved to
/// MySQL. Every check also keeps the session alive.
class Fetcher {
  Fetcher(this.store, this.dataDir, {this.log = _print});
  final Store store;
  final String dataDir;
  final void Function(String) log;

  final _running = <int, Future<FetchOutcome>>{};

  /// One check of [account]; a check already running is joined, not repeated.
  Future<FetchOutcome> run(int account, {bool full = false}) =>
      // The callback must not return the removed future: whenComplete would wait for it (itself).
      _running[account] ??= _run(account, full).whenComplete(() {
        _running.remove(account);
      });

  bool isRunning(int account) => _running.containsKey(account);

  Future<FetchOutcome> _run(int account, bool forceFull) async {
    final session = await store.session(account);
    if (session == null || session.endedAt != null || session.cookies.isEmpty) return FetchOutcome.noSession;

    // A fresh cookie jar from the stored cookies (MySQL is the source of truth).
    final dir = Directory('$dataDir${Platform.pathSeparator}cookies${Platform.pathSeparator}$account');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final client = LmsClient('${dir.path}${Platform.pathSeparator}');
    await client.importCookies(session.cookies);

    final prev = await store.latestSnapshot(account);
    final full = forceFull || prev == null || needsFullSync(prev, DateTime.now());
    final run = await store.startRun(account, full);
    final sw = Stopwatch()..start();
    try {
      final fresh = await fetchSnapshot(client, previous: prev, full: full);
      final changes = prev == null ? const <LmsChange>[] : diffSnapshots(prev, fresh);
      await store.saveSnapshot(account, fresh, full: full);
      await store.addChanges(account, changes, DateTime.now());
      await store.writeCurrentState(account, fresh);
      await store.sessionChecked(account, await client.currentCookies());
      await store.finishRun(run, ok: true, changes: changes.length, failedParts: fresh.errors.keys.toList(), ms: sw.elapsedMilliseconds);
      log('account $account: ${full ? 'full' : 'light'} check ok, ${changes.length} changes'
          '${fresh.errors.isEmpty ? '' : ', kept old data for ${fresh.errors.keys.join(', ')}'} (${sw.elapsedMilliseconds} ms)');
      return FetchOutcome.ok;
    } on SessionExpiredException {
      await store.sessionEnded(account);
      await store.finishRun(run, ok: false, error: 'LMS ended the session; waiting for the app to send a new one', ms: sw.elapsedMilliseconds);
      log('account $account: LMS ended the session');
      return FetchOutcome.sessionEnded;
    } catch (e) {
      await store.finishRun(run, ok: false, error: e.toString(), ms: sw.elapsedMilliseconds);
      log('account $account: check failed: $e');
      return FetchOutcome.failed;
    }
  }
}

/// Starts a check for every account whose turn it is (accounts.fetch_minutes
/// since the last one), once a minute.
class Scheduler {
  Scheduler(this.store, this.fetcher, {this.log = _print});
  final Store store;
  final Fetcher fetcher;
  final void Function(String) log;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => tick());
    unawaited(tick());
  }

  void stop() => _timer?.cancel();

  Future<void> tick() async {
    try {
      for (final account in await store.accountIds()) {
        if (fetcher.isRunning(account)) continue;
        final last = await store.lastRun(account);
        final every = Duration(minutes: await store.fetchMinutes(account));
        // A little early is fine: the timer ticks once a minute.
        if (last != null && DateTime.now().toUtc().difference(last.startedAt) < every - const Duration(seconds: 30)) continue;
        unawaited(fetcher.run(account));
      }
    } catch (e) {
      log('scheduler: $e');
    }
  }
}

void _print(String line) => stdout.writeln('${DateTime.now().toUtc().toIso8601String()} $line');
