import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../constants/app_colors.dart';
import '../models/forensic/forensic_progress.dart';
import 'button_lauriva_spinner.dart';
import 'glass_card.dart';

/// Luxury glassmorphic progress card displaying live forensic audit progress,
/// multi-chunk indicators, and live layout shimmer matching the final report structure.
class ForensicChunkProgressCard extends StatefulWidget {
  final ForensicProgress? progress;

  const ForensicChunkProgressCard({
    super.key,
    this.progress,
  });

  @override
  State<ForensicChunkProgressCard> createState() => _ForensicChunkProgressCardState();
}

class _ForensicChunkProgressCardState extends State<ForensicChunkProgressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prog = widget.progress;
    final isMultiChunk = prog != null && prog.totalChunks > 1;
    final stageText = prog?.stage ?? 'Auditing stylistic, neural & syntactic vectors...';

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Header Bar (1:1 parity with PlagiarismAuditCard header)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: ButtonLaurivaSpinner(
                        size: 16,
                        ringColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMultiChunk
                                ? 'CHUNK ${prog.currentChunk.clamp(1, prog.totalChunks)} OF ${prog.totalChunks}'
                                : 'FORENSIC AUDIT IN PROGRESS',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: AppColors.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            stageText,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (prog != null && prog.totalWords > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Text(
                    '${prog.wordsProcessed} / ${prog.totalWords} words',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Single Unified Progress Bar: Segmented dashes for multi-chunk, or sleek line for single/indeterminate
          if (isMultiChunk && prog.totalChunks <= 16) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: List.generate(prog.totalChunks, (index) {
                  final chunkNum = index + 1;
                  final isDone = chunkNum < prog.currentChunk;
                  final isCurrent = chunkNum == prog.currentChunk;

                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppColors.primary
                            : (isCurrent
                                ? AppColors.primary
                                : AppColors.surfaceElevated),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: prog != null
                    ? LinearProgressIndicator(
                        value: prog.progressRatio > 0 ? prog.progressRatio : null,
                        backgroundColor: AppColors.surfaceElevated,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        minHeight: 2.5,
                      )
                    : LinearProgressIndicator(
                        backgroundColor: AppColors.surfaceElevated,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        minHeight: 2.5,
                      ),
              ),
            ),
          ],

          // 4. Report Anticipation Skeleton (Animated with GPU Ticker)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final opacity = 0.45 + (_pulseController.value * 0.45);
              final ringScale = 0.97 + (_pulseController.value * 0.06);

              return Opacity(
                opacity: opacity,
                child: Column(
                  children: [
                    // Top Assessment Box Skeleton
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(
                        children: [
                          // Radial Gauge Placeholder
                          Transform.scale(
                            scale: ringScale,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.35),
                                  width: 5,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 28,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Shimmer Text Lines Placeholder
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 80,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 110,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Grid of 4 Dimensions Skeleton
                    Row(
                      children: [
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.brain,
                            label: 'AI Authorship',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.bookOpen,
                            label: 'Source Match',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.activity,
                            label: 'Burstiness',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.shieldAlert,
                            label: 'Confidence',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionSkeleton({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: 38,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}
