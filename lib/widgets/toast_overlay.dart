import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/toast_notification.dart';
import '../providers/toast_provider.dart';

class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ToastProvider>();
    final toasts = provider.toasts;

    if (toasts.isEmpty) return const SizedBox.shrink();

    final activeToast = toasts.last;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Position toast cleanly above the floating bottom navigation menu (height ~70 + margin 10)
    final toastBottom = 88.0 + bottomInset;

    return Positioned(
      bottom: toastBottom,
      left: 20,
      right: 20,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: _buildToast(context, activeToast, provider),
        ),
      ),
    );
  }

  Widget _buildToast(BuildContext context, ToastNotification toast, ToastProvider provider) {
    final isSuccess = toast.type == ToastType.success;
    final isError = toast.type == ToastType.error;

    final borderColor = isSuccess
        ? AppColors.success.withValues(alpha: 0.4)
        : (isError ? AppColors.error.withValues(alpha: 0.4) : AppColors.glassBorder);

    final iconColor = isSuccess
        ? AppColors.success
        : (isError ? AppColors.error : AppColors.paletteCerulean);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.glassBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
                BoxShadow(
                  color: AppColors.primaryGlow,
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuccess
                      ? LucideIcons.checkCircle2
                      : (isError ? LucideIcons.alertCircle : LucideIcons.info),
                  size: 16,
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    toast.message,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                if (toast.actionLabel != null && toast.onAction != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      provider.dismissToast(toast.id);
                      toast.onAction!();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        toast.actionLabel!,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => provider.dismissToast(toast.id),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms, curve: Curves.easeOut)
        .slideY(begin: 0.3, end: 0, duration: 250.ms, curve: Curves.easeOut);
  }
}
