import 'package:mysql_client/mysql_client.dart';

import 'config.dart';
import 'schema.dart';

/// The MySQL connection pool and the schema.
class Db {
  Db(this.pool);
  final MySQLConnectionPool pool;

  /// Connects (TLS to the local server; MySQL 8 makes its own certificate)
  /// and checks the connection works.
  static Future<Db> open(Config c) async {
    final pool = MySQLConnectionPool(
      host: c.dbHost,
      port: c.dbPort,
      userName: c.dbUser,
      password: c.dbPassword,
      databaseName: c.dbName,
      maxConnections: 4,
      secure: true,
      collation: 'utf8mb4_0900_ai_ci',
    );
    await pool.execute('SELECT 1');
    return Db(pool);
  }

  Future<IResultSet> q(String sql, [Map<String, dynamic>? params]) => pool.execute(sql, params);

  Future<T> tx<T>(Future<T> Function(MySQLConnection c) body) => pool.transactional(body);

  /// Creates missing tables (sql/schema.sql; every statement is IF NOT EXISTS).
  Future<void> applySchema() async {
    for (final statement in splitSql(schemaSql)) {
      await pool.execute(statement);
    }
  }

  Future<void> close() => pool.close();
}

/// Statements of an SQL script: whole-line "--" comments dropped, split at
/// semicolons that are not inside quotes.
List<String> splitSql(String script) {
  final text = script.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
  final out = <String>[];
  final b = StringBuffer();
  var quote = '';
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quote.isNotEmpty) {
      b.write(ch);
      if (ch == quote) {
        // '' inside a string is an escaped quote, not the end.
        if (i + 1 < text.length && text[i + 1] == quote) {
          b.write(text[++i]);
        } else {
          quote = '';
        }
      }
    } else if (ch == "'" || ch == '"' || ch == '`') {
      quote = ch;
      b.write(ch);
    } else if (ch == ';') {
      final s = b.toString().trim();
      if (s.isNotEmpty) out.add(s);
      b.clear();
    } else {
      b.write(ch);
    }
  }
  final rest = b.toString().trim();
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

/// MySQL DATETIME text for a moment, in UTC (server times) or as given
/// (LMS times, which are Tashkent local).
String sqlTime(DateTime t, {bool utc = true}) {
  final d = utc ? t.toUtc() : t;
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = d.millisecond.toString().padLeft(3, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}.$ms';
}

/// A DATETIME value read back as UTC.
DateTime? fromSqlUtc(String? v) => v == null ? null : DateTime.tryParse('${v.replaceFirst(' ', 'T')}Z');
