import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../constants/app_colors.dart';
import 'button_lauriva_spinner.dart';
import 'glass_card.dart';

/// Luxury Skeleton & Shimmer System for Lauriva
///
/// Implements unified visual parity with Forensics [ForensicChunkProgressCard]:
/// - Synchronized 1400ms GPU-accelerated breathing pulse animation
/// - Opacity breathing between 0.45 and 0.90
/// - Dark glassmorphic color tokens respecting [AppColors]
/// - Zero timer leaks and 100% test friendly
class LaurivaSkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final Color? baseColor;
  final Color? highlightColor;
  final Widget? child;

  const LaurivaSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
    this.baseColor,
    this.highlightColor,
    this.child,
  });

  @override
  State<LaurivaSkeletonBox> createState() => _LaurivaSkeletonBoxState();
}

class _LaurivaSkeletonBoxState extends State<LaurivaSkeletonBox>
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
    final base = widget.baseColor ?? AppColors.surfaceSubtle;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.45 + (_pulseController.value * 0.45);
        return Opacity(
          opacity: opacity,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: AppColors.glassBorder.withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Shimmer line placeholder for text paragraphs
class LaurivaSkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const LaurivaSkeletonLine({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return LaurivaSkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
      baseColor: AppColors.surfaceElevated,
    );
  }
}

/// Full Output Area Skeleton for Studio & Humanizer screens during text generation
/// Features the exact Forensics 1400ms pulse animation with realistic line variance
class LaurivaTextOutputSkeleton extends StatefulWidget {
  final String? subtitle;

  const LaurivaTextOutputSkeleton({
    super.key,
    this.subtitle,
  });

  @override
  State<LaurivaTextOutputSkeleton> createState() => _LaurivaTextOutputSkeletonState();
}

class _LaurivaTextOutputSkeletonState extends State<LaurivaTextOutputSkeleton>
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
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.45 + (_pulseController.value * 0.45);

        return Opacity(
          opacity: opacity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Paragraph shimmer lines with varied natural lengths
              _buildLine(width: double.infinity, height: 13),
              const SizedBox(height: 9),
              _buildLine(width: double.infinity, height: 13),
              const SizedBox(height: 9),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.88,
                child: _buildLine(height: 13),
              ),
              const SizedBox(height: 9),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.62,
                child: _buildLine(height: 13),
              ),
              const SizedBox(height: 16),

              // Metrics badge skeleton pill
              Row(
                children: [
                  Container(
                    width: 96,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Controls action bar skeleton
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // TTS Bar capsule
                  Container(
                    width: 120,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  // Action buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      4,
                      (index) => Container(
                        margin: const EdgeInsets.only(left: 6),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLine({double? width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Anticipation Skeleton for Humanizer Report Card during evaluation
/// Matches Forensics [ForensicChunkProgressCard] with 1:1 visual fidelity
class LaurivaHumanizerReportSkeleton extends StatefulWidget {
  final String? stage;

  const LaurivaHumanizerReportSkeleton({
    super.key,
    this.stage,
  });

  @override
  State<LaurivaHumanizerReportSkeleton> createState() => _LaurivaHumanizerReportSkeletonState();
}

class _LaurivaHumanizerReportSkeletonState extends State<LaurivaHumanizerReportSkeleton>
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
    final stageText = widget.stage ?? 'Evaluating stylometric & AI bypass metrics...';

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Header Bar matching Forensics & Humanizer Report Card
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
                            'HUMANIZER AUDIT IN PROGRESS',
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
            ],
          ),

          // 2. Sleek Linear Progress Line matching Forensics
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                backgroundColor: AppColors.surfaceElevated,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 2.5,
              ),
            ),
          ),

          // 3. Report Anticipation Skeleton (Animated with GPU Ticker matching Forensics 1:1)
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
                          // Radial Gauge Placeholder with Forensics scale pulse
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

                    // Grid of 4 Dimensions Skeleton matching Forensics & Humanizer Report
                    Row(
                      children: [
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.brain,
                            label: 'AI Risk',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.checkCheck,
                            label: 'Fidelity',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.shieldCheck,
                            label: 'Preserved',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDimensionSkeleton(
                            icon: LucideIcons.clock,
                            label: 'Read Time',
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

/// Generic List Skeleton Loader with Forensics pulse animation for Modals
class LaurivaListSkeleton extends StatefulWidget {
  final int itemCount;
  final double itemHeight;

  const LaurivaListSkeleton({
    super.key,
    this.itemCount = 4,
    this.itemHeight = 64,
  });

  @override
  State<LaurivaListSkeleton> createState() => _LaurivaListSkeletonState();
}

class _LaurivaListSkeletonState extends State<LaurivaListSkeleton>
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
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.45 + (_pulseController.value * 0.45);

        return Opacity(
          opacity: opacity,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return Container(
                height: widget.itemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 180,
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
              );
            },
          ),
        );
      },
    );
  }
}
