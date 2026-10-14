import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Centralized typographic scale for Lauriva.
///
/// Designed to eliminate micro-type accessibility defects (<11sp) and harmonize
/// font scaling across all dark/light glassmorphic surfaces using [GoogleFonts.outfit].
abstract final class AppTypography {
  // ── Baseline Font Family ──────────────────────────────────────────────────
  static TextStyle outfit({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.outfit(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.textPrimary,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      decoration: decoration,
    );
  }

  // ── Scale Tokens ──────────────────────────────────────────────────────────

  /// All-caps overlines, section category tags, and mini status pills (11sp).
  static TextStyle get overline => GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.textMuted,
      );

  /// Micro badges and compact indicators (11sp, w600).
  static TextStyle get badge => GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      );

  /// Captions, metadata, word/char counters, and bottom nav labels (12sp).
  static TextStyle get caption => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      );

  /// Interactive chips, small action buttons, and segmented control tabs (13sp).
  static TextStyle get buttonSmall => GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  /// Standard buttons, dialog actions, and primary CTAs (14sp).
  static TextStyle get button => GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );

  /// Secondary body text, explanatory labels, and card descriptions (14sp).
  static TextStyle get bodySecondary => GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: AppColors.textSecondary,
      );

  /// Primary multi-line text input fields (15sp, height: 1.5).
  static TextStyle get bodyInput => GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: AppColors.textPrimary,
      );

  /// Primary prose reading output, generated text, and TTS playback (16sp, height: 1.55).
  static TextStyle get bodyOutput => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: AppColors.textPrimary,
      );

  /// Subsections, card titles, and modal subheadings (17-18sp).
  static TextStyle get titleMedium => GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  /// Screen headers and major card headers (20-22sp).
  static TextStyle get titleLarge => GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  /// Hero metric numerals and percentage gauges (28-32sp).
  static TextStyle get displayMetric => GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      );
}
