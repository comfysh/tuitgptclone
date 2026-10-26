# Changelog

All notable changes to TuitMate. The release notes on GitHub are taken from this file:
add a section `## [x.y.z] - date` and raise `version:` in `pubspec.yaml` (and `lib/core/version.dart`)
to publish a new release.

## [1.4.0] - 2026-10-26

Your own server with a MySQL database: it checks LMS every 5 minutes, day and night.

### Highlights
- **TuitMate server** (`server/`, for an Ubuntu VPS): a small service that keeps your LMS session
  alive and checks LMS every 5 minutes, storing everything in **MySQL 8**: each check's data
  (JSON), what changed, your courses, tasks, NB, exams, classes and news as normal tables, and a
  log of every check. One command installs it (`tuitmate-server-install.sh` from the release):
  MySQL, the service, an encryption key, a self-signed certificate and a connection code.
- **Connect the app** (*Profile › Sync › TuitMate server*): paste the code. The app then takes the
  newest data from your server (and asks it to check LMS right away when you refresh), hands it its
  LMS session after you sign in, and takes the session back when its own copy expires, so it rarely
  has to sign in. Without the server, or when it is off, the app goes to LMS directly as before.
- **Your password stays on the phone**: the server never signs in to LMS itself; it only keeps the
  session the app gives it alive. The session is stored encrypted (AES-256-GCM, key outside the
  database); the app pins the server's certificate and uses a token stored on the server only as a hash.
- **Learn MySQL with your own data**: `server/sql/schema.sql` explains every table,
  `server/sql/practice.sql` has queries from `SELECT` to `JOIN`, `GROUP BY`, time zones and JSON,
  and `server/README.md` shows where the database is and how to open it from your PC (SSH tunnel).
- The LMS code is now a shared package (`packages/tuitmate_lms`) used by both the app and the server.

## [1.3.0] - 2026-10-26

Signs in by itself, checks more often and more completely, six themes, and a Today screen you arrange yourself.

### Highlights
- **Saved sign-in** (*Profile › Sign-in*): see which LMS login is saved, add or change the login and
  password (useful after signing in with OneID), and see when TuitMate last signed in by itself.
  **Try now** tests it.
- **Automatic sign-in never gives up**: after a failure it waits 20 min, 1 h, 3 h, then tries every 6 h,
  instead of stopping after three tries. The login page opens by itself at most once per ended session.
- **Always up to date**: while the app is open (on PC also in the tray) it checks LMS every 10 minutes
  and whenever you return to it after 2 minutes. Background checks on Android now run every 15 minutes
  by default and also load teacher files, profile and study plan at least every hour, so new teacher
  files are noticed without opening the app. Parts that fail to load are retried (after 30 s, 90 s and
  5 min); if they still fail, a banner says which ones and the saved copy is shown. A background check
  that fails because of the network runs again soon instead of waiting for the next slot.
- **Sync** (*Profile › Sync*): when LMS was last checked, when teacher files were last loaded, how often
  checks run, and **Check everything now**.
- **Six themes**, each light and dark: **Paper**, **Ocean**, **Lagoon**, **Plum**, **Terracotta** and
  **Graphite**, with their own colours and title font, and a **pure black** option for OLED screens.
- **Customize Today** (sliders button at the top of Today): drag sections into your order, switch them on or off, add the new
  *Workload by week*, *Attendance* and *Latest news* sections, and choose the place the app opens on
  (Today, Plan, Inbox or Study).

### Fixed
- Workload by week counted deadlines against the device clock instead of the day it was showing.

## [1.2.0] - 2026-10-23

A new way around the app: four places built around what you want to do, not the LMS menu, and one
box to search everything or ask the AI.

### Highlights
- **New navigation**: **Today**, **Plan** (schedule, deadlines, exams), **Inbox** (updates, news) and
  **Study** (courses, grades, attendance, files). Each place has its sections as tabs under the title
  and opens where you left it. On phones the **Ask** button sits in the middle of the bottom bar; on PC
  the sidebar has an Ask box, the class on now (or the next one, or the nearest deadline) and the AI
  chat, LMS website and profile at the bottom.
- **Ask** (Ctrl+K on PC): one box that finds tasks, courses, teacher files, exams, news and pages as
  you type, and sends anything else to the AI together with your timetable, tasks and grades. Ready-made
  questions when the box is empty. Works with the keyboard (↑↓, Enter, Esc).
- **Inbox**: every change TuitMate finds (new tasks, changed deadlines, grades, NB, exam changes and
  results, teacher files, LMS news) in one list grouped by day, with unread marks, filters and
  "mark all as read". Tap an update to open the task, file or article. It also fills while the app is
  closed (Android background checks), and muted kinds still appear here.
- **What's new** on Today: your latest unread updates.
- **Workload by week** (Plan › Deadlines): open tasks and exams in each of the next 8 weeks, with the
  busiest week named, so you can start early.
- Tapping a notification opens the Inbox (deadline reminders open your tasks); on Windows it also
  brings the window out of the tray.

## [1.1.0] - 2026-10-23

A new look of its own, quieter notifications that work without opening the app, more AI providers,
and automation for the owner.

### Highlights
- **New "paper" design**: warm paper background, ink-black headers, a serif font (Source Serif 4) for titles and numbers, flat bordered cards and calm colours. Light and dark mode.
- **Today is now an agenda**: your day from top to bottom (classes, free time between them, tasks due today and exams) with a red *now* line. Below it: due in the coming days, your numbers, tomorrow's classes, the next exam and tuition debt. Two columns on PC.
- **Stay signed in**: when LMS ends the session (about every 2 hours), TuitMate signs in again by itself with the saved password, also in the background, so checks and notifications keep working without opening the app. If LMS refuses, you get one notification.
- **Quieter notifications**: quiet hours (default 22:30–07:00, nothing makes a sound then), several updates from one check arrive as **one** notification, a **morning brief** with today's classes and deadlines (default 07:30), and you choose which kinds of updates notify you (new teacher files are off by default).
- **Windows: runs in the system tray**. Closing the window keeps TuitMate in the tray so checks and notifications go on; *Start with Windows* starts it hidden in the tray. Open, refresh or quit from the tray icon.
- **More AI providers**: **DeepSeek**, OpenRouter, Groq, Mistral, OpenAI, Together, xAI, local models (Ollama / LM Studio) and any OpenAI-compatible API, next to Gemini. Each provider keeps its own key and model.
- **Automation (owner only)**: TuitMate can send your LMS events (new tasks, deadlines, grades, NB, exams, files, news, a daily summary) to your own n8n workflow or server, encrypted with AES-256-GCM and signed. A ready n8n workflow and a guide for AI assistants are in [docs/AUTOMATION.md](docs/AUTOMATION.md).

### Fixed
- The expected grade counts missed tasks, so it is honest late in the semester too.
- The Android background check no longer stops silently when the session cookie expires.

## [1.0.0] - 2026-10-22

First full version for Android and Windows.

### Highlights
- **New design** on every screen, for phones and PCs, in light and dark mode (Inter font, brand colours, cards, rings and charts).
- **Today**: current or next class with a countdown, today's classes with breaks, nearest deadlines, open tasks, NB hours, GPA, average rating, next exam and tuition debt.
- **Schedule**: week strip with dates on phones and a full weekly grid on PC. Odd / even weeks (*toq / juft*) are detected from LMS and can be corrected with one tap. Classes you missed are marked **NB**.
- **Tasks**: grouped by overdue, today, tomorrow, this week, later, waiting for grade and graded, with search and course filters. The task sheet shows criteria, the teacher's file, your answer and the grade. Upload answers up to 50 MB.
- **Courses**: rating, the grade each course is heading for (from the work graded so far), a grade forecast (points still needed for 3 / 4 / 5), lessons with teacher files and NB marks, written exam questions.
- **Grades & GPA** (new): GPA as the LMS shows it, credits, grade distribution, every semester of the study plan and a **GPA simulator**.
- **Files** (new): every teacher file of the semester with search, type and course filters, open or Ask AI.
- **Attendance**: hours used against the 74-hour limit (1 NB = 2 hours), classes you can still miss, per-subject breakdown, excused absences marked.
- **Exams**: live countdown, results, test points, written questions.
- **News**: full article page.
- **Android home-screen widget** *TuitMate · Today*: current or next class, nearest deadline, open tasks and NB hours; updates at class start and end even when the app is closed.
- **AI assistant**: suggestions based on your LMS data, file attachments, retry, and "Ask in ChatGPT".
- Works with the **2026 redesign of lms.tuit.uz** (checked against a real account).

### Fixed
- The expected grade no longer reads 2 early in the semester: tasks that are not due yet don't count as zero.
- Open tasks, NB and file counts are the same on every screen and in the widget.
- Teachers who teach both the lecture and the practice are listed once.
- The schedule moves on to the new day when the app stays open overnight.
- Russian plurals, tab labels and text that did not fit on small phones.
