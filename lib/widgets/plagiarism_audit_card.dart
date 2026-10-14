import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../models/forensic/forensic_report.dart';
import '../models/forensic/forensic_scan_mode.dart';
import '../models/forensic/forensic_span.dart';
import '../models/forensic/source_similarity_evidence.dart';
import '../models/forensic/token_predictability.dart';
import '../models/plagiarism_report.dart';
import '../models/toast_notification.dart';
import '../providers/humanizer_provider.dart';
import '../providers/plagiarism_provider.dart';
import '../providers/toast_provider.dart';
import 'glass_card.dart';
import 'inline_forensic_highlighter.dart';
import 'score_gauge_widget.dart';
import 'citation_export_modal.dart';
import '../services/forensic/sources/citation_generator_service.dart';
import '../utils/share_helper.dart';

/// Perspectives for progressive disclosure in the audit report.
enum AuditPerspective {
  deepForensic(label: 'Deep Forensic', icon: LucideIcons.scanLine),
  executive(label: 'Executive View', icon: LucideIcons.clipboardCheck);

  final String label;
  final IconData icon;
  const AuditPerspective({required this.label, required this.icon});
}

/// Available visualization layers in the interactive forensic inspector.
enum ForensicHeatmapLayer {
  ai(label: 'AI Risk', icon: LucideIcons.brain),
  tokenMap(label: 'Token Map', icon: LucideIcons.binary),
  sources(label: 'Sources', icon: LucideIcons.bookOpen),
  cadence(label: 'Cadence', icon: LucideIcons.activity),
  spans(label: 'Spans', icon: LucideIcons.highlighter);

  final String label;
  final IconData icon;
  const ForensicHeatmapLayer({required this.label, required this.icon});
}

/// Luxury glassmorphic card displaying the Plagiarism & AI Detection Audit
/// with interactive sentence heatmap and one-click humanizer fix.
class PlagiarismAuditCard extends StatefulWidget {
  final PlagiarismReport report;
  /// Invoked once the "Humanize" fix produces a result, so the
  /// caller can open the Humanizer tab to show it — humanized output belongs
  /// in the Humanizer, not left buried on the Detector screen.
  final VoidCallback? onNavigateToHumanizer;

  const PlagiarismAuditCard({
    super.key,
    required this.report,
    this.onNavigateToHumanizer,
  });

  @override
  State<PlagiarismAuditCard> createState() => _PlagiarismAuditCardState();
}

class _PlagiarismAuditCardState extends State<PlagiarismAuditCard> {
  bool _showSentenceBreakdown = true;
  int? _selectedSpanIndex;
  late ForensicHeatmapLayer _activeHeatmapLayer;
  AuditPerspective _perspective = AuditPerspective.deepForensic;
  bool _showAllExecutiveSentences = false;
  bool _showAllForensicSentences = false;
  bool _showAllCadenceSentences = false;

  @override
  void initState() {
    super.initState();
    _activeHeatmapLayer = ForensicHeatmapLayer.ai;
  }

  @override
  Widget build(BuildContext context) {
    final plagiarism = context.watch<PlagiarismProvider>();
    final toast = context.read<ToastProvider>();
    final report = widget.report;

    final forensic = plagiarism.forensicReport;
    final scanMode = forensic?.metadata.scanMode ?? plagiarism.scanMode;

    final double displayScore;
    final String gaugeLabel;
    final String modeHeaderLabel;
    final String leftBarLabel;
    final String rightBarLabel;
    final double rightScore;

    switch (scanMode) {
      case ForensicScanMode.sourceScan:
        displayScore = forensic != null ? forensic.sourceSimilarity.overallSimilarityScore : report.overallScore;
        gaugeLabel = 'Source Match';
        modeHeaderLabel = 'Source Scan';
        leftBarLabel = 'Matched: ${displayScore.toStringAsFixed(0)}%';
        rightScore = (100.0 - displayScore).clamp(0.0, 100.0);
        rightBarLabel = 'Original: ${rightScore.toStringAsFixed(0)}%';
        break;
      case ForensicScanMode.forensic:
        displayScore = forensic != null ? forensic.aiAuthorship.aiProbability : report.overallScore;
        gaugeLabel = 'AI Risk';
        modeHeaderLabel = 'Forensic Scan';
        leftBarLabel = 'Risk: ${displayScore.toStringAsFixed(0)}%';
        rightScore = (100.0 - displayScore).clamp(0.0, 100.0);
        rightBarLabel = 'Original: ${rightScore.toStringAsFixed(0)}%';
        break;
      case ForensicScanMode.fullForensic:
        displayScore = forensic != null ? forensic.overallScore : report.overallScore;
        gaugeLabel = 'Forensic Risk';
        modeHeaderLabel = 'Full Forensic';
        leftBarLabel = 'Risk: ${displayScore.toStringAsFixed(0)}%';
        rightScore = (100.0 - displayScore).clamp(0.0, 100.0);
        rightBarLabel = 'Original: ${rightScore.toStringAsFixed(0)}%';
        break;
    }
    final displayRiskLevel = PlagiarismRiskLevel.fromScore(displayScore);

    final String displayBadge;
    final Color displayBadgeColor;
    final Color displayBadgeBgColor;
    final String displaySummaryText;

    if (scanMode == ForensicScanMode.sourceScan) {
      if (displayScore < 5.0) {
        displayBadge = 'NO SOURCES · 100% ORIGINAL';
        displayBadgeColor = const Color(0xFF10B981);
        displayBadgeBgColor = const Color(0x2610B981);
        displaySummaryText = (forensic != null && forensic.sourceSimilarity.defensibleSummary.isNotEmpty)
            ? forensic.sourceSimilarity.defensibleSummary
            : 'No matching literature or web sources found across scanned repositories.';
      } else if (displayScore < 20.0) {
        displayBadge = 'MINOR SOURCE OVERLAP';
        displayBadgeColor = const Color(0xFF38BDF8);
        displayBadgeBgColor = const Color(0x2638BDF8);
        displaySummaryText = (forensic != null && forensic.sourceSimilarity.defensibleSummary.isNotEmpty)
            ? forensic.sourceSimilarity.defensibleSummary
            : 'Minor common phrasing or standardized terminology matched across literature.';
      } else if (displayScore < 50.0) {
        displayBadge = 'MIXED SOURCES';
        displayBadgeColor = const Color(0xFFF59E0B);
        displayBadgeBgColor = const Color(0x26F59E0B);
        displaySummaryText = (forensic != null && forensic.sourceSimilarity.defensibleSummary.isNotEmpty)
            ? forensic.sourceSimilarity.defensibleSummary
            : 'Moderate passage similarity and paraphrased sections matched to external sources.';
      } else {
        displayBadge = 'HEAVY SOURCE MATCH';
        displayBadgeColor = const Color(0xFFEF4444);
        displayBadgeBgColor = const Color(0x26EF4444);
        displaySummaryText = (forensic != null && forensic.sourceSimilarity.defensibleSummary.isNotEmpty)
            ? forensic.sourceSimilarity.defensibleSummary
            : 'Extensive verbatim or closely matched passages identified in external literature.';
      }
    } else {
      displayBadge = displayRiskLevel.badge;
      displayBadgeColor = displayRiskLevel.color;
      displayBadgeBgColor = displayRiskLevel.bgColor;
      displaySummaryText = (report.defensibleSummary != null && report.defensibleSummary!.isNotEmpty)
          ? report.defensibleSummary!
          : displayRiskLevel.description;
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withAlpha(80)),
                      ),
                      child: Icon(
                        LucideIcons.shieldCheck,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AUDIT RESULT · ${scanMode.badge}',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            modeHeaderLabel,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (context) {
                  final sourceMatches = plagiarism.forensicReport?.sourceSimilarity.matches ?? const [];
                  if (sourceMatches.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      CitationExportModal.show(
                        context,
                        matches: sourceMatches,
                        initialIndex: -1,
                      );
                    },
                    icon: Icon(LucideIcons.graduationCap, size: 17, color: AppColors.primary),
                    tooltip: 'Academic Citations & Bibliography',
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final forensic = plagiarism.forensicReport;
                  final summary = _buildExecutiveReport(report, forensic, scanMode);
                  ShareHelper.shareText(
                    title: 'Lauriva Forensic Audit Certificate',
                    text: summary,
                  );
                },
                icon: Icon(LucideIcons.share2, size: 17, color: AppColors.primary),
                tooltip: 'Share Audit Certificate',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () {
                  plagiarism.clearPlagiarismReport();
                },
                icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMuted),
                tooltip: 'Dismiss Report',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Main Rating Gauge & Risk Summary with Big % and Big Text
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.glassInputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                // Animated SSS-Tier Radial Score Gauge with Big %
                ScoreGaugeWidget(
                  score: displayScore,
                  label: gaugeLabel,
                  showBadgeInside: false,
                  size: 88,
                ),
                const SizedBox(width: 14),

                // Big Text, Risk Badge & Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final maxBadgeWidth = constraints.maxWidth;
                          return Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: maxBadgeWidth),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: displayBadgeBgColor,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: displayBadgeColor.withAlpha(100)),
                                  ),
                                  child: Text(
                                    displayBadge,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: displayBadgeColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: maxBadgeWidth),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceSubtle,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.glassBorder),
                                  ),
                                  child: Text(
                                    report.confidenceLevel.toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: AppColors.textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        displaySummaryText,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Human vs AI probability split bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              Expanded(
                                flex: (displayScore * 10).toInt().clamp(1, 999),
                                child: Container(color: displayBadgeColor),
                              ),
                              Expanded(
                                flex: (rightScore * 10).toInt().clamp(1, 999),
                                child: Container(color: const Color(0xFF10B981)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              leftBarLabel,
                              style: GoogleFonts.outfit(fontSize: 11.5, color: displayBadgeColor, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              rightBarLabel,
                              style: GoogleFonts.outfit(fontSize: 11.5, color: const Color(0xFF10B981), fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Perspective Switcher: Executive View vs Deep Forensic Audit
          _buildPerspectiveSwitcher(),
          const SizedBox(height: 10),

          if (_perspective == AuditPerspective.executive) ...[
            _buildExecutiveView(
              plagiarism: plagiarism,
              report: report,
              forensic: forensic,
              scanMode: scanMode,
              displayScore: displayScore,
              displayBadgeColor: displayBadgeColor,
              displayBadge: displayBadge,
              displaySummaryText: displaySummaryText,
            ),
          ] else ...[
            // Subtle Forensic Dimensions Summary
            if (forensic != null) ...[
              _buildForensicPillars(forensic, scanMode, report: report),
              const SizedBox(height: 2),
            ],
            // 6. Sentence & Multi-Layer Forensic Heatmap
            const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final String inspectorTitle;
              switch (scanMode) {
                case ForensicScanMode.sourceScan:
                  inspectorTitle = 'Source Inspector';
                  break;
                case ForensicScanMode.forensic:
                  inspectorTitle = 'Forensic AI Inspector';
                  break;
                case ForensicScanMode.fullForensic:
                  inspectorTitle = 'Forensic Inspector';
                  break;
              }

              final effectiveLayer = (scanMode == ForensicScanMode.sourceScan)
                  ? ForensicHeatmapLayer.sources
                  : ((scanMode == ForensicScanMode.forensic && _activeHeatmapLayer == ForensicHeatmapLayer.sources)
                      ? ForensicHeatmapLayer.ai
                      : _activeHeatmapLayer);

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.glassInputBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _showSentenceBreakdown = !_showSentenceBreakdown;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          children: [
                            Icon(
                              _showSentenceBreakdown ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              scanMode == ForensicScanMode.sourceScan ? LucideIcons.bookOpen : LucideIcons.scanLine,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                inspectorTitle,
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showSentenceBreakdown) ...[
                      const SizedBox(height: 12),
                      // Layer Switcher Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (scanMode != ForensicScanMode.sourceScan) ...[
                              _buildHeatmapTabChip('AI Risk', ForensicHeatmapLayer.ai, LucideIcons.brain, activeLayer: effectiveLayer),
                              const SizedBox(width: 6),
                              _buildHeatmapTabChip(
                                'Token Map',
                                ForensicHeatmapLayer.tokenMap,
                                LucideIcons.binary,
                                activeLayer: effectiveLayer,
                                badge: report.tokenPredictabilityReport != null
                                    ? '${report.tokenPredictabilityReport!.top10Percentage.toStringAsFixed(0)}%'
                                    : null,
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (scanMode != ForensicScanMode.forensic) ...[
                              _buildHeatmapTabChip(
                                'Sources',
                                ForensicHeatmapLayer.sources,
                                LucideIcons.bookOpen,
                                activeLayer: effectiveLayer,
                                badge: (plagiarism.forensicReport?.sourceSimilarity.uniqueSourceCount ?? 0) > 0
                                    ? '${plagiarism.forensicReport!.sourceSimilarity.uniqueSourceCount}'
                                    : null,
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (scanMode != ForensicScanMode.sourceScan) ...[
                              _buildHeatmapTabChip('Cadence', ForensicHeatmapLayer.cadence, LucideIcons.activity, activeLayer: effectiveLayer),
                              const SizedBox(width: 6),
                              _buildHeatmapTabChip(
                                'Spans',
                                ForensicHeatmapLayer.spans,
                                LucideIcons.highlighter,
                                activeLayer: effectiveLayer,
                                badge: (plagiarism.forensicReport?.spans.length ?? 0) > 0
                                    ? '${plagiarism.forensicReport!.spans.length}'
                                    : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildActiveHeatmapLayer(plagiarism, report, layer: effectiveLayer),
                    ],
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // 7. Action Footer: One-Click Fix & Copy
          Row(
            children: [
              // High-impact Fix Button
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // Pre-fill input for Humanizer and clear old output, preserving exact paragraph linebreaks
                      final humanizer = Provider.of<HumanizerProvider?>(context, listen: false);
                      final plagiarism = Provider.of<PlagiarismProvider?>(context, listen: false);
                      final rawInput = plagiarism?.inputText.trim() ?? '';
                      final forensicRaw = forensic?.rawText.trim() ?? '';
                      final fullText = rawInput.isNotEmpty
                          ? plagiarism!.inputText
                          : (forensicRaw.isNotEmpty
                              ? forensic!.rawText
                              : report.sentences.map((s) => s.text).join('\n\n'));

                      if (humanizer != null && fullText.trim().isNotEmpty) {
                        humanizer.setInputText(fullText);
                        humanizer.clearOutput();
                      }
                      widget.onNavigateToHumanizer?.call();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.fingerprint, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Humanize',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Copy Audit Summary Button
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: () async {
                      final executiveReport = _buildExecutiveReport(report, forensic, scanMode);
                      await Clipboard.setData(ClipboardData(text: executiveReport));
                      toast.showToast('Copied Executive Audit Report to clipboard!', ToastType.success);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.glassBorderHover),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.copy, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Copy Report',
                            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

  Widget _buildPerspectiveSwitcher() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _perspective = AuditPerspective.executive);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6.5),
                decoration: BoxDecoration(
                  color: _perspective == AuditPerspective.executive ? AppColors.surfaceElevated : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: _perspective == AuditPerspective.executive
                      ? Border.all(color: AppColors.primary.withAlpha(120))
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.clipboardCheck,
                      size: 13,
                      color: _perspective == AuditPerspective.executive ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Executive',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: _perspective == AuditPerspective.executive ? FontWeight.w700 : FontWeight.w600,
                          color: _perspective == AuditPerspective.executive ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _perspective = AuditPerspective.deepForensic);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6.5),
                decoration: BoxDecoration(
                  color: _perspective == AuditPerspective.deepForensic ? AppColors.surfaceElevated : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: _perspective == AuditPerspective.deepForensic
                      ? Border.all(color: AppColors.primary.withAlpha(120))
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.scanLine,
                      size: 13,
                      color: _perspective == AuditPerspective.deepForensic ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Deep Forensic',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: _perspective == AuditPerspective.deepForensic ? FontWeight.w700 : FontWeight.w600,
                          color: _perspective == AuditPerspective.deepForensic ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveView({
    required PlagiarismProvider plagiarism,
    required PlagiarismReport report,
    required ForensicReport? forensic,
    required ForensicScanMode scanMode,
    required double displayScore,
    required Color displayBadgeColor,
    required String displayBadge,
    required String displaySummaryText,
  }) {
    final matches = forensic?.sourceSimilarity.matches ?? const [];
    final burstiness = report.burstinessScore;
    final cadenceLabel = burstiness > 0.55
        ? 'Dynamic (Human)'
        : (burstiness < 0.35 ? 'Uniform (AI)' : 'Moderate');
    final cadenceColor = burstiness > 0.55
        ? const Color(0xFF10B981)
        : (burstiness < 0.35 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));

    final tellsCount = report.detectedTells.length;
    final originalPercent = (100.0 - displayScore).clamp(0.0, 100.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Executive Key Metrics Grid (Consistent with Deep Forensic Pillars)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.glassInputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.clipboardCheck, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'EXECUTIVE AUDIT DIMENSIONS',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildExecutiveMetricTile(
                      'Originality',
                      '${originalPercent.toStringAsFixed(0)}%',
                      originalPercent >= 70.0 ? 'Defensible Original' : 'Review Needed',
                      originalPercent >= 70.0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      LucideIcons.shieldCheck,
                      isHighlighted: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildExecutiveMetricTile(
                      'Cadence & Flow',
                      cadenceLabel,
                      'CV ${burstiness.toStringAsFixed(2)} · Burstiness',
                      cadenceColor,
                      LucideIcons.activity,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildExecutiveMetricTile(
                      'Literature Match',
                      matches.isEmpty ? '0 Sources' : '${matches.length} Sources',
                      matches.isEmpty ? 'Zero Overlap' : '${matches.length} Matched',
                      matches.isEmpty ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                      LucideIcons.bookOpen,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildExecutiveMetricTile(
                      'Syntactic Tells',
                      tellsCount == 0 ? 'None' : '$tellsCount Detected',
                      tellsCount == 0 ? 'Clean Prose' : 'Boilerplate Flagged',
                      tellsCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      LucideIcons.fingerprint,
                      isHighlighted: tellsCount > 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Executive Verdict & Findings Card (Deep Forensic Consistency)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.glassInputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.fileCheck2, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'EXECUTIVE VERDICT',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: displayBadgeColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: displayBadgeColor.withAlpha(80)),
                    ),
                    child: Text(
                      report.riskLevel.name.toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: displayBadgeColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (report.defensibleSummary != null && report.defensibleSummary!.isNotEmpty)
                    ? report.defensibleSummary!
                    : displaySummaryText,
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildExecutivePill(scanMode.label, LucideIcons.scanLine, AppColors.textSecondary),
                  _buildExecutivePill(displayBadge, LucideIcons.shieldAlert, displayBadgeColor),
                  _buildExecutivePill('Lexical: ${report.lexicalRichness.toStringAsFixed(0)}%', LucideIcons.sparkles, AppColors.textSecondary),
                ],
              ),
            ],
          ),
        ),

        // 3. Screened Document Passage & Highlights (Interactive Sentence Diagnostic)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: forensic != null && forensic.sentences.isNotEmpty
              ? InlineForensicHighlighter(
                  report: forensic,
                  maxSentences: _showAllExecutiveSentences ? null : 4,
                  isExpanded: _showAllExecutiveSentences,
                  onToggleExpand: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showAllExecutiveSentences = !_showAllExecutiveSentences);
                  },
                )
              : InlineForensicHighlighter(
                  plagiarismReport: report,
                  maxSentences: _showAllExecutiveSentences ? null : 4,
                  isExpanded: _showAllExecutiveSentences,
                  onToggleExpand: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showAllExecutiveSentences = !_showAllExecutiveSentences);
                  },
                ),
        ),

        // 4. Deep Forensic Inspector Launch Card
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.glassInputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withAlpha(70)),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _perspective = AuditPerspective.deepForensic);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(LucideIcons.scanLine, size: 16, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Deep Forensic Inspector',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'DETAILED',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Token maps, sentence heatmaps, and literature fragments available.',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, size: 16, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 5. Action Footer: One-Click Fix & Copy
        Row(
          children: [
            // Humanize Button
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final humanizer = Provider.of<HumanizerProvider?>(context, listen: false);
                    final plagiarism = Provider.of<PlagiarismProvider?>(context, listen: false);
                    final rawInput = plagiarism?.inputText.trim() ?? '';
                    final forensicRaw = forensic?.rawText.trim() ?? '';
                    final fullText = rawInput.isNotEmpty
                        ? plagiarism!.inputText
                        : (forensicRaw.isNotEmpty
                            ? forensic!.rawText
                            : report.sentences.map((s) => s.text).join('\n\n'));

                    if (humanizer != null && fullText.trim().isNotEmpty) {
                      humanizer.setInputText(fullText);
                      humanizer.clearOutput();
                    }
                    widget.onNavigateToHumanizer?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.fingerprint, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Humanize',
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Copy Certificate Button
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () async {
                    final executiveReport = _buildExecutiveReport(report, forensic, scanMode);
                    await Clipboard.setData(ClipboardData(text: executiveReport));
                    if (mounted) {
                      context.read<ToastProvider>().showToast('Copied Executive Audit Report to clipboard!', ToastType.success);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.glassBorderHover),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.copy, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Copy Report',
                          style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExecutiveMetricTile(
    String label,
    String value,
    String sub,
    Color color,
    IconData icon, {
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(isHighlighted ? 40 : 20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlighted ? color : color.withAlpha(50),
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
                    color: isHighlighted ? color : AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 13, color: isHighlighted ? color : color.withAlpha(200)),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              sub,
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExecutivePill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: color),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildForensicPillars(ForensicReport forensic, ForensicScanMode scanMode, {PlagiarismReport? report}) {
    final String dimensionsTitle;
    final IconData dimensionsIcon;
    final Widget row1;
    final Widget row2;

    switch (scanMode) {
      case ForensicScanMode.sourceScan:
        dimensionsTitle = 'SOURCE DIMENSIONS';
        dimensionsIcon = LucideIcons.bookOpen;
        row1 = Row(
          children: [
            Expanded(
              child: _buildPillarItem(
                'Source Match',
                '${forensic.sourceSimilarity.overallSimilarityScore.toStringAsFixed(0)}%',
                '${forensic.sourceSimilarity.uniqueSourceCount} Sources',
                forensic.sourceSimilarity.overallSimilarityScore >= 20.0 ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
                isHighlighted: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPillarItem(
                'Unique Sources',
                '${forensic.sourceSimilarity.uniqueSourceCount}',
                'Indexed Repositories',
                AppColors.primary,
              ),
            ),
          ],
        );
        row2 = Row(
          children: [
            Expanded(
              child: _buildPillarItem(
                'Doc Coverage',
                '${forensic.sourceSimilarity.documentCoveragePercent.toStringAsFixed(0)}%',
                '${forensic.sourceSimilarity.matchedTokenCount} Words Matched',
                const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPillarItem(
                'Confidence',
                forensic.sourceSimilarity.confidenceLevel.contains('HIGH') ? 'HIGH' : 'STANDARD',
                'Attribution Evidence',
                const Color(0xFF10B981),
              ),
            ),
          ],
        );
        break;

      case ForensicScanMode.forensic:
        dimensionsTitle = 'FORENSIC AI DIMENSIONS';
        dimensionsIcon = LucideIcons.fingerprint;
        final predPercentage = report?.tokenPredictabilityReport?.top10Percentage;
        row1 = Row(
          children: [
            Expanded(
              child: _buildPillarItem(
                'AI Authorship',
                '${forensic.aiAuthorship.aiProbability.toStringAsFixed(0)}%',
                forensic.aiAuthorship.authorshipClass.badge,
                forensic.aiAuthorship.aiProbability >= 65.0 ? const Color(0xFFF97316) : const Color(0xFF10B981),
                isHighlighted: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPillarItem(
                'Predictability',
                predPercentage != null ? '${predPercentage.toStringAsFixed(0)}%' : 'N/A',
                'Top 10 Tokens',
                const Color(0xFF38BDF8),
              ),
            ),
          ],
        );
        row2 = Row(
          children: [
            Expanded(
              child: _buildPillarItem(
                'Repetition',
                '${forensic.internalRepetition.repetitionScore.toStringAsFixed(0)}%',
                '${forensic.internalRepetition.flaggedBoilerplates.length} Boilerplates',
                forensic.internalRepetition.repetitionScore >= 30.0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPillarItem(
                'Confidence',
                forensic.confidence.uncertainty <= 0.35 ? 'HIGH' : 'STANDARD',
                forensic.confidence.uncertainty <= 0.35 ? 'High Accuracy' : 'Standard Audit',
                forensic.confidence.uncertainty <= 0.35 ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
              ),
            ),
          ],
        );
        break;

      case ForensicScanMode.fullForensic:
        dimensionsTitle = 'FORENSIC DIMENSIONS';
        dimensionsIcon = LucideIcons.shieldCheck;
        row1 = Row(
          children: [
            Expanded(
              child: _buildPillarItem(
                'AI Authorship',
                '${forensic.aiAuthorship.aiProbability.toStringAsFixed(0)}%',
                forensic.aiAuthorship.authorshipClass.badge,
                forensic.aiAuthorship.aiProbability >= 65.0 ? const Color(0xFFF97316) : const Color(0xFF10B981),
                isHighlighted: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPillarItem(
                'Source Match',
                '${forensic.sourceSimilarity.overallSimilarityScore.toStringAsFixed(0)}%',
                '${forensic.sourceSimilarity.uniqueSourceCount} Sources',
                forensic.sourceSimilarity.overallSimilarityScore >= 20.0 ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
              ),
            ),
          ],
        );
        row2 = Row(
          children: [
            Expanded(
              child: _buildPillarItem(
                'Repetition',
                '${forensic.internalRepetition.repetitionScore.toStringAsFixed(0)}%',
                '${forensic.internalRepetition.flaggedBoilerplates.length} Boilerplates',
                forensic.internalRepetition.repetitionScore >= 30.0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPillarItem(
                'Confidence',
                forensic.confidence.uncertainty <= 0.35 ? 'HIGH' : 'STANDARD',
                forensic.confidence.uncertainty <= 0.35 ? 'High Accuracy' : 'Standard Audit',
                forensic.confidence.uncertainty <= 0.35 ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                isHighlighted: true,
              ),
            ),
          ],
        );
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(dimensionsIcon, size: 13, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dimensionsTitle,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          row1,
          const SizedBox(height: 8),
          row2,
        ],
      ),
    );
  }

  Widget _buildPillarItem(String label, String value, String sub, Color color, {bool isHighlighted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(isHighlighted ? 40 : 20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted ? color : color.withAlpha(50),
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
                    color: isHighlighted ? color : AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isHighlighted)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sub,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapTabChip(
    String label,
    ForensicHeatmapLayer layer,
    IconData icon, {
    ForensicHeatmapLayer? activeLayer,
    String? badge,
  }) {
    final isSelected = (activeLayer ?? _activeHeatmapLayer) == layer;
    return InkWell(
      onTap: () {
        setState(() {
          _activeHeatmapLayer = layer;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withAlpha(35) : AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.glassBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveHeatmapLayer(
    PlagiarismProvider plagiarism,
    PlagiarismReport report, {
    ForensicHeatmapLayer? layer,
  }) {
    final effective = layer ?? _activeHeatmapLayer;
    switch (effective) {
      case ForensicHeatmapLayer.ai:
        if (plagiarism.forensicReport != null && plagiarism.forensicReport!.sentences.isNotEmpty) {
          return InlineForensicHighlighter(
            report: plagiarism.forensicReport!,
            maxSentences: _showAllForensicSentences ? null : 4,
            isExpanded: _showAllForensicSentences,
            onToggleExpand: () {
              HapticFeedback.selectionClick();
              setState(() => _showAllForensicSentences = !_showAllForensicSentences);
            },
          );
        }
        return InlineForensicHighlighter(
          plagiarismReport: report,
          maxSentences: _showAllForensicSentences ? null : 4,
          isExpanded: _showAllForensicSentences,
          onToggleExpand: () {
            HapticFeedback.selectionClick();
            setState(() => _showAllForensicSentences = !_showAllForensicSentences);
          },
        );
      case ForensicHeatmapLayer.tokenMap:
        return _buildTokenPredictabilityLayer(report);
      case ForensicHeatmapLayer.sources:
        return _buildSourcesLayer(plagiarism);
      case ForensicHeatmapLayer.cadence:
        return _buildCadenceLayer(report);
      case ForensicHeatmapLayer.spans:
        return _buildSpansLayer(plagiarism);
    }
  }

  Widget _buildTokenPredictabilityLayer(PlagiarismReport report) {
    final tokenRep = report.tokenPredictabilityReport;
    if (tokenRep == null || tokenRep.tokens.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassInputBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(
          'Token predictability metrics not available for this sample.',
          style: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4 Tiers Legend
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildTokenLegendBadge(
                label: 'Top 10 (${tokenRep.top10Percentage.toStringAsFixed(0)}%)',
                color: const Color(0xFF10B981),
                bgColor: const Color(0x3310B981),
              ),
              _buildTokenLegendBadge(
                label: 'Top 100 (${tokenRep.top100Percentage.toStringAsFixed(0)}%)',
                color: const Color(0xFF38BDF8),
                bgColor: const Color(0x3338BDF8),
              ),
              _buildTokenLegendBadge(
                label: 'Top 1000 (${tokenRep.top1000Percentage.toStringAsFixed(0)}%)',
                color: const Color(0xFFF97316),
                bgColor: const Color(0x33F97316),
              ),
              _buildTokenLegendBadge(
                label: 'Rare Tail (${tokenRep.rareTailPercentage.toStringAsFixed(0)}%)',
                color: const Color(0xFFEF4444),
                bgColor: const Color(0x33EF4444),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tokenRep.defensibleSummary,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          // Interactive Tokens Wrap
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tokenRep.tokens.map((token) {
              Color fg;
              Color bg;
              switch (token.tier) {
                case TokenTier.top10:
                  fg = const Color(0xFF34D399);
                  bg = const Color(0x3310B981);
                  break;
                case TokenTier.top100:
                  fg = const Color(0xFF7DD3FC);
                  bg = const Color(0x2838BDF8);
                  break;
                case TokenTier.top1000:
                  fg = const Color(0xFFFDBA74);
                  bg = const Color(0x28F97316);
                  break;
                case TokenTier.rareTail:
                  fg = const Color(0xFFFCA5A5);
                  bg = const Color(0x38EF4444);
                  break;
              }

              return Tooltip(
                message: '${token.token}: rank ~${token.rankEstimate} (${token.tier.label})',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: fg.withValues(alpha: 0.3), width: 0.8),
                  ),
                  child: Text(
                    token.token,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenLegendBadge({
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
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

  Widget _buildSourcesLayer(PlagiarismProvider plagiarism) {
    final matches = plagiarism.forensicReport?.sourceSimilarity.matches ?? [];
    if (matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x1410B981),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x3310B981)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.checkCircle2, color: Color(0xFF10B981), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Zero external overlap detected. Text appears original across indexed literature and baseline corpora.',
                style: GoogleFonts.outfit(fontSize: 11.5, color: const Color(0xFF6EE7B7)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MATCHED LITERATURE SOURCES (${matches.length})',
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          ...matches.map((m) {
            final isCited = m.citationStatus == CitationStatus.quotedAndCited || m.citationStatus == CitationStatus.cited;
            final color = isCited ? const Color(0xFF10B981) : const Color(0xFFEF4444);
            final isParaphrase = m.matchType == SourceMatchType.fuzzyParaphrase;
            final isExact = m.matchType == SourceMatchType.exact;
            final canOpen = m.sourceUrl != null && m.sourceUrl!.trim().isNotEmpty;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canOpen ? () => _openSourceUrl(context, m.sourceUrl) : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withAlpha(15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withAlpha(50)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.sourceTitle,
                                style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isParaphrase) ...[
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
                                ),
                                child: Text(
                                  'PARAPHRASED',
                                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning),
                                ),
                              ),
                            ] else if (isExact) ...[
                              Container(
                                margin: const EdgeInsets.only(right: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                                ),
                                child: Text(
                                  'EXACT QUOTE',
                                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                                ),
                              ),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                m.citationStatus.label,
                                style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.glassInputBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1, right: 6),
                                child: Icon(LucideIcons.quote, size: 10, color: AppColors.primary),
                              ),
                              Expanded(
                                child: Text(
                                  '"${m.matchedText}"',
                                  style: GoogleFonts.outfit(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${m.similarityPercent.toStringAsFixed(0)}% similarity • ${m.matchType.label}',
                                style: GoogleFonts.outfit(fontSize: 11.5, color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (canOpen) ...[
                              const SizedBox(width: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Open source',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(LucideIcons.externalLink, size: 11, color: AppColors.primary),
                                ],
                              ),
                            ],
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                CitationExportModal.show(
                                  context,
                                  matches: matches,
                                  initialIndex: matches.indexOf(m),
                                );
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withAlpha(25),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.primary.withAlpha(70)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.graduationCap, size: 11, color: AppColors.primary),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Cite',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
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
          }),
        ],
      ),
    );
  }

  Widget _buildCadenceLayer(PlagiarismReport report) {
    if (report.sentences.isEmpty) return const SizedBox.shrink();
    final totalWords = report.sentences.fold<int>(0, (sum, s) => sum + s.wordCount);
    final mean = totalWords / report.sentences.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Document Mean: ${mean.toStringAsFixed(1)} words/sentence',
              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final allEntries = report.sentences.asMap().entries.toList();
              final visibleEntries = (_showAllCadenceSentences || allEntries.length <= 4)
                  ? allEntries
                  : allEntries.take(4).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...visibleEntries.map((entry) {
                    final idx = entry.key;
                    final s = entry.value;
                    final diff = s.wordCount - mean;
                    final prevCount = idx > 0 ? report.sentences[idx - 1].wordCount : null;
                    final isMonotonous = prevCount != null && (s.wordCount - prevCount).abs() <= 1;
                    final cadenceColor = isMonotonous ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cadenceColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: cadenceColor.withAlpha(50)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'Sentence ${idx + 1} • ${s.wordCount} words',
                                        style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: cadenceColor),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '(${diff >= 0 ? "+${diff.toStringAsFixed(1)}" : diff.toStringAsFixed(1)})',
                                      style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cadenceColor.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isMonotonous ? 'Uniform Pacing' : 'Varied Rhythm',
                                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: cadenceColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            s.text,
                            style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  }),
                  if (allEntries.length > 4) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _showAllCadenceSentences = !_showAllCadenceSentences);
                      },
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
                              _showAllCadenceSentences ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _showAllCadenceSentences
                                  ? 'Collapse to top 4 sentences'
                                  : 'Show all ${allEntries.length} sentences (+${allEntries.length - 4} more)',
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
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpansLayer(PlagiarismProvider plagiarism) {
    final spans = plagiarism.forensicReport?.spans ?? [];
    if (spans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x1410B981),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x3310B981)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.checkCircle2, color: Color(0xFF10B981), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No isolated anomaly spans flagged in document text.',
                style: GoogleFonts.outfit(fontSize: 11.5, color: const Color(0xFF6EE7B7)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassInputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spans.asMap().entries.map((entry) {
          final idx = entry.key;
          final span = entry.value;
          final isSelected = _selectedSpanIndex == idx;

          Color sevColor;
          switch (span.severity) {
            case SpanSeverity.critical:
              sevColor = const Color(0xFFEF4444);
              break;
            case SpanSeverity.high:
              sevColor = const Color(0xFFF97316);
              break;
            case SpanSeverity.moderate:
              sevColor = const Color(0xFFF59E0B);
              break;
            case SpanSeverity.low:
            case SpanSeverity.info:
              sevColor = const Color(0xFF38BDF8);
              break;
          }

          return InkWell(
            onTap: () {
              setState(() {
                _selectedSpanIndex = isSelected ? null : idx;
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: sevColor.withAlpha(15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? sevColor : sevColor.withAlpha(50),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: sevColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          span.severity.name.toUpperCase(),
                          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          span.type.label,
                          style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: sevColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Chars ${span.startOffset}..${span.endOffset}',
                        style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '"${span.text}"',
                    style: GoogleFonts.outfit(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.textPrimary),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isSelected || span.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      span.explanation,
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _openSourceUrl(BuildContext context, String? url) async {
    if (url == null || url.trim().isEmpty) return;
    try {
      final uri = Uri.parse(url.trim());
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        context.read<ToastProvider>().showToast('Could not open source URL: $url', ToastType.error);
      }
    } catch (e) {
      if (context.mounted) {
        context.read<ToastProvider>().showToast('Unable to open source link: $e', ToastType.error);
      }
    }
  }

  String _buildExecutiveReport(
    PlagiarismReport report,
    ForensicReport? forensic,
    ForensicScanMode scanMode,
  ) {
    final buffer = StringBuffer();
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final totalWords = forensic?.wordCount ?? report.sentences.fold<int>(0, (sum, s) => sum + s.wordCount);
    final totalSentences = forensic?.sentenceCount ?? report.sentences.length;

    final sim = forensic?.sourceSimilarity;
    final matchScore = sim?.overallSimilarityScore ?? report.plagiarismRiskScore;
    final origScore = (100.0 - matchScore).clamp(0.0, 100.0);
    final matches = sim?.matches ?? const [];

    // Executive Verdict calculation
    final String verdictEmoji;
    final String verdictLabel;

    if (scanMode == ForensicScanMode.sourceScan) {
      if (matchScore < 10.0) {
        verdictEmoji = '✅';
        verdictLabel = 'ORIGINAL WORK (${origScore.toStringAsFixed(1)}% Original · Clean)';
      } else if (matchScore < 25.0) {
        verdictEmoji = '⚖️';
        verdictLabel = 'MODERATE SOURCE OVERLAP (${matchScore.toStringAsFixed(1)}% Match)';
      } else {
        verdictEmoji = '⚠️';
        verdictLabel = 'HIGH LITERATURE OVERLAP (${matchScore.toStringAsFixed(1)}% Match)';
      }
    } else if (scanMode == ForensicScanMode.forensic) {
      if (report.overallScore < 30.0) {
        verdictEmoji = '✅';
        verdictLabel = 'AUTHENTIC HUMAN PROSE (${report.humanScore.toStringAsFixed(1)}% Authenticity)';
      } else if (report.overallScore < 65.0) {
        verdictEmoji = '⚖️';
        verdictLabel = 'MIXED / PARTIAL AI (${report.overallScore.toStringAsFixed(1)}% AI Likelihood)';
      } else {
        verdictEmoji = '⚠️';
        verdictLabel = 'HIGH PROBABILITY AI-GENERATED (${report.overallScore.toStringAsFixed(1)}% AI Likelihood)';
      }
    } else {
      // Full Forensic
      if (report.overallScore < 30.0 && matchScore < 15.0) {
        verdictEmoji = '✅';
        verdictLabel = 'AUTHENTIC & ORIGINAL (${report.humanScore.toStringAsFixed(1)}% Human · ${origScore.toStringAsFixed(1)}% Original)';
      } else if (report.overallScore < 65.0) {
        verdictEmoji = '⚖️';
        verdictLabel = 'MIXED FORENSIC SIGNALS (${report.overallScore.toStringAsFixed(1)}% AI · ${matchScore.toStringAsFixed(1)}% Overlap)';
      } else {
        verdictEmoji = '⚠️';
        verdictLabel = 'HIGH AI AUTHORSHIP (${report.overallScore.toStringAsFixed(1)}% AI Likelihood)';
      }
    }

    buffer.writeln('🛡️ *LAURIVA FORENSIC AUDIT REPORT*');
    buffer.writeln('─────────────────────────────');
    buffer.writeln('$verdictEmoji *Verdict:* $verdictLabel');
    buffer.writeln('📋 *Mode:* ${scanMode.label}');
    buffer.writeln('📝 *Scope:* $totalWords words · $totalSentences sentences');
    buffer.writeln('📅 *Date:* $dateStr');
    buffer.writeln('─────────────────────────────');

    if (scanMode == ForensicScanMode.sourceScan) {
      buffer.writeln('\n🔍 *LITERATURE SCAN METRICS*');
      buffer.writeln('• *Literature Match:* ${matchScore.toStringAsFixed(1)}%');
      buffer.writeln('• *Document Originality:* ${origScore.toStringAsFixed(1)}%');
      if (sim != null) {
        buffer.writeln('• *Unique Sources Matched:* ${sim.uniqueSourceCount}');
        buffer.writeln('• *Document Corpus Coverage:* ${sim.documentCoveragePercent.toStringAsFixed(1)}%');
        buffer.writeln('• *Longest Contiguous Match:* ${sim.longestContiguousTokenMatch} tokens');
      }

      buffer.writeln('\n📚 *SOURCE CITATIONS & EVIDENCE*');
      if (matches.isNotEmpty) {
        for (int i = 0; i < matches.length; i++) {
          final m = matches[i];
          buffer.writeln('\n[${i + 1}] *${m.sourceTitle}*');
          buffer.writeln('    • Similarity: ${m.similarityPercent.toStringAsFixed(0)}% · ${m.matchType.label}');
          buffer.writeln('    • Status: ${m.citationStatus.label}');
          buffer.writeln('    • Excerpt: _"${m.matchedText.trim()}"_');
          if (m.sourceUrl != null && m.sourceUrl!.trim().isNotEmpty) {
            buffer.writeln('    • Link: ${m.sourceUrl!.trim()}');
          }
        }
      } else {
        buffer.writeln('• No external verbatim or paraphrased matches detected.');
      }
    } else if (scanMode == ForensicScanMode.forensic) {
      buffer.writeln('\n📊 *AI AUTHORSHIP ANALYSIS*');
      buffer.writeln('• *AI Likelihood:* ${report.overallScore.toStringAsFixed(1)}% (${report.riskLevel.badge})');
      buffer.writeln('• *Human Authenticity:* ${report.humanScore.toStringAsFixed(1)}%');
      buffer.writeln('• *Confidence:* ${report.confidenceLevel}');
      if (report.defensibleSummary != null && report.defensibleSummary!.isNotEmpty) {
        buffer.writeln('• *Summary:* _${report.defensibleSummary!.trim()}_');
      }

      buffer.writeln('\n⚡ *STYLOMETRIC & CADENCE METRICS*');
      final burstDesc = report.burstinessScore >= 0.8 ? '(Natural human variance)' : '(Uniform AI-like pacing)';
      buffer.writeln('• *Burstiness (CV):* ${report.burstinessScore.toStringAsFixed(2)} $burstDesc');
      buffer.writeln('• *Lexical Richness:* ${report.lexicalRichness.toStringAsFixed(1)}%');
      buffer.writeln('• *Formulaic N-Grams:* ${report.ngramOverlapScore.toStringAsFixed(1)}%');

      final tokenPred = forensic?.tokenPredictability ?? report.tokenPredictabilityReport;
      if (tokenPred != null && tokenPred.tokens.isNotEmpty) {
        buffer.writeln('• *Token Predictability:*');
        buffer.writeln('    - Top-10 Expected: ${tokenPred.top10Percentage.toStringAsFixed(1)}%');
        buffer.writeln('    - Top-100 Tokens: ${tokenPred.top100Percentage.toStringAsFixed(1)}%');
        buffer.writeln('    - Rare / Surprising Tokens: ${tokenPred.rareTailPercentage.toStringAsFixed(1)}%');
      }

      if (report.detectedTells.isNotEmpty) {
        buffer.writeln('\n🔎 *DETECTED SYNTACTIC PATTERNS*');
        for (final tell in report.detectedTells) {
          buffer.writeln('• $tell');
        }
      }
    } else {
      // Full Forensic
      buffer.writeln('\n📊 *DUAL-STREAM FORENSIC FINDINGS*');
      buffer.writeln('• *AI Authorship:* ${report.overallScore.toStringAsFixed(1)}% (${report.riskLevel.badge})');
      buffer.writeln('• *Human Authenticity:* ${report.humanScore.toStringAsFixed(1)}%');
      buffer.writeln('• *Literature Match:* ${matchScore.toStringAsFixed(1)}% (${origScore.toStringAsFixed(1)}% Original)');
      buffer.writeln('• *Confidence Level:* ${report.confidenceLevel}');
      if (report.defensibleSummary != null && report.defensibleSummary!.isNotEmpty) {
        buffer.writeln('• *Executive Finding:* _${report.defensibleSummary!.trim()}_');
      }

      buffer.writeln('\n⚡ *STYLOMETRIC CADENCE SIGNALS*');
      final burstDesc = report.burstinessScore >= 0.8 ? '(Natural human variance)' : '(Uniform AI-like pacing)';
      buffer.writeln('• *Sentence Burstiness:* ${report.burstinessScore.toStringAsFixed(2)} $burstDesc');
      buffer.writeln('• *Lexical Richness:* ${report.lexicalRichness.toStringAsFixed(1)}%');
      buffer.writeln('• *Formulaic Overlap:* ${report.ngramOverlapScore.toStringAsFixed(1)}%');

      final tokenPred = forensic?.tokenPredictability ?? report.tokenPredictabilityReport;
      if (tokenPred != null && tokenPred.tokens.isNotEmpty) {
        buffer.writeln('• *Token Predictability:* ${tokenPred.top10Percentage.toStringAsFixed(1)}% in Top-10');
      }

      if (matches.isNotEmpty) {
        buffer.writeln('\n📚 *MATCHED LITERATURE SOURCES (${matches.length})*');
        for (int i = 0; i < matches.length; i++) {
          final m = matches[i];
          buffer.writeln('\n[${i + 1}] *${m.sourceTitle}*');
          buffer.writeln('    • Overlap: ${m.similarityPercent.toStringAsFixed(0)}% · ${m.matchType.label}');
          buffer.writeln('    • Status: ${m.citationStatus.label}');
          buffer.writeln('    • Excerpt: _"${m.matchedText.trim()}"_');
          if (m.sourceUrl != null && m.sourceUrl!.trim().isNotEmpty) {
            buffer.writeln('    • Source: ${m.sourceUrl!.trim()}');
          }
        }
      }

      if (report.detectedTells.isNotEmpty) {
        buffer.writeln('\n🔎 *DETECTED WRITING PATTERNS*');
        for (final tell in report.detectedTells) {
          buffer.writeln('• $tell');
        }
      }

      if (matches.isNotEmpty) {
        final citationService = CitationGeneratorService();
        buffer.writeln('\n🎓 *WORKS CITED / BIBLIOGRAPHY (APA 7th)*');
        final uniqueMatches = <SourceMatchSegment>[];
        final seenTitles = <String>{};
        for (final m in matches) {
          if (!seenTitles.contains(m.sourceTitle.toLowerCase().trim())) {
            seenTitles.add(m.sourceTitle.toLowerCase().trim());
            uniqueMatches.add(m);
          }
        }
        for (int i = 0; i < uniqueMatches.length; i++) {
          final m = uniqueMatches[i];
          final meta = SourceMetadata(
            title: m.sourceTitle,
            url: m.sourceUrl ?? m.oaUrl,
          );
          buffer.writeln('${i + 1}. ${citationService.formatCitation(meta, CitationStyle.apa7)}');
        }
      }
    }

    if (report.fixedText != null && report.fixedScore != null) {
      buffer.writeln('\n─────────────────────────────');
      buffer.writeln('🌿 *LAURIVA HUMANIZER POST-FIX*');
      buffer.writeln('• *Original AI Score:* ${report.overallScore.toStringAsFixed(1)}%');
      buffer.writeln('• *Humanized AI Score:* ${report.fixedScore!.toStringAsFixed(1)}% (${report.fixedRiskLevel?.badge ?? "CLEAN"})');
      buffer.writeln('• *AI Risk Reduction:* -${(report.overallScore - report.fixedScore!).clamp(0, 100).toStringAsFixed(1)}%');
      buffer.writeln('• *Status:* Cleared for Natural Submission');
    }

    buffer.writeln('\n─────────────────────────────');
    buffer.writeln('✨ *Audited with Lauriva* · Deep Forensic & Literature Intelligence');
    return buffer.toString().trim();
  }
}
