import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';
import '../../models/llm_provider.dart';

/// API key input field with provider auto-detection indicator, quick paste,
/// live verification badge, and portal link.
class ApiKeySection extends StatefulWidget {
  final LlmProvider selectedProvider;
  final TextEditingController controller;
  final VoidCallback onLaunchKeyPortal;
  final VoidCallback onKeyChanged;
  final bool isVerifying;
  final String? verifyStatus;

  const ApiKeySection({
    super.key,
    required this.selectedProvider,
    required this.controller,
    required this.onLaunchKeyPortal,
    required this.onKeyChanged,
    this.isVerifying = false,
    this.verifyStatus,
  });

  @override
  State<ApiKeySection> createState() => _ApiKeySectionState();
}

class _ApiKeySectionState extends State<ApiKeySection> {
  bool _obscureKey = true;

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      widget.controller.text = data.text!.trim();
      widget.onKeyChanged();
      HapticFeedback.lightImpact();
    }
  }

  void _clearKey() {
    widget.controller.clear();
    widget.onKeyChanged();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.selectedProvider.requiresKey) {
      return const SizedBox.shrink();
    }

    final hasText = widget.controller.text.trim().isNotEmpty;
    final detectedProviderId = LlmProvider.detectProviderFromKey(widget.controller.text);
    final isDetected = detectedProviderId != null &&
        detectedProviderId == widget.selectedProvider.id;

    final isError = widget.verifyStatus != null &&
        (widget.verifyStatus!.toLowerCase().contains('fail') ||
            widget.verifyStatus!.toLowerCase().contains('not valid') ||
            widget.verifyStatus!.toLowerCase().contains('invalid') ||
            widget.verifyStatus!.toLowerCase().contains('error'));
    final isSuccess = widget.verifyStatus != null &&
        (widget.verifyStatus!.toLowerCase().contains('verified') ||
            widget.verifyStatus!.toLowerCase().contains('saved') ||
            widget.verifyStatus!.toLowerCase().contains('active')) &&
        !isError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'API KEY',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: InkWell(
                onTap: widget.onLaunchKeyPortal,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Get Key from ${widget.selectedProvider.name}',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(LucideIcons.externalLink, size: 11, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.glassBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isVerifying
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : isSuccess || isDetected
                      ? AppColors.success.withValues(alpha: 0.5)
                      : isError
                          ? AppColors.error.withValues(alpha: 0.5)
                          : AppColors.glassBorder,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  obscureText: _obscureKey,
                  onChanged: (_) => widget.onKeyChanged(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.selectedProvider.keyHint,
                    hintStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),

              // Quick Paste Button when empty
              if (!hasText)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: _pasteFromClipboard,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.clipboard, size: 11, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Paste',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Loading Spinner when Verifying
              if (widget.isVerifying)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                )
              else if (isSuccess)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    LucideIcons.checkCircle,
                    size: 16,
                    color: AppColors.success,
                  ),
                )
              else if (isError)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    LucideIcons.alertCircle,
                    size: 16,
                    color: AppColors.error,
                  ),
                ),

              // Clear key action when text exists
              if (hasText)
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 15),
                  color: AppColors.textMuted,
                  onPressed: _clearKey,
                  tooltip: 'Clear API key',
                ),

              IconButton(
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
                icon: Icon(
                  _obscureKey ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),

        // Live Auto-Save / Auto-Verify Status Pill
        if (widget.verifyStatus != null && widget.verifyStatus!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Icon(
                  widget.isVerifying
                      ? LucideIcons.refreshCw
                      : isSuccess
                          ? LucideIcons.checkCircle2
                          : isError
                              ? LucideIcons.alertCircle
                              : LucideIcons.info,
                  size: 12,
                  color: widget.isVerifying
                      ? AppColors.primary
                      : isSuccess
                          ? AppColors.success
                          : isError
                              ? AppColors.error
                              : AppColors.textMuted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    widget.verifyStatus!,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: widget.isVerifying
                          ? AppColors.primary
                          : isSuccess
                              ? AppColors.success
                              : isError
                                  ? AppColors.error
                                  : AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
