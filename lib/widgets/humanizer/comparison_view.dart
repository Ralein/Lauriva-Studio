import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../models/plagiarism_report.dart';
import '../../providers/humanizer_provider.dart';
import '../../models/toast_notification.dart';
import '../../utils/share_helper.dart';
import 'humanizer_report_card.dart';
import '../glass_card.dart';
import '../lauriva_skeleton.dart';
import '../studio/visual_diff_viewer.dart';
import '../tts_highlight_text_view.dart';
import '../tts_player_bar.dart';
import '../rephrase_selection_sheet.dart';

/// Zone 3: Output Area, Humanized Result with Compare/Diff inspector,
/// and luxury Stylometric Humanization Audit Report matching Forensics.
class ComparisonView extends StatefulWidget {
  final String inputText;
  final String outputText;
  final bool isLoading;
  final PlagiarismReport? outputReport;
  final PlagiarismReport? inputReport;
  final double? semanticPreservationScore;
  final VoidCallback onReverify;
  final VoidCallback onUseAsInput;
  final void Function(String message, ToastType type) onShowToast;

  const ComparisonView({
    super.key,
    required this.inputText,
    required this.outputText,
    required this.isLoading,
    required this.outputReport,
    required this.inputReport,
    required this.semanticPreservationScore,
    required this.onReverify,
    required this.onUseAsInput,
    required this.onShowToast,
  });

  @override
  State<ComparisonView> createState() => _ComparisonViewState();
}

class _ComparisonViewState extends State<ComparisonView> {
  bool _showComparison = false;
  bool _showDiff = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final hasOutput = widget.outputText.isNotEmpty;
    final outputWordCount = widget.outputText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final readTimeSec = ((outputWordCount / 220) * 60).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── ZONE 3: Header with Dot, OUTPUT / RESULT, and Compare/Diff Actions ──
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
                      color: hasOutput ? AppColors.primary : AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasOutput ? 'RESULT' : 'OUTPUT',
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: hasOutput ? AppColors.primary : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Only show Compare & Diff when output is generated!
                  if (hasOutput && widget.inputText.isNotEmpty) ...[
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _showComparison = !_showComparison;
                          if (_showComparison) _showDiff = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showComparison ? LucideIcons.columns : LucideIcons.arrowLeftRight,
                              size: 12,
                              color: _showComparison ? AppColors.primary : AppColors.accentText,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showComparison ? 'Result only' : 'Compare',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _showComparison ? AppColors.primary : AppColors.accentText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _showDiff = !_showDiff;
                          if (_showDiff) _showComparison = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.gitCompare,
                              size: 12,
                              color: _showDiff ? AppColors.primary : AppColors.accentText,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showDiff ? 'Hide Diff' : 'Diff',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _showDiff ? AppColors.primary : AppColors.accentText,
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

        // ── Humanized Result GlassCard ────────────────────────────────────────
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Chunk progress indicator & message when loading
              if (widget.isLoading) ...[
                Builder(
                  builder: (context) {
                    final humanizer = Provider.of<HumanizerProvider?>(context);
                    final msg = humanizer?.chunkProgressMessage;
                    final ratio = humanizer?.chunkProgressRatio;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: (ratio != null && ratio > 0.0) ? ratio : null,
                              backgroundColor: AppColors.surfaceElevated,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                              minHeight: 3.0,
                            ),
                          ),
                          if (msg != null && msg.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              msg,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: AppColors.paletteCerulean,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],

              if (hasOutput) ...[
                // Compare Diff Mode: Show original snippet
                if (_showComparison) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ORIGINAL TEXT',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.inputText,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Humanized Text Body with Selection Rephrase Menu & Live Speech Highlighting
                TtsHighlightTextView(
                  text: widget.outputText,
                  contextMenuBuilder: (ctx, editableTextState) {
                    final value = editableTextState.textEditingValue;
                    final selection = value.selection;
                    final buttonItems = List<ContextMenuButtonItem>.from(editableTextState.contextMenuButtonItems);
                    if (selection.isValid && !selection.isCollapsed && selection.start >= 0 && selection.end <= value.text.length) {
                      final selected = selection.textInside(value.text).trim();
                      if (selected.isNotEmpty) {
                        buttonItems.insert(
                          0,
                          ContextMenuButtonItem(
                            label: 'Humanize',
                            onPressed: () {
                              ContextMenuController.removeAny();
                              RephraseSelectionSheet.show(
                                context,
                                selectedText: selected,
                                fullText: widget.outputText,
                                startIndex: selection.start,
                                endIndex: selection.end,
                                title: 'Humanize Selection',
                                headerIcon: LucideIcons.fingerprint,
                              );
                            },
                          ),
                        );
                      }
                    }
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editableTextState.contextMenuAnchors,
                      buttonItems: buttonItems,
                    );
                  },
                ),
                // Metrics bar
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '$outputWordCount words · ${widget.outputText.length} chars',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // Revision Inspector: word-level diff view copied from Studio
                if (_showDiff && widget.inputText.isNotEmpty) ...[
                  VisualDiffViewer(
                    originalText: widget.inputText,
                    modifiedText: widget.outputText,
                  ),
                  const SizedBox(height: 12),
                ],

                // Metrics & Action Controls Footer (TTS Player Bar + Minimal GPT-style Actions)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Left: Full-featured Speech / TTS Player Bar
                    TtsPlayerBar(textToSpeak: widget.outputText),

                    // Right: Minimal GPT-style Actions: Rephrase, Copy, Share, Export, Use as Input
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Humanize Selection Action Button
                        _buildMinimalIconButton(
                          icon: LucideIcons.fingerprint,
                          tooltip: 'Humanize Selection',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            RephraseSelectionSheet.show(
                              context,
                              selectedText: '',
                              fullText: widget.outputText,
                              title: 'Humanize Selection',
                              headerIcon: LucideIcons.fingerprint,
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        // Copy Button (GPT style)
                        _buildMinimalIconButton(
                          icon: _copied ? LucideIcons.check : LucideIcons.copy,
                          tooltip: _copied ? 'Copied' : 'Copy',
                          isSuccess: _copied,
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            await Clipboard.setData(ClipboardData(text: widget.outputText));
                            setState(() => _copied = true);
                            widget.onShowToast('Copied humanized text!', ToastType.success);
                            Future.delayed(const Duration(seconds: 2), () {
                              if (mounted) setState(() => _copied = false);
                            });
                          },
                        ),
                        const SizedBox(width: 6),

                        // Share Button (GPT style)
                        _buildMinimalIconButton(
                          icon: LucideIcons.share2,
                          tooltip: 'Share',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            final box = context.findRenderObject() as RenderBox?;
                            ShareHelper.shareText(
                              title: 'Lauriva Humanized Text',
                              text: widget.outputText,
                              sharePositionOrigin: box != null
                                  ? box.localToGlobal(Offset.zero) & box.size
                                  : null,
                            );
                          },
                        ),
                        const SizedBox(width: 6),

                        // Use as Input Button (GPT style)
                        _buildMinimalIconButton(
                          icon: LucideIcons.cornerDownLeft,
                          tooltip: 'Use as Input',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onUseAsInput();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ] else if (widget.isLoading) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LaurivaTextOutputSkeleton(),
                ),
              ] else ...[
                // Clean Empty State Placeholder matching Studio
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your humanized result will appear here.',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select a tone action above to transform your text.',
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          color: AppColors.textMuted.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Humanizer Audit Report Card ─────────────────────────────────────
        if (widget.isLoading) ...[
          const SizedBox(height: 16),
          const LaurivaHumanizerReportSkeleton(),
        ] else if (hasOutput && widget.inputReport != null && widget.outputReport != null) ...[
          const SizedBox(height: 16),
          HumanizerReportCard(
            originalScore: widget.inputReport!.overallScore,
            humanizedScore: widget.outputReport!.overallScore,
            semanticFidelity: (widget.semanticPreservationScore ?? 0.97) * 100,
            contentPreserved: 100.0,
            wordCount: outputWordCount,
            charCount: widget.outputText.length,
            readTimeSec: readTimeSec > 0 ? readTimeSec : 1,
          ),
        ],
      ],
    );
  }

  /// Minimal GPT-style rounded icon action button with tooltip and subtle glass styling
  Widget _buildMinimalIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isSuccess = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSuccess
                    ? AppColors.successBg
                    : AppColors.glassInputBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSuccess
                      ? AppColors.success.withValues(alpha: 0.4)
                      : AppColors.glassBorder,
                  width: 1.0,
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 15,
                  color: isSuccess
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
