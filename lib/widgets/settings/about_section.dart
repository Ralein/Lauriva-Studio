import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/theme_provider.dart';
import '../../screens/onboarding_screen.dart';
import '../lauriva_logo.dart';
import 'legal_policy_sheet.dart';

/// App information and developer credits section for Settings.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ABOUT',
          style: GoogleFonts.outfit(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.glassBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                children: [
                  _aboutRow(
                    leading: const LaurivaLogo(
                      size: 15,
                      outlineOnly: true,
                    ),
                    label: 'Lauriva',
                    value: 'AI Writing Assistant',
                  ),
                  Divider(height: 1, color: AppColors.glassBorder),
                  _aboutRow(
                    icon: LucideIcons.user,
                    label: 'Developer',
                    value: 'Ralein Nova',
                    valueColor: AppColors.accentText,
                  ),
                  Divider(height: 1, color: AppColors.glassBorder),
                  _aboutRow(
                    icon: LucideIcons.code,
                    label: 'Version',
                    value: '1.0.0',
                  ),
                  Divider(height: 1, color: AppColors.glassBorder),
                  InkWell(
                    onTap: () {
                      // Always replays the full intro: converge, hold, glide to header.
                      Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          transitionDuration: const Duration(milliseconds: 250),
                          reverseTransitionDuration:
                              const Duration(milliseconds: 200),
                          pageBuilder: (routeContext, _, _) => OnboardingScreen(
                            animateFromSplash: true,
                            onComplete: () => Navigator.of(routeContext).pop(),
                          ),
                          transitionsBuilder: (_, animation, _, child) =>
                              FadeTransition(opacity: animation, child: child),
                        ),
                      );
                    },
                    child: _aboutRow(
                      icon: LucideIcons.compass,
                      label: 'Onboarding Tutorial',
                      value: 'Replay Guide',
                      valueColor: AppColors.paletteCerulean,
                    ),
                  ),
                  Divider(height: 1, color: AppColors.glassBorder),
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      LegalPolicySheet.show(context);
                    },
                    child: _aboutRow(
                      icon: LucideIcons.shieldCheck,
                      label: 'Legal & AI Policies',
                      value: 'View Details',
                      valueColor: AppColors.paletteTeal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _aboutRow({
    IconData? icon,
    Widget? leading,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    assert(icon != null || leading != null, 'Either icon or leading must be provided');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: Center(
              child: leading ?? Icon(icon, size: 15, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
