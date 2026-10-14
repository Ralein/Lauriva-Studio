import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';
import '../lauriva_logo.dart';
import '../metric_ring.dart';

/// Luxury glowing Transformation Hero card matching Screen 2 in the design reference.
/// Features a centered glowing arc gauge, dual fidelity cards, side-by-side delta,
/// document metadata pill, and full-width "View Humanized Text" expander.
class HumanizerResultsHero extends StatelessWidget {
  final double originalScore;
  final double humanizedScore;
  final double semanticFidelity;
  final double contentPreserved;
  final int wordCount;
  final int charCount;
  final int readTimeSec;
  final bool isTextViewExpanded;
  final VoidCallback onViewTextPressed;

  const HumanizerResultsHero({
    super.key,
    required this.originalScore,
    required this.humanizedScore,
    this.semanticFidelity = 97.0,
    this.contentPreserved = 100.0,
    required this.wordCount,
    required this.charCount,
    required this.readTimeSec,
    required this.isTextViewExpanded,
    required this.onViewTextPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Centered Unified Lauriva Metric Ring (exact parity with Forensics)
        Center(
          child: MetricRing(
            value: humanizedScore,
            size: 154,
            color: AppColors.primary,
            label: 'AI Likelihood',
            topWidget: const LaurivaLogo(size: 24),
          ),
        ),

        const SizedBox(height: 16),

        // 2. Dual Fidelity Cards Row (97% Semantic Fidelity & 100% Content Preserved)
        Row(
          children: [
            Expanded(
              child: _buildFidelityCard(
                icon: LucideIcons.shieldCheck,
                value: '${semanticFidelity.round()}%',
                label: 'Semantic Fidelity',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFidelityCard(
                icon: LucideIcons.checkCheck,
                value: '${contentPreserved.round()}%',
                label: 'Content Preserved',
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // 3. Original vs Humanized Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Clock icon + "Before & After"
              Row(
                children: [
                  Icon(LucideIcons.clock, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Before & After',
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Side-by-side comparison boxes
              Row(
                children: [
                  // Original box (Coral)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFF43F5E).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Original',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${originalScore.round()}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFF43F5E),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'AI Likelihood',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Arrow ->
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      LucideIcons.arrowRight,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ),

                  // Humanized box (Teal)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Humanized',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${humanizedScore.round()}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'AI Likelihood',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Bottom note with green check
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    child: Icon(
                      LucideIcons.check,
                      size: 11,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your content now reads more naturally while keeping the same meaning.',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 4. Document Details Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.glassBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.fileText, size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$wordCount words  •  $charCount characters  •  ~${readTimeSec > 0 ? readTimeSec : 1}s read',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 5. Full-width Glowing Button: "View Humanized Text >"
        Semantics(
          button: true,
          label: isTextViewExpanded ? 'Collapse Humanized Text' : 'View Humanized Text',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onViewTextPressed();
              },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.fileCode,
                      size: 17,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isTextViewExpanded ? 'Hide Text Inspector' : 'View Humanized Text',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isTextViewExpanded ? LucideIcons.chevronUp : LucideIcons.chevronRight,
                      size: 17,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFidelityCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.15),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
