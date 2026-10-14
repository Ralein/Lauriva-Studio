import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Lauriva brand botanical dual-leaf sprout logo.
/// Faithfully reproduces the vector SVG brand mark with two-tone shading,
/// organic leaf curves, and subtle central vein structure.
class LaurivaLogo extends StatelessWidget {
  final double size;
  final bool outlineOnly;
  final Color? outlineColor;
  final double? strokeWidth;

  const LaurivaLogo({
    super.key,
    this.size = 40,
    this.outlineOnly = false,
    this.outlineColor,
    this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SproutPainter(
          isDark: AppColors.isDark,
          outlineOnly: outlineOnly,
          outlineColor: outlineColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SproutPainter extends CustomPainter {
  final bool isDark;
  final bool outlineOnly;
  final Color? outlineColor;
  final double? strokeWidth;

  const _SproutPainter({
    required this.isDark,
    this.outlineOnly = false,
    this.outlineColor,
    this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sx = w / 512.0;
    final sy = h / 512.0;

    if (outlineOnly) {
      final color = outlineColor ?? AppColors.textMuted;
      final effectiveStrokeWidth =
          strokeWidth ?? (w <= 20 ? 1.25 : (w * 0.08).clamp(1.4, 3.5));

      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = effectiveStrokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // ── 1. Stem Outline ──────────────────────────────────────────────────
      final stemPath = Path();
      stemPath.moveTo(238 * sx, 382 * sy);
      stemPath.cubicTo(
        236 * sx,
        405 * sy,
        230 * sx,
        425 * sy,
        222 * sx,
        445 * sy,
      );
      stemPath.cubicTo(
        228 * sx,
        448 * sy,
        237 * sx,
        448 * sy,
        243 * sx,
        446 * sy,
      );
      stemPath.cubicTo(
        248 * sx,
        428 * sy,
        252 * sx,
        406 * sy,
        252 * sx,
        382 * sy,
      );
      canvas.drawPath(stemPath, strokePaint);

      // ── 2. Left Leaf Contour ─────────────────────────────────────────────
      final leftLeaf = Path();
      leftLeaf.moveTo(238 * sx, 385 * sy);
      leftLeaf.cubicTo(
        175 * sx,
        385 * sy,
        75 * sx,
        320 * sy,
        48 * sx,
        240 * sy,
      );
      leftLeaf.cubicTo(30 * sx, 190 * sy, 45 * sx, 135 * sy, 75 * sx, 105 * sy);
      leftLeaf.cubicTo(
        115 * sx,
        105 * sy,
        175 * sx,
        140 * sy,
        218 * sx,
        215 * sy,
      );
      leftLeaf.cubicTo(
        238 * sx,
        250 * sy,
        244 * sx,
        310 * sy,
        238 * sx,
        385 * sy,
      );
      leftLeaf.close();
      canvas.drawPath(leftLeaf, strokePaint);

      // ── 3. Left Leaf Central Vein ────────────────────────────────────────
      final leftVein = Path();
      leftVein.moveTo(75 * sx, 105 * sy);
      leftVein.cubicTo(
        115 * sx,
        155 * sy,
        175 * sx,
        250 * sy,
        238 * sx,
        385 * sy,
      );
      canvas.drawPath(leftVein, strokePaint);

      // ── 4. Right Leaf Contour ────────────────────────────────────────────
      final rightLeaf = Path();
      rightLeaf.moveTo(245 * sx, 385 * sy);
      rightLeaf.cubicTo(
        244 * sx,
        300 * sy,
        248 * sx,
        200 * sy,
        280 * sx,
        115 * sy,
      );
      rightLeaf.cubicTo(
        292 * sx,
        85 * sy,
        305 * sx,
        60 * sy,
        320 * sx,
        45 * sy,
      );
      rightLeaf.cubicTo(
        365 * sx,
        70 * sy,
        415 * sx,
        125 * sy,
        435 * sx,
        190 * sy,
      );
      rightLeaf.cubicTo(
        455 * sx,
        255 * sy,
        420 * sx,
        330 * sy,
        370 * sx,
        365 * sy,
      );
      rightLeaf.cubicTo(
        325 * sx,
        395 * sy,
        275 * sx,
        392 * sy,
        245 * sx,
        385 * sy,
      );
      rightLeaf.close();
      canvas.drawPath(rightLeaf, strokePaint);

      // ── 5. Right Leaf Central Vein ───────────────────────────────────────
      final rightVein = Path();
      rightVein.moveTo(320 * sx, 45 * sy);
      rightVein.cubicTo(
        310 * sx,
        120 * sy,
        290 * sx,
        235 * sy,
        245 * sx,
        385 * sy,
      );
      canvas.drawPath(rightVein, strokePaint);

      return;
    }

    final Rect bounds = Rect.fromLTWH(0, 0, w, h);

    // ── Gradients ──────────────────────────────────────────────────────────
    final leftOuterGrad = LinearGradient(
      colors: isDark
          ? const [Color(0xFF2E8B84), Color(0xFF4A9B8D), Color(0xFF7CA982)]
          : const [Color(0xFF1E5E57), Color(0xFF2E8B84), Color(0xFF4A9B8D)],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).createShader(bounds);

    final leftInnerGrad = LinearGradient(
      colors: isDark
          ? const [Color(0xFF1E5E57), Color(0xFF2E8B84), Color(0xFF4A9B8D)]
          : const [Color(0xFF14433E), Color(0xFF1E5E57), Color(0xFF2E8B84)],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).createShader(bounds);

    final rightInnerGrad = LinearGradient(
      colors: isDark
          ? const [Color(0xFF1E5E57), Color(0xFF2E8B84), Color(0xFF4A9B8D)]
          : const [Color(0xFF14433E), Color(0xFF1E5E57), Color(0xFF2E8B84)],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).createShader(bounds);

    final rightOuterGrad = LinearGradient(
      colors: isDark
          ? const [Color(0xFF2E8B84), Color(0xFF7CA982), Color(0xFF93C572)]
          : const [Color(0xFF1E5E57), Color(0xFF38927E), Color(0xFF7CA982)],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).createShader(bounds);

    final stemGrad = LinearGradient(
      colors: isDark
          ? const [Color(0xFF2E8B84), Color(0xFF1E5E57)]
          : const [Color(0xFF1E5E57), Color(0xFF14433E)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(bounds);

    // ── 1. Stem ────────────────────────────────────────────────────────────
    final stemPath = Path();
    stemPath.moveTo(238 * sx, 382 * sy);
    stemPath.cubicTo(
      236 * sx,
      405 * sy,
      230 * sx,
      425 * sy,
      222 * sx,
      445 * sy,
    );
    stemPath.cubicTo(
      228 * sx,
      448 * sy,
      237 * sx,
      448 * sy,
      243 * sx,
      446 * sy,
    );
    stemPath.cubicTo(
      248 * sx,
      428 * sy,
      252 * sx,
      406 * sy,
      252 * sx,
      382 * sy,
    );
    stemPath.close();
    canvas.drawPath(
      stemPath,
      Paint()
        ..shader = stemGrad
        ..style = PaintingStyle.fill,
    );

    // ── 2. Left Leaf Outer Half ────────────────────────────────────────────
    final leftOuter = Path();
    leftOuter.moveTo(238 * sx, 385 * sy);
    leftOuter.cubicTo(175 * sx, 385 * sy, 75 * sx, 320 * sy, 48 * sx, 240 * sy);
    leftOuter.cubicTo(30 * sx, 190 * sy, 45 * sx, 135 * sy, 75 * sx, 105 * sy);
    leftOuter.cubicTo(
      115 * sx,
      155 * sy,
      175 * sx,
      250 * sy,
      238 * sx,
      385 * sy,
    );
    leftOuter.close();
    canvas.drawPath(
      leftOuter,
      Paint()
        ..shader = leftOuterGrad
        ..style = PaintingStyle.fill,
    );

    // ── 3. Left Leaf Inner Half ────────────────────────────────────────────
    final leftInner = Path();
    leftInner.moveTo(75 * sx, 105 * sy);
    leftInner.cubicTo(
      115 * sx,
      105 * sy,
      175 * sx,
      140 * sy,
      218 * sx,
      215 * sy,
    );
    leftInner.cubicTo(
      238 * sx,
      250 * sy,
      244 * sx,
      310 * sy,
      238 * sx,
      385 * sy,
    );
    leftInner.cubicTo(
      175 * sx,
      250 * sy,
      115 * sx,
      155 * sy,
      75 * sx,
      105 * sy,
    );
    leftInner.close();
    canvas.drawPath(
      leftInner,
      Paint()
        ..shader = leftInnerGrad
        ..style = PaintingStyle.fill,
    );

    // ── 4. Right Leaf Inner Half ───────────────────────────────────────────
    final rightInner = Path();
    rightInner.moveTo(245 * sx, 385 * sy);
    rightInner.cubicTo(
      244 * sx,
      300 * sy,
      248 * sx,
      200 * sy,
      280 * sx,
      115 * sy,
    );
    rightInner.cubicTo(292 * sx, 85 * sy, 305 * sx, 60 * sy, 320 * sx, 45 * sy);
    rightInner.cubicTo(
      310 * sx,
      120 * sy,
      290 * sx,
      235 * sy,
      245 * sx,
      385 * sy,
    );
    rightInner.close();
    canvas.drawPath(
      rightInner,
      Paint()
        ..shader = rightInnerGrad
        ..style = PaintingStyle.fill,
    );

    // ── 5. Right Leaf Outer Half ───────────────────────────────────────────
    final rightOuter = Path();
    rightOuter.moveTo(320 * sx, 45 * sy);
    rightOuter.cubicTo(
      365 * sx,
      70 * sy,
      415 * sx,
      125 * sy,
      435 * sx,
      190 * sy,
    );
    rightOuter.cubicTo(
      455 * sx,
      255 * sy,
      420 * sx,
      330 * sy,
      370 * sx,
      365 * sy,
    );
    rightOuter.cubicTo(
      325 * sx,
      395 * sy,
      275 * sx,
      392 * sy,
      245 * sx,
      385 * sy,
    );
    rightOuter.cubicTo(
      290 * sx,
      235 * sy,
      310 * sx,
      120 * sy,
      320 * sx,
      45 * sy,
    );
    rightOuter.close();
    canvas.drawPath(
      rightOuter,
      Paint()
        ..shader = rightOuterGrad
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_SproutPainter old) =>
      old.isDark != isDark ||
      old.outlineOnly != outlineOnly ||
      old.outlineColor != outlineColor ||
      old.strokeWidth != strokeWidth;
}
