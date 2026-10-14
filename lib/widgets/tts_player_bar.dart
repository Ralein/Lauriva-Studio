import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/tts_highlight.dart';
import '../providers/speech_provider.dart';
import '../providers/studio_provider.dart';
import '../services/tts_service.dart';
import 'voice_mini_settings.dart';

class TtsPlayerBar extends StatefulWidget {
  final String? textToSpeak;

  const TtsPlayerBar({super.key, this.textToSpeak});

  @override
  State<TtsPlayerBar> createState() => _TtsPlayerBarState();
}

class _TtsPlayerBarState extends State<TtsPlayerBar> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speech = context.watch<SpeechProvider>();
    final studio = context.watch<StudioProvider>();
    final isPlaying = speech.speechState == TtsState.playing;
    final isPaused = speech.speechState == TtsState.paused;
    final isIdle = speech.speechState == TtsState.idle;

    // Use custom text if provided (e.g. on Humanize screen), otherwise fall back to studio output
    final activeText = widget.textToSpeak ?? (
      (studio.activeFeatureId != 'PlagiarismCheck') ? studio.outputText : ''
    );
    final hasOutput = activeText.trim().isNotEmpty;

    if (isPlaying) {
      if (!_animController.isAnimating) {
        _animController.repeat(reverse: true);
      }
    } else {
      if (_animController.isAnimating) {
        _animController.stop();
        _animController.reset();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.paletteSlateBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Play / Pause / Read Aloud Volume Button
            IconButton(
              onPressed: hasOutput
                  ? () {
                      HapticFeedback.lightImpact();
                      if (isPlaying) {
                        if (widget.textToSpeak != null) {
                          speech.pause();
                        } else {
                          studio.pauseSpeech();
                        }
                      } else if (isPaused) {
                        // If text changed while paused, start new text from start; otherwise resume from where it left
                        if (widget.textToSpeak != null) {
                          if (speech.fullTextBeingRead.isNotEmpty &&
                              speech.fullTextBeingRead != widget.textToSpeak) {
                            speech.speak(widget.textToSpeak!, targetLanguage: studio.selectedLanguage);
                          } else {
                            speech.resume();
                          }
                        } else {
                          if (speech.fullTextBeingRead.isNotEmpty &&
                              speech.fullTextBeingRead != studio.outputText) {
                            studio.speakSpeech();
                          } else {
                            studio.resumeSpeech();
                          }
                        }
                      } else {
                        // Stopped / Idle: start reading cleanly from the beginning
                        if (widget.textToSpeak != null) {
                          speech.speak(widget.textToSpeak!, targetLanguage: studio.selectedLanguage);
                        } else {
                          studio.speakSpeech();
                        }
                      }
                    }
                  : null,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(
                isPlaying
                    ? LucideIcons.pause
                    : (isPaused ? LucideIcons.play : LucideIcons.volume2),
                size: 20,
                color: hasOutput ? AppColors.accentText : AppColors.textMuted,
              ),
              tooltip: isPlaying ? 'Pause' : (isPaused ? 'Resume' : 'Read Aloud'),
            ),

            // Stop Playback Button (shown when active or paused)
            if (!isIdle) ...[
              const SizedBox(width: 2),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (widget.textToSpeak != null) {
                    speech.stop();
                  } else {
                    studio.stopSpeech();
                  }
                },
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(
                  LucideIcons.square,
                  size: 16,
                  color: AppColors.error,
                ),
                tooltip: 'Stop (Reset to Start)',
              ),
            ],

            // Voice Mini Settings Button (hidden during active playback/pause)
            if (isIdle) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  showVoiceMiniSettings(context);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.glassInputBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.slidersHorizontal, size: 12, color: AppColors.accentText),
                      const SizedBox(width: 4),
                      Text(
                        'Voice',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(width: 4),

            // Speed selector pills (0.7x, 1x, 1.4x)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.glassInputBg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSpeedButton('slow', '0.7x', speech, studio),
                  _buildSpeedButton('normal', '1x', speech, studio),
                  _buildSpeedButton('fast', '1.4x', speech, studio),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Equalizer wave
            _buildEqualizerWave(isPlaying),

            // Real-time voice reading progress indicator
            ValueListenableBuilder<TtsHighlight?>(
              valueListenable: speech.highlightNotifier,
              builder: (context, highlight, _) {
                if (highlight == null || isIdle) return const SizedBox.shrink();
                final percent = (highlight.progress * 100).clamp(0.0, 100.0).toInt();
                return Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.32),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isPlaying ? AppColors.primary : AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$percent%',
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedButton(String speedId, String label, SpeechProvider speech, StudioProvider studio) {
    final isActive = speech.speechSpeed == speedId;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        if (widget.textToSpeak != null) {
          speech.setSpeed(speedId, replayText: widget.textToSpeak!, targetLanguage: studio.selectedLanguage);
        } else {
          studio.setSpeechSpeed(speedId);
        }
      },
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.paletteCerulean.withValues(alpha: 0.28)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: isActive
              ? Border.all(color: AppColors.paletteCerulean.withValues(alpha: 0.6), width: 1.0)
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isActive ? AppColors.accentText : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildEqualizerWave(bool isPlaying) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final val = _animController.value;

        // 6 oscillating harmonic bar heights with increased dynamic range
        final h1 = isPlaying ? 4.0 + 10.0 * ((val * 1.3) % 1.0) : 4.0;
        final h2 = isPlaying ? 4.0 + 14.0 * (((1.0 - val) * 1.7) % 1.0) : 4.0;
        final h3 = isPlaying ? 4.0 + 18.0 * ((val * 1.9) % 1.0) : 4.0;
        final h4 = isPlaying ? 4.0 + 15.0 * (((1.0 - val) * 1.4) % 1.0) : 4.0;
        final h5 = isPlaying ? 4.0 + 11.0 * ((val * 2.1) % 1.0) : 4.0;
        final h6 = isPlaying ? 4.0 + 7.0 * (((1.0 - val) * 1.1) % 1.0) : 4.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: BoxDecoration(
            color: isPlaying ? AppColors.primary.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildWaveBar(h1, AppColors.paletteTeal),
              const SizedBox(width: 2.0),
              _buildWaveBar(h2, AppColors.paletteSage),
              const SizedBox(width: 2.0),
              _buildWaveBar(h3, AppColors.palettePistachio),
              const SizedBox(width: 2.0),
              _buildWaveBar(h4, AppColors.primary),
              const SizedBox(width: 2.0),
              _buildWaveBar(h5, AppColors.paletteSage),
              const SizedBox(width: 2.0),
              _buildWaveBar(h6, AppColors.paletteTeal),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaveBar(double height, Color color) {
    return Container(
      width: 2.4,
      height: height.clamp(4.0, 18.0),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2.0),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 3,
          ),
        ],
      ),
    );
  }
}
