import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/forensic/forensic_progress.dart';
import '../models/forensic/forensic_scan_mode.dart';
import '../models/toast_notification.dart';
import '../providers/plagiarism_provider.dart';
import '../providers/speech_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/toast_provider.dart';
import '../widgets/button_lauriva_spinner.dart';
import '../widgets/forensic_chunk_progress_card.dart';
import '../widgets/forensic_mini_settings.dart';
import '../widgets/glass_card.dart';
import '../widgets/header_bar.dart';
import '../widgets/plagiarism_audit_card.dart';
import 'settings_screen.dart';

/// Dedicated screen for comprehensive AI writing and plagiarism detection.
class DetectorScreen extends StatefulWidget {
  /// Where "Humanize" sends the user once it produces a result —
  /// the Humanizer tab, never Studio, so the humanized output always opens
  /// in its dedicated home.
  final VoidCallback? onNavigateToHumanizer;
  final VoidCallback? onNavigateToSettings;

  const DetectorScreen({
    super.key,
    this.onNavigateToHumanizer,
    this.onNavigateToSettings,
  });

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen> {
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final plagiarism = context.read<PlagiarismProvider>();
    _textController = TextEditingController(text: plagiarism.inputText);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final plagiarism = context.read<PlagiarismProvider>();
    final toast = context.read<ToastProvider>();
    if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
      setState(() {
        _textController.text = data.text!;
      });
      plagiarism.setInputText(data.text!);
      toast.showToast('Pasted text from clipboard', ToastType.info);
    } else {
      toast.showToast('Clipboard is empty', ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } catch (_) {}
    final plagiarism = context.watch<PlagiarismProvider>();
    final speech = context.watch<SpeechProvider>();
    final toast = context.read<ToastProvider>();
    final report = plagiarism.plagiarismReport;
    final isLoading = plagiarism.isScanning;
    final isRecording = speech.isRecording;

    final wordCount = _textController.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final charCount = _textController.text.length;

    // Keep controller in sync with provider if updated externally (like voice dictation)
    if (_textController.text != plagiarism.inputText && (!_focusNode.hasFocus || isRecording)) {
      _textController.text = plagiarism.inputText;
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Screen Header
              HeaderBar(
                title: 'Forensics',
                onSettingsPressed: widget.onNavigateToSettings ?? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 18),

              // ── ZONE 1: Input Text Section (Parity with Humanizer) ─────────
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
                          label: 'Paste text from clipboard into document to audit',
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
                        if (_textController.text.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: 'Clear document input text',
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _textController.clear();
                                setState(() {});
                                _textController.clear();
                                plagiarism.clearInput();
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

              // Input GlassCard
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _textController,
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
                            : 'Type or paste text to audit...',
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 15,
                          color: AppColors.textMuted.withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) {
                        setState(() {});
                        plagiarism.setInputText(val);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            wordCount == 0
                                ? '0 words · 0 chars'
                                : '$wordCount words · $charCount chars',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Tactile Voice Dictation Mic Button (parity with Humanizer and Studio)
                        _buildVoiceButton(context, isRecording),

                        if (_textController.text.trim().isNotEmpty) ...[
                          const SizedBox(width: 6),

                          // Primary Scan CTA (parity with Humanizer Action button)
                          ElevatedButton.icon(
                            onPressed: isLoading
                                ? null
                                : () {
                                    HapticFeedback.mediumImpact();
                                    final text = _textController.text.trim();
                                    if (text.isEmpty) {
                                      toast.showToast('Please enter or paste text to audit.', ToastType.error);
                                      return;
                                    }
                                    plagiarism.setInputText(text);
                                    plagiarism.runPlagiarismCheck(text);
                                  },
                            icon: isLoading
                                ? const ButtonLaurivaSpinner(
                                    size: 14,
                                    ringColor: Colors.white,
                                  )
                                : const Icon(LucideIcons.scan, size: 13),
                            label: Text(
                              isLoading
                                  ? (plagiarism.scanMode == ForensicScanMode.sourceScan
                                      ? 'Searching Sources...'
                                      : (plagiarism.scanMode == ForensicScanMode.forensic
                                          ? 'Auditing AI...'
                                          : 'Auditing...'))
                                  : (plagiarism.scanMode == ForensicScanMode.sourceScan
                                      ? 'Run Source Scan'
                                      : (plagiarism.scanMode == ForensicScanMode.forensic
                                          ? 'Run Forensic Scan'
                                          : 'Run Full Audit')),
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
              const SizedBox(height: 14),

              // ── ZONE 2: Forensic Profile & Mini Settings ───────────────────
              ForensicMiniSettings(),
              const SizedBox(height: 16),

              // ── ZONE 3: Output Area & Forensic Audit Card ──────────────────
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isLoading || report != null ? AppColors.primary : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLoading
                              ? 'AUDITING'
                              : (report != null ? 'RESULT' : 'OUTPUT'),
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: isLoading || report != null ? AppColors.primary : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (isLoading) ...[
                ValueListenableBuilder<ForensicProgress?>(
                  valueListenable: plagiarism.progressNotifier,
                  builder: (context, progress, _) {
                    return ForensicChunkProgressCard(progress: progress);
                  },
                ),
              ] else if (plagiarism.isFixingPlagiarism) ...[
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ButtonLaurivaSpinner(size: 16, ringColor: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              plagiarism.chunkProgressMessage ?? 'Humanizing document in chunks...',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (plagiarism.chunkProgressRatio != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: plagiarism.chunkProgressRatio,
                            backgroundColor: AppColors.surfaceSubtle,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else if (report != null) ...[
                PlagiarismAuditCard(
                  report: report,
                  onNavigateToHumanizer: widget.onNavigateToHumanizer,
                ),
              ] else ...[
                // Clean Overview Card matching Studio and Humanizer empty state
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your forensic audit will appear here.',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            color: AppColors.textMuted.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Run a scan to inspect AI probability, source matches, and originality.',
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            color: AppColors.textMuted.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
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
            final speech = context.read<SpeechProvider>();
            if (speech.isRecording) {
              speech.stopListening();
            } else {
              speech.startListening(
                onResult: (words, isFinal) {
                  setState(() {
                    _textController.text = words;
                  });
                  context.read<PlagiarismProvider>().setInputText(words);
                },
              );
            }
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
