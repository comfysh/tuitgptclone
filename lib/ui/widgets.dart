import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import 'design.dart';
import 'lms_web_page.dart';
import 'nav.dart';

export 'design.dart';

/// Round icon button used in page headers.
class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.busy = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: cs.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: busy
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.primary))
                    : Icon(icon, size: 20, color: cs.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The header every page uses: title (or, for a section of a hub, the hub's
/// name with the section tabs below), the page's own buttons, "open in LMS"
/// and refresh.
PreferredSizeWidget pageAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget> actions = const [],
  String? lmsPath,
  PreferredSizeWidget? bottom,
}) {
  final app = context.watch<AppState>();
  final s = S.of(context);
  final cs = Theme.of(context).colorScheme;
  final section = HubSection.of(context);
  final hub = section == null ? null : hubOf(section);
  final tabs = hub != null && hubInfo[hub]!.sections.length > 1 ? HubTabs(hub: hub, current: section!) : null;
  return AppBar(
    toolbarHeight: subtitle == null ? 64 : 72,
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(tabs != null ? s[hubInfo[hub]!.key] : title),
      if (subtitle != null)
        Text(subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
    ]),
    bottom: tabs == null
        ? bottom
        : PreferredSize(
            preferredSize: Size.fromHeight(HubTabs.height + (bottom?.preferredSize.height ?? 0)),
            child: Column(children: [tabs, ?bottom]),
          ),
    actions: [
      ...actions,
      if (lmsPath != null)
        HeaderButton(icon: Icons.open_in_new_rounded, tooltip: s['openInLms'], onPressed: () => LmsWebPage.open(context, lmsPath)),
      HeaderButton(
        icon: Icons.refresh_rounded,
        tooltip: s['refresh'],
        busy: app.syncing,
        onPressed: () => app.refresh(),
      ),
      const SizedBox(width: 6),
    ],
  );
}

/// The sections of a hub as text tabs under the title ("Schedule · Deadlines ·
/// Exams"); the open one is underlined in ink.
class HubTabs extends StatelessWidget {
  const HubTabs({super.key, required this.hub, required this.current});
  final Hub hub;
  final Dest current;

  static const height = 42.0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    return Container(
      height: height,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
      alignment: Alignment.bottomLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in hubInfo[hub]!.sections)
            _tab(context, d, s[destInfo[d]!.tab], d == current, cs, d == Dest.inbox ? app.unread : 0),
        ]),
      ),
    );
  }

  Widget _tab(BuildContext context, Dest d, String label, bool selected, ColorScheme cs, int badge) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: selected ? null : () => context.read<NavController>().go(d),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? cs.onSurface : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                )),
            if (badge > 0) ...[const SizedBox(width: 6), CountBadge(badge)],
          ]),
        ),
      ),
    );
  }
}

/// Small rounded count, e.g. unread updates.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(9)),
      child: Text(count > 99 ? '99+' : '$count',
          style: TextStyle(color: cs.onPrimary, fontSize: 11, fontWeight: FontWeight.w700, height: 1, fontFeatures: tabular)),
    );
  }
}

/// Standard page: header (see [pageAppBar]), sync banner, pull-to-refresh
/// and a centred column on wide screens.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.lmsPath,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 28),
    this.fab,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final String? lmsPath;
  final PreferredSizeWidget? bottom;
  final EdgeInsets padding;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: pageAppBar(context, title: title, subtitle: subtitle, actions: actions, lmsPath: lmsPath, bottom: bottom),
      floatingActionButton: fab,
      body: RefreshIndicator(
        onRefresh: () => app.refresh(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
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

/// Session/error banner, or skeleton cards while the very first sync runs.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    if (app.sessionExpired) {
      return _Banner(
        color: Brand.warning,
        icon: Icons.lock_clock_rounded,
        text: s['sessionExpired'],
        action: FilledButton(onPressed: () => LmsWebPage.login(context), child: Text(s['signInAgain'])),
      );
    }
    if (app.lastError != null) {
      return _Banner(
        color: Brand.danger,
        icon: Icons.cloud_off_rounded,
        text: app.snapshot.isEmpty ? app.lastError! : s.f('savedData', {'time': fmtAgo(app.snapshot.updatedAt, s)}),
        action: TextButton(onPressed: () => app.refresh(), child: Text(s['retry'])),
      );
    }
    if (app.snapshot.isEmpty && app.syncing) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
            const SizedBox(width: 10),
            Text(s['syncing'], style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        const Skeleton(height: 150),
        const SizedBox(height: 12),
        const Row(children: [
          Expanded(child: Skeleton(height: 110)),
          SizedBox(width: 12),
          Expanded(child: Skeleton(height: 110)),
        ]),
        const SizedBox(height: 12),
        const Skeleton(height: 220),
      ]);
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
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(children: [
          TintIcon(icon, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
          ?action,
        ]),
      ),
    );
  }
}

/// Section title (kept for existing screens; same look as [SectionHeader]).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        ?trailing,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => EmptyView(icon: icon, title: text);
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Tag(text, color: color, icon: icon);
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size * 0.32)),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ),
        Expanded(child: SelectableText(value!, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
