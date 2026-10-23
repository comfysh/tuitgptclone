// TuitMate design system, "paper" look: warm paper, ink text, one green
// accent, hairline-bordered flat cards, serif titles, no gradients. Every
// screen builds on these pieces (cards, header block, tags, rings, badges…).

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colours of the "paper" look: warm paper, ink-black text and one green
/// accent. Status colours are muted inks, not neon.
class Brand {
  static const primary = Color(0xFF1E7A53); // green ink (accent)
  static const primaryDeep = Color(0xFF155C3E);
  static const violet = Color(0xFF6E5A9C); // plum ink
  static const success = Color(0xFF2E8B57);
  static const warning = Color(0xFFB7791F); // ochre
  static const danger = Color(0xFFB4412F); // brick red
  static const info = Color(0xFF2B6CB0); // blue ink

  static const ink = Color(0xFF1C1B17);
  static const paper = Color(0xFFF6F4EE);
  static const paperCard = Color(0xFFFFFDF8);
  static const line = Color(0xFFE3DED2);
  static const inkMuted = Color(0xFF6A665C);

  // The paper look has no gradients: these stay as flat fills so screens that
  // ask for a "gradient" get a solid colour block.
  static const hero = LinearGradient(colors: [ink, ink]);
  static const heroDark = LinearGradient(colors: [Color(0xFF1F3A2D), Color(0xFF1F3A2D)]);
  static const sunrise = LinearGradient(colors: [Color(0xFF8C3A26), Color(0xFF8C3A26)]);
  static const mint = LinearGradient(colors: [primaryDeep, primaryDeep]);

  static LinearGradient heroFor(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? heroDark : hero;
}

const radiusL = 14.0;
const radiusM = 12.0;
const radiusS = 8.0;

/// Serif for page titles and big numbers; Inter for everything else.
const serif = 'SourceSerif';

/// Times and counts line up in columns.
const tabular = [FontFeature.tabularFigures()];

ThemeData buildAppTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final ink = dark ? const Color(0xFFECE9E0) : Brand.ink;
  final muted = dark ? const Color(0xFFA29E92) : Brand.inkMuted;
  final line = dark ? const Color(0xFF2E2F29) : Brand.line;
  final card = dark ? const Color(0xFF1B1C18) : Brand.paperCard;
  final bg = dark ? const Color(0xFF121310) : Brand.paper;
  final accent = dark ? const Color(0xFF6CC79A) : Brand.primary;
  final scheme = ColorScheme.fromSeed(seedColor: Brand.primary, brightness: b).copyWith(
    primary: accent,
    onPrimary: dark ? const Color(0xFF0E2A1D) : Colors.white,
    primaryContainer: dark ? const Color(0xFF1F3A2D) : const Color(0xFFE3F0E8),
    onPrimaryContainer: dark ? const Color(0xFFCDEBDB) : const Color(0xFF0F3D28),
    secondary: dark ? const Color(0xFFC8B98F) : const Color(0xFF7A6A43),
    surface: card,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceContainerHighest: dark ? const Color(0xFF26271F) : const Color(0xFFEFEBE2),
    surfaceContainer: dark ? const Color(0xFF1F201B) : const Color(0xFFF2EFE7),
    outline: dark ? const Color(0xFF6E6A60) : const Color(0xFF9A958A),
    outlineVariant: line,
    error: Brand.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Inter', brightness: b);
  final t = base.textTheme;
  TextStyle serifStyle(TextStyle? s, double size, {FontWeight w = FontWeight.w700, double ls = -0.3}) =>
      (s ?? const TextStyle()).copyWith(fontFamily: serif, fontSize: size, fontWeight: w, letterSpacing: ls, color: ink);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    textTheme: t.copyWith(
      displaySmall: serifStyle(t.displaySmall, 34, ls: -0.6),
      headlineMedium: serifStyle(t.headlineMedium, 28, ls: -0.5),
      headlineSmall: serifStyle(t.headlineSmall, 24, ls: -0.4),
      titleLarge: serifStyle(t.titleLarge, 21),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.4),
      bodySmall: t.bodySmall?.copyWith(height: 1.35),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: serif, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: ink),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL), side: BorderSide(color: line)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? ink : muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(size: 23, color: states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : muted)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      indicatorColor: scheme.primaryContainer,
      selectedLabelTextStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: ink),
      unselectedLabelTextStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, color: muted),
    ),
    chipTheme: base.chipTheme.copyWith(
      showCheckmark: false,
      backgroundColor: card,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
      labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: ink),
      secondaryLabelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusS), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusS), borderSide: BorderSide(color: accent, width: 1.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : scheme.surfaceContainerHighest),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : line),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFECE9E0) : Brand.ink,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: dark ? Brand.ink : Brand.paper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

// ---------------------------------------------------------------- surfaces

/// Flat paper card: card colour, a hairline border, no shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.gradient,
    this.radius = radiusL,
    this.accent,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final double radius;

  /// Coloured strip on the left (subject colour).
  final Color? accent;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 3, color: accent),
          Expanded(child: content),
        ]),
      );
    }
    final filled = gradient != null || color != null;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? cs.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: filled ? null : Border.all(color: cs.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Page header block: a solid ink (or subject-coloured) panel with light text.
/// [gradient] is accepted for compatibility; its first colour is used flat.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.gradient, this.padding = const EdgeInsets.all(20), this.onTap});
  final Widget child;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = gradient ?? Brand.heroFor(context);
    final fill = g.colors.isEmpty ? Brand.ink : g.colors.first;
    const fg = Color(0xFFF6F4EE);
    return AppCard(
      color: fill,
      padding: padding,
      onTap: onTap,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: fg),
        child: IconTheme.merge(data: const IconThemeData(color: fg), child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------- small pieces

/// Icon on a faint tinted square.
class TintIcon extends StatelessWidget {
  const TintIcon(this.icon, {super.key, required this.color, this.size = 40, this.iconSize});
  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(size * 0.24)),
        child: Icon(icon, color: color, size: iconSize ?? size * 0.5),
      );
}

/// Small label, like a stamp: tinted fill and a thin border in its colour.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.icon, this.filled = false});
  final String text;
  final Color? color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final fg = filled ? Colors.white : c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: filled ? c : c.withValues(alpha: 0.32)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
        ),
      ]),
    );
  }
}

/// A number with a label, on a bordered card (icon small, number in serif).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
          ),
          ?trailing,
        ]),
        const SizedBox(height: 8),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontFamily: serif, fontSize: 26, fontWeight: FontWeight.w700, color: cs.onSurface, height: 1.1, fontFeatures: tabular)),
      ]),
    );
  }
}

/// Circular progress with a centred child.
class Ring extends StatelessWidget {
  const Ring({
    super.key,
    required this.value,
    required this.color,
    this.size = 64,
    this.stroke = 5,
    this.child,
    this.track,
  });
  final double value; // 0..1
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => CustomPaint(
          painter: _RingPainter(v, color, track ?? color.withValues(alpha: 0.13), stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

/// Thin rounded progress bar.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.value, required this.color, this.height = 6});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

/// 5-point grade colours (LMS: 5 excellent, 4 good, 3 satisfactory, 2 fail).
Color gradeColor(int? g, ColorScheme cs) => switch (g) {
      null => cs.outline,
      >= 5 => Brand.success,
      4 => Brand.primary,
      3 => Brand.warning,
      _ => Brand.danger,
    };

/// Grade on a 5-point scale in a coloured rounded square.
class GradeBadge extends StatelessWidget {
  const GradeBadge(this.grade, {super.key, this.size = 36});
  final int? grade;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = gradeColor(grade, Theme.of(context).colorScheme);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(grade?.toString() ?? '—',
          style: TextStyle(fontFamily: serif, color: c, fontWeight: FontWeight.w700, fontSize: size * 0.5)),
    );
  }
}

/// Section label in small capitals with a thin rule, and an optional action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(2, 22, 2, 8),
      // The label takes the room it needs (up to 75 %); the rule fills the rest.
      child: LayoutBuilder(builder: (context, box) => Row(children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.75),
          child: Text(title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: cs.outlineVariant)),
        if (action != null) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ])),
    );
  }
}

/// Placeholder block shown while data loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 80, this.radius = radiusL, this.width});
  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.05 + 0.05 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Friendly empty state.
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.subtitle, this.color});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.withValues(alpha: 0.35), width: 1.4)),
          child: Icon(icon, size: 30, color: c),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ]),
    );
  }
}

/// Two-column grid on wide screens, single column on phones.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 340, this.spacing = 12});
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = math.max(1, (c.maxWidth / minItemWidth).floor());
      if (cols == 1) {
        return Column(children: [
          for (final w in children) Padding(padding: EdgeInsets.only(bottom: spacing), child: w),
        ]);
      }
      final width = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(spacing: spacing, runSpacing: spacing, children: [
        for (final w in children) SizedBox(width: width, child: w),
      ]);
    });
  }
}
