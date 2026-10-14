import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../constants/app_colors.dart';
import '../models/forensic/forensic_report.dart';
import '../models/plagiarism_report.dart';
import '../services/forensic/explainer/score_explainer.dart';

/// Interactive sentence-level inline document highlighter.
/// Renders analyzed text with subtle, translucent risk tints.
/// Tapping any sentence opens a glassmorphic "Why Flagged?" diagnostic bottom sheet.
class InlineForensicHighlighter extends StatelessWidget {
  final ForensicReport? report;
  final PlagiarismReport? plagiarismReport;
  final ScoreExplainer explainer;
  final int? maxSentences;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  const InlineForensicHighlighter({
    super.key,
    this.report,
    this.plagiarismReport,
    this.explainer = const ScoreExplainer(),
    this.maxSentences,
    this.isExpanded = false,
    this.onToggleExpand,
  }) : assert(report != null || plagiarismReport != null, 'Either report or plagiarismReport must be provided');

  List<SentenceAudit> get sentences =>
      report?.sentences ?? plagiarismReport?.sentences ?? const [];

  int get wordCount =>
      report?.wordCount ??
      sentences.fold<int>(0, (sum, s) => sum + s.wordCount);

  int get sentenceCount =>
      report?.sentenceCount ?? sentences.length;

  String get rawText =>
      report?.rawText ?? sentences.map((s) => s.text).join(' ');

  Color _getRiskColor(PlagiarismRiskLevel risk) {
    switch (risk) {
      case PlagiarismRiskLevel.clean:
        return AppColors.success;
      case PlagiarismRiskLevel.low:
        return AppColors.primary;
      case PlagiarismRiskLevel.moderate:
        return AppColors.warning;
      case PlagiarismRiskLevel.high:
        return const Color(0xFFF97316);
      case PlagiarismRiskLevel.critical:
        return AppColors.error;
    }
  }

  void _showSentenceSheet(BuildContext context, SentenceAudit audit) {
    final docWordCount = wordCount;
    final docSentenceCount = sentenceCount;
    final averageDocWords = (docWordCount / (docSentenceCount > 0 ? docSentenceCount : 1)).round();
    final reasons = explainer.explainSentence(
      audit,
      averageDocWords: averageDocWords,
    );
    final riskColor = _getRiskColor(audit.riskLevel);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          bottom: true,
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: AppColors.glassBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: AppColors.isDark ? 0.6 : 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle & Header bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.textMuted.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: riskColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(LucideIcons.scanLine, color: riskColor, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Sentence ${audit.index + 1} Diagnostic',
                                        style: GoogleFonts.outfit(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 17,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Forensic Signal Breakdown',
                                        style: GoogleFonts.outfit(
                                          color: AppColors.textMuted,
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                decoration: BoxDecoration(
                                  color: riskColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: riskColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  '${audit.aiProbability.toStringAsFixed(0)}% AI RISK',
                                  style: GoogleFonts.outfit(
                                    color: riskColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(LucideIcons.x, size: 20, color: AppColors.textMuted),
                                onPressed: () => Navigator.pop(ctx),
                                tooltip: 'Close',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(color: AppColors.glassBorder, height: 12),

                // Scrollable Diagnostic Content
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Metadata Chips Row
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildInfoChip(
                              icon: LucideIcons.fileText,
                              label: '${audit.wordCount} words',
                              color: AppColors.textSecondary,
                            ),
                            _buildInfoChip(
                              icon: audit.riskLevel.icon,
                              label: audit.riskLevel.badge,
                              color: riskColor,
                            ),
                            if (audit.detectedTells.isNotEmpty)
                              _buildInfoChip(
                                icon: LucideIcons.fingerprint,
                                label: '${audit.detectedTells.length} AI marker${audit.detectedTells.length > 1 ? 's' : ''}',
                                color: const Color(0xFFF97316),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Sentence Quote Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: riskColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            '"${audit.text}"',
                            style: GoogleFonts.outfit(
                              color: AppColors.textPrimary,
                              fontSize: 14.5,
                              fontStyle: FontStyle.italic,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Why Flagged Section Header
                        Row(
                          children: [
                            Icon(LucideIcons.search, size: 13, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(
                              'WHY FLAGGED (EXPLAINABILITY AUDIT)',
                              style: GoogleFonts.outfit(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // List of explanation reasons
                        ...reasons.map((reason) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: audit.riskLevel == PlagiarismRiskLevel.clean ||
                                        audit.riskLevel == PlagiarismRiskLevel.low
                                    ? const Color(0x1210B981)
                                    : const Color(0x18F97316),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: audit.riskLevel == PlagiarismRiskLevel.clean ||
                                          audit.riskLevel == PlagiarismRiskLevel.low
                                      ? const Color(0x3310B981)
                                      : const Color(0x38F97316),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, right: 9),
                                    child: Icon(
                                      audit.riskLevel == PlagiarismRiskLevel.clean ||
                                              audit.riskLevel == PlagiarismRiskLevel.low
                                          ? LucideIcons.checkCircle2
                                          : LucideIcons.alertTriangle,
                                      color: riskColor,
                                      size: 15,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      reason,
                                      style: GoogleFonts.outfit(
                                        color: AppColors.textPrimary,
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ),

                // Bottom Action Button with safe padding
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(LucideIcons.check, size: 16),
                      label: Text(
                        'Done with Sentence ${audit.index + 1}',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sentList = sentences;
    if (sentList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          rawText.isNotEmpty ? rawText : 'No text content available for analysis.',
          style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 13.5, height: 1.45),
        ),
      );
    }

    final effectiveSentences = (maxSentences != null && !isExpanded)
        ? sentList.take(maxSentences!).toList()
        : sentList;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(LucideIcons.fileText, size: 15, color: AppColors.primary),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Document Passage',
                        style: GoogleFonts.outfit(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.scanLine, size: 11, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to Diagnose',
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$wordCount words · $sentenceCount sentences · Tap any sentence to diagnose forensic risk.',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          // Responsive list of sentence highlight cards
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: effectiveSentences.map((sent) {
              final color = _getRiskColor(sent.riskLevel);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showSentenceSheet(context, sent),
                    borderRadius: BorderRadius.circular(10),
                    splashColor: color.withValues(alpha: 0.15),
                    highlightColor: color.withValues(alpha: 0.08),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.9),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2, right: 9),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: color.withValues(alpha: 0.3), width: 0.7),
                            ),
                            child: Text(
                              'S${sent.index + 1}',
                              style: GoogleFonts.outfit(
                                color: color,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              sent.text,
                              style: GoogleFonts.outfit(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sent.aiProbability >= 80
                                      ? 'High Risk'
                                      : (sent.aiProbability >= 40 ? 'Mixed' : 'Human'),
                                  style: GoogleFonts.outfit(
                                    color: color,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'AI: ${sent.aiProbability.toStringAsFixed(0)}%',
                                style: GoogleFonts.outfit(
                                  fontSize: 10.5,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          if (maxSentences != null && sentList.length > maxSentences!) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onToggleExpand,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isExpanded
                          ? 'Collapse to top $maxSentences sentences'
                          : 'Show all ${sentList.length} sentences (+${sentList.length - maxSentences!} more)',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
