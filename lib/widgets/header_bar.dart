import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/history_provider.dart';
import '../providers/theme_provider.dart';
import 'history_drawer.dart';
import '../screens/settings_screen.dart';

/// Universal header bar matching Studio design system across all pages.
/// Clean text title on the left with History and Settings buttons on the far right.
class HeaderBar extends StatelessWidget {
  final String title;
  final bool showHistory;
  final bool showSettings;
  final VoidCallback? onSettingsPressed;
  final VoidCallback? onHistoryPressed;
  final Widget? leading;
  final Widget? trailing;

  const HeaderBar({
    super.key,
    this.title = 'Lauriva',
    this.showHistory = true,
    this.showSettings = true,
    this.onSettingsPressed,
    this.onHistoryPressed,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } catch (_) {}
    final historyCount =
        context.select<HistoryProvider, int>((p) => p.history.length);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: 8),
        ],

        // Clean page title without icons/logos — consistent across all screens
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),

        // Right-side action buttons: History and Settings
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHistory)
              Semantics(
                button: true,
                label: 'Open Transformation History ($historyCount items)',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (onHistoryPressed != null) {
                        onHistoryPressed!();
                      } else {
                        showHistoryModal(context);
                      }
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.glassBg,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                            color: AppColors.glassBorder, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                                alpha: AppColors.isDark ? 0.20 : 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.history,
                            size: 14,
                            color: AppColors.accentText,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'History',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (historyCount > 0) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '$historyCount',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            if (showHistory && showSettings) const SizedBox(width: 8),

            if (showSettings)
              Semantics(
                button: true,
                label: 'Open Settings',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (onSettingsPressed != null) {
                        onSettingsPressed!();
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.glassBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.glassBorder, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                                alpha: AppColors.isDark ? 0.20 : 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        LucideIcons.sliders,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            if (trailing != null) ...[
              if (showHistory || showSettings) const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ],
    );
  }
}
