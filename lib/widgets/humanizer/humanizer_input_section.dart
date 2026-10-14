import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/humanizer_provider.dart';
import '../../providers/speech_provider.dart';
import '../button_lauriva_spinner.dart';
import '../glass_card.dart';

/// Zone 1: Document Passage input card with Paste/Clear actions, Voice Dictation, and Humanize trigger.
class HumanizerInputSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onHumanize;

  const HumanizerInputSection({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onChanged,
    required this.onPaste,
    required this.onClear,
    required this.onHumanize,
  });

  @override
  Widget build(BuildContext context) {
    final isRecording = context.select<SpeechProvider, bool>((p) => p.isRecording);
    final inputWordCount = controller.text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isRecording ? AppColors.error : AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: isRecording
                            ? [
                                BoxShadow(
                                  color: AppColors.error.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isRecording ? 'LISTENING' : 'YOUR TEXT',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onPaste();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.clipboard, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Paste',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClear();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.trash2, size: 12, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              'Clear',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 6,
                minLines: 4,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: isRecording
                      ? 'Listening...'
                      : 'Type or paste text to humanize...',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 15,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onChanged,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$inputWordCount words · ${controller.text.length} chars',
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Tactile Voice Dictation Mic Button (parity with Studio Zone 1)
                  _buildVoiceButton(context, isRecording),

                  if (controller.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: isLoading ? null : onHumanize,
                      icon: isLoading
                          ? const ButtonLaurivaSpinner(
                              size: 16,
                              ringColor: Colors.white,
                            )
                          : const Icon(LucideIcons.fingerprint, size: 14),
                      label: Text(
                        isLoading ? 'Humanizing...' : 'Humanize',
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Live Voice Visualizer removed for clean tactile design
      ],
    );
  }

  Widget _buildVoiceButton(BuildContext context, bool isRecording) {
    return Semantics(
      button: true,
      label: isRecording ? 'Stop listening' : 'Start microphone dictation',
      hint: isRecording ? 'Double tap to finish voice input' : 'Double tap to record speech',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            context.read<HumanizerProvider>().toggleRecording();
          },
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRecording ? AppColors.error : AppColors.surfaceSubtle,
              border: Border.all(
                color: isRecording ? Colors.transparent : AppColors.glassBorder,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isRecording
                      ? AppColors.error.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isRecording ? LucideIcons.micOff : LucideIcons.mic,
              size: 16,
              color: isRecording ? Colors.white : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
