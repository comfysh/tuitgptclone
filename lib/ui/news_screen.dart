import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import '../lms/models.dart';
import 'lms_web_page.dart';
import 'widgets.dart';

/// University announcements from LMS: the newest as a featured card, the rest
/// in a list (two columns on wide screens). Tap opens the full article.
class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final news = _newestFirst(snap.news);
    return PageScaffold(
      title: s['news'],
      lmsPath: '/dashboard/news',
      children: [
        if (news.isEmpty) ...[
          if (!(snap.isEmpty && app.syncing))
            AppCard(
              child: snap.isEmpty
                  ? EmptyView(
                      icon: Icons.cloud_sync_rounded,
                      title: s['nwNotSynced'],
                      subtitle: s['nwNotSyncedSub'],
                      color: Brand.info)
                  : EmptyView(
                      icon: Icons.campaign_rounded,
                      title: s['nwEmptyTitle'],
                      subtitle: s['nwEmptySub'],
                      color: Brand.info),
            ),
        ] else ...[
          _FeaturedCard(news.first),
          if (news.length > 1) ...[
            SectionHeader(s['nwEarlier']),
            for (var i = 1; i < news.length; i += 2)
              _Pair(_NewsCard(news[i]), i + 1 < news.length ? _NewsCard(news[i + 1]) : null),
          ],
        ],
      ],
    );
  }
}

/// Full article: title, date, the whole text (selectable) and links to the
/// original page.
class NewsDetailPage extends StatelessWidget {
  const NewsDetailPage({super.key, required this.item});
  final NewsItem item;

  static Future<void> open(BuildContext context, NewsItem item) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewsDetailPage(item: item)));

  Future<void> _openExternal(BuildContext context, String url) async {
    final s = S.read(context);
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      final uri = Uri.tryParse(url);
      if (uri != null) ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(s['nwOpenFailed'])));
  }

  Future<void> _copy(BuildContext context, String url) async {
    final s = S.read(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(SnackBar(content: Text(s['copied'])));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final url = item.url;
    final date = item.date;
    final lines = _bodyLines(item);
    return Scaffold(
      appBar: AppBar(
        title: Text(s['news']),
        actions: [
          if (url != null) ...[
            IconButton(
              tooltip: s['nwCopyLink'],
              icon: const Icon(Icons.link_rounded),
              onPressed: () => _copy(context, url),
            ),
            IconButton(
              tooltip: s['nwOpenBrowser'],
              icon: const Icon(Icons.public_rounded),
              onPressed: () => _openExternal(context, url),
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              AppCard(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (date != null)
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      Tag('${fmtWeekday(date, s.lang)}, ${fmtDateFull(date, s.lang)}',
                          icon: Icons.event_rounded, color: Brand.info),
                      if (_isNew(date)) Tag(s['nwNew'], color: Brand.success),
                    ]),
                  const SizedBox(height: 14),
                  SelectableText(
                    _title(item),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontSize: 22, height: 1.25, fontWeight: FontWeight.w800),
                  ),
                  const Divider(height: 34),
                  if (lines.isEmpty)
                    Row(children: [
                      Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s['nwNoBody'], style: TextStyle(color: cs.onSurfaceVariant))),
                    ])
                  else
                    _ArticleBody(lines),
                ]),
              ),
              if (url != null) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton.icon(
                    onPressed: () => LmsWebPage.open(context, url),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(s['openInLms']),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openExternal(context, url),
                    icon: const Icon(Icons.public_rounded),
                    label: Text(s['nwOpenBrowser']),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- helpers

/// Newest first; undated items keep their LMS order after the dated ones.
List<NewsItem> _newestFirst(List<NewsItem> news) {
  final indexed = [for (var i = 0; i < news.length; i++) (i, news[i])];
  indexed.sort((a, b) {
    final da = a.$2.date, db = b.$2.date;
    if (da != null && db != null) {
      final c = db.compareTo(da);
      if (c != 0) return c;
    } else if (da != null) {
      return -1;
    } else if (db != null) {
      return 1;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

String _title(NewsItem n) => n.title.trim().isEmpty ? '—' : n.title.trim();

/// Non-empty paragraphs of the body, without a first line that repeats the title.
List<String> _bodyLines(NewsItem n) {
  final lines = (n.body ?? '').split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isNotEmpty && lines.first == n.title.trim()) lines.removeAt(0);
  return lines;
}

/// The start of the body on one line, for cards.
String? _excerpt(NewsItem n) {
  final t = _bodyLines(n).join(' ').replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  final runes = t.runes;
  return runes.length > 400 ? String.fromCharCodes(runes.take(400)) : t;
}

/// Whole calendar days between [d] and today (DST-safe).
int _daysAgo(DateTime d) {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
}

bool _isNew(DateTime d) {
  final ago = _daysAgo(d);
  return ago >= 0 && ago <= 2;
}

String _dateLabel(DateTime d, S s) {
  final ago = _daysAgo(d);
  if (ago == 0) return s['nwToday'];
  if (ago == 1) return s['nwYesterday'];
  return d.year == DateTime.now().year ? fmtDate(d, s.lang) : fmtDateFull(d, s.lang);
}

// ---------------------------------------------------------------- pieces

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard(this.n);
  final NewsItem n;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final white70 = Colors.white.withValues(alpha: 0.8);
    final excerpt = _excerpt(n);
    final date = n.date;
    return HeroCard(
      onTap: () => NewsDetailPage.open(context, n),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.campaign_rounded, size: 14),
              const SizedBox(width: 5),
              Text(s['nwLatest'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: date == null
                ? const SizedBox.shrink()
                : Text(_dateLabel(date, s),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: white70, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 16),
        Text(_title(n),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.4)),
        if (excerpt != null) ...[
          const SizedBox(height: 8),
          Text(excerpt, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: white70, height: 1.4)),
        ],
        const SizedBox(height: 16),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(s['nwReadMore'], style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_rounded, size: 18),
        ]),
      ]),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard(this.n);
  final NewsItem n;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final excerpt = _excerpt(n);
    final date = n.date;
    return AppCard(
      onTap: () => NewsDetailPage.open(context, n),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (date != null) Tag(_dateLabel(date, s), icon: Icons.event_rounded, color: Brand.info),
          if (date != null && _isNew(date)) ...[const SizedBox(width: 6), Tag(s['nwNew'], color: Brand.success)],
          const Spacer(),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
        const SizedBox(height: 10),
        Text(_title(n),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.2)),
        if (excerpt != null) ...[
          const SizedBox(height: 6),
          Text(excerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5, height: 1.4)),
        ],
      ]),
    );
  }
}

/// Article text: paragraphs with a small gap, list items kept together.
class _ArticleBody extends StatelessWidget {
  const _ArticleBody(this.lines);
  final List<String> lines;

  static final _listItem = RegExp(r'^(•|\d+\.)\s');

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.6);
    const gap = TextStyle(fontSize: 9, height: 1);
    return SelectableText.rich(
      TextSpan(style: style, children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const TextSpan(text: '\n'),
          if (i > 0 && !(_listItem.hasMatch(lines[i - 1]) && _listItem.hasMatch(lines[i])))
            const TextSpan(text: '\n', style: gap),
          TextSpan(text: lines[i]),
        ],
      ]),
    );
  }
}

/// Two cards side by side with equal height on wide screens, stacked on phones.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a;
  final Widget? b;

  @override
  Widget build(BuildContext context) {
    final b = this.b;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 680) {
          return Column(children: [a, if (b != null) ...[const SizedBox(height: 12), b]]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b ?? const SizedBox.shrink()),
          ]),
        );
      }),
    );
  }
}
