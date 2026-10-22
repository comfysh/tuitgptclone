import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import 'design.dart';
import 'lms_web_page.dart';

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

/// Standard page: big title, refresh / open-in-LMS buttons, sync banner,
/// pull-to-refresh and a centred column on wide screens.
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
    final app = context.watch<AppState>();
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: subtitle == null ? 64 : 72,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title),
          if (subtitle != null)
            Text(subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ]),
        bottom: bottom,
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
      ),
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
          if (action != null) action!,
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
