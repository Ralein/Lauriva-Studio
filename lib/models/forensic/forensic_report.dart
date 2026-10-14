import 'dart:math';
import '../plagiarism_report.dart';
import '../../services/forensic/ai/adversarial_obfuscation_detector.dart';
import 'ai_authorship_evidence.dart';
import 'confidence_assessment.dart';
import 'forensic_scan_mode.dart';
import 'forensic_span.dart';
import 'internal_repetition_evidence.dart';
import 'source_similarity_evidence.dart';
import 'token_predictability.dart';

/// Metadata capturing forensic versioning, hashing, and execution parameters.
class ForensicReportMetadata {
  final String analysisId;
  final String textHash;
  final DateTime analyzedAt;
  final String engineVersion;
  final String featureSchemaVersion;
  final Duration executionDuration;
  final ForensicScanMode scanMode;
  final ForensicSensitivity sensitivity;

  const ForensicReportMetadata({
    required this.analysisId,
    required this.textHash,
    required this.analyzedAt,
    this.engineVersion = '3.5.0',
    this.featureSchemaVersion = '3',
    this.executionDuration = Duration.zero,
    this.scanMode = ForensicScanMode.fullForensic,
    this.sensitivity = ForensicSensitivity.balanced,
  });

  factory ForensicReportMetadata.fromJson(Map<String, dynamic> json) =>
      ForensicReportMetadata(
        analysisId: json['analysisId'] as String,
        textHash: json['textHash'] as String,
        analyzedAt: DateTime.parse(json['analyzedAt'] as String),
        engineVersion: json['engineVersion'] as String? ?? '3.5.0',
        featureSchemaVersion: json['featureSchemaVersion'] as String? ?? '3',
        executionDuration: Duration(
          milliseconds: (json['executionDurationMs'] as num?)?.toInt() ?? 0,
        ),
        scanMode: ForensicScanMode.fromName(json['scanMode'] as String?),
        sensitivity: ForensicSensitivity.fromName(json['sensitivity'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'analysisId': analysisId,
        'textHash': textHash,
        'analyzedAt': analyzedAt.toIso8601String(),
        'engineVersion': engineVersion,
        'featureSchemaVersion': featureSchemaVersion,
        'executionDurationMs': executionDuration.inMilliseconds,
        'scanMode': scanMode.name,
        'sensitivity': sensitivity.name,
      };
}

/// The master multi-dimensional forensic report produced by Lauriva Forensics Engine 3.0.
///
/// Decouples AI writing likelihood, external source similarity, internal repetition,
/// and statistical uncertainty into independent, evidence-backed dimensions while
/// providing full backward-compatibility with [PlagiarismReport] for existing UI components.
class ForensicReport {
  final ForensicReportMetadata metadata;
  final String rawText;
  final String normalizedText;
  final int wordCount;
  final int charCount;
  final int sentenceCount;
  final int paragraphCount;

  // Four Independent Forensic Dimensions
  final AiAuthorshipEvidence aiAuthorship;
  final SourceSimilarityEvidence sourceSimilarity;
  final InternalRepetitionEvidence internalRepetition;
  final ConfidenceAssessment confidence;
  final TokenPredictabilityReport? tokenPredictability;
  final AdversarialObfuscationEvidence? adversarialEvidence;

  // Span & Sentence Evidence
  final List<ForensicSpan> spans;
  final List<SentenceAudit> sentences;
  final String summary;

  const ForensicReport({
    required this.metadata,
    required this.rawText,
    required this.normalizedText,
    required this.wordCount,
    required this.charCount,
    required this.sentenceCount,
    required this.paragraphCount,
    required this.aiAuthorship,
    required this.sourceSimilarity,
    required this.internalRepetition,
    required this.confidence,
    this.tokenPredictability,
    this.adversarialEvidence,
    this.spans = const [],
    this.sentences = const [],
    required this.summary,
  });

  // ── Backward-Compatibility Getters for Existing UI ─────────────────────────

  /// Overall composite score (0.0 to 100.0) where 100.0 = high AI/plagiarism.
  /// Dynamically reflects the selected forensic audit mode and calibration.
  double get overallScore {
    switch (metadata.scanMode) {
      case ForensicScanMode.sourceScan:
        return sourceSimilarity.overallSimilarityScore.clamp(0.0, 100.0);
      case ForensicScanMode.forensic:
        return aiAuthorship.aiProbability.clamp(0.0, 100.0);
      case ForensicScanMode.fullForensic:
        final ai = aiAuthorship.aiProbability;
        final source = sourceSimilarity.overallSimilarityScore;
        return max(ai, source).clamp(0.0, 100.0);
    }
  }

  /// Percentage likelihood of authentic human authorship.
  double get humanScore => (100.0 - overallScore).clamp(0.0, 100.0);

  /// Risk level matching [PlagiarismRiskLevel] enum used by [PlagiarismAuditCard].
  PlagiarismRiskLevel get riskLevel => PlagiarismRiskLevel.fromScore(overallScore);

  /// Normalized burstiness measure for text metrics.
  double get burstinessScore {
    if (aiAuthorship.featureVector.length > 6) {
      return aiAuthorship.featureVector[6]; // burstinessCv
    }
    return 0.5;
  }

  /// Predictability index.
  double get predictabilityScore => overallScore;

  /// Lexical richness metric (0.0 to 100.0).
  double get lexicalRichness => internalRepetition.lexicalRichness;

  /// Flagged phrases and micro-tells for the UI tell badges.
  List<String> get flaggedPhrases {
    final list = <String>[];
    for (final s in aiAuthorship.detectedSignals) {
      list.add('${s.name}: ${s.description}');
    }
    for (final bp in internalRepetition.flaggedBoilerplates) {
      list.add('Boilerplate: "$bp"');
    }
    for (final rep in internalRepetition.repeatedNgrams.take(5)) {
      list.add('Repeated sequence: "$rep"');
    }
    return list;
  }

  /// Defensible forensic summary for UI export and displays.
  String get defensibleSummary => summary;

  /// Converts this [ForensicReport] directly into the legacy [PlagiarismReport]
  /// so that any existing service, provider, or widget receives identical data without refactoring.
  PlagiarismReport toLegacyPlagiarismReport() {
    return PlagiarismReport(
      overallScore: overallScore,
      riskLevel: riskLevel,
      humanScore: humanScore,
      burstinessScore: burstinessScore,
      predictabilityScore: predictabilityScore,
      lexicalRichness: lexicalRichness,
      ngramOverlapScore: internalRepetition.repetitionScore,
      repeatedNgrams: internalRepetition.repeatedNgrams,
      detectedTells: flaggedPhrases,
      sentences: sentences,
      modelSource: 'Lauriva Forensic Engine 3.5',
      plagiarismRiskScore: sourceSimilarity.overallSimilarityScore,
      flaggedBoilerplates: internalRepetition.flaggedBoilerplates,
      uncertaintyScore: confidence.uncertainty,
      confidenceLevel: confidence.level.name,
      authorshipBadge: aiAuthorship.authorshipClass.badge,
      defensibleSummary: summary,
      tokenPredictabilityReport: tokenPredictability,
      adversarialEvidence: adversarialEvidence,
      analyzedAt: metadata.analyzedAt,
    );
  }

  factory ForensicReport.fromJson(Map<String, dynamic> json) => ForensicReport(
        metadata: ForensicReportMetadata.fromJson(
            json['metadata'] as Map<String, dynamic>),
        rawText: json['rawText'] as String,
        normalizedText: json['normalizedText'] as String,
        wordCount: (json['wordCount'] as num).toInt(),
        charCount: (json['charCount'] as num).toInt(),
        sentenceCount: (json['sentenceCount'] as num).toInt(),
        paragraphCount: (json['paragraphCount'] as num).toInt(),
        aiAuthorship: AiAuthorshipEvidence.fromJson(
            json['aiAuthorship'] as Map<String, dynamic>),
        sourceSimilarity: SourceSimilarityEvidence.fromJson(
            json['sourceSimilarity'] as Map<String, dynamic>),
        internalRepetition: InternalRepetitionEvidence.fromJson(
            json['internalRepetition'] as Map<String, dynamic>),
        confidence: ConfidenceAssessment.fromJson(
            json['confidence'] as Map<String, dynamic>),
        spans: (json['spans'] as List<dynamic>? ?? [])
            .map((s) => ForensicSpan.fromJson(s as Map<String, dynamic>))
            .toList(),
        sentences: const [], // sentences are rebuilt on main thread — not serialized
        summary: json['summary'] as String,
      );

  /// Null-safe deserialization — returns [ForensicReport.empty()] on any cast
  /// failure so malformed isolate JSON never crashes the main thread.
  static ForensicReport fromJsonSafe(Map<String, dynamic> json) {
    try {
      return ForensicReport.fromJson(json);
    } catch (_) {
      return ForensicReport.empty();
    }
  }

  /// Returns a safe minimal empty report for error-fallback paths.
  factory ForensicReport.empty() {
    final now = DateTime.now();
    return ForensicReport(
      metadata: ForensicReportMetadata(
        analysisId: 'empty_${now.millisecondsSinceEpoch}',
        textHash: '',
        analyzedAt: now,
      ),
      rawText: '',
      normalizedText: '',
      wordCount: 0,
      charCount: 0,
      sentenceCount: 0,
      paragraphCount: 0,
      aiAuthorship: const AiAuthorshipEvidence(
        aiProbability: 0.0,
        humanProbability: 100.0,
        authorshipClass: AuthorshipClass.inconclusive,
        uncertainty: 1.0,
        detectedSignals: [],
        defensibleSummary: 'Insufficient data for analysis.',
      ),
      sourceSimilarity: const SourceSimilarityEvidence.clean(),
      internalRepetition: const InternalRepetitionEvidence(
        repetitionScore: 0.0,
        lexicalRichness: 0.0,
        repeatedNgrams: [],
        flaggedBoilerplates: [],
        defensibleSummary: 'No data.',
      ),
      confidence: const ConfidenceAssessment(
        level: ForensicConfidenceLevel.insufficient,
        score: 0.0,
        uncertainty: 1.0,
        summary: 'Analysis unavailable.',
      ),
      summary: 'Analysis unavailable.',
    );
  }

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'rawText': rawText,
        'normalizedText': normalizedText,
        'wordCount': wordCount,
        'charCount': charCount,
        'sentenceCount': sentenceCount,
        'paragraphCount': paragraphCount,
        'aiAuthorship': aiAuthorship.toJson(),
        'sourceSimilarity': sourceSimilarity.toJson(),
        'internalRepetition': internalRepetition.toJson(),
        'confidence': confidence.toJson(),
        'spans': spans.map((s) => s.toJson()).toList(),
        'summary': summary,
      };
}
