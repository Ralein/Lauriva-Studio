import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'lauriva_logo.dart';

/// Luxury micro-loading widget featuring the Lauriva botanical sprout logo
/// enclosed inside a glowing, smoothly spinning orbital ring.
/// Designed specifically for primary CTAs, action chips, and compact buttons.
typedef ButtonClarivaSpinner = ButtonLaurivaSpinner;

class ButtonLaurivaSpinner extends StatefulWidget {
  final double size;
  final Color? ringColor;

  const ButtonLaurivaSpinner({super.key, this.size = 20, this.ringColor});

  @override
  State<ButtonLaurivaSpinner> createState() => _ButtonLaurivaSpinnerState();
}

class _ButtonLaurivaSpinnerState extends State<ButtonLaurivaSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeRingColor =
        widget.ringColor ??
        (AppColors.isDark ? const Color(0xFF00E5CC) : AppColors.primary);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Orbital Spinning Arc
          RotationTransition(
            turns: _rotationController,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _SpinnerRingPainter(
                ringColor: activeRingColor,
                strokeWidth: (widget.size * 0.11).clamp(1.8, 2.6),
              ),
            ),
          ),
          // Botanical Sprout Logo in center
          LaurivaLogo(size: widget.size * 0.58),
        ],
      ),
    );
  }
}

class _SpinnerRingPainter extends CustomPainter {
  final Color ringColor;
  final double strokeWidth;

  const _SpinnerRingPainter({
    required this.ringColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Subtle background track
    final trackPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Glowing active sweep arc
    final sweepPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.35,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerRingPainter oldDelegate) {
    return oldDelegate.ringColor != ringColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
