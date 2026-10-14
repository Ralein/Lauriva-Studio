import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import 'metric_ring.dart';

export 'metric_ring.dart';

/// Animated radial score gauge matching Lauriva Design System.
/// Delegates to the unified [MetricRing] component for system-wide visual parity.
class ScoreGaugeWidget extends StatelessWidget {
  final double score;
  final String label;
  final double size;
  final bool animate;
  final bool showBadgeInside;
  final String? subtitle;

  const ScoreGaugeWidget({
    super.key,
    required this.score,
    required this.label,
    this.size = 140,
    this.animate = true,
    this.showBadgeInside = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    Color resolveColor(double val) {
      if (val < 25.0) return AppColors.success;
      if (val < 45.0) return AppColors.primary;
      if (val < 65.0) return AppColors.warning;
      if (val < 85.0) return const Color(0xFFF97316);
      return AppColors.error;
    }

    final color = resolveColor(score);

    return MetricRing(
      value: score,
      size: size,
      animate: animate,
      color: color,
      label: null,
      subtitle: subtitle,
      badge: showBadgeInside
          ? Container(
              constraints: BoxConstraints(maxWidth: size * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
              ),
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: size * 0.08,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            )
          : null,
    );
  }
}
