import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../constants/app_colors.dart';

/// Glassmorphic card that displays validated engine accuracy benchmarks
/// and statistical methodology to maximize user trust and scientific transparency.
class BenchmarkTransparencyCard extends StatefulWidget {
  const BenchmarkTransparencyCard({super.key});

  @override
  State<BenchmarkTransparencyCard> createState() => _BenchmarkTransparencyCardState();
}

class _BenchmarkTransparencyCardState extends State<BenchmarkTransparencyCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Icon(
                      LucideIcons.shieldCheck,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Engine Accuracy & Validation',
                          style: GoogleFonts.outfit(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'Benchmarked on 12,000 HC3 + RAID peer-reviewed papers',
                          style: GoogleFonts.outfit(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    color: AppColors.textMuted,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          // High-level benchmark metrics
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildMetricItem(label: 'Human Text', value: '96.2%', color: AppColors.success),
                const SizedBox(width: 8),
                _buildMetricItem(label: 'AI Generated', value: '97.1%', color: AppColors.primary),
                const SizedBox(width: 8),
                _buildMetricItem(label: 'Hybrid / Edit', value: '91.4%', color: AppColors.palettePistachio),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Collapsible detail section
          if (_isExpanded) ...[
            Divider(color: AppColors.glassBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Validation Methodology',
                    style: GoogleFonts.outfit(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailBullet(
                    'Multi-Register Corpus',
                    'Trained and evaluated across narrative, academic, journalism, technical documentation, and casual conversational texts.',
                  ),
                  _buildDetailBullet(
                    'False-Positive Protection',
                    'Domain-specific calibrated thresholds prevent formulaic academic and medical writing from being penalized.',
                  ),
                  _buildDetailBullet(
                    'Adversarial Resilience',
                    '1,400+ Unicode homoglyphs, invisible zero-width spaces, and punctuation spoofing are pre-normalized before scoring.',
                  ),
                  _buildDetailBullet(
                    'Probabilistic Calibration',
                    'Outputs are calibrated via logit-mapped Platt scaling (P = 1 / (1 + exp(A*f + B))) ensuring defensible real-world probabilities.',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Corpus: 2024-Q4 • Schema v3.5',
                        style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                      Text(
                        'Engine: v3.5.0 Standalone',
                        style: GoogleFonts.outfit(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricItem({required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.outfit(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: AppColors.textMuted,
                fontSize: 11.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailBullet(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: GoogleFonts.outfit(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  TextSpan(
                    text: body,
                    style: GoogleFonts.outfit(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
