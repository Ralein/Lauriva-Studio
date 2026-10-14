import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';

/// Shows the minimalist dark glassmorphic Legal, Privacy, and AI Policy modal sheet.
Future<void> showLegalPolicySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const LegalPolicySheet(),
  );
}

/// Minimalist, dark glassmorphic legal and policies viewer compliant with App Store & Play Store
/// AI disclosure guidelines.
class LegalPolicySheet extends StatefulWidget {
  const LegalPolicySheet({super.key});

  static Future<void> show(BuildContext context) => showLegalPolicySheet(context);

  @override
  State<LegalPolicySheet> createState() => _LegalPolicySheetState();
}

class _LegalPolicySheetState extends State<LegalPolicySheet> {
  int _selectedTab = 0; // 0: AI Disclaimer, 1: Privacy, 2: Terms & Ethics

  final List<String> _tabs = [
    'AI Disclaimer',
    'Privacy Policy',
    'Terms & Ethics',
  ];

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.padding.bottom;
    final maxHeight = mediaQuery.size.height * 0.88;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: AppColors.glassBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Handle Pill ─────────────────────────────────────────────
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Header Bar ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.paletteTeal.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.paletteTeal.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            LucideIcons.shieldCheck,
                            size: 16,
                            color: AppColors.paletteTeal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Legal & Policies',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'AI Disclaimers · Privacy · Fair Use',
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      color: AppColors.textMuted,
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Tab Bar Navigation ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.glassBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    children: List.generate(_tabs.length, (index) {
                      final isSelected = _selectedTab == index;
                      return Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedTab = index);
                          },
                          borderRadius: BorderRadius.circular(9),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              _tabs[index],
                              style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Tab Content Body ────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 36 + bottomInset),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _buildSelectedTabContent(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildAiDisclaimerTab();
      case 1:
        return _buildPrivacyPolicyTab();
      case 2:
      default:
        return _buildTermsTab();
    }
  }

  // ── 1. AI Accuracy & Limitations Tab ──────────────────────────────────────
  Widget _buildAiDisclaimerTab() {
    return Column(
      key: const ValueKey('ai_disclaimer_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Highlight Box: "AI Can Make Mistakes"
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.30),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.alertTriangle,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Can Make Mistakes',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lauriva uses probabilistic language models for text transformation and forensic analysis. Generative AI may produce inaccurate, incomplete, or biased information. Always independently verify critical facts, figures, and technical citations.',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textPrimary.withValues(alpha: 0.90),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _buildSectionCard(
          title: 'Core AI Limitations',
          icon: LucideIcons.cpu,
          iconColor: AppColors.primary,
          items: [
            _PolicyItem(
              title: 'No Guarantees of Absolute Accuracy',
              body:
                  'Writing enhancements, translations, tone adjustments, and summaries are generated automatically. Nuance, domain-specific terminology, and original context may occasionally be misinterpreted.',
            ),
            _PolicyItem(
              title: 'Forensic & Plagiarism Scoring Limits',
              body:
                  'AI detection and originality scores represent statistical heuristics based on burstiness, perplexity, and known corpus patterns. They are evidentiary guides, not definitive legal or academic proofs.',
            ),
            _PolicyItem(
              title: 'User Editorial Responsibility',
              body:
                  'You remain solely responsible for reviewing, confirming, and validating any output generated with Lauriva prior to publication, distribution, or academic submission.',
            ),
            _PolicyItem(
              title: 'Not Professional Advice',
              body:
                  'Lauriva is not a substitute for qualified human editors, certified legal counsel, financial advisors, or medical practitioners.',
            ),
          ],
        ),
      ],
    );
  }

  // ── 2. Privacy Policy Tab ────────────────────────────────────────────────
  Widget _buildPrivacyPolicyTab() {
    return Column(
      key: const ValueKey('privacy_policy_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Highlight Box: "Zero-Retention Architecture"
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.paletteTeal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.paletteTeal.withValues(alpha: 0.30),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.shieldCheck,
                size: 18,
                color: AppColors.paletteTeal,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zero-Retention & Privacy by Design',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.paletteTeal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lauriva operates without user accounts or tracking databases. Your drafts, keys, and session data stay entirely on your device and are never sold or used to train third-party models.',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textPrimary.withValues(alpha: 0.90),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _buildSectionCard(
          title: 'Data Handling Guarantees',
          icon: LucideIcons.lock,
          iconColor: AppColors.paletteTeal,
          items: [
            _PolicyItem(
              title: 'Direct Client-to-Provider Routing',
              body:
                  'When you perform AI tasks using your API keys (e.g. Groq, Gemini, Cerebras), requests connect directly from your device to the official provider endpoint. No intermediary server stores your text.',
            ),
            _PolicyItem(
              title: 'Encrypted On-Device Storage',
              body:
                  'Your API keys and preferences are stored exclusively on your device in secure local storage. Uninstalling or clearing app data wipes them permanently.',
            ),
            _PolicyItem(
              title: 'Keyless & Offline Forensic Audits',
              body:
                  'Stylometric and neural AI detection modules run directly on-device using local inference models whenever supported, eliminating unnecessary cloud dependencies.',
            ),
            _PolicyItem(
              title: 'Minimal Source Query Excerpts',
              body:
                  'Plagiarism searches query public academic and open-access search indices using short anonymized n-gram phrases without publishing full documents.',
            ),
          ],
        ),
      ],
    );
  }

  // ── 3. Terms of Service & Academic Integrity Tab ──────────────────────────
  Widget _buildTermsTab() {
    return Column(
      key: const ValueKey('terms_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Highlight Box: "Ethical AI Assistance"
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.paletteCerulean.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.paletteCerulean.withValues(alpha: 0.30),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.scale,
                size: 18,
                color: AppColors.paletteCerulean,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ethical Use & Academic Integrity',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.paletteCerulean,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lauriva is engineered to refine prose, eliminate robotic cliches, and verify originality. Use Lauriva transparently and in compliance with your institutional guidelines.',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textPrimary.withValues(alpha: 0.90),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _buildSectionCard(
          title: 'Acceptable Use Guidelines',
          icon: LucideIcons.bookOpen,
          iconColor: AppColors.paletteCerulean,
          items: [
            _PolicyItem(
              title: 'Academic & Institutional Compliance',
              body:
                  'Users remain responsible for adhering to all institutional honor codes, university guidelines, and publisher policies regarding generative AI attribution.',
            ),
            _PolicyItem(
              title: 'No Malicious or Deceptive Misuse',
              body:
                  'You agree not to use Lauriva to produce defamatory, hateful, fraudulent, copyright-infringing, or unlawful content.',
            ),
            _PolicyItem(
              title: 'Intellectual Property Ownership',
              body:
                  'You own and retain all intellectual property rights in the original text you enter and the transformed outputs you generate.',
            ),
            _PolicyItem(
              title: 'Third-Party Terms',
              body:
                  'When using external LLM providers with your personal API keys, you agree to comply with those respective providers’ terms of service.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<_PolicyItem> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Icon(icon, size: 15, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.glassBorder),
          ...items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1;
            final item = entry.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.body,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(height: 1, color: AppColors.glassBorder.withValues(alpha: 0.5)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _PolicyItem {
  final String title;
  final String body;

  const _PolicyItem({
    required this.title,
    required this.body,
  });
}
