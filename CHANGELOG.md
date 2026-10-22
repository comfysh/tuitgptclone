# Changelog

All notable changes to TuitMate. The release notes on GitHub are taken from this file:
add a section `## [x.y.z] - date` and raise `version:` in `pubspec.yaml` (and `lib/core/version.dart`)
to publish a new release.

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
