import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tuitmate_server/api.dart';
import 'package:tuitmate_server/config.dart';
import 'package:tuitmate_server/db.dart';
import 'package:tuitmate_server/fetcher.dart';
import 'package:tuitmate_server/secret_box.dart';
import 'package:tuitmate_server/store.dart';

const _usage = '''
TuitMate server $serverVersion

Usage: tuitmate-server <command>

  serve              run the API and the LMS checks (what systemd runs)
  init               create the database tables (safe to run again)
  new-token [label]  make a token for the app and print its connection code
  revoke-tokens      delete every app token (the app has to be connected again)
  fetch [--full]     check LMS once now and print the result
  status             show the session, the last checks and the snapshot time
  fingerprint        print the TLS certificate fingerprint
  version            print the version

Settings come from /etc/tuitmate/server.env (or the file in TUITMATE_CONFIG).
''';

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'serve' : args.first;
  if (command == 'version' || command == '--version') return stdout.writeln(serverVersion);
  if (command == 'help' || command == '--help' || command == '-h') return stdout.write(_usage);

  final config = Config.load();
  if (command == 'fingerprint') return stdout.writeln(await certFingerprint(config.tlsCert));

  final db = await Db.open(config);
  final store = Store(db, Vault.fromFile(config.secretKeyFile));
  try {
    switch (command) {
      case 'serve':
        await _serve(config, db, store);
        return; // runs until stopped
      case 'init':
        await db.applySchema();
        final account = await store.ensureAccount(fetchMinutes: config.fetchMinutes);
        stdout.writeln('Database ready (account $account).');
      case 'new-token':
        await db.applySchema();
        final account = await store.ensureAccount(fetchMinutes: config.fetchMinutes);
        final token = await store.newToken(account, label: args.length > 1 ? args[1] : 'app');
        final fp = await certFingerprint(config.tlsCert);
        if (config.publicUrl.isEmpty) stderr.writeln('PUBLIC_URL is not set in the config; the code below has no address.');
        stdout
          ..writeln('Connection code for the app (Profile › Sync › TuitMate server):')
          ..writeln()
          ..writeln(connectionCode(config.publicUrl, token, fp))
          ..writeln()
          ..writeln('Keep it private: it lets the app read your LMS data from this server.');
      case 'revoke-tokens':
        final account = await store.ensureAccount(fetchMinutes: config.fetchMinutes);
        stdout.writeln('Deleted ${await store.revokeTokens(account)} token(s).');
      case 'fetch':
        final account = await store.ensureAccount(fetchMinutes: config.fetchMinutes);
        final outcome = await Fetcher(store, config.dataDir).run(account, full: args.contains('--full'));
        stdout.writeln('Result: ${outcome.name}');
        if (outcome == FetchOutcome.noSession) {
          stdout.writeln('No live LMS session yet: connect the app and sign in to LMS in it once.');
        }
      case 'status':
        final account = await store.ensureAccount(fetchMinutes: config.fetchMinutes);
        final api = Api(store, Fetcher(store, config.dataDir));
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(await api.status(account)));
      default:
        stderr.write(_usage);
        exitCode = 64;
    }
  } finally {
    if (command != 'serve') await db.close();
  }
}

Future<void> _serve(Config config, Db db, Store store) async {
  await db.applySchema();
  await store.ensureAccount(fetchMinutes: config.fetchMinutes);
  final fetcher = Fetcher(store, config.dataDir);
  final tls = SecurityContext()
    ..useCertificateChain(config.tlsCert)
    ..usePrivateKey(config.tlsKey);
  final api = Api(store, fetcher);
  await api.start(address: config.listen, port: config.port, tls: tls);
  final scheduler = Scheduler(store, fetcher)..start();

  // systemd stops the service with SIGTERM.
  final done = Completer<void>();
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    });
  }
  await done.future;
  scheduler.stop();
  await api.stop();
  await db.close();
  exit(0);
}
