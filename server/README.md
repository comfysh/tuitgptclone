# TuitMate server (your VPS + MySQL)

The server keeps your LMS session alive and checks LMS every 5 minutes, day and night, storing
everything in a **MySQL 8** database on your VPS. The app then takes the newest data from the server
(fast, and also when LMS is slow) and notifies you as before.

```
 TuitMate app ──HTTPS (token + pinned certificate)──▶ tuitmate-server ──▶ lms.tuit.uz
   │  hands over its LMS session after you sign in        │  every 5 min, keeps the session alive
   └─ gets the newest snapshot, notifies you              └─▶ MySQL 8 "tuitmate" (127.0.0.1 only)
```

- **Your password stays on your phone.** The server never signs in to LMS by itself: after you sign
  in in the app, the app gives the server that session, and the server's checks every 5 minutes keep
  it alive (LMS ends a session only after 2 hours without use). If it ever ends (for example the VPS
  was off for hours), the next sign-in in the app hands over a new one.
- The session is stored **encrypted** (AES-256-GCM, key in `/etc/tuitmate/secret.key`, not in the
  database). The app's token is stored only as a SHA-256 hash.
- The server uses the same LMS code as the app (`packages/tuitmate_lms`), so the data is identical.

## 1. Install (Ubuntu 22.04 or 24.04, x86_64)

Before you put anything on the VPS: **change its root password** (it was shared in a chat), better
still use an SSH key and turn password login off.

```bash
ssh root@<your-vps-ip>
curl -fsSLO https://github.com/comfysh/tuitgptclone/releases/latest/download/tuitmate-server-install.sh
sudo bash tuitmate-server-install.sh
```

It installs MySQL 8 from Ubuntu's packages, downloads `tuitmate-server` (checked against
`SHA256SUMS.txt` of the same release), creates the database, the MySQL user, the encryption key, a
self-signed certificate and the systemd service, and finally prints a **connection code**
(`tmsrv1.…`). Running it again updates the program and keeps your data.

If your VPS provider has a firewall in its control panel, allow **TCP 8443** there.

## 2. Connect the app

TuitMate › **Profile › Sync › TuitMate server › Connect** → paste the code → the app checks the
connection and the certificate. Then sign in to LMS in the app once (or it hands over its current
session right away). From then on the server checks LMS every 5 minutes.

A new code (for a second device): `sudo -u tuitmate tuitmate-server new-token laptop`.
Lost phone? `sudo -u tuitmate tuitmate-server revoke-tokens`, then make a new code.

## 3. Where the database is

| What | Where |
|---|---|
| Server | MySQL 8 on the VPS, listening on **127.0.0.1:3306** only (not reachable from the internet) |
| Database | **`tuitmate`** (data files in `/var/lib/mysql/tuitmate/`) |
| User for the service | `'tuitmate'@'localhost'`, password in `/etc/tuitmate/server.env` (`DB_PASSWORD=`) |
| Admin access | `sudo mysql` (MySQL's root logs in through the Linux root user, no password) |
| Tables | `sql/schema.sql` (every table explained) |
| Encryption key | `/etc/tuitmate/secret.key` (keep a copy: without it the stored session can't be read) |
| Settings | `/etc/tuitmate/server.env` |
| Logs | `journalctl -u tuitmate-server -f` |

### Open it on the VPS

```bash
sudo mysql tuitmate
mysql> SHOW TABLES;
mysql> SELECT subject, rating_percent FROM courses;
```

### Open it from your PC (MySQL Workbench, DBeaver, DataGrip…)

MySQL stays closed to the internet; you reach it through SSH:

```bash
ssh -N -L 3307:127.0.0.1:3306 root@<your-vps-ip>
```

Leave that running and connect your tool to **host 127.0.0.1, port 3307**, user `tuitmate`, the
password from `server.env`, database `tuitmate`. (Or in Workbench pick "Standard TCP/IP over SSH" and
fill in the VPS and MySQL details; it makes the tunnel itself.)

For practice it is safer to make a read-only user:

```sql
-- in: sudo mysql
CREATE USER 'learner'@'localhost' IDENTIFIED BY 'choose-a-password';
GRANT SELECT ON tuitmate.* TO 'learner'@'localhost';
```

## 4. Learn MySQL with your own data

[`sql/practice.sql`](sql/practice.sql) walks through it with real queries on your LMS data:

1. `SHOW TABLES`, `DESCRIBE`, `SHOW CREATE TABLE`
2. `SELECT … WHERE … ORDER BY … LIMIT` (open tasks, nearest deadline first)
3. dates and time zones (`CONVERT_TZ`, `TIMESTAMPDIFF`, `INTERVAL 7 DAY`): LMS times are Tashkent
   time, the server's clock is UTC
4. `JOIN` and `LEFT JOIN` (tasks with their course)
5. `GROUP BY`, `COUNT`, `SUM`, `HAVING` (NB hours per subject, the 74-hour limit)
6. the history of changes, per day
7. how reliable the checks are (`fetch_runs`)
8. JSON columns (`->>`, `JSON_LENGTH`, `JSON_TABLE`) on the stored snapshots
9. exercises that change data: `UPDATE`, views, `EXPLAIN`, `mysqldump` backups

The tables to start with: `courses`, `assignments`, `absences`, `exams`, `classes`, `news`
(rewritten after every check), `changes` (what changed, kept), `fetch_runs` (every check).

## 5. Everyday commands

```bash
sudo systemctl status tuitmate-server        # running?
journalctl -u tuitmate-server -f             # live log: every check, its changes and errors
sudo -u tuitmate tuitmate-server status      # session, last check, snapshot time (JSON)
sudo -u tuitmate tuitmate-server fetch       # check LMS now (--full: also teacher files etc.)
sudo mysqldump tuitmate > backup.sql         # backup
```

## 6. Remove it

```bash
sudo systemctl disable --now tuitmate-server
sudo rm /etc/systemd/system/tuitmate-server.service /usr/local/bin/tuitmate-server
sudo mysql -e "DROP DATABASE tuitmate; DROP USER 'tuitmate'@'localhost';"
sudo rm -r /etc/tuitmate /var/lib/tuitmate && sudo userdel tuitmate
# MySQL itself: sudo apt purge mysql-server
```

## API (for the app or your own scripts)

All calls need `Authorization: Bearer <token>` (the token is inside the connection code). HTTPS with a
self-signed certificate: check its SHA-256 (`sudo tuitmate-server fingerprint`) instead of a CA.

| Call | What it does |
|---|---|
| `GET /health` | `ok` (no token) |
| `GET /v1/status` | session state, last check, last successful check, snapshot time |
| `PUT /v1/session` | `{"cookies":[{"name":…,"value":…,"path":"/","expires":ms,"secure":true,"httpOnly":true}]}` |
| `GET /v1/session` | the live session with its renewed expiry (`404` when not live) |
| `DELETE /v1/session` | forget the session |
| `GET /v1/snapshot?after=<ISO time>` | newest snapshot (`{"fetched_at":…,"snapshot":{…}}`), `204` if none newer |
| `POST /v1/refresh?full=1` | check LMS now and wait (up to 2 min) |
| `GET /v1/changes?after=<id>` | changes after that id, oldest first |

## Development

```bash
cd server
dart pub get
dart run bin/tuitmate_server.dart help
TUITMATE_TEST_DB_USER=… TUITMATE_TEST_DB_PASSWORD=… dart test   # database tests need MySQL 8
dart compile exe bin/tuitmate_server.dart -o tuitmate-server-linux-x64
```
`lib/schema.dart` is generated from `sql/schema.sql` (a test checks they match).
