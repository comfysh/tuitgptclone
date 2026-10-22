import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import 'design.dart';
import 'lms_web_page.dart';

/// First screen: what TuitMate does, the language switcher and "Sign in with LMS".
/// Hero on the left and a sign-in card on the right on PC; one column on phones.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900 ? const _WideLayout() : const _PhoneLayout(),
      ),
    );
  }
}

/// The four highlights shown on the welcome screen.
const _features = [
  (Icons.calendar_month_rounded, Brand.primary, 'wlFeatTimetable', 'wlFeatTimetableSub'),
  (Icons.assignment_turned_in_rounded, Brand.warning, 'wlFeatTasks', 'wlFeatTasksSub'),
  (Icons.workspace_premium_rounded, Brand.success, 'wlFeatGrades', 'wlFeatGradesSub'),
  (Icons.auto_awesome_rounded, Brand.violet, 'wlFeatAi', 'wlFeatAiSub'),
];

void _signIn(BuildContext context) => LmsWebPage.login(context);

// ---------------------------------------------------------------- PC

class _WideLayout extends StatelessWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Expanded(flex: 6, child: _HeroPanel()),
      Expanded(
        flex: 5,
        child: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: _CenteredScroll(
                padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: const AppCard(padding: EdgeInsets.fromLTRB(28, 30, 28, 24), child: _SignInPanel()),
                ),
              ),
            ),
            const Positioned(top: 20, right: 24, child: _LangSwitch()),
          ]),
        ),
      ),
    ]);
  }
}

/// Full-height gradient with the mark, tagline and feature tiles.
class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final white80 = Colors.white.withValues(alpha: 0.82);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: Brand.heroFor(context)),
      child: Stack(children: [
        Positioned(right: -90, top: -110, child: _Circle(340, Colors.white.withValues(alpha: 0.08))),
        Positioned(left: -70, bottom: -120, child: _Circle(300, Colors.white.withValues(alpha: 0.06))),
        Positioned(right: 80, bottom: 60, child: _Circle(90, Colors.white.withValues(alpha: 0.07))),
        SafeArea(
          child: _CenteredScroll(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const _BrandRow(size: 52),
                  const SizedBox(height: 40),
                  Text(s['welcomeTitle'],
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 14),
                  Text(s['welcomeBody'], style: TextStyle(color: white80, fontSize: 16, height: 1.4)),
                  const SizedBox(height: 32),
                  for (var i = 0; i < _features.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: _HeroFeature(_features[i])),
                        const SizedBox(width: 12),
                        Expanded(child: _HeroFeature(_features[i + 1])),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Translucent white feature tile on the gradient.
class _HeroFeature extends StatelessWidget {
  const _HeroFeature(this.f);
  final (IconData, Color, String, String) f;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radiusM),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TintIcon(f.$1, color: Colors.white, size: 38),
        const SizedBox(height: 12),
        Text(s[f.$3], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text(s[f.$4], style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 13, height: 1.35)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- phone

class _PhoneLayout extends StatelessWidget {
  const _PhoneLayout();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    return SafeArea(
      child: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            // Full-bleed on phones; a centred 640 px column on wider windows.
            final side = c.maxWidth > 640 ? (c.maxWidth - 640) / 2 : 0.0;
            return ListView(padding: EdgeInsets.fromLTRB(side, 0, side, 16), children: [
            const _PhoneHero(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Column(children: [
                    for (var i = 0; i < _features.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 52, color: cs.outlineVariant.withValues(alpha: 0.35)),
                      _FeatureRow(_features[i]),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),
                const _PrivacyNote(),
                const SizedBox(height: 14),
                Text(s['unofficial'],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
              ]),
            ),
          ]);
          }),
        ),
        // The main action stays visible on short screens.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SizedBox(width: double.infinity, child: _SignInButton(enabled: !app.wiping)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PhoneHero extends StatelessWidget {
  const _PhoneHero();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: Brand.heroFor(context),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(right: -50, top: -60, child: _Circle(190, Colors.white.withValues(alpha: 0.09))),
        Positioned(left: -40, bottom: -70, child: _Circle(150, Colors.white.withValues(alpha: 0.07))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 26),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Align(alignment: Alignment.centerRight, child: _LangSwitch(onGradient: true)),
            const SizedBox(height: 14),
            const _BrandRow(size: 56),
            const SizedBox(height: 18),
            Text(s['welcomeTitle'],
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.4)),
            const SizedBox(height: 6),
            Text(s['wlSignInSub'], style: TextStyle(color: Colors.white.withValues(alpha: 0.82), height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.f);
  final (IconData, Color, String, String) f;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        TintIcon(f.$1, color: f.$2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s[f.$3], style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(s[f.$4], style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- shared pieces

/// Mark (rounded square with a school icon) and the app name.
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
        ),
        child: Icon(Icons.school_rounded, color: Colors.white, size: size * 0.56),
      ),
      const SizedBox(width: 14),
      Flexible(
        child: Text('TuitMate',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
      ),
    ]);
  }
}

/// PC sign-in card content.
class _SignInPanel extends StatelessWidget {
  const _SignInPanel();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(gradient: Brand.heroFor(context), borderRadius: BorderRadius.circular(radiusS)),
          child: const Icon(Icons.school_rounded, color: Colors.white, size: 26),
        ),
      ),
      const SizedBox(height: 18),
      Text(s['wlHello'], style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(s['wlSignInSub'], style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 22),
      _SignInButton(enabled: !app.wiping),
      const SizedBox(height: 14),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        Tag(s['wlMethodPassword'], icon: Icons.password_rounded, color: Brand.primary),
        const Tag('OneID', icon: Icons.verified_user_rounded, color: Brand.success),
      ]),
      const SizedBox(height: 18),
      const _PrivacyNote(),
      const SizedBox(height: 18),
      Text(s['unofficial'],
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
    ]);
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Brand.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16),
        ),
        onPressed: enabled ? () => _signIn(context) : null,
        icon: enabled
            ? const Icon(Icons.login_rounded)
            : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
        label: Text(s['wlSignInBtn'], maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// "You sign in on the real lms.tuit.uz page…" with a lock icon.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radiusS),
        border: Border.all(color: Brand.success.withValues(alpha: 0.18)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TintIcon(Icons.lock_rounded, color: Brand.success, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Text(s['signInNote'],
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
        ),
      ]),
    );
  }
}

/// EN / UZ / RU segmented switch.
class _LangSwitch extends StatelessWidget {
  const _LangSwitch({this.onGradient = false});
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppState>();
    final fg = onGradient ? Colors.white : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onGradient ? Colors.white.withValues(alpha: 0.16) : cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: onGradient ? Colors.white.withValues(alpha: 0.22) : cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.translate_rounded, size: 16, color: fg),
        ),
        for (final e in S.languages.entries)
          _LangSegment(
            code: e.key.toUpperCase(),
            name: e.value,
            selected: app.language == e.key,
            onGradient: onGradient,
            onTap: () => app.setLanguage(e.key),
          ),
      ]),
    );
  }
}

class _LangSegment extends StatelessWidget {
  const _LangSegment({
    required this.code,
    required this.name,
    required this.selected,
    required this.onGradient,
    required this.onTap,
  });
  final String code;
  final String name;
  final bool selected;
  final bool onGradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? (onGradient ? Colors.white : cs.primary) : Colors.transparent;
    final fg = selected
        ? (onGradient ? Brand.primaryDeep : cs.onPrimary)
        : (onGradient ? Colors.white : cs.onSurfaceVariant);
    return Tooltip(
      message: name,
      child: Semantics(
        button: true,
        selected: selected,
        label: name,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: selected ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(code,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.3)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scrollable area that centres its child when it fits.
class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.child, required this.padding});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (c.maxHeight - padding.vertical).clamp(0, double.infinity)),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle(this.size, this.color);
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}
