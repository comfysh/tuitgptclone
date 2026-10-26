-- =====================================================================
-- TuitMate server database (MySQL 8)
-- =====================================================================
-- Database: tuitmate   (created by install.sh:
--   CREATE DATABASE tuitmate CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;)
--
-- How the data flows:
--   1. After you sign in to LMS in the app, the app hands its LMS session
--      (cookies) to the server (PUT /v1/session); it is stored ENCRYPTED in
--      `lms_sessions`. Your password never leaves the phone.
--   2. Every few minutes the server checks LMS with that session (which also
--      keeps it alive: LMS ends a session only after 2 hours without use),
--      downloads everything (the same code the app uses) and stores:
--        - the whole result as JSON in `snapshots`,
--        - what changed since last time in `changes`,
--        - the current state as normal rows in `courses`, `assignments`,
--          `absences`, `exams`, `classes`, `news` (good for practising SQL),
--        - how the run went in `fetch_runs`.
--   3. The app asks the server for the newest snapshot instead of going to
--      LMS itself, then notifies you. If the session ever ends (for example
--      the server was off for hours), the next sign-in in the app hands over
--      a fresh one.
--
-- Times:
--   *_at columns written by the server are UTC (DATETIME(3), milliseconds).
--   LMS times (deadline, exam start, class start, NB date) are Tashkent
--   local time, exactly as LMS shows them. Tashkent = UTC+5:
--     SELECT CONVERT_TZ(fetched_at, '+00:00', '+05:00') FROM snapshots;
--
-- Secrets never stored in plain text:
--   lms_sessions.cookies_enc is AES-256-GCM encrypted (base64 of 12-byte IV
--   + ciphertext + 16-byte tag). The key is the file
--   /etc/tuitmate/secret.key, NOT in the database, so a database dump alone
--   does not give anyone your LMS session.
--   api_tokens.token_sha256 is only a hash of the app's token.
--
-- Every statement is "IF NOT EXISTS": running this file again is harmless.
-- The server applies it at start (and records the version in schema_version).
-- =====================================================================

CREATE TABLE IF NOT EXISTS schema_version (
  version     INT UNSIGNED NOT NULL PRIMARY KEY,
  applied_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- One row per LMS account (normally just you).
CREATE TABLE IF NOT EXISTS accounts (
  id             INT UNSIGNED  NOT NULL AUTO_INCREMENT PRIMARY KEY,
  label          VARCHAR(64)   NOT NULL DEFAULT 'me',
  fetch_minutes  SMALLINT UNSIGNED NOT NULL DEFAULT 5 COMMENT 'how often LMS is checked',
  created_at     DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at     DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Tokens the app uses to talk to the server (only their SHA-256 is kept).
CREATE TABLE IF NOT EXISTS api_tokens (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id    INT UNSIGNED NOT NULL,
  token_sha256  CHAR(64)     NOT NULL COMMENT 'hex SHA-256 of the token',
  label         VARCHAR(64)  NOT NULL DEFAULT 'app',
  created_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_used_at  DATETIME(3)  NULL,
  UNIQUE KEY uq_token (token_sha256),
  CONSTRAINT fk_tokens_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- The live LMS session (cookies) the app handed over after signing in.
-- checked_at = last time LMS accepted it; ended_at = when LMS stopped
-- accepting it (the app then sends a fresh one at its next sign-in).
CREATE TABLE IF NOT EXISTS lms_sessions (
  account_id   INT UNSIGNED NOT NULL PRIMARY KEY,
  cookies_enc  TEXT         NOT NULL COMMENT 'AES-256-GCM, base64 JSON list of cookies',
  obtained_at  DATETIME(3)  NOT NULL,
  checked_at   DATETIME(3)  NULL,
  ended_at     DATETIME(3)  NULL,
  CONSTRAINT fk_sessions_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Every LMS check: when, whether it loaded everything, how long, what failed.
CREATE TABLE IF NOT EXISTS fetch_runs (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id   INT UNSIGNED NOT NULL,
  started_at   DATETIME(3)  NOT NULL,
  finished_at  DATETIME(3)  NULL,
  full_sync    BOOLEAN      NOT NULL COMMENT 'also teacher files, profile, study plan',
  ok           BOOLEAN      NOT NULL DEFAULT FALSE,
  changes      INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'rows added to `changes`',
  failed_parts VARCHAR(512) NULL COMMENT 'parts that kept their previous data, e.g. "news,lessons:30893"',
  error        TEXT         NULL,
  duration_ms  INT UNSIGNED NULL,
  KEY ix_runs_account_time (account_id, started_at),
  CONSTRAINT fk_runs_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Everything LMS returned in one check, as JSON (the same format the app
-- saves). Only the newest 100 per account are kept.
--   SELECT JSON_LENGTH(data, '$.courses') FROM snapshots ORDER BY id DESC LIMIT 1;
CREATE TABLE IF NOT EXISTS snapshots (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id  INT UNSIGNED NOT NULL,
  fetched_at  DATETIME(3)  NOT NULL,
  full_sync   BOOLEAN      NOT NULL,
  data        JSON         NOT NULL,
  KEY ix_snapshots_account_time (account_id, fetched_at),
  CONSTRAINT fk_snapshots_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- What changed between two checks (new task, new grade, NB, exam change,
-- teacher file, news), the same list the app shows in its Inbox.
CREATE TABLE IF NOT EXISTS changes (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id   INT UNSIGNED NOT NULL,
  detected_at  DATETIME(3)  NOT NULL,
  kind         VARCHAR(32)  NOT NULL COMMENT 'newAssignment, deadlineChanged, gradePosted, examGrade, examChanged, newAbsence, newFile, news',
  change_key   VARCHAR(700) NOT NULL,
  subject      VARCHAR(255) NOT NULL,
  detail       TEXT         NULL,
  when_at      DATETIME     NULL COMMENT 'deadline / exam start / NB date (Tashkent time)',
  value        DECIMAL(8,2) NULL COMMENT 'grade, if any',
  max_value    DECIMAL(8,2) NULL,
  KEY ix_changes_account_id (account_id, id),
  KEY ix_changes_kind (kind),
  CONSTRAINT fk_changes_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- The current state as normal rows (rewritten after every successful
-- check). These are the tables to practise SELECT / JOIN / GROUP BY on;
-- see practice.sql.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS courses (
  account_id      INT UNSIGNED  NOT NULL,
  course_id       INT           NOT NULL COMMENT 'LMS course id',
  subject         VARCHAR(255)  NOT NULL,
  teachers        VARCHAR(512)  NULL,
  streams         VARCHAR(255)  NULL,
  absence_count   INT           NOT NULL DEFAULT 0,
  rating_percent  DECIMAL(5,2)  NULL,
  points          DECIMAL(6,2)  NULL COMMENT 'points achieved so far',
  max_points      DECIMAL(6,2)  NULL,
  grade           TINYINT       NULL COMMENT '2..5 as LMS shows it',
  PRIMARY KEY (account_id, course_id),
  CONSTRAINT fk_courses_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS assignments (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id  INT UNSIGNED  NOT NULL,
  course_id   INT           NOT NULL,
  title       VARCHAR(500)  NOT NULL,
  task_type   VARCHAR(100)  NULL COMMENT 'Laboratoriya, Amaliy, Mustaqil ish…',
  teacher     VARCHAR(255)  NULL,
  deadline    DATETIME      NULL COMMENT 'Tashkent time',
  status      ENUM('notSubmitted', 'submitted', 'graded') NOT NULL,
  grade       DECIMAL(6,2)  NULL,
  max_grade   DECIMAL(6,2)  NULL,
  your_file   VARCHAR(500)  NULL COMMENT 'name of the file you uploaded',
  task_file   VARCHAR(1000) NULL COMMENT 'URL of the teacher''s task file',
  KEY ix_assignments_account_deadline (account_id, deadline),
  KEY ix_assignments_course (account_id, course_id),
  CONSTRAINT fk_assignments_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS absences (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id    INT UNSIGNED NOT NULL,
  subject       VARCHAR(255) NOT NULL,
  subject_id    INT          NOT NULL,
  absent_on     DATE         NULL,
  lesson_type   VARCHAR(64)  NULL,
  theme         VARCHAR(500) NULL,
  theme_number  INT          NOT NULL DEFAULT 0,
  excused       BOOLEAN      NOT NULL DEFAULT FALSE,
  KEY ix_absences_account (account_id, absent_on),
  CONSTRAINT fk_absences_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS exams (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id  INT UNSIGNED NOT NULL,
  subject     VARCHAR(255) NOT NULL,
  subject_id  INT          NOT NULL,
  starts_at   DATETIME     NULL COMMENT 'Tashkent time',
  ends_at     VARCHAR(8)   NULL COMMENT 'e.g. 10:20',
  room        VARCHAR(64)  NULL,
  stream      VARCHAR(64)  NULL,
  grade       INT          NULL COMMENT 'result out of 100',
  KEY ix_exams_account (account_id, starts_at),
  CONSTRAINT fk_exams_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- The timetable as LMS lists it for the current week.
CREATE TABLE IF NOT EXISTS classes (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id  INT UNSIGNED NOT NULL,
  starts_at   DATETIME     NOT NULL COMMENT 'Tashkent time',
  subject     VARCHAR(255) NULL,
  lesson_type ENUM('lecture', 'practice', 'laboratory') NOT NULL,
  room        VARCHAR(64)  NULL,
  stream      VARCHAR(64)  NULL,
  week_side   ENUM('both', 'odd', 'even') NOT NULL DEFAULT 'both',
  KEY ix_classes_account (account_id, starts_at),
  CONSTRAINT fk_classes_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS news (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  account_id  INT UNSIGNED  NOT NULL,
  title       VARCHAR(500)  NOT NULL,
  published   DATETIME      NULL,
  url         VARCHAR(1000) NULL,
  body        TEXT          NULL,
  KEY ix_news_account (account_id, published),
  CONSTRAINT fk_news_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT IGNORE INTO schema_version (version) VALUES (1);
