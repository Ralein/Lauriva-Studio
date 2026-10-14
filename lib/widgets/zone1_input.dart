import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/feature_type.dart';
import '../models/toast_notification.dart';
import '../providers/speech_provider.dart';
import '../providers/studio_provider.dart';
import '../providers/toast_provider.dart';
import 'button_lauriva_spinner.dart';
import 'glass_card.dart';

class Zone1Input extends StatefulWidget {
  const Zone1Input({super.key});

  @override
  State<Zone1Input> createState() => _Zone1InputState();
}

class _Zone1InputState extends State<Zone1Input> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final provider = context.read<StudioProvider>();
    _controller = TextEditingController(text: provider.inputText);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final studio = context.read<StudioProvider>();
    final toast = context.read<ToastProvider>();
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _controller.text = data.text!;
      studio.setInputText(data.text!);
      toast.showToast('Pasted from clipboard', ToastType.info);
    } else {
      toast.showToast('Clipboard is empty', ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentInputText = context.select<StudioProvider, String>((p) => p.inputText);
    final isRecording = context.select<SpeechProvider, bool>((p) => p.isRecording);
    if (_controller.text != currentInputText && (!_focusNode.hasFocus || isRecording)) {
      final currentOffset = _controller.selection.baseOffset;
      final newOffset = currentOffset >= 0 && currentOffset <= currentInputText.length
          ? currentOffset
          : currentInputText.length;
      _controller.value = _controller.value.copyWith(
        text: currentInputText,
        selection: TextSelection.collapsed(offset: newOffset),
      );
    }
    final isLoading = context.select<StudioProvider, bool>((p) => p.isLoading);
    final studioActionId = context.select<StudioProvider, String>((p) => p.studioActionId);
    final activeFeature = FeatureType.fromId(studioActionId) ?? FeatureType.rephrase;
    final effectiveText = _controller.text.isNotEmpty ? _controller.text : currentInputText;
    final inputWordCount = effectiveText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Section Header: Label & Quick Clipboard Actions
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
                  Semantics(
                    button: true,
                    label: 'Paste text from clipboard into input field',
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _pasteFromClipboard();
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
                  ),
                  if (currentInputText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: 'Clear input field text',
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _controller.clear();
                          context.read<StudioProvider>().clearInput();
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
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Text field container matching Humanizer GlassCard
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 6,
                minLines: 4,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  hintText: isRecording
                      ? 'Listening...'
                      : 'Type or paste text to transform...',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 15,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) => context.read<StudioProvider>().setInputText(val),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$inputWordCount words',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          ' · ${currentInputText.length} chars',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Modern Tactile Voice Dictate Button matching Humanizer
                  _buildVoiceButton(context, isRecording),

                  if (_controller.text.trim().isNotEmpty || currentInputText.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: isLoading
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              final textToRun = _controller.text.trim();
                              final studio = context.read<StudioProvider>();
                              studio.setInputText(_controller.text);
                              if (textToRun.isEmpty) {
                                context.read<ToastProvider>().showToast(
                                  'Please type or record some text first.',
                                  ToastType.error,
                                );
                                return;
                              }
                              studio.handleFeatureClick(studio.studioActionId);
                            },
                      icon: isLoading
                          ? const ButtonLaurivaSpinner(
                              size: 14,
                              ringColor: Colors.white,
                            )
                          : Icon(activeFeature.icon, size: 14),
                      label: Text(
                        isLoading
                            ? 'Working...'
                            : (activeFeature == FeatureType.translate
                                ? 'Translate'
                                : activeFeature.label),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
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
            context.read<StudioProvider>().toggleRecording();
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
