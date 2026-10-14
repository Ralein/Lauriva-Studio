import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Available transformation features in Lauriva
enum FeatureType {
  // Plagiarism/AI check leads the row by design: check -> rate -> fix is the
  // primary studio loop (see PlagiarismAuditCard's "Fix Plagiarism with
  // Lauriva" action, which chains straight into StudioProvider.humanize).
  plagiarismCheck(
    id: 'PlagiarismCheck',
    label: 'Check for AI',
    icon: LucideIcons.shield,
  ),
  humanize(
    id: 'Humanize',
    label: 'Humanize',
    icon: LucideIcons.fingerprint,
  ),
  translate(
    id: 'Translate',
    label: 'Translate',
    icon: LucideIcons.globe,
    isDropdown: true,
  ),
  grammar(
    id: 'Grammar',
    label: 'Fix Grammar',
    icon: LucideIcons.checkCheck,
  ),
  concise(
    id: 'Concise',
    label: 'Make Shorter',
    icon: LucideIcons.arrowRight,
  ),
  professional(
    id: 'Professional',
    label: 'Professional',
    icon: LucideIcons.briefcase,
  ),
  polite(
    id: 'Polite',
    label: 'Friendly',
    icon: LucideIcons.smile,
  ),
  rephrase(
    id: 'Rephrase',
    label: 'Rewrite',
    icon: LucideIcons.repeat,
  ),
  styleWitty(
    id: 'Style: Witty',
    label: 'Witty',
    icon: LucideIcons.lightbulb,
  ),
  styleAssertive(
    id: 'Style: Assertive',
    label: 'Confident',
    icon: LucideIcons.target,
  ),
  styleEmpathetic(
    id: 'Style: Empathetic',
    label: 'Warm',
    icon: LucideIcons.heart,
  ),
  styleDirect(
    id: 'Style: Direct',
    label: 'Direct',
    icon: LucideIcons.target,
  ),
  styleStorytelling(
    id: 'Style: Storytelling',
    label: 'Story',
    icon: LucideIcons.bookOpen,
  );

  final String id;
  final String label;
  final IconData icon;
  final bool isDropdown;

  const FeatureType({
    required this.id,
    required this.label,
    required this.icon,
    this.isDropdown = false,
  });

  /// Studio-only features: AI Check and Humanize live exclusively in their dedicated tabs.
  static List<FeatureType> get studioFeatures => FeatureType.values
      .where((f) => f != FeatureType.plagiarismCheck && f != FeatureType.humanize)
      .toList();

  static FeatureType? fromId(String id) {
    for (final feature in FeatureType.values) {
      if (feature.id == id) return feature;
    }
    return null;
  }
}

/// Target languages for Translation feature
enum TargetLanguage {
  english(name: 'English', nativeName: 'English', code: 'en-US'),
  tamil(name: 'Tamil', nativeName: 'தமிழ்', code: 'ta-IN'),
  spanish(name: 'Spanish', nativeName: 'Español', code: 'es-ES'),
  french(name: 'French', nativeName: 'Français', code: 'fr-FR'),
  german(name: 'German', nativeName: 'Deutsch', code: 'de-DE'),
  hindi(name: 'Hindi', nativeName: 'हिन्दी', code: 'hi-IN'),
  japanese(name: 'Japanese', nativeName: '日本語', code: 'ja-JP'),
  chinese(name: 'Chinese', nativeName: '中文', code: 'zh-CN'),
  arabic(name: 'Arabic', nativeName: 'العربية', code: 'ar-SA'),
  portuguese(name: 'Portuguese', nativeName: 'Português', code: 'pt-BR'),
  russian(name: 'Russian', nativeName: 'Русский', code: 'ru-RU'),
  italian(name: 'Italian', nativeName: 'Italiano', code: 'it-IT'),
  korean(name: 'Korean', nativeName: '한국어', code: 'ko-KR'),
  dutch(name: 'Dutch', nativeName: 'Nederlands', code: 'nl-NL'),
  turkish(name: 'Turkish', nativeName: 'Türkçe', code: 'tr-TR'),
  bengali(name: 'Bengali', nativeName: 'বাংলা', code: 'bn-IN'),
  vietnamese(name: 'Vietnamese', nativeName: 'Tiếng Việt', code: 'vi-VN'),
  indonesian(name: 'Indonesian', nativeName: 'Bahasa Indonesia', code: 'id-ID'),
  polish(name: 'Polish', nativeName: 'Polski', code: 'pl-PL'),
  telugu(name: 'Telugu', nativeName: 'తెలుగు', code: 'te-IN'),
  marathi(name: 'Marathi', nativeName: 'मराठी', code: 'mr-IN'),
  swedish(name: 'Swedish', nativeName: 'Svenska', code: 'sv-SE');

  final String name;
  final String nativeName;
  final String code;

  const TargetLanguage({
    required this.name,
    required this.nativeName,
    required this.code,
  });
}
