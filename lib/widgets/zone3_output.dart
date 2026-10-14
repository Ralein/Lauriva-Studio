import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/studio_provider.dart';
import '../services/slop_linter.dart';
import '../services/slop_repair_service.dart';
import '../utils/share_helper.dart';
import 'glass_card.dart';
import 'lauriva_skeleton.dart';
import 'studio/slop_report_chip.dart';
import 'studio/visual_diff_viewer.dart';
import 'tts_highlight_text_view.dart';
import 'tts_player_bar.dart';
import 'rephrase_selection_sheet.dart';

class Zone3Output extends StatefulWidget {
  const Zone3Output({super.key});

  @override
  State<Zone3Output> createState() => _Zone3OutputState();
}

class _Zone3OutputState extends State<Zone3Output> {
  bool _showComparison = false;
  bool _showDiff = false;

  @override
  Widget build(BuildContext context) {
    // StudioProvider's input/output text is a single shared workspace across
    // Studio, Detector, and Humanizer — but a result should only ever show
    // up on the screen whose feature actually produced it. Gate on
    // activeFeatureId so, e.g., running "Humanize" from the Humanizer tab
    // doesn't leave its output looking like it came from Studio.
    final activeFeatureId = context.select<StudioProvider, String>((p) => p.activeFeatureId);
    final belongsToStudio = activeFeatureId != 'Humanize' && activeFeatureId != 'PlagiarismCheck';
    final rawOutputText = context.select<StudioProvider, String>((p) => p.outputText);
    final outputText = belongsToStudio ? rawOutputText : '';
    final hasOutput = outputText.isNotEmpty;
    final isLoading = context.select<StudioProvider, bool>((p) => p.isLoading);
    final isStreaming = context.select<StudioProvider, bool>((p) => p.isStreaming);
    final copied = context.select<StudioProvider, bool>((p) => p.copied);
    final inputText = context.select<StudioProvider, String>((p) => p.inputText);
    final isPolishing = context.select<StudioProvider, bool>((p) => p.isPolishing);
    final slopReport = context.select<StudioProvider, SlopReport?>((p) => p.lastSlopReport);
    final slopRepair = context.select<StudioProvider, SlopRepairResult?>((p) => p.lastSlopRepair);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        // Top Section Header: Label & Comparison Toggle
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

              // View Toggle & Stop Generation Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    Semantics(
                      button: true,
                      label: 'Stop in-flight text generation',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            context.read<StudioProvider>().stopGeneration();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.square, size: 10, color: AppColors.error),
                                const SizedBox(width: 4),
                                Text(
                                  'Stop',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (hasOutput && inputText.isNotEmpty)
                    Semantics(
                      button: true,
                      label: _showComparison ? 'Show output text only' : 'Compare output with original input text',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _showComparison = !_showComparison;
                              if (_showComparison) _showDiff = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showComparison ? LucideIcons.columns : LucideIcons.arrowLeftRight,
                                  size: 13,
                                  color: _showComparison ? AppColors.primary : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showComparison ? 'Result only' : 'Compare',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _showComparison ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (hasOutput && inputText.isNotEmpty)
                    Semantics(
                      button: true,
                      label: _showDiff ? 'Hide diff inspector' : 'Show word-level diff revision inspector',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _showDiff = !_showDiff;
                              if (_showDiff) _showComparison = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.gitCompare,
                                  size: 13,
                                  color: _showDiff ? AppColors.primary : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showDiff ? 'Hide Diff' : 'Diff',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _showDiff ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Output text display container matching Humanizer GlassCard
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clean linear progress indicator when loading
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      backgroundColor: AppColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 2.5,
                    ),
                  ),
                ),

              if (hasOutput) ...[
                if (_showComparison) ...[
                  // Original Input Snippet
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
                          inputText,
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

                // Output Result Text with Selection Rephrase Menu & Live Speech Highlighting
                TtsHighlightTextView(
                  text: outputText,
                  isStreaming: isStreaming,
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
                            label: 'Rephrase',
                            onPressed: () {
                              ContextMenuController.removeAny();
                              RephraseSelectionSheet.show(
                                context,
                                selectedText: selected,
                                fullText: outputText,
                                startIndex: selection.start,
                                endIndex: selection.end,
                                title: 'Rephrase Selection',
                                headerIcon: LucideIcons.repeat,
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

                // Text metrics + AI-pattern check chip
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${outputText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words · ${outputText.length} chars',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isPolishing)
                        Text(
                          'Polishing AI patterns…',
                          style: GoogleFonts.outfit(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                        )
                      else if (slopReport != null && !isLoading)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 64),
                          child: SlopReportChip(report: slopReport, repair: slopRepair),
                        ),
                    ],
                  ),
                ),

                // Revision Inspector: word-level diff view
                if (_showDiff && inputText.isNotEmpty) ...[
                  VisualDiffViewer(
                    originalText: inputText,
                    modifiedText: outputText,
                  ),
                  const SizedBox(height: 12),
                ],

                // Controls footer (TTS Player + Minimal GPT-style Action buttons)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Left: TTS Player Bar
                    const TtsPlayerBar(),

                    // Right: GPT-style Minimal Icon Actions: Rephrase, Copy, Share, Use as Input
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Rephrase Selection Action Button
                        _buildMinimalIconButton(
                          icon: LucideIcons.repeat,
                          tooltip: 'Rephrase Selection',
                          onTap: () {
                            HapticFeedback.lightImpact();
                            RephraseSelectionSheet.show(
                              context,
                              selectedText: '',
                              fullText: outputText,
                              title: 'Rephrase Selection',
                              headerIcon: LucideIcons.repeat,
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        // Copy Button (GPT style)
                        _buildMinimalIconButton(
                          icon: copied ? LucideIcons.check : LucideIcons.copy,
                          tooltip: copied ? 'Copied' : 'Copy',
                          isSuccess: copied,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.read<StudioProvider>().copyOutputToClipboard();
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
                              title: 'Lauriva Studio Result',
                              text: outputText,
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
                            context.read<StudioProvider>().useOutputAsInput();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ] else if (isLoading) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LaurivaTextOutputSkeleton(),
                ),
              ] else ...[
                // Clean Empty State Placeholder matching Humanizer
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your result will appear here.',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select an action above to transform your text.',
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
