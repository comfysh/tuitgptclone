# Changelog

All notable changes to TuitMate. The release notes on GitHub are taken from this file:
add a section `## [x.y.z] - date` and raise `version:` in `pubspec.yaml` (and `lib/core/version.dart`)
to publish a new release.

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
