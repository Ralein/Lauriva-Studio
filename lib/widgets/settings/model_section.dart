import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';
import '../../models/llm_provider.dart';
import '../model_picker_modal.dart';

/// Model selection button with catalog link and custom base URL configuration.
class ModelSection extends StatelessWidget {
  final LlmProvider selectedProvider;
  final String selectedModel;
  final TextEditingController apiKeyController;
  final TextEditingController customUrlController;
  final VoidCallback onLaunchCatalog;
  final ValueChanged<String> onModelSelected;

  const ModelSection({
    super.key,
    required this.selectedProvider,
    required this.selectedModel,
    required this.apiKeyController,
    required this.customUrlController,
    required this.onLaunchCatalog,
    required this.onModelSelected,
  });

  @override
  Widget build(BuildContext context) {
    final needsKey = selectedProvider.requiresKey && apiKeyController.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Custom base URL (for custom providers)
        if (selectedProvider.isCustom) ...[
          Row(
            children: [
              Text(
                'BASE URL',
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Icon(
                        LucideIcons.globe,
                        size: 15,
                        color: AppColors.primary,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: customUrlController,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. http://localhost:11434/v1 or https://...',
                          hintStyle: GoogleFonts.jetBrainsMono(
                            fontSize: 13.5,
                            color: AppColors.textMuted,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Model Picker Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MODEL',
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
                onTap: onLaunchCatalog,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Browse models',
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
                      Icon(LucideIcons.chevronRight, size: 12, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Model Picker Button
        InkWell(
          onTap: () {
            showModelPickerModal(
              context: context,
              provider: selectedProvider,
              currentModel: selectedModel,
              apiKey: apiKeyController.text.trim().isEmpty ? null : apiKeyController.text.trim(),
              customBaseUrl: selectedProvider.isCustom ? customUrlController.text.trim() : null,
              onModelSelected: onModelSelected,
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.glassBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      needsKey ? LucideIcons.keyRound : LucideIcons.cpu,
                      size: 16,
                      color: needsKey ? AppColors.textMuted : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        needsKey ? 'Paste API key to fetch models' : selectedModel,
                        style: needsKey
                            ? GoogleFonts.outfit(
                                fontSize: 14,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              )
                            : GoogleFonts.jetBrainsMono(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: AppColors.textMuted,
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
}
