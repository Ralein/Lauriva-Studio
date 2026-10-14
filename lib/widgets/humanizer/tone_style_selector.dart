import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/theme_provider.dart';
import '../glass_card.dart';

/// Tone and style definitions for the Humanizer engine.
class HumanizerToneOption {
  final String id;
  final String label;
  final IconData icon;
  final String desc;

  const HumanizerToneOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.desc,
  });
}

class ToneStyleSelector extends StatelessWidget {
  static const List<HumanizerToneOption> tones = [
    HumanizerToneOption(
      id: 'professional',
      label: 'Professional',
      icon: LucideIcons.briefcase,
      desc: 'Polished, authoritative executive tone without formulaic clichés',
    ),
    HumanizerToneOption(
      id: 'academic',
      label: 'Academic',
      icon: LucideIcons.graduationCap,
      desc: 'Rigorous, formal syntax free of formulaic filler and clichés',
    ),
    HumanizerToneOption(
      id: 'casual',
      label: 'Casual',
      icon: LucideIcons.coffee,
      desc: 'Relaxed, natural everyday voice with conversational ease',
    ),
    HumanizerToneOption(
      id: 'conversational',
      label: 'Conversational',
      icon: LucideIcons.messageSquare,
      desc: 'Warm, spoken-word feel with human idiomatic flow',
    ),
    HumanizerToneOption(
      id: 'punchy',
      label: 'Direct',
      icon: LucideIcons.target,
      desc: 'Crisp, punchy sentence length with zero fluff',
    ),
    HumanizerToneOption(
      id: 'balanced',
      label: 'Natural',
      icon: LucideIcons.feather,
      desc: 'Authentic human cadence & varied sentence rhythm',
    ),
  ];

  static const List<Map<String, String>> styles = [
    {'id': 'balanced', 'label': 'Balanced'},
    {'id': 'concise', 'label': 'Concise'},
    {'id': 'detailed', 'label': 'Detailed'},
    {'id': 'technical', 'label': 'Technical'},
    {'id': 'simple', 'label': 'Simple'},
  ];

  final String selectedTone;
  final String selectedStyle;
  final ValueChanged<String> onToneSelected;
  final ValueChanged<String> onStyleSelected;
  final bool isLoading;
  final int? intensity;
  final ValueChanged<int>? onIntensityChanged;

  const ToneStyleSelector({
    super.key,
    required this.selectedTone,
    required this.selectedStyle,
    required this.onToneSelected,
    required this.onStyleSelected,
    this.isLoading = false,
    this.intensity,
    this.onIntensityChanged,
  });

  HumanizerToneOption get activeToneItem {
    return tones.firstWhere(
      (t) => t.id == selectedTone,
      orElse: () => tones.first,
    );
  }

  void showMiniSettingsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.glassBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        var currentTone = selectedTone;
        var currentStyle = selectedStyle;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              bottom: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textMuted.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(LucideIcons.sliders, size: 16, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Mini Settings',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x, size: 18),
                          color: AppColors.textMuted,
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'WRITING TONE',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tones.map((tone) {
                        final isSelected = currentTone == tone.id;
                        return InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setModalState(() {
                              currentTone = tone.id;
                            });
                            onToneSelected(tone.id);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.glassBorder,
                                width: isSelected ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tone.icon,
                                  size: 13,
                                  color: isSelected ? Colors.white : AppColors.accentText,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  tone.label,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'CONSTRAINTS & LENGTH',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: styles.map((style) {
                        final isSelected = currentStyle == style['id'];
                        return InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setModalState(() {
                              currentStyle = style['id']!;
                            });
                            onStyleSelected(style['id']!);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.glassBorder,
                                width: isSelected ? 1.4 : 1.0,
                              ),
                            ),
                            child: Text(
                              style['label']!,
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        onToneSelected(currentTone);
                        onStyleSelected(currentStyle);
                        Navigator.pop(modalCtx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Apply Settings',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.slidersHorizontal,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'WRITING PROFILE',
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    showMiniSettingsModal(context);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Icon(
                          activeToneItem.icon,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                activeToneItem.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: Text(
                                selectedStyle.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronDown,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  showMiniSettingsModal(context);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.settings2, size: 12, color: AppColors.primary),
                      const SizedBox(width: 5),
                      Text(
                        'Settings',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

      ],
    );
  }
}
