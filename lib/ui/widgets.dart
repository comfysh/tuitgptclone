import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import 'lms_web_page.dart';

/// Standard page: app bar with refresh, sync/session banner, pull-to-refresh.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.lmsPath,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
    this.fab,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final String? lmsPath;
  final PreferredSizeWidget? bottom;
  final EdgeInsets padding;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: bottom,
        actions: [
          ...actions,
          if (lmsPath != null)
            IconButton(
              tooltip: s['openInLms'],
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => LmsWebPage.open(context, lmsPath),
            ),
          IconButton(
            tooltip: s['refresh'],
            icon: app.syncing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Theme.of(context).appBarTheme.foregroundColor ?? Theme.of(context).colorScheme.onSurface))
                : const Icon(Icons.refresh),
            onPressed: app.syncing ? null : () => app.refresh(),
          ),
        ],
      ),
      floatingActionButton: fab,
      body: RefreshIndicator(
        onRefresh: () => app.refresh(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: padding,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [const SyncBanner(), ...children],
            ),
          ),
        ),
      ),
    );
  }
}

class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    if (app.sessionExpired) {
      return _Banner(
        color: cs.errorContainer,
        icon: Icons.lock_clock,
        text: s['sessionExpired'],
        action: FilledButton.tonal(onPressed: () => LmsWebPage.login(context), child: Text(s['signInAgain'])),
      );
    }
    if (app.lastError != null) {
      return _Banner(
        color: cs.errorContainer,
        icon: Icons.cloud_off,
        text: app.snapshot.isEmpty ? app.lastError! : s.f('savedData', {'time': fmtAgo(app.snapshot.updatedAt, s)}),
        action: TextButton(onPressed: () => app.refresh(), child: Text(s['retry'])),
      );
    }
    if (app.snapshot.isEmpty && app.syncing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(s['syncing']),
        ]),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text, this.action});
  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            if (action != null) action!,
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(children: [
        Icon(icon, size: 44, color: cs.outline),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Big number in a coloured circle, e.g. a score.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.text, required this.color, this.size = 46});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.32)),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 140,
          child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: SelectableText(value!)),
      ]),
    );
  }
}
