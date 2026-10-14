import 'package:flutter/material.dart';

/// Which surface/text palette [AppColors]'s dynamic tokens currently resolve to.
enum AppBrightness { dark, light }

/// App color tokens — Lauriva Softened Botanical & Slate Design System.
///
/// Refined palette: Teal Mist (#38B2AC), Sage (#7CA982), Pistachio (#93C572),
/// Slate Obsidian (#0F1216) — reduces heavy green saturation, replacing harsh
/// moss-tinted surfaces with neutral dark slate and calming botanical accents.
class AppColors {
  AppColors._();

  static AppBrightness _brightness = AppBrightness.dark;
  static bool get isDark => _brightness == AppBrightness.dark;

  /// Called exactly once per `LaurivaApp._buildTheme()` invocation, which is
  /// itself driven by `context.select<ThemeProvider>` — so it fires only when
  /// the user's theme preference actually changes, never mid-frame or during
  /// a route animation.
  ///
  /// This is safe despite being a static mutation because Flutter's widget
  /// build scheduler runs all builds on a single isolate in a deterministic
  /// single-threaded sequence. Two `build()` calls on the same isolate can
  /// never execute concurrently, so there is no race condition here.
  ///
  /// If AppColors is ever refactored into an InheritedWidget, this method
  /// should be removed and brightness should be passed as a constructor param.
  static void setBrightness(AppBrightness brightness) {
    _brightness = brightness;
  }

  // ── 1. Core Brand Palette (calm botanicals & teal) ────────────────────────
  static const Color paletteTeal      = Color(0xFF38B2AC); // refined teal mist (dark mode)
  static const Color paletteTealLight = Color(0xFF0D9488); // vibrant accessible teal for light mode (WCAG AA 4.6:1)
  static const Color paletteSage      = Color(0xFF7CA982); // soft, muted sage green
  static const Color palettePistachio = Color(0xFF93C572); // warm soft pistachio
  static const Color paletteEmerald   = Color(0xFF2E8B84); // deep teal-emerald accent
  static const Color paletteForest    = Color(0xFF235347); // deep forest green accent
  static const Color paletteCream     = Color(0xFFF1F5F9); // cool crisp off-white slate

  // Backward compatibility aliases
  static const Color paletteMint      = paletteTeal;

  // ── 2. Semantic Brand Roles ───────────────────────────────────────────────
  static Color get primary    => isDark ? paletteTeal      : paletteTealLight;
  static Color get secondary  => isDark ? paletteSage      : paletteSage;
  static Color get accent     => isDark ? palettePistachio : palettePistachio;
  static Color get ice        => isDark ? paletteTeal      : paletteCream;

  // ── 3. Background Tokens (Neutral Dark Slate Obsidian) ────────────────────
  static Color get bgCenter => isDark
      ? const Color(0xFF0F1216)   // obsidian dark slate (neutral, no moss tint)
      : const Color(0xFFF8FAF9);  // clean airy off-white

  static Color get bgTopLeft => isDark
      ? const Color(0xFF0C0E12)
      : const Color(0xFFF1F5F3);

  static Color get bgBottomRight => isDark
      ? const Color(0xFF13171C)
      : const Color(0xFFF1F5F3);

  // Decorative leaf watermark color (used in BackgroundGlow)
  static Color get bgLeafTint => isDark
      ? const Color(0x0A38B2AC)   // very subtle translucent teal
      : const Color(0x0E0D9488);

  // ── 4. Card & Surface Tokens (Neutral Glassmorphic Slate) ─────────────────
  static Color get glassBg => isDark
      ? const Color(0xFF161A1F)   // neutral dark slate card
      : const Color(0xFFFFFFFF);  // pure white card

  static Color get glassBorder => isDark
      ? const Color(0xFF232932)   // neutral slate border
      : const Color(0xFFE2E8F0);  // light slate border

  static Color get glassBorderHover => isDark
      ? paletteTeal
      : paletteTealLight;

  static Color get glassInputBg => isDark
      ? const Color(0xFF111418)
      : const Color(0xFFFFFFFF);

  static Color get glassOutputBg => isDark
      ? const Color(0xFF13171C)
      : const Color(0xFFF8FAF9);

  static Color get surfaceSubtle => isDark
      ? const Color(0x0FFFFFFF)
      : const Color(0x080D9488);

  static Color get surfaceElevated => isDark
      ? const Color(0xFF1B2128)
      : const Color(0xFFFFFFFF);

  static Color get divider => isDark
      ? const Color(0xFF232932)
      : const Color(0xFFE2E8F0);

  // ── 5. Chip Tokens ────────────────────────────────────────────────────────
  static Color get chipInactiveBg => isDark
      ? const Color(0xFF161A1F)
      : const Color(0xFFFFFFFF);

  static Color get chipInactiveBorder => isDark
      ? const Color(0xFF232932)
      : const Color(0xFFE2E8F0);

  static Color get chipInactiveText => isDark
      ? const Color(0xFF94A3B8)   // Slate-400 (clean neutral)
      : const Color(0xFF475569);  // Slate-600

  // ── 6. Typography Tokens (Neutral Slate — Zero Green Tint on text!) ───────
  static Color get textPrimary => isDark
      ? const Color(0xFFF1F5F9)   // Slate-100 (crisp, readable)
      : const Color(0xFF0F172A);  // Slate-900

  static Color get textSecondary => isDark
      ? const Color(0xFF94A3B8)   // Slate-400 (clean, readable neutral)
      : const Color(0xFF475569);  // Slate-600

  static Color get textMuted => isDark
      ? const Color(0xFF64748B)   // Slate-500 (balanced muted)
      : const Color(0xFF94A3B8);  // Slate-400

  static Color get accentText => isDark ? paletteTeal : paletteTealLight;

  // ── 7. Glow Tints (translucent tints for chip/icon backgrounds) ───────────
  static Color get primaryGlow => isDark
      ? const Color(0x2438B2AC)   // teal mist glow
      : const Color(0x180D9488);

  static const Color secondaryGlow = Color(0x207CA982); // sage glow
  static const Color accentGlow    = Color(0x2093C572); // pistachio glow
  static const Color iceGlow       = Color(0x14F1F5F9);

  // ── 8. Status Colors ─────────────────────────────────────────────────────
  static const Color error      = Color(0xFFEF4444);
  static const Color errorBg    = Color(0x24EF4444);
  static const Color success    = Color(0xFF22C55E);
  static const Color successBg  = Color(0x2422C55E);
  static const Color warning    = Color(0xFFF59E0B);
  static const Color warningBg  = Color(0x24F59E0B);

  // ── 9. Nav Bar Tokens ────────────────────────────────────────────────────
  static Color get navBarBg => isDark
      ? const Color(0xFF13171C)
      : const Color(0xFFFFFFFF);

  static Color get navBarActivePill => isDark
      ? const Color(0xFF1C2524)   // subtle teal-slate pill
      : const Color(0xFFE6F4F2);  // clean crisp teal tint

  // ── 10. Gradients ────────────────────────────────────────────────────────
  static LinearGradient get primaryGradient => LinearGradient(
    colors: isDark
        ? [paletteTeal, paletteSage]
        : [paletteTealLight, paletteEmerald],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [paletteSage, palettePistachio],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient leafGradient = LinearGradient(
    colors: [paletteTeal, paletteSage, palettePistachio],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient voiceWaveGradient = LinearGradient(
    colors: [paletteTeal, paletteSage, palettePistachio],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient micActiveGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get brandTextGradient => isDark
      ? const LinearGradient(
          colors: [paletteTeal, paletteSage],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        )
      : const LinearGradient(
          colors: [paletteTealLight, paletteEmerald],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );

  // Legacy aliases — kept so existing call-sites don't break without surgery
  static Color get paletteCosmicIndigo => isDark ? paletteTeal : paletteTealLight;
  static Color get paletteSlateBlue    => paletteEmerald;
  static Color get paletteCerulean     => isDark ? paletteSage : paletteSage;
  static const Color paletteIceWhite   = Color(0xFFF1F5F9);
  static const Color paletteIceCyan    = paletteTeal;
}
