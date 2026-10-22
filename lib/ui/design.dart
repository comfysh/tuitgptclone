// TuitMate design system: colours, theme, and the building blocks every
// screen uses (cards, hero gradient, stat tiles, rings, badges, skeletons).

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand colours.
class Brand {
  static const primary = Color(0xFF3C6EFF);
  static const primaryDeep = Color(0xFF2848E0);
  static const violet = Color(0xFF7A5CFF);
  static const success = Color(0xFF16A36A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFE5484D);
  static const info = Color(0xFF0EA5E9);

  static const hero = LinearGradient(
    colors: [Color(0xFF3C6EFF), Color(0xFF6D5BFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const heroDark = LinearGradient(
    colors: [Color(0xFF2A47C9), Color(0xFF4B3FC2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const sunrise = LinearGradient(
    colors: [Color(0xFFFF8A4C), Color(0xFFFF5E8A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const mint = LinearGradient(
    colors: [Color(0xFF12B886), Color(0xFF0EA5E9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient heroFor(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? heroDark : hero;
}

const radiusL = 22.0;
const radiusM = 16.0;
const radiusS = 12.0;

ThemeData buildAppTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.primary,
    brightness: b,
    primary: dark ? const Color(0xFF8AA6FF) : Brand.primary,
    surface: dark ? const Color(0xFF161A24) : Colors.white,
  );
  final bg = dark ? const Color(0xFF0D1018) : const Color(0xFFF3F5FA);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Inter', brightness: b);
  final t = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    textTheme: t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.35),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      selectedLabelTextStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: scheme.primary),
      unselectedLabelTextStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
    ),
    chipTheme: base.chipTheme.copyWith(
      showCheckmark: false,
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
      labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: scheme.onSurface),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C2130) : const Color(0xFFF0F2F8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusM), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusL)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
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

/// Rounded card with a soft shadow (light) or a hairline border (dark).
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: accent),
          Expanded(child: content),
        ]),
      );
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? cs.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: dark && gradient == null ? Border.all(color: Colors.white.withValues(alpha: 0.06)) : null,
        boxShadow: dark
            ? null
            : [
                BoxShadow(color: const Color(0xFF1B2559).withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 4)),
              ],
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

/// Big gradient card used as a page hero.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.gradient, this.padding = const EdgeInsets.all(20), this.onTap});
  final Widget child;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      gradient: gradient ?? Brand.heroFor(context),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Stack(children: [
        // Soft decorative circles.
        Positioned(right: -40, top: -50, child: _Bubble(160, Colors.white.withValues(alpha: 0.10))),
        Positioned(right: 60, bottom: -70, child: _Bubble(140, Colors.white.withValues(alpha: 0.07))),
        Padding(
          padding: padding,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: child),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.size, this.color);
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

// ---------------------------------------------------------------- small pieces

/// Icon in a tinted rounded square.
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(size * 0.32)),
        child: Icon(icon, color: color, size: iconSize ?? size * 0.52),
      );
}

/// Small rounded label.
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: -0.1)),
        ),
      ]),
    );
  }
}

/// Number tile: icon, value, label.
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
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [TintIcon(icon, color: color, size: 34), const Spacer(), ?trailing]),
        const SizedBox(height: 12),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
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
    this.stroke = 7,
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
          painter: _RingPainter(v, color, track ?? color.withValues(alpha: 0.15), stroke),
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
  const Bar({super.key, required this.value, required this.color, this.height = 8});
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
          backgroundColor: color.withValues(alpha: 0.14),
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
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(grade?.toString() ?? '—',
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: size * 0.45)),
    );
  }
}

/// Section title with an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ]),
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
          width: 76,
          height: 76,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.10)),
          child: Icon(icon, size: 36, color: c),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
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
