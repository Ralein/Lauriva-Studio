import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/toast_notification.dart';
import '../providers/speech_provider.dart';
import '../providers/toast_provider.dart';

/// Shows the consistent Voice Mini Settings bottom sheet modal.
void showVoiceMiniSettings(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.glassBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalCtx) => const VoiceMiniSettingsModal(),
  );
}

class VoiceMiniSettingsModal extends StatefulWidget {
  const VoiceMiniSettingsModal({super.key});

  @override
  State<VoiceMiniSettingsModal> createState() => _VoiceMiniSettingsModalState();
}

class _VoiceMiniSettingsModalState extends State<VoiceMiniSettingsModal> {
  String _searchQuery = '';
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final speech = context.watch<SpeechProvider>();
    final toast = context.read<ToastProvider>();
    final voices = speech.availableVoices;
    final selectedVoice = speech.selectedVoice;
    final currentSpeed = speech.speechSpeed;

    // Filter voices by search query
    final filtered = _searchQuery.trim().isEmpty
        ? voices
        : voices.where((v) {
            final name = (v['name'] ?? '').toLowerCase();
            final locale = (v['locale'] ?? '').toLowerCase();
            final query = _searchQuery.toLowerCase();
            return name.contains(query) || locale.contains(query);
          }).toList();

    // Group by locale prefix
    final Map<String, List<Map<String, String>>> grouped = {};
    for (final v in filtered) {
      final prefix = (v['locale'] ?? '').split('-').first.toUpperCase();
      grouped.putIfAbsent(prefix, () => []).add(v);
    }

    final size = MediaQuery.of(context).size;

    return SafeArea(
      bottom: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
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

              // Header: Icon + Title + Close Action
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
                        child: Icon(
                          LucideIcons.sliders,
                          size: 16,
                          color: AppColors.primary,
                        ),
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Text(
                          'VOICE',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    color: AppColors.textMuted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scrollable body
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── SECTION 1: READING SPEED ────────────────────────────
                      Text(
                        'READING SPEED',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildSpeedOption('slow', '0.7x Slow', currentSpeed, speech),
                          const SizedBox(width: 6),
                          _buildSpeedOption('normal', '1.0x Normal', currentSpeed, speech),
                          const SizedBox(width: 6),
                          _buildSpeedOption('fast', '1.4x Fast', currentSpeed, speech),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── SECTION 2: TTS VOICE ────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TTS VOICE',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: AppColors.textMuted,
                            ),
                          ),
                          InkWell(
                            onTap: _isRefreshing
                                ? null
                                : () async {
                                    HapticFeedback.lightImpact();
                                    setState(() => _isRefreshing = true);
                                    await speech.refreshVoices();
                                    if (mounted) setState(() => _isRefreshing = false);
                                    toast.showToast('Voices refreshed', ToastType.info);
                                  },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isRefreshing)
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  else
                                    Icon(
                                      LucideIcons.refreshCw,
                                      size: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Refresh',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Search bar
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search voices by language or name…',
                            hintStyle: GoogleFonts.outfit(
                              fontSize: 12.5,
                              color: AppColors.textMuted,
                            ),
                            prefixIcon: Icon(
                              LucideIcons.search,
                              size: 15,
                              color: AppColors.textMuted,
                            ),
                            prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            border: InputBorder.none,
                          ),
                          style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Auto (Best) Option Card
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          speech.selectVoice(null);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedVoice == null ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedVoice == null ? AppColors.primary : AppColors.glassBorder,
                              width: selectedVoice == null ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selectedVoice == null ? LucideIcons.circleCheck : LucideIcons.circle,
                                size: 15,
                                color: selectedVoice == null ? AppColors.primary : AppColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Auto (Best Neural Voice)',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: selectedVoice == null ? FontWeight.w700 : FontWeight.w600,
                                        color: selectedVoice == null ? AppColors.accentText : AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Automatically chooses the clearest device engine',
                                      style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Voice List Container
                      Container(
                        constraints: const BoxConstraints(maxHeight: 240),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!speech.voicesLoaded)
                                  Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  )
                                else if (filtered.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Center(
                                      child: Text(
                                        voices.isEmpty
                                            ? 'No voices available on this device.'
                                            : 'No voices matching "$_searchQuery".',
                                        style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMuted),
                                      ),
                                    ),
                                  )
                                else ...[
                                  for (final entry in grouped.entries) ...[
                                    Container(
                                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                      color: AppColors.glassInputBg,
                                      child: Text(
                                        entry.key,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textMuted,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                    for (final voice in entry.value) ...[
                                      _buildVoiceItem(
                                        voice: voice,
                                        isSelected: selectedVoice != null && selectedVoice['name'] == voice['name'],
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          speech.selectVoice(voice);
                                        },
                                      ),
                                      if (voice != entry.value.last)
                                        Divider(
                                          height: 1,
                                          color: AppColors.glassBorder,
                                          indent: 12,
                                          endIndent: 12,
                                        ),
                                    ],
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Apply Button
              ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
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
      ),
    );
  }

  Widget _buildSpeedOption(
    String speedId,
    String label,
    String currentSpeed,
    SpeechProvider speech,
  ) {
    final isSelected = currentSpeed == speedId;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          speech.setSpeed(speedId);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.glassBorder,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceItem({
    required Map<String, String> voice,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final name = _cleanVoiceName(voice['name'] ?? '');
    final locale = voice['locale'] ?? '';
    final quality = voice['quality'] ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(
              isSelected ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 14,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.accentText : AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (locale.isNotEmpty)
                    Text(
                      locale,
                      style: GoogleFonts.outfit(fontSize: 10.5, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            if (quality.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  quality.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _cleanVoiceName(String raw) {
    if (raw.isEmpty) return raw;
    return raw.replaceAll('-local', '').replaceAll('-network', '');
  }
}
