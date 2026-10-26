-- =====================================================================
-- MySQL practice on your own LMS data (database "tuitmate").
-- Open MySQL on the VPS:   sudo mysql tuitmate
-- then copy one query at a time. Nothing here changes data except the
-- clearly marked exercises at the end.
-- =====================================================================

-- ---------------------------------------------------------------- 1. Look around
SHOW TABLES;
DESCRIBE assignments;                       -- columns and their types
-- The full definition; \G instead of ; shows one field per line.
SHOW CREATE TABLE changes\G
SELECT COUNT(*) FROM snapshots;

-- ---------------------------------------------------------------- 2. SELECT, WHERE, ORDER BY, LIMIT
-- Your courses and their rating, best first.
SELECT subject, rating_percent, grade
FROM courses
ORDER BY rating_percent DESC;

-- Tasks you have not handed in yet, nearest deadline first.
SELECT title, task_type, deadline
FROM assignments
WHERE status = 'notSubmitted'
ORDER BY deadline
LIMIT 10;

-- ---------------------------------------------------------------- 3. Dates and time zones
-- LMS times are Tashkent time (UTC+5); the server's clock is UTC.
-- "Now in Tashkent":
SELECT CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+05:00') AS tashkent_now;

-- Due in the next 7 days (Tashkent time on both sides).
SELECT title, deadline,
       TIMESTAMPDIFF(HOUR, CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+05:00'), deadline) AS hours_left
FROM assignments
WHERE status = 'notSubmitted'
  AND deadline BETWEEN CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+05:00')
                   AND CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+05:00') + INTERVAL 7 DAY
ORDER BY deadline;

-- Today's classes (DATE() keeps only the day).
SELECT TIME(starts_at) AS starts, subject, lesson_type, room
FROM classes
WHERE DATE(starts_at) = DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+05:00'))
ORDER BY starts_at;

-- ---------------------------------------------------------------- 4. JOIN
-- Every task with its course's rating (assignments.course_id = courses.course_id).
SELECT c.subject, a.title, a.status, a.grade, a.max_grade, c.rating_percent
FROM assignments AS a
JOIN courses AS c
  ON c.account_id = a.account_id AND c.course_id = a.course_id
ORDER BY c.subject, a.deadline;

-- LEFT JOIN keeps courses that have no tasks at all.
SELECT c.subject, COUNT(a.id) AS tasks
FROM courses AS c
LEFT JOIN assignments AS a
  ON a.account_id = c.account_id AND a.course_id = c.course_id
GROUP BY c.subject;

-- ---------------------------------------------------------------- 5. GROUP BY, aggregates, HAVING
-- Tasks per status.
SELECT status, COUNT(*) AS n FROM assignments GROUP BY status;

-- NB per subject and the hours they cost (1 NB = 2 academic hours).
SELECT subject, COUNT(*) AS nb, COUNT(*) * 2 AS hours, SUM(excused) AS excused
FROM absences
GROUP BY subject
ORDER BY nb DESC;

-- Total NB hours against the 74-hour limit.
SELECT COUNT(*) * 2 AS hours_used, 74 - COUNT(*) * 2 AS hours_left FROM absences WHERE excused = FALSE;

-- Courses where you earned less than half of the points graded so far.
SELECT c.subject, SUM(a.grade) AS got, SUM(a.max_grade) AS possible
FROM assignments AS a
JOIN courses AS c ON c.account_id = a.account_id AND c.course_id = a.course_id
WHERE a.status = 'graded'
GROUP BY c.subject
HAVING SUM(a.grade) < SUM(a.max_grade) / 2;

-- ---------------------------------------------------------------- 6. What changed (history)
-- The newest 20 changes, in Tashkent time.
SELECT CONVERT_TZ(detected_at, '+00:00', '+05:00') AS seen, kind, subject, detail
FROM changes
ORDER BY id DESC
LIMIT 20;

-- Changes per day and kind.
SELECT DATE(CONVERT_TZ(detected_at, '+00:00', '+05:00')) AS day, kind, COUNT(*) AS n
FROM changes
GROUP BY day, kind
ORDER BY day DESC, n DESC;

-- ---------------------------------------------------------------- 7. How well the server works
-- Checks per day: how many, how many failed, average time.
SELECT DATE(started_at) AS day,
       COUNT(*) AS checks,
       SUM(ok = FALSE) AS failed,
       ROUND(AVG(duration_ms)) AS avg_ms
FROM fetch_runs
GROUP BY day
ORDER BY day DESC;

-- The last errors.
SELECT started_at, error FROM fetch_runs WHERE ok = FALSE ORDER BY id DESC LIMIT 5;

-- Is the LMS session alive? (never shows the cookies: they are encrypted)
SELECT obtained_at, checked_at, ended_at,
       TIMESTAMPDIFF(MINUTE, checked_at, UTC_TIMESTAMP()) AS minutes_since_check
FROM lms_sessions;

-- ---------------------------------------------------------------- 8. JSON (the snapshots table)
-- How big the stored snapshots are.
SELECT id, fetched_at, full_sync, ROUND(LENGTH(data) / 1024) AS kb FROM snapshots ORDER BY id DESC LIMIT 5;

-- Read inside the JSON of the newest snapshot.
SELECT data->>'$.info.fullName'        AS name,
       data->>'$.info.group'           AS group_name,
       JSON_LENGTH(data, '$.courses')  AS courses,
       JSON_LENGTH(data, '$.news')     AS news
FROM snapshots ORDER BY id DESC LIMIT 1;

-- Turn a JSON array into rows (JSON_TABLE): the news titles.
SELECT jt.title, jt.date
FROM snapshots,
     JSON_TABLE(data, '$.news[*]' COLUMNS (title VARCHAR(300) PATH '$.title', date VARCHAR(40) PATH '$.date')) AS jt
WHERE snapshots.id = (SELECT MAX(id) FROM snapshots);

-- ---------------------------------------------------------------- 9. Exercises that change data
-- Check LMS every 10 minutes instead of 5 (the server picks it up within a minute):
--   UPDATE accounts SET fetch_minutes = 10 WHERE id = 1;
-- A view: a saved query you can SELECT from like a table.
--   CREATE OR REPLACE VIEW open_tasks AS
--     SELECT c.subject, a.title, a.deadline
--     FROM assignments a JOIN courses c ON c.account_id = a.account_id AND c.course_id = a.course_id
--     WHERE a.status = 'notSubmitted';
--   SELECT * FROM open_tasks ORDER BY deadline;
-- EXPLAIN shows whether MySQL uses an index:
--   EXPLAIN SELECT * FROM assignments WHERE account_id = 1 ORDER BY deadline;
-- Backup and restore (in the shell, not in mysql):
--   sudo mysqldump tuitmate > tuitmate-backup.sql
--   sudo mysql tuitmate < tuitmate-backup.sql
