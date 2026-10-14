import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';
import '../glass_card.dart';

/// Subtle, glassmorphic notification banner displayed on the Humanizer screen
/// when an auto-failover event switched models for the active session.
class FailoverAlertBanner extends StatelessWidget {
  final String providerName;
  final String modelName;
  final VoidCallback onSaveDefault;
  final VoidCallback onDismiss;

  const FailoverAlertBanner({
    super.key,
    required this.providerName,
    required this.modelName,
    required this.onSaveDefault,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        borderRadius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderColor: AppColors.accent.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.15),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: const Icon(
                LucideIcons.zap,
                size: 18,
                color: AppColors.palettePistachio,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Auto-Switched to $providerName',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Session',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.palettePistachio,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Credits depleted on primary. Using $modelName for this session.',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onSaveDefault,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                'Save Default',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}
