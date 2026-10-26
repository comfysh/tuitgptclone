import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import 'widgets.dart';

/// Profile › Appearance › Theme: every theme as a small preview (its paper,
/// header block, a card, the accent and the title font), plus "pure black".
Future<void> showThemePicker(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _ThemePicker()),
    );

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 640 ? 3 : 2;
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(s['thStyle'], style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
          children: [
            for (final style in AppStyle.values)
              ThemePreview(
                style: style,
                brightness: b,
                pureBlack: app.settings.pureBlack,
                selected: app.style == style,
                onTap: () => app.setStyle(style),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: app.settings.pureBlack,
            onChanged: app.setPureBlack,
            title: Text(s['thPureBlack'], style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(s['thPureBlackSub'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          ),
        ),
      ]);
    });
  }
}

/// A theme drawn in miniature with its own colours.
class ThemePreview extends StatelessWidget {
  const ThemePreview({
    super.key,
    required this.style,
    required this.brightness,
    required this.selected,
    required this.onTap,
    this.pureBlack = false,
  });
  final AppStyle style;
  final Brightness brightness;
  final bool selected;
  final bool pureBlack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final spec = styleSpecs[style]!;
    final p = spec.of(brightness, pureBlack: pureBlack);
    final font = spec.serifTitles ? brandFont : 'Inter';
    Widget bar(double w, Color c, {double h = 6}) =>
        Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));
    return Semantics(
      selected: selected,
      button: true,
      label: s[spec.nameKey],
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusL),
        child: Container(
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(radiusL),
            border: Border.all(color: selected ? p.accent : p.line, width: selected ? 2.4 : 1),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header block with the title font.
            Container(
              height: 46,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: p.hero, borderRadius: BorderRadius.circular(8)),
              child: Text('3.60',
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 20,
                    fontWeight: spec.serifTitles ? FontWeight.w700 : FontWeight.w800,
                    color: const Color(0xFFF6F4EE),
                  )),
            ),
            const SizedBox(height: 8),
            // A card with text lines and an accent chip.
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  bar(64, p.ink),
                  const SizedBox(height: 6),
                  bar(90, p.muted, h: 5),
                  const Spacer(),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(5)),
                      child: bar(22, p.onAccentSoft, h: 5),
                    ),
                    const Spacer(),
                    Container(width: 26, height: 14, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(7))),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(s[spec.nameKey],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 15, color: p.ink)),
              ),
              if (selected) Icon(Icons.check_circle_rounded, size: 18, color: p.accent),
            ]),
            Text(s['${spec.nameKey}Sub'],
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.25)),
          ]),
        ),
      ),
    );
  }
}
