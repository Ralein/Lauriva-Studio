import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';
import '../../services/slop_linter.dart';
import '../../services/slop_repair_service.dart';

/// Compact "AI-pattern check" chip; tap opens a sheet listing the findings.
class SlopReportChip extends StatelessWidget {
  final SlopReport report;
  final SlopRepairResult? repair;

  const SlopReportChip({super.key, required this.report, this.repair});

  @override
  Widget build(BuildContext context) {
    final clean = report.isClean;
    final color = clean ? AppColors.success : AppColors.warning;
    final flags = report.findings.length;
    final label = clean && flags == 0
        ? 'AI-pattern check ${report.score}/5'
        : '${report.score}/5 · $flags flag${flags == 1 ? '' : 's'}';
    return Semantics(
      button: true,
      label: 'AI-pattern check, score ${report.score} of 5. Tap for details',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.lightImpact();
            SlopReportSheet.show(context, report: report, repair: repair);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(clean ? LucideIcons.shieldCheck : LucideIcons.triangleAlert, size: 12, color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SlopReportSheet extends StatelessWidget {
  final SlopReport report;
  final SlopRepairResult? repair;

  const SlopReportSheet({super.key, required this.report, this.repair});

  static Future<void> show(BuildContext context, {required SlopReport report, SlopRepairResult? repair}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SlopReportSheet(report: report, repair: repair),
    );
  }

  static const _titles = {
    SlopCategory.vocabulary: 'Stock vocabulary',
    SlopCategory.sentencePatterns: 'Sentence patterns',
    SlopCategory.punctuation: 'Punctuation',
    SlopCategory.threeItemLists: 'Three-item lists',
    SlopCategory.unsupportedProof: 'Unsupported claims',
  };

  @override
  Widget build(BuildContext context) {
    final groups = report.byCategory;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            Text(
              'AI-pattern check ${report.score}/5',
              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            if (repair != null) ...[
              const SizedBox(height: 6),
              Text(
                'Polished: ${repair!.before.findings.length} → ${repair!.after.findings.length} flags',
                style: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.success, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            if (groups.isEmpty)
              Text(
                'No AI-writing patterns found.',
                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary),
              ),
            for (final entry in groups.entries) ...[
              Text(
                _titles[entry.key] ?? entry.key.name,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              for (final f in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${f.label}: ',
                        style: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textSecondary),
                      ),
                      TextSpan(
                        text: f.match.trim(),
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
