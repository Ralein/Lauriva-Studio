import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/toast_notification.dart';
import '../providers/toast_provider.dart';

/// Renders a side-by-side Before/After delta comparison following a humanization pass.
/// Highlights score drop, fact preservation fidelity, and one-tap clipboard copy.
class FixAndVerifyCard extends StatelessWidget {
  final double scoreBefore;
  final double scoreAfter;
  final String labelBefore;
  final String labelAfter;
  final double? preservationScore;
  final String humanizedText;
  final VoidCallback? onReverify;
  final bool showCopyButton;

  const FixAndVerifyCard({
    super.key,
    required this.scoreBefore,
    required this.scoreAfter,
    this.labelBefore = 'LIKELY AI',
    this.labelAfter = 'LIKELY HUMAN',
    this.preservationScore = 98.0,
    required this.humanizedText,
    this.onReverify,
    this.showCopyButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final delta = (scoreBefore - scoreAfter).round();
    final isImproved = delta > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isImproved ? AppColors.primary.withValues(alpha: 0.4) : AppColors.glassBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(LucideIcons.fingerprint, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Humanizer Delta & Verification',
                        style: GoogleFonts.outfit(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isImproved)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.arrowDownRight, color: AppColors.success, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        '-$delta pts',
                        style: GoogleFonts.outfit(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Before vs After Comparison Row
          Row(
            children: [
              // Before
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ORIGINAL',
                        style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${scoreBefore.toStringAsFixed(0)}%',
                        style: GoogleFonts.outfit(
                          color: AppColors.error,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        labelBefore,
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(LucideIcons.arrowRight, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              // After
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HUMANIZED',
                        style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${scoreAfter.toStringAsFixed(0)}%',
                        style: GoogleFonts.outfit(
                          color: AppColors.success,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        labelAfter,
                        style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (preservationScore != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.checkCircle2, color: AppColors.primary, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${preservationScore!.toStringAsFixed(0)}% Semantic & Citation Fidelity Preserved',
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action Buttons
          if (showCopyButton || onReverify != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (showCopyButton)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: humanizedText));
                        final toast = Provider.of<ToastProvider?>(context, listen: false);
                        if (toast != null) {
                          toast.showToast('Copied humanized text to clipboard', ToastType.success);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied humanized text to clipboard', style: GoogleFonts.outfit()),
                              backgroundColor: AppColors.bgBottomRight,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: Icon(LucideIcons.copy, size: 14, color: AppColors.primary),
                      label: Text('Copy Output', style: GoogleFonts.outfit(color: AppColors.primary, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                if (showCopyButton && onReverify != null) const SizedBox(width: 8),
                if (onReverify != null)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onReverify,
                      icon: const Icon(LucideIcons.refreshCw, size: 14, color: Colors.white),
                      label: Text('Re-Verify', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
