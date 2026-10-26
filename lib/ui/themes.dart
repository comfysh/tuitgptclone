// The app's themes. Each has a light and a dark colour set and its own title
// font; "pure black" turns any dark set into a true-black one (OLED screens).

import 'package:flutter/material.dart';

/// One colour set of a theme.
class Palette {
  const Palette({
    required this.bg,
    required this.card,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.high,
    required this.container,
    required this.outline,
    required this.hero,
    required this.secondary,
  });

  /// Page background, cards, text, secondary text and hairlines.
  final Color bg, card, ink, muted, line;

  /// The accent (buttons, links, switches) and what goes on it.
  final Color accent, onAccent;

  /// Selected chips, highlighted rows.
  final Color accentSoft, onAccentSoft;

  /// Filled fields and pressed rows, a step darker than cards.
  final Color high, container, outline;

  /// The solid header block (grades, exams, courses…).
  final Color hero;
  final Color secondary;

  /// The same set on true black.
  Palette pureBlack() => Palette(
        bg: Colors.black,
        card: const Color(0xFF0B0B0B),
        ink: ink,
        muted: muted,
        line: const Color(0xFF222222),
        accent: accent,
        onAccent: onAccent,
        accentSoft: accentSoft,
        onAccentSoft: onAccentSoft,
        high: const Color(0xFF181818),
        container: const Color(0xFF121212),
        outline: outline,
        hero: Color.lerp(hero, Colors.black, 0.35)!,
        secondary: secondary,
      );
}

enum AppStyle { paper, ocean, lagoon, plum, terracotta, graphite }

class StyleSpec {
  const StyleSpec(this.nameKey, this.light, this.dark, {this.serifTitles = true});

  /// Text key of the theme's name (lib/core/strings/look.dart); its
  /// description is the same key with "Sub".
  final String nameKey;
  final Palette light, dark;

  /// Source Serif for titles and big numbers; otherwise Inter everywhere.
  final bool serifTitles;

  Palette of(Brightness b, {bool pureBlack = false}) =>
      b == Brightness.dark ? (pureBlack ? dark.pureBlack() : dark) : light;
}

AppStyle styleById(String? id) => AppStyle.values.where((s) => s.name == id).firstOrNull ?? AppStyle.paper;

const styleSpecs = {
  // Warm paper, ink text, green ink accent (the original look).
  AppStyle.paper: StyleSpec(
    'thPaper',
    Palette(
      bg: Color(0xFFF6F4EE),
      card: Color(0xFFFFFDF8),
      ink: Color(0xFF1C1B17),
      muted: Color(0xFF6A665C),
      line: Color(0xFFE3DED2),
      accent: Color(0xFF1E7A53),
      onAccent: Colors.white,
      accentSoft: Color(0xFFE3F0E8),
      onAccentSoft: Color(0xFF0F3D28),
      high: Color(0xFFEFEBE2),
      container: Color(0xFFF2EFE7),
      outline: Color(0xFF9A958A),
      hero: Color(0xFF1C1B17),
      secondary: Color(0xFF7A6A43),
    ),
    Palette(
      bg: Color(0xFF121310),
      card: Color(0xFF1B1C18),
      ink: Color(0xFFECE9E0),
      muted: Color(0xFFA29E92),
      line: Color(0xFF2E2F29),
      accent: Color(0xFF6CC79A),
      onAccent: Color(0xFF0E2A1D),
      accentSoft: Color(0xFF1F3A2D),
      onAccentSoft: Color(0xFFCDEBDB),
      high: Color(0xFF26271F),
      container: Color(0xFF1F201B),
      outline: Color(0xFF6E6A60),
      hero: Color(0xFF1F3A2D),
      secondary: Color(0xFFC8B98F),
    ),
  ),
  // Cool grey-blue, blue accent, sans-serif titles.
  AppStyle.ocean: StyleSpec(
    'thOcean',
    Palette(
      bg: Color(0xFFF3F6FA),
      card: Color(0xFFFFFFFF),
      ink: Color(0xFF0F1B2D),
      muted: Color(0xFF5B6B80),
      line: Color(0xFFDCE3EC),
      accent: Color(0xFF2457C5),
      onAccent: Colors.white,
      accentSoft: Color(0xFFE1EAFB),
      onAccentSoft: Color(0xFF0E2A66),
      high: Color(0xFFE9EEF5),
      container: Color(0xFFEEF2F7),
      outline: Color(0xFF8A97A8),
      hero: Color(0xFF14233D),
      secondary: Color(0xFF4B5D7A),
    ),
    Palette(
      bg: Color(0xFF0D1320),
      card: Color(0xFF151D2C),
      ink: Color(0xFFE6ECF5),
      muted: Color(0xFF97A6BA),
      line: Color(0xFF26314A),
      accent: Color(0xFF7FA6F5),
      onAccent: Color(0xFF0B1F4D),
      accentSoft: Color(0xFF1D3160),
      onAccentSoft: Color(0xFFD6E2FD),
      high: Color(0xFF1E283A),
      container: Color(0xFF18212F),
      outline: Color(0xFF5F6E85),
      hero: Color(0xFF1D3160),
      secondary: Color(0xFFA9B8D0),
    ),
    serifTitles: false,
  ),
  // Soft grey-green, teal accent, sans-serif titles.
  AppStyle.lagoon: StyleSpec(
    'thLagoon',
    Palette(
      bg: Color(0xFFF2F7F6),
      card: Color(0xFFFFFFFF),
      ink: Color(0xFF10201E),
      muted: Color(0xFF587170),
      line: Color(0xFFD9E6E4),
      accent: Color(0xFF0F766E),
      onAccent: Colors.white,
      accentSoft: Color(0xFFDDF1EE),
      onAccentSoft: Color(0xFF08403B),
      high: Color(0xFFE6EFEE),
      container: Color(0xFFECF3F2),
      outline: Color(0xFF87A09E),
      hero: Color(0xFF0F2E2B),
      secondary: Color(0xFF3F6460),
    ),
    Palette(
      bg: Color(0xFF0C1514),
      card: Color(0xFF131F1E),
      ink: Color(0xFFE3EFED),
      muted: Color(0xFF93ADAA),
      line: Color(0xFF233533),
      accent: Color(0xFF5FD4C4),
      onAccent: Color(0xFF053330),
      accentSoft: Color(0xFF154340),
      onAccentSoft: Color(0xFFCFF5EF),
      high: Color(0xFF1B2928),
      container: Color(0xFF162322),
      outline: Color(0xFF5C7774),
      hero: Color(0xFF154340),
      secondary: Color(0xFF9CC3BE),
    ),
    serifTitles: false,
  ),
  // Lavender paper, plum accent, serif titles.
  AppStyle.plum: StyleSpec(
    'thPlum',
    Palette(
      bg: Color(0xFFF6F3F8),
      card: Color(0xFFFFFDFF),
      ink: Color(0xFF1F1726),
      muted: Color(0xFF6B6075),
      line: Color(0xFFE5DEEB),
      accent: Color(0xFF6B4FA0),
      onAccent: Colors.white,
      accentSoft: Color(0xFFECE4F6),
      onAccentSoft: Color(0xFF2E1D4D),
      high: Color(0xFFEEE8F3),
      container: Color(0xFFF1ECF5),
      outline: Color(0xFF9C91A6),
      hero: Color(0xFF2B1F3D),
      secondary: Color(0xFF7A5E8C),
    ),
    Palette(
      bg: Color(0xFF141119),
      card: Color(0xFF1D1823),
      ink: Color(0xFFEEE8F3),
      muted: Color(0xFFA99FB3),
      line: Color(0xFF2F2838),
      accent: Color(0xFFB9A0E8),
      onAccent: Color(0xFF2A1A47),
      accentSoft: Color(0xFF382A52),
      onAccentSoft: Color(0xFFE9DEFB),
      high: Color(0xFF28212F),
      container: Color(0xFF211B28),
      outline: Color(0xFF6F6579),
      hero: Color(0xFF382A52),
      secondary: Color(0xFFC9B3D6),
    ),
  ),
  // Warm cream, terracotta accent, serif titles.
  AppStyle.terracotta: StyleSpec(
    'thTerracotta',
    Palette(
      bg: Color(0xFFF8F2EA),
      card: Color(0xFFFFFCF7),
      ink: Color(0xFF2A1E16),
      muted: Color(0xFF7A6A5D),
      line: Color(0xFFEADFD2),
      accent: Color(0xFFB4532A),
      onAccent: Colors.white,
      accentSoft: Color(0xFFF6E3D8),
      onAccentSoft: Color(0xFF4D1F0C),
      high: Color(0xFFF1E8DC),
      container: Color(0xFFF4ECE2),
      outline: Color(0xFFA39282),
      hero: Color(0xFF3B2418),
      secondary: Color(0xFF8A6A3E),
    ),
    Palette(
      bg: Color(0xFF16110D),
      card: Color(0xFF201914),
      ink: Color(0xFFF2E9DF),
      muted: Color(0xFFB3A393),
      line: Color(0xFF33291F),
      accent: Color(0xFFF0A07A),
      onAccent: Color(0xFF4A1D08),
      accentSoft: Color(0xFF4A2A1A),
      onAccentSoft: Color(0xFFFBE1D3),
      high: Color(0xFF2A211A),
      container: Color(0xFF231C16),
      outline: Color(0xFF7A6A5C),
      hero: Color(0xFF4A2A1A),
      secondary: Color(0xFFD7B98E),
    ),
  ),
  // Black and white only, sans-serif titles.
  AppStyle.graphite: StyleSpec(
    'thGraphite',
    Palette(
      bg: Color(0xFFF4F4F4),
      card: Color(0xFFFFFFFF),
      ink: Color(0xFF111111),
      muted: Color(0xFF5E5E5E),
      line: Color(0xFFE0E0E0),
      accent: Color(0xFF111111),
      onAccent: Colors.white,
      accentSoft: Color(0xFFE6E6E6),
      onAccentSoft: Color(0xFF111111),
      high: Color(0xFFEBEBEB),
      container: Color(0xFFF0F0F0),
      outline: Color(0xFF9E9E9E),
      hero: Color(0xFF111111),
      secondary: Color(0xFF555555),
    ),
    Palette(
      bg: Color(0xFF0F0F0F),
      card: Color(0xFF1A1A1A),
      ink: Color(0xFFEDEDED),
      muted: Color(0xFFA3A3A3),
      line: Color(0xFF2C2C2C),
      accent: Color(0xFFEDEDED),
      onAccent: Color(0xFF111111),
      accentSoft: Color(0xFF333333),
      onAccentSoft: Color(0xFFF5F5F5),
      high: Color(0xFF262626),
      container: Color(0xFF1F1F1F),
      outline: Color(0xFF707070),
      hero: Color(0xFF2A2A2A),
      secondary: Color(0xFFBDBDBD),
    ),
    serifTitles: false,
  ),
};
