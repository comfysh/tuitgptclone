import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import 'lms_web_page.dart';
import 'widgets.dart';

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final news = app.snapshot.news;
    return PageScaffold(
      title: s['news'],
      lmsPath: '/dashboard/news',
      children: [
        if (news.isEmpty && !app.snapshot.isEmpty) EmptyState(icon: Icons.campaign_outlined, text: s['noData']),
        for (final n in news)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: n.url == null ? null : () => LmsWebPage.open(context, n.url),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (n.date != null)
                      Text(fmtDateFull(n.date!, s.lang), style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (n.body != null) ...[
                      const SizedBox(height: 6),
                      Text(n.body!, maxLines: 6, overflow: TextOverflow.ellipsis),
                    ],
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
