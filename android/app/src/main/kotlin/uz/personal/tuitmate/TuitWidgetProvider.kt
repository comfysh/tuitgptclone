package uz.personal.tuitmate

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.icu.text.DateFormat
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import java.util.Date
import java.util.Locale
import org.json.JSONObject

/**
 * Home-screen widget "TuitMate · Today".
 *
 * The app (lib/services/home_widget_service.dart) saves the class slots of the next days,
 * the deadlines of open tasks, NB hours and the texts in the user's language. This provider
 * picks the current / next class and counts the open tasks itself on every redraw, so the
 * widget stays right while the app is closed. It redraws after each sync, every 30 minutes,
 * and at the next class start / end, deadline or midnight (an inexact alarm it re-arms on
 * every redraw).
 */
class TuitWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) draw(context, appWidgetManager, id, widgetData)
        scheduleNext(context, appWidgetManager, widgetData)
    }

    /** All widgets removed: drop the pending redraw. */
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        try {
            context.getSystemService(AlarmManager::class.java)?.cancel(redrawIntent(context, IntArray(0)))
        } catch (e: Exception) {
        }
    }

    /**
     * Arms one redraw at the next moment the widget's content changes: a class starts or ends,
     * a deadline passes, a new day begins or the saved schedule runs out. Non-wakeup and
     * inexact (no extra permission); Android may delay it by a few minutes.
     */
    private fun scheduleNext(context: Context, manager: AppWidgetManager, prefs: SharedPreferences) {
        try {
            val alarms = context.getSystemService(AlarmManager::class.java) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, TuitWidgetProvider::class.java))
            val data = readJson(prefs, DATA_KEY)
            if (ids.isEmpty() || data == null) {
                alarms.cancel(redrawIntent(context, ids))
                return
            }
            val now = System.currentTimeMillis()
            val times = ArrayList<Long>()
            for (slot in parseSlots(data)) {
                times.add(slot.start)
                times.add(slot.end)
            }
            for (task in parseTasks(data)) if (task.due > 0L) times.add(task.due)
            times.add(startOfDay(now, 1))
            times.add(data.optLong("until", 0L))
            val next = times.filter { it > now }.minOrNull() ?: return
            // A second late, so the class / deadline has really started or passed.
            alarms.setWindow(AlarmManager.RTC, next + 1000L, ALARM_WINDOW_MS, redrawIntent(context, ids))
        } catch (e: Exception) {
            // The 30-minute updatePeriodMillis still redraws the widget.
        }
    }

    /** Broadcast that makes this provider redraw [ids]. One per app (same request code). */
    private fun redrawIntent(context: Context, ids: IntArray): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST,
            Intent(context, TuitWidgetProvider::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /** Resized: show or hide the optional rows for the new height. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        draw(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun draw(context: Context, manager: AppWidgetManager, widgetId: Int, prefs: SharedPreferences) {
        try {
            val labels = Labels(readJson(prefs, LABELS_KEY))
            val views =
                try {
                    build(context, labels, readJson(prefs, DATA_KEY), heightDp(context, manager, widgetId))
                } catch (e: Exception) {
                    message(context, labels, labels.text("openApp", "Open TuitMate to see your day"))
                }
            views.setOnClickPendingIntent(
                android.R.id.background,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            manager.updateAppWidget(widgetId, views)
        } catch (e: Exception) {
            // Never crash the app process from a broadcast; the widget keeps its last content.
        }
    }

    private fun build(context: Context, l: Labels, data: JSONObject?, heightDp: Int): RemoteViews {
        if (data == null) return message(context, l, l.text("openApp", "Open TuitMate to see your day"))
        val now = System.currentTimeMillis()
        // The saved schedule only covers a week: past it, ask for a sync instead of guessing.
        if (data.optLong("until", 0L) <= now) return message(context, l, l.text("sync", "Open TuitMate to sync"))

        val todayStart = startOfDay(now, 0)
        val tomorrowStart = startOfDay(now, 1)
        val dayAfterStart = startOfDay(now, 2)

        val slots = parseSlots(data)
        val today = slots.filter { it.start >= todayStart && it.start < tomorrowStart }
        val current = today.firstOrNull { now < it.end }
        val later = slots.firstOrNull { it.start >= tomorrowStart }

        val views = RemoteViews(context.packageName, R.layout.tuit_widget)
        views.setTextViewText(R.id.tw_date, l.date(now))

        if (current != null) {
            val isNow = now >= current.start
            val state = if (isNow) l.text("now", "Now") else l.text("next", "Next")
            views.setViewVisibility(R.id.tw_badge, View.VISIBLE)
            views.setTextViewText(R.id.tw_badge, "$state · ${clock(current.start)}–${clock(current.end)}")
            views.setInt(
                R.id.tw_badge,
                "setBackgroundResource",
                if (isNow) R.drawable.tuit_widget_pill_now else R.drawable.tuit_widget_pill,
            )
            views.setTextColor(
                R.id.tw_badge,
                context.getColor(if (isNow) R.color.tuit_widget_now_text else R.color.tuit_widget_text),
            )
            views.setTextViewText(R.id.tw_title, current.subject.ifEmpty { "—" })
            val meta = joinParts(current.room, current.kind)
            views.setTextViewText(R.id.tw_subtitle, meta)
            views.setViewVisibility(R.id.tw_subtitle, if (meta.isEmpty()) View.GONE else View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.tw_badge, View.GONE)
            views.setTextViewText(
                R.id.tw_title,
                if (today.isEmpty()) l.text("free", "No classes today")
                else l.text("noMore", "No more classes today"),
            )
            val sub =
                when {
                    later == null -> l.text("noneWeek", "No classes in the next 7 days")
                    later.start < dayAfterStart ->
                        joinParts(
                            l.text("tomorrowAt", "Tomorrow, {time}").replace("{time}", clock(later.start)),
                            later.subject,
                        )
                    else -> joinParts(l.weekday(later.start) + ", " + clock(later.start), later.subject)
                }
            views.setTextViewText(R.id.tw_subtitle, sub)
            views.setViewVisibility(R.id.tw_subtitle, View.VISIBLE)
        }

        // Nearest deadline. Tasks without a deadline (due 0) are open too.
        val tasks = parseTasks(data).filter { it.due == 0L || it.due > now }
        val nearest = tasks.filter { it.due > 0L }.minByOrNull { it.due } ?: tasks.firstOrNull()
        if (nearest == null) {
            views.setImageViewResource(R.id.tw_due_icon, R.drawable.tuit_widget_ic_done)
            views.setTextViewText(R.id.tw_due_title, l.text("noTasks", "No open tasks"))
            views.setViewVisibility(R.id.tw_due_when, View.GONE)
        } else {
            views.setImageViewResource(R.id.tw_due_icon, R.drawable.tuit_widget_ic_due)
            views.setTextViewText(R.id.tw_due_title, nearest.title.ifEmpty { "—" })
            if (nearest.due > 0L) {
                views.setTextViewText(R.id.tw_due_when, dueText(l, nearest.due, todayStart, tomorrowStart, dayAfterStart))
                views.setViewVisibility(R.id.tw_due_when, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.tw_due_when, View.GONE)
            }
        }

        // Classes today | open tasks | NB hours
        views.setTextViewText(R.id.tw_classes_value, today.size.toString())
        views.setTextViewText(R.id.tw_classes_label, l.text("classes", "classes today"))
        views.setTextViewText(R.id.tw_tasks_value, tasks.size.toString())
        views.setTextViewText(R.id.tw_tasks_label, l.text("tasks", "open tasks"))
        views.setTextViewText(R.id.tw_nb_value, "${data.optInt("nbUsed", 0)}/${data.optInt("nbLimit", 0)}")
        views.setTextViewText(R.id.tw_nb_label, l.text("nb", "NB hours"))
        views.setViewVisibility(R.id.tw_stats, View.VISIBLE)

        // Short widgets (resized, landscape) drop the header first, then the deadline row.
        // 0 means the launcher did not say: show everything.
        views.setViewVisibility(R.id.tw_header, if (heightDp in 1 until FULL_HEIGHT_DP) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.tw_due_row, if (heightDp in 1 until DUE_ROW_HEIGHT_DP) View.GONE else View.VISIBLE)
        return views
    }

    /** Only a line of text: no data (never synced / signed out) or an outdated schedule. */
    private fun message(context: Context, l: Labels, text: String): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.tuit_widget)
        views.setTextViewText(R.id.tw_date, l.date(System.currentTimeMillis()))
        views.setViewVisibility(R.id.tw_header, View.VISIBLE)
        views.setViewVisibility(R.id.tw_badge, View.GONE)
        views.setTextViewText(R.id.tw_title, text)
        views.setViewVisibility(R.id.tw_subtitle, View.GONE)
        views.setViewVisibility(R.id.tw_due_row, View.GONE)
        views.setViewVisibility(R.id.tw_stats, View.GONE)
        return views
    }

    private fun dueText(l: Labels, due: Long, todayStart: Long, tomorrowStart: Long, dayAfterStart: Long): String =
        when {
            due < tomorrowStart -> l.text("dueToday", "today, {time}").replace("{time}", clock(due))
            due < dayAfterStart -> l.text("dueTomorrow", "tomorrow, {time}").replace("{time}", clock(due))
            else -> {
                // Calendar days; the half day absorbs a DST shift.
                val days = (startOfDay(due, 0) - todayStart + DAY_MS / 2) / DAY_MS
                l.text("inDays", "in {n} days").replace("{n}", days.toString())
            }
        }

    /** Height the widget has now, in dp (0 when the launcher did not report it). */
    private fun heightDp(context: Context, manager: AppWidgetManager, widgetId: Int): Int {
        val options = manager.getAppWidgetOptions(widgetId) ?: return 0
        val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        // Portrait uses the "max" height, landscape the "min" one.
        val key =
            if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
            else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
        return options.getInt(key, 0)
    }

    private class Slot(val start: Long, val end: Long, val subject: String, val room: String, val kind: String)

    private class Task(val title: String, val due: Long)

    private fun parseSlots(data: JSONObject): List<Slot> {
        val arr = data.optJSONArray("slots") ?: return emptyList()
        val out = ArrayList<Slot>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val start = o.optLong("s", 0L)
            val end = o.optLong("e", 0L)
            if (start <= 0L || end <= start) continue
            out.add(Slot(start, end, str(o, "t").trim(), str(o, "r").trim(), str(o, "k").trim()))
        }
        out.sortBy { it.start }
        return out
    }

    private fun parseTasks(data: JSONObject): List<Task> {
        val arr = data.optJSONArray("tasks") ?: return emptyList()
        val out = ArrayList<Task>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            // 0 = no deadline (still an open task).
            val due = o.optLong("d", 0L).coerceAtLeast(0L)
            out.add(Task(str(o, "t").trim(), due))
        }
        return out
    }

    /** Texts saved by the app in the user's language, with English fallbacks. */
    private class Labels(private val json: JSONObject?) {
        val locale: Locale = str(json, "lang").let { if (it.isEmpty()) Locale.getDefault() else Locale.forLanguageTag(it) }

        fun text(key: String, fallback: String): String = str(json, key).ifEmpty { fallback }

        /** Short weekday name, e.g. "Mon" / "Du" / "Пн". */
        fun weekday(time: Long): String {
            val c = Calendar.getInstance()
            c.timeInMillis = time
            val index = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 // Monday = 0 … Sunday = 6
            val name = json?.optJSONArray("wd")?.optString(index, "") ?: ""
            return name.ifEmpty { format("EEE", time) }
        }

        /** Header date, e.g. "Thu, Oct 22" / "Pay, 22-okt" / "Чт, 22 окт.". */
        fun date(time: Long): String =
            format("EEEdMMM", time).replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }

        private fun format(skeleton: String, time: Long): String =
            try {
                DateFormat.getInstanceForSkeleton(skeleton, locale).format(Date(time))
            } catch (e: Exception) {
                ""
            }
    }

    private companion object {
        const val DATA_KEY = "tuitmate_widget_data"
        const val LABELS_KEY = "tuitmate_widget_labels"
        const val DAY_MS = 24L * 60 * 60 * 1000
        const val ALARM_REQUEST = 4711
        const val ALARM_WINDOW_MS = 60_000L

        /** Below this height (dp) the header row is hidden. */
        const val FULL_HEIGHT_DP = 205

        /** Below this height (dp) the deadline row is hidden too. */
        const val DUE_ROW_HEIGHT_DP = 182

        /** A JSON object the app saved, or null when it is missing or unreadable. */
        fun readJson(prefs: SharedPreferences, key: String): JSONObject? =
            try {
                prefs.getString(key, null)?.let { JSONObject(it) }
            } catch (e: Exception) {
                null
            }

        fun str(o: JSONObject?, key: String): String =
            if (o == null || o.isNull(key)) "" else o.optString(key, "")

        fun joinParts(vararg parts: String): String = parts.filter { it.isNotEmpty() }.joinToString(" · ")

        fun clock(time: Long): String {
            val c = Calendar.getInstance()
            c.timeInMillis = time
            return String.format(Locale.ROOT, "%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
        }

        /** Local midnight [plusDays] days after the day of [time]. */
        fun startOfDay(time: Long, plusDays: Int): Long {
            val c = Calendar.getInstance()
            c.timeInMillis = time
            c.set(Calendar.HOUR_OF_DAY, 0)
            c.set(Calendar.MINUTE, 0)
            c.set(Calendar.SECOND, 0)
            c.set(Calendar.MILLISECOND, 0)
            if (plusDays != 0) c.add(Calendar.DAY_OF_YEAR, plusDays)
            return c.timeInMillis
        }
    }
}
