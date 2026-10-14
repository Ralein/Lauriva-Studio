import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// Unified Lauriva Design System circular metric visualization.
///
/// Ensures exact parity between Forensics score rings and Humanizer transformation
/// gauges: identical diameter ratio, stroke width, easing curves, glowing aura,
/// and typography hierarchy.
class MetricRing extends StatefulWidget {
  final double value;
  final double size;
  final Color? color;
  final String? label;
  final String? subtitle;
  final Widget? topWidget;
  final Widget? badge;
  final bool animate;
  final double? strokeWidth;

  const MetricRing({
    super.key,
    required this.value,
    this.size = 140,
    this.color,
    this.label,
    this.subtitle,
    this.topWidget,
    this.badge,
    this.animate = true,
    this.strokeWidth,
  });

  @override
  State<MetricRing> createState() => _MetricRingState();
}

class _MetricRingState extends State<MetricRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animate ? const Duration(milliseconds: 1100) : Duration.zero,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(MetricRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _resolveColor(double val) {
    if (widget.color != null) return widget.color!;
    if (val < 25.0) return AppColors.success;
    if (val < 45.0) return AppColors.primary;
    if (val < 65.0) return AppColors.warning;
    if (val < 85.0) return const Color(0xFFF97316);
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final stroke = widget.strokeWidth ?? (widget.size * 0.082).clamp(5.0, 12.0);
    final resolvedColor = _resolveColor(widget.value);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final animatedVal = widget.value * _animation.value;
        final progress = (animatedVal / 100.0).clamp(0.0, 1.0);

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radial Track & Glow Painter
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _MetricRingPainter(
                  progress: progress,
                  color: resolvedColor,
                  trackColor: AppColors.surfaceSubtle,
                  strokeWidth: stroke,
                ),
              ),

              // Centered Metrics Content
              Padding(
                padding: EdgeInsets.only(top: widget.topWidget != null ? 4 : 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.topWidget != null) ...[
                      widget.topWidget!,
                      const SizedBox(height: 2),
                    ],

                    // Value readout with % symbol
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          animatedVal.toStringAsFixed(0),
                          style: GoogleFonts.outfit(
                            color: AppColors.textPrimary,
                            fontSize: widget.size * (widget.topWidget != null ? 0.25 : 0.28),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 1),
                        Text(
                          '%',
                          style: GoogleFonts.outfit(
                            color: resolvedColor,
                            fontSize: widget.size * (widget.topWidget != null ? 0.13 : 0.15),
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),

                    if (widget.label != null && widget.label!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.label!,
                        style: GoogleFonts.outfit(
                          fontSize: (widget.size * 0.08).clamp(9.0, 12.0),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.outfit(
                          fontSize: (widget.size * 0.075).clamp(8.5, 11.0),
                          fontWeight: FontWeight.w500,
                          color: resolvedColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    if (widget.badge != null) ...[
                      const SizedBox(height: 4),
                      widget.badge!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _MetricRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth * 2.2) / 2;

    const startAngle = -math.pi * 0.8;
    const totalSweep = math.pi * 1.6;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      totalSweep,
      false,
      trackPaint,
    );

    if (progress > 0) {
      final activeSweep = totalSweep * progress;

      // Glow aura
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        activeSweep,
        false,
        glowPaint,
      );

      // Core progress arc
      final activePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        activeSweep,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetricRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
