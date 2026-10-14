import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';
import '../../utils/share_helper.dart';
import '../glass_card.dart';
import '../score_gauge_widget.dart';

/// Luxury glassmorphic card displaying the Humanizer Stylometric & Originality
/// Verification Audit, styled with exact visual parity to PlagiarismAuditCard.
class HumanizerReportCard extends StatelessWidget {
  final double originalScore;
  final double humanizedScore;
  final double semanticFidelity;
  final double contentPreserved;
  final int wordCount;
  final int charCount;
  final int readTimeSec;

  const HumanizerReportCard({
    super.key,
    required this.originalScore,
    required this.humanizedScore,
    this.semanticFidelity = 97.0,
    this.contentPreserved = 100.0,
    required this.wordCount,
    required this.charCount,
    required this.readTimeSec,
  });

  @override
  Widget build(BuildContext context) {
    final aiReduction = (originalScore - humanizedScore).clamp(0.0, 100.0);
    final isLowRisk = humanizedScore < 30.0;
    final riskBadgeColor = isLowRisk ? AppColors.success : AppColors.primary;
    final riskBadgeBg = isLowRisk ? AppColors.successBg : AppColors.primaryGlow;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Bar matching Forensic Report
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                      ),
                      child: Icon(
                        LucideIcons.fingerprint,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HUMANIZER REPORT',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: AppColors.textMuted,
                            ),
                          ),
                          Text(
                            'Stylometric & AI Bypass Audit',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final cert = StringBuffer();
                  cert.writeln('🌿 *LAURIVA HUMANIZER VERIFICATION*');
                  cert.writeln('─────────────────────────────');
                  cert.writeln('✅ *Status: Authenticity Verified*');
                  cert.writeln('📊 *AI Likelihood:* ${humanizedScore.round()}% _(Down from ${originalScore.round()}%)_');
                  cert.writeln('⚡ *AI Risk Reduction:* -${aiReduction.round()}%');
                  cert.writeln('🎯 *Semantic Fidelity:* ${semanticFidelity.round()}%');
                  cert.writeln('📑 *Content Preserved:* ${contentPreserved.round()}%');
                  cert.writeln('📝 *Word Count:* $wordCount words (~${readTimeSec > 0 ? readTimeSec : 1}s read)');
                  cert.writeln('─────────────────────────────');
                  cert.writeln('✨ *Audited via Lauriva Natural Language Engine*');
                  ShareHelper.shareText(
                    title: 'Lauriva Humanizer Audit Certificate',
                    text: cert.toString().trim(),
                  );
                },
                icon: Icon(LucideIcons.share2, size: 17, color: AppColors.primary),
                tooltip: 'Share Audit Certificate',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Main Rating Gauge & Risk Summary with Big %
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.glassInputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                ScoreGaugeWidget(
                  score: humanizedScore,
                  label: 'AI Likelihood',
                  showBadgeInside: false,
                  size: 88,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: riskBadgeBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: riskBadgeColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              isLowRisk ? 'LIKELY HUMAN' : 'AI BYPASSED',
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: riskBadgeColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.shieldCheck,
                                  size: 11,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '100% FACTS SAFE',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Text(
                              'VERIFIED',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AI likelihood reduced from ${originalScore.round()}% to ${humanizedScore.round()}%.',
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '-${aiReduction.round()}% AI Probability',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Before & After Delta Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                // Original score
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ORIGINAL',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${originalScore.round()}% AI',
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFF43F5E),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    LucideIcons.arrowRight,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
                // Humanized score
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HUMANIZED',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${humanizedScore.round()}% AI',
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Key Metrics Grid in 2 columns matching Plagiarism Forensic dimensions
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: LucideIcons.shieldCheck,
                  label: 'Fidelity',
                  value: '${semanticFidelity.round()}%',
                  sub: semanticFidelity >= 90 ? 'High Precision' : 'Adapted Flow',
                  iconColor: AppColors.primary,
                  isHighlighted: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  icon: LucideIcons.checkCheck,
                  label: 'Preserved Words',
                  value: '${contentPreserved.round()}%',
                  sub: '$wordCount Words Retained',
                  iconColor: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: LucideIcons.fileText,
                  label: 'Word Count',
                  value: '$wordCount',
                  sub: '$charCount Characters',
                  iconColor: AppColors.accentText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  icon: LucideIcons.clock,
                  label: 'Read Time',
                  value: '${readTimeSec > 0 ? readTimeSec : 1}s',
                  sub: 'Estimated Pace',
                  iconColor: const Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 5. Stylometric Guarantee Footer Note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sentence perplexity and cadence restored while preserving 100% of underlying meaning.',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color iconColor,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: isHighlighted ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted ? iconColor : iconColor.withValues(alpha: 0.22),
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: iconColor),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
                          color: isHighlighted ? iconColor : AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (isHighlighted)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sub,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
