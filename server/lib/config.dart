import 'dart:io';

/// Server settings, from /etc/tuitmate/server.env (written by install.sh)
/// with process environment variables taking precedence.
class Config {
  Config(Map<String, String> env)
      : dbHost = env['DB_HOST'] ?? '127.0.0.1',
        dbPort = int.tryParse(env['DB_PORT'] ?? '') ?? 3306,
        dbName = env['DB_NAME'] ?? 'tuitmate',
        dbUser = env['DB_USER'] ?? 'tuitmate',
        dbPassword = env['DB_PASSWORD'] ?? '',
        secretKeyFile = env['SECRET_KEY_FILE'] ?? '/etc/tuitmate/secret.key',
        tlsCert = env['TLS_CERT'] ?? '/etc/tuitmate/tls/cert.pem',
        tlsKey = env['TLS_KEY'] ?? '/etc/tuitmate/tls/key.pem',
        listen = env['LISTEN_ADDRESS'] ?? '0.0.0.0',
        port = int.tryParse(env['LISTEN_PORT'] ?? '') ?? 8443,
        publicUrl = env['PUBLIC_URL'] ?? '',
        dataDir = env['DATA_DIR'] ?? '/var/lib/tuitmate',
        chrome = (env['CHROME'] ?? '').isEmpty ? null : env['CHROME'],
        fetchMinutes = (int.tryParse(env['FETCH_MINUTES'] ?? '') ?? 5).clamp(2, 120);

  final String dbHost;
  final int dbPort;
  final String dbName, dbUser, dbPassword;
  final String secretKeyFile;
  final String tlsCert, tlsKey;
  final String listen;
  final int port;

  /// How the app reaches this server, e.g. https://203.0.113.5:8443.
  final String publicUrl;

  /// Cookie jars (one folder per account).
  final String dataDir;

  /// Chrome/Chromium for signing in to LMS (reCAPTCHA needs a real browser).
  final String? chrome;
  final int fetchMinutes;

  static const defaultFile = '/etc/tuitmate/server.env';

  /// Reads [file] (KEY=VALUE lines, # comments) and the environment.
  static Config load({String? file}) {
    final env = <String, String>{};
    final f = File(file ?? Platform.environment['TUITMATE_CONFIG'] ?? defaultFile);
    if (f.existsSync()) env.addAll(parseEnv(f.readAsStringSync()));
    for (final e in Platform.environment.entries) {
      if (_keys.contains(e.key)) env[e.key] = e.value;
    }
    return Config(env);
  }

  static const _keys = {
    'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'SECRET_KEY_FILE', 'TLS_CERT', 'TLS_KEY', //
    'LISTEN_ADDRESS', 'LISTEN_PORT', 'PUBLIC_URL', 'DATA_DIR', 'CHROME', 'FETCH_MINUTES',
  };

  static Map<String, String> parseEnv(String text) {
    final out = <String, String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final i = line.indexOf('=');
      if (i <= 0) continue;
      var v = line.substring(i + 1).trim();
      if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
        v = v.substring(1, v.length - 1);
      }
      out[line.substring(0, i).trim()] = v;
    }
    return out;
  }
}
