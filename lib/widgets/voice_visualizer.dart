import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/speech_provider.dart';
import '../providers/studio_provider.dart';

/// Full-width Voice Visualizer matching the reference design:
/// - Large central glowing mic button with concentric pulse rings
/// - Symmetric animated equalizer bars left & right of the mic
/// - "Listening..." status header + bottom cancel bar
class VoiceVisualizerWidget extends StatefulWidget {
  const VoiceVisualizerWidget({super.key});

  @override
  State<VoiceVisualizerWidget> createState() => _VoiceVisualizerWidgetState();
}

class _VoiceVisualizerWidgetState extends State<VoiceVisualizerWidget>
    with TickerProviderStateMixin {
  // Drives the equalizer bar animation
  late final AnimationController _waveController;
  // Drives the concentric ring pulse
  late final AnimationController _ring1Controller;
  late final AnimationController _ring2Controller;
  late final AnimationController _ring3Controller;
  // Drives the blinking dot
  late final AnimationController _blinkController;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _ring1Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _ring2Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _ring3Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  void _startAnimations() {
    if (!_waveController.isAnimating) _waveController.repeat();
    if (!_ring1Controller.isAnimating) _ring1Controller.repeat();
    if (!_ring2Controller.isAnimating) {
      _ring2Controller.repeat();
      _ring2Controller.forward(from: 0.22);
    }
    if (!_ring3Controller.isAnimating) {
      _ring3Controller.repeat();
      _ring3Controller.forward(from: 0.44);
    }
    if (!_blinkController.isAnimating) _blinkController.repeat(reverse: true);
  }

  void _stopAnimations() {
    _waveController.stop();
    _ring1Controller.stop();
    _ring2Controller.stop();
    _ring3Controller.stop();
    _blinkController.stop();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _ring1Controller.dispose();
    _ring2Controller.dispose();
    _ring3Controller.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording =
        context.select<SpeechProvider, bool>((p) => p.isRecording);

    if (!isRecording) {
      _stopAnimations();
      return const SizedBox.shrink();
    }

    _startAnimations();

    final speech = context.read<SpeechProvider>();
    final studio = context.read<StudioProvider>();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isDark ? 0.30 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Status header: "Listening..." + timer ─────────────────────
            _buildStatusHeader(speech),

            const SizedBox(height: 18),

            // ── Main visualizer: bars | mic | bars ────────────────────────
            SizedBox(
              height: 120,
              child: ValueListenableBuilder<double>(
                valueListenable: speech.soundLevelNotifier,
                builder: (context, soundLevel, _) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left equalizer bars
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, _) => CustomPaint(
                            painter: _EqBarsPainter(
                              progress: _waveController.value,
                              soundLevel: soundLevel,
                              mirrored: true, // bars grow from right edge
                            ),
                          ),
                        ),
                      ),

                      // Central glowing mic button
                      _buildMicButton(studio),

                      // Right equalizer bars
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, _) => CustomPaint(
                            painter: _EqBarsPainter(
                              progress: _waveController.value,
                              soundLevel: soundLevel,
                              mirrored: false, // bars grow from left edge
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // ── Bottom action bar: dot + "Listening..." + Cancel ──────────
            _buildBottomBar(studio),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }

  // ── Sub-builders ─────────────────────────────────────────────────────────

  Widget _buildStatusHeader(SpeechProvider speech) {
    return Row(
      children: [
        // Waveform icon (mini)
        Icon(
          LucideIcons.audioLines,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Listening...',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            Text(
              'Speak now',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Timer
        ValueListenableBuilder<int>(
          valueListenable: speech.recordingSecondsNotifier,
          builder: (context, seconds, _) {
            final m = (seconds ~/ 60).toString().padLeft(2, '0');
            final s = (seconds % 60).toString().padLeft(2, '0');
            return Text(
              '$m:$s',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMicButton(StudioProvider studio) {
    final Color mintColor = AppColors.primary;

    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring 3 — outermost, slowest
          AnimatedBuilder(
            animation: _ring3Controller,
            builder: (context, _) {
              final v = _ring3Controller.value;
              return Container(
                width: 90 * (0.8 + v * 0.2),
                height: 90 * (0.8 + v * 0.2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: mintColor.withValues(alpha: (1 - v) * 0.18),
                    width: 1.5,
                  ),
                ),
              );
            },
          ),

          // Ring 2
          AnimatedBuilder(
            animation: _ring2Controller,
            builder: (context, _) {
              final v = _ring2Controller.value;
              return Container(
                width: 72 * (0.85 + v * 0.15),
                height: 72 * (0.85 + v * 0.15),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: mintColor.withValues(alpha: (1 - v) * 0.28),
                    width: 1.5,
                  ),
                ),
              );
            },
          ),

          // Ring 1 — closest to button
          AnimatedBuilder(
            animation: _ring1Controller,
            builder: (context, _) {
              final v = _ring1Controller.value;
              return Container(
                width: 56 * (0.9 + v * 0.1),
                height: 56 * (0.9 + v * 0.1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: mintColor.withValues(alpha: (1 - v) * 0.45),
                    width: 2.0,
                  ),
                ),
              );
            },
          ),

          // Central button with gradient + glow
          Semantics(
            button: true,
            label: 'Stop voice recording',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                studio.toggleRecording();
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      mintColor.withValues(alpha: 0.9),
                      AppColors.paletteEmerald,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: mintColor.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: mintColor.withValues(alpha: 0.20),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.mic,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(StudioProvider studio) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.glassBorder,
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Blinking dot
          AnimatedBuilder(
            animation: _blinkController,
            builder: (context, _) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary
                    .withValues(alpha: 0.5 + _blinkController.value * 0.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Listening...',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          // Cancel / done button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              studio.toggleRecording();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.x, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    'Cancel',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Equalizer Bar Painter ────────────────────────────────────────────────────

/// Renders animated equalizer bars.
/// [mirrored] = true draws bars from right→left (for the left side of the mic).
class _EqBarsPainter extends CustomPainter {
  final double progress;
  final double soundLevel;
  final bool mirrored;

  static const int _barCount = 10;

  _EqBarsPainter({
    required this.progress,
    required this.soundLevel,
    required this.mirrored,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double normalizedLevel = soundLevel > 0
        ? math.min(1.0, math.max(0.25, soundLevel / 10.0))
        : 0.5;

    final double totalWidth = size.width;
    final double barWidth = 3.0;
    // Space bars evenly across the available width
    final double slot = totalWidth / _barCount;
    final double centerY = size.height / 2;

    for (int i = 0; i < _barCount; i++) {
      // For mirrored (left side), bar index 0 is closest to edge, index N-1 nearest mic
      final int barIndex = mirrored ? (_barCount - 1 - i) : i;

      // x position — evenly distributed
      final double rawX = i * slot + slot / 2;
      final double x = mirrored ? (totalWidth - rawX) : rawX;

      // Envelope: bars taper as they move away from center (near mic = taller)
      // normalizedPos: 0 = far from mic, 1 = nearest to mic
      final double normalizedPos = barIndex / (_barCount - 1.0);
      final double envelope = 0.25 + 0.75 * normalizedPos;

      // Animated wave — different phase per bar
      final double phase = progress * 2 * math.pi + barIndex * 0.55;
      final double wave = (math.sin(phase) * 0.5 + math.cos(phase * 1.7) * 0.5).abs();

      final double minH = 4.0;
      final double maxH = size.height * 0.85;
      final double height = minH + (maxH - minH) * envelope * (0.3 + 0.7 * wave) * (0.5 + 0.5 * normalizedLevel);

      // Opacity: bars further from mic are more translucent
      final double opacity = 0.3 + 0.7 * normalizedPos;

      final Paint paint = Paint()
        ..color = AppColors.primary.withValues(alpha: opacity)
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqBarsPainter old) =>
      old.progress != progress ||
      old.soundLevel != soundLevel ||
      old.mirrored != mirrored;
}
