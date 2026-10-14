import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../models/forensic/confidence_assessment.dart';

/// Renders a statistical uncertainty interval bar for calibrated confidence estimation:
/// e.g. `AI Probability: 68% [───|───] ±12% (56%–80%)`.
class ConfidenceIntervalBar extends StatelessWidget {
  final double score;
  final ConfidenceAssessment confidence;

  const ConfidenceIntervalBar({
    super.key,
    required this.score,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    final margin = (confidence.uncertainty * 100.0).clamp(3.0, 35.0);
    final lowerBound = (score - margin).clamp(0.0, 100.0);
    final upperBound = (score + margin).clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Statistical Confidence Band',
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '±${margin.toStringAsFixed(0)}% (${lowerBound.toStringAsFixed(0)}%–${upperBound.toStringAsFixed(0)}%)',
                style: GoogleFonts.outfit(
                  color: AppColors.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Visual horizontal interval bar
          SizedBox(
            height: 14,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final leftPos = (lowerBound / 100.0) * width;
                final rightPos = (upperBound / 100.0) * width;
                final markerPos = (score / 100.0) * width;
                final intervalWidth = (rightPos - leftPos).clamp(6.0, width);

                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Background track (0 to 100%)
                    Container(
                      width: width,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Uncertainty interval band
                    Positioned(
                      left: leftPos,
                      width: intervalWidth,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 0.8),
                        ),
                      ),
                    ),

                    // Center score marker pin
                    Positioned(
                      left: (markerPos - 2).clamp(0.0, width - 4),
                      child: Container(
                        width: 4,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.8),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle
          Text(
            confidence.uncertainty > 0.35
                ? 'High statistical variance: text sample is short or exhibits mixed structural markers.'
                : 'High stability: stylometric vector distribution exhibits low variance across paragraphs.',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
