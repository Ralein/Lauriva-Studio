import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'forensic/token_predictability.dart';
import '../services/forensic/ai/adversarial_obfuscation_detector.dart';

/// Risk classification for plagiarism and AI-generated content
enum PlagiarismRiskLevel {
  clean(
    label: 'Original / Human',
    badge: 'HUMAN WRITTEN',
    color: Color(0xFF10B981), // Emerald
    bgColor: Color(0x2610B981),
    icon: LucideIcons.checkCircle2,
    description: 'High burstiness and natural linguistic entropy. Very low likelihood of AI or copied text.',
  ),
  low(
    label: 'Low Risk',
    badge: 'MOSTLY HUMAN',
    color: Color(0xFF38BDF8), // Sky
    bgColor: Color(0x2638BDF8),
    icon: LucideIcons.info,
    description: 'Predominantly human phrasing with minor repetitive sequences.',
  ),
  moderate(
    label: 'Moderate Risk',
    badge: 'SUSPICIOUS / MIXED',
    color: Color(0xFFF59E0B), // Amber
    bgColor: Color(0x26F59E0B),
    icon: LucideIcons.alertTriangle,
    description: 'Mixed characteristics. Several formulaic n-grams or uniform sentence structures detected.',
  ),
  high(
    label: 'High Risk',
    badge: 'LIKELY AI / PLAGIARIZED',
    color: Color(0xFFF97316), // Orange
    bgColor: Color(0x26F97316),
    icon: LucideIcons.alertCircle,
    description: 'Strong AI writing tells, low burstiness, and high n-gram predictability.',
  ),
  critical(
    label: 'Critical Risk',
    badge: 'HEAVILY AI-GENERATED',
    color: Color(0xFFEF4444), // Red
    bgColor: Color(0x26EF4444),
    icon: LucideIcons.alertOctagon,
    description: 'Severe AI writing patterns, stock clichés, and near-zero syntactic variation.',
  );

  final String label;
  final String badge;
  final Color color;
  final Color bgColor;
  final IconData icon;
  final String description;

  const PlagiarismRiskLevel({
    required this.label,
    required this.badge,
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.description,
  });

  static PlagiarismRiskLevel fromScore(double score) {
    if (score < 18.0) return PlagiarismRiskLevel.clean;
    if (score < 38.0) return PlagiarismRiskLevel.low;
    if (score < 65.0) return PlagiarismRiskLevel.moderate;
    if (score < 85.0) return PlagiarismRiskLevel.high;
    return PlagiarismRiskLevel.critical;
  }
}

/// Audit details for an individual sentence in the inspected text
class SentenceAudit {
  final int index;
  final String text;
  final double aiProbability; // 0.0 to 100.0
  final PlagiarismRiskLevel riskLevel;
  final List<String> detectedTells;
  final int wordCount;
  final double burstinessDelta;

  const SentenceAudit({
    required this.index,
    required this.text,
    required this.aiProbability,
    required this.riskLevel,
    required this.detectedTells,
    required this.wordCount,
    this.burstinessDelta = 0.0,
  });
}

/// Complete inspection report produced by PlagiarismDetectorService
class PlagiarismReport {
  final double overallScore; // 0.0 to 100.0 (Higher = more AI / plagiarized)
  final PlagiarismRiskLevel riskLevel;
  final double humanScore; // 100.0 - overallScore
  final double burstinessScore; // Standard deviation of sentence lengths / mean (0.0 to 1.5+)
  final double predictabilityScore; // N-gram predictability index (0.0 to 100.0)
  final double lexicalRichness; // Type-Token Ratio / Guiraud's R (0.0 to 100.0)
  final double ngramOverlapScore; // Repeated n-gram percentage
  final List<String> repeatedNgrams;
  final List<String> detectedTells;
  final List<SentenceAudit> sentences;
  final DateTime analyzedAt;
  final String modelSource; // 'On-Device NLP Engine' or 'Hugging Face (Hello-SimpleAI/chatgpt-detector-roberta)'
  final double plagiarismRiskScore; // 0.0 to 100.0
  final List<String> flaggedBoilerplates;
  
  // Calibrated Forensics Engine v2 additions
  final double uncertaintyScore; // 0.0 (certain) to 1.0 (high uncertainty)
  final String confidenceLevel; // 'Insufficient Evidence', 'Low Confidence', etc.
  final String authorshipBadge; // 'HUMAN WRITTEN', 'MIXED / EDITED', 'LIKELY AI', etc.
  final String? defensibleSummary;

  // Forensic Engine v3.5 additions
  final TokenPredictabilityReport? tokenPredictabilityReport;
  final AdversarialObfuscationEvidence? adversarialEvidence;

  // Post-fix comparison fields
  final String? fixedText;
  final double? fixedScore;
  final PlagiarismRiskLevel? fixedRiskLevel;

  PlagiarismReport({
    required this.overallScore,
    required this.riskLevel,
    required this.humanScore,
    required this.burstinessScore,
    required this.predictabilityScore,
    required this.lexicalRichness,
    required this.ngramOverlapScore,
    required this.repeatedNgrams,
    required this.detectedTells,
    required this.sentences,
    this.modelSource = 'Lauriva Forensic Engine',
    double? plagiarismRiskScore,
    this.flaggedBoilerplates = const [],
    this.uncertaintyScore = 0.0,
    this.confidenceLevel = 'Evaluated',
    this.authorshipBadge = 'EVALUATED',
    this.defensibleSummary,
    this.tokenPredictabilityReport,
    this.adversarialEvidence,
    DateTime? analyzedAt,
    this.fixedText,
    this.fixedScore,
    this.fixedRiskLevel,
  })  : plagiarismRiskScore = plagiarismRiskScore ??
            ((ngramOverlapScore * 0.7) + ((100.0 - lexicalRichness).clamp(0.0, 100.0) * 0.3)).clamp(0.0, 100.0),
        analyzedAt = analyzedAt ?? DateTime.now();

  /// Create a copy of the report with post-fix results attached
  PlagiarismReport withFix({
    required String fixedText,
    required double fixedScore,
    required PlagiarismRiskLevel fixedRiskLevel,
  }) {
    return PlagiarismReport(
      overallScore: overallScore,
      riskLevel: riskLevel,
      humanScore: humanScore,
      burstinessScore: burstinessScore,
      predictabilityScore: predictabilityScore,
      lexicalRichness: lexicalRichness,
      ngramOverlapScore: ngramOverlapScore,
      repeatedNgrams: repeatedNgrams,
      detectedTells: detectedTells,
      sentences: sentences,
      modelSource: modelSource,
      plagiarismRiskScore: plagiarismRiskScore,
      flaggedBoilerplates: flaggedBoilerplates,
      uncertaintyScore: uncertaintyScore,
      confidenceLevel: confidenceLevel,
      authorshipBadge: authorshipBadge,
      defensibleSummary: defensibleSummary,
      tokenPredictabilityReport: tokenPredictabilityReport,
      adversarialEvidence: adversarialEvidence,
      analyzedAt: analyzedAt,
      fixedText: fixedText,
      fixedScore: fixedScore,
      fixedRiskLevel: fixedRiskLevel,
    );
  }

  /// Generate a concise summary text for export or clipboard
  String toSummaryText() {
    final buffer = StringBuffer();
    buffer.writeln('=== Lauriva AI Plagiarism & Originality Report ===');
    buffer.writeln('Detector Engine: $modelSource');
    buffer.writeln('AI Likelihood: ${overallScore.toStringAsFixed(1)}% (${riskLevel.badge})');
    buffer.writeln('Confidence Level: $confidenceLevel');
    buffer.writeln('Human Authenticity: ${humanScore.toStringAsFixed(1)}%');
    if (defensibleSummary != null && defensibleSummary!.isNotEmpty) {
      buffer.writeln('Forensic Finding: $defensibleSummary');
    }
    buffer.writeln('Plagiarism & Boilerplate Risk: ${plagiarismRiskScore.toStringAsFixed(1)}%');
    buffer.writeln('Burstiness Variance: ${burstinessScore.toStringAsFixed(2)} (Higher is more human)');
    buffer.writeln('Lexical Richness: ${lexicalRichness.toStringAsFixed(1)}%');
    buffer.writeln('Formulaic N-Gram Overlap: ${ngramOverlapScore.toStringAsFixed(1)}%');
    
    if (detectedTells.isNotEmpty) {
      buffer.writeln('\nDetected AI Patterns:');
      for (final tell in detectedTells) {
        buffer.writeln('- $tell');
      }
    }

    if (fixedText != null && fixedScore != null) {
      buffer.writeln('\n=== Lauriva Humanized Fix Result ===');
      buffer.writeln('Post-Fix AI Score: ${fixedScore!.toStringAsFixed(1)}% (${fixedRiskLevel?.badge ?? "CLEAN"})');
      buffer.writeln('Improvement: -${(overallScore - fixedScore!).clamp(0, 100).toStringAsFixed(1)}% AI reduction');
    }

    return buffer.toString();
  }
}
