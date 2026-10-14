import 'dart:math' as math;

import '../../../models/forensic/ai_authorship_evidence.dart';
import '../../../models/forensic/confidence_assessment.dart';
import '../../../models/forensic/forensic_evidence.dart';
import '../../../models/forensic/forensic_scan_mode.dart';
import '../../../models/forensic/internal_repetition_evidence.dart';
import '../../../models/forensic/neural_detection_result.dart';
import '../../../models/forensic/source_similarity_evidence.dart';
import '../../../models/forensic/token_predictability.dart';
import '../ai/sliding_window_analyzer.dart';
import '../document/document_segmenter.dart';
import 'confidence_calculator.dart';
import 'fusion_config.dart';
import 'probability_calibrator.dart';

/// Calibrated evidence fusion result combining independent forensic streams.
class FusionResult {
  final double calibratedAiProbability; // 0.0 -> 100.0 presentation format
  final AuthorshipClass calibratedAuthorshipClass;
  final ConfidenceAssessment confidence;
  final String executiveSummary;
  final double neuralWeight;
  final double forensicWeight;
  final List<ForensicEvidence> evidence;
  final bool isNeuralFallback;

  const FusionResult({
    required this.calibratedAiProbability,
    required this.calibratedAuthorshipClass,
    required this.confidence,
    required this.executiveSummary,
    this.neuralWeight = 0.0,
    this.forensicWeight = 1.0,
    this.evidence = const [],
    this.isNeuralFallback = true,
  });
}

/// Summary of sentence-level attribution consensus across the document.
class SentenceConsensusSummary {
  final double meanAiProbability;
  final double tellDensity; // 0.0 - 1.0 (fraction of sentences with >=1 explicit tell)
  final double highConfidenceAiRatio; // fraction with score >= 65.0
  final double cleanSentenceRatio; // fraction with score < 35.0

  const SentenceConsensusSummary({
    required this.meanAiProbability,
    required this.tellDensity,
    required this.highConfidenceAiRatio,
    required this.cleanSentenceRatio,
  });
}

/// Master Evidence Fusion Engine (Lauriva Dual-Stream Forensics 4.0).
///
/// Responsibilities:
/// 1. Combines deep transformer neural stream ($P_{neural}$) with 38-feature stylometry ($P_{forensic}$).
/// 2. Applies dynamic uncertainty weighting based on text length and Shannon entropy.
/// 3. Calibrates raw probabilities using Platt logistic scaling.
/// 4. Reconciles contradictions between AI authorship and external plagiarism.
/// 5. Produces an auditable, legally and academically defensible executive summary.
class EvidenceFusionEngine {
  final FusionConfig config;
  final ProbabilityCalibrator calibrator;
  final ConfidenceCalculator confidenceCalculator;

  EvidenceFusionEngine({
    this.config = const FusionConfig(),
    this.calibrator = const ProbabilityCalibrator(),
    this.confidenceCalculator = const ConfidenceCalculator(),
  });

  /// Computes dynamic uncertainty-weighted ensemble weights.
  static List<double> computeDynamicWeights(List<({double score, double uncertainty})> outputs) {
    if (outputs.isEmpty) return const [];
    final rawWeights = outputs.map((o) => (1.0 - o.uncertainty).clamp(0.05, 1.0)).toList();
    final total = rawWeights.reduce((a, b) => a + b);
    return rawWeights.map((w) => w / total).toList();
  }

  /// Calculates sample-dependent dynamic weight for the neural stream.
  double calculateNeuralWeight({
    required int wordCount,
    required double neuralUncertainty,
    required bool isFallback,
  }) {
    if (isFallback) return 0.0;
    final lengthFactor = (wordCount / config.fullContextWordCount).clamp(0.5, 1.0);
    final certaintyFactor = (1.0 - (neuralUncertainty * 0.35)).clamp(0.5, 1.0);

    return (config.neuralBaseWeight * lengthFactor * certaintyFactor).clamp(
      config.minimumNeuralWeight,
      config.maximumNeuralWeight,
    );
  }

  /// Calibrated AI probability (0-1) from the stacked log-odds of both streams.
  double stackedProbability(double neural01, double forensic01) {
    double clippedLogit(double p) {
      final q = p.clamp(1e-6, 1.0 - 1e-6);
      return math.log(q / (1.0 - q)).clamp(-config.stackLogitClip, config.stackLogitClip);
    }

    final z = config.stackNeuralCoef * clippedLogit(neural01) +
        config.stackForensicCoef * clippedLogit(forensic01) +
        config.stackBias;
    return 1.0 / (1.0 + math.exp(-z));
  }

  /// Dual-stream evidence fusion combining Neural Detector + 38-feature Forensic Engine.
  FusionResult fuseDualStream({
    required SegmentedDocument document,
    required NeuralDetectionResult neuralResult,
    required AiAuthorshipEvidence forensicEvidence,
    required SourceSimilarityEvidence sourceEvidence,
    required InternalRepetitionEvidence repetitionEvidence,
    required SlidingWindowAnalysisResult windowResult,
    double structuralScore = 0.0,
    TokenPredictabilityReport? tokenPredictability,
    SentenceConsensusSummary? sentenceConsensus,
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
  }) {
    final wordCount = document.totalWordCount;
    final isFallback = neuralResult.isFallback;

    // 1. Calculate Dynamic Stream Weights
    final neuralWeight = calculateNeuralWeight(
      wordCount: wordCount,
      neuralUncertainty: neuralResult.uncertainty,
      isFallback: isFallback,
    );
    final forensicWeight = 1.0 - neuralWeight;

    // 2. Fused Raw Score (0.0 -> 1.0 standard)
    final neuralScore01 = neuralResult.aiProbability.clamp(0.0, 1.0);
    final forensicScore01 = (forensicEvidence.aiProbability / 100.0).clamp(0.0, 1.0);

    final double calibratedAiProb;
    if (isFallback) {
      var rawFused01 = forensicScore01;

      // 3. Structural & Predictability Refinements
      if (structuralScore > 25.0) {
        final structFactor = (structuralScore / 100.0) * 0.15;
        rawFused01 = (rawFused01 * (1.0 - structFactor) + (structuralScore / 100.0) * structFactor).clamp(0.0, 1.0);
      }

      if (tokenPredictability != null && tokenPredictability.tokens.isNotEmpty) {
        if (tokenPredictability.predictabilityScore >= 60.0 && rawFused01 >= 0.45) {
          final predWeight = ((tokenPredictability.predictabilityScore - 50.0) / 100.0) * 0.12;
          rawFused01 = (rawFused01 * (1.0 - predWeight) + (tokenPredictability.predictabilityScore / 100.0) * predWeight).clamp(0.0, 1.0);
        } else if (tokenPredictability.rareTailPercentage >= 14.0 && rawFused01 <= 0.40) {
          rawFused01 = (rawFused01 * 0.88).clamp(0.0, 1.0);
        }
      }

      // 4. Logistic Platt Calibration
      // For authentic human authorship with low forensic risk scores, do not artificially
      // compress into the uncertainty band with Platt scaling (which has an empirical floor of ~35%).
      if (rawFused01 <= config.humanThreshold || forensicEvidence.authorshipClass == AuthorshipClass.likelyHuman) {
        calibratedAiProb = (rawFused01 * 100.0).clamp(0.0, 100.0);
      } else {
        calibratedAiProb = (calibrator.calibrate(rawFused01) * 100.0).clamp(0.0, 100.0);
      }
    } else {
      // The forensic stream already folds in structural/predictability evidence
      // and Platt scaling, and the stack is itself calibrated, so neither is
      // re-applied here.
      calibratedAiProb = (stackedProbability(neuralScore01, forensicScore01) * 100.0).clamp(0.0, 100.0);
    }

    // 5. Build Unified Forensic Evidence Set
    final evidenceList = <ForensicEvidence>[];
    if (!isFallback) {
      evidenceList.add(ForensicEvidence(
        type: EvidenceType.neural,
        label: 'Neural Transformer Embedding',
        description: 'Deep contextual representation signals AI generation likelihood of ${(neuralScore01 * 100.0).toStringAsFixed(1)}%.',
        strength: neuralScore01,
        confidence: (1.0 - neuralResult.uncertainty).clamp(0.0, 1.0),
        source: EvidenceSource.modelLogits,
      ));
    }

    evidenceList.add(ForensicEvidence(
      type: EvidenceType.stylometric,
      label: '38-Feature Stylometric Profile',
      description: 'Lexical richness, syntax complexity, and burstiness vector score of ${forensicEvidence.aiProbability.toStringAsFixed(1)}%.',
      strength: forensicScore01,
      confidence: (1.0 - forensicEvidence.uncertainty).clamp(0.0, 1.0),
      source: EvidenceSource.stylometricVector,
    ));

    if (structuralScore > 20.0) {
      evidenceList.add(ForensicEvidence(
        type: EvidenceType.structural,
        label: 'Structural Fingerprint Pattern',
        description: 'Detected uniform opener templates and clause symmetry invariant to vocabulary substitution.',
        strength: (structuralScore / 100.0).clamp(0.0, 1.0),
        confidence: 0.80,
        source: EvidenceSource.structuralGrammar,
      ));
    }

    // 6. Multi-Factor Uncertainty & Confidence Assessment
    final factors = <ConfidenceFactor>[];
    factors.add(ConfidenceFactor(
      name: 'Document Length Stability',
      score: (wordCount / 300.0).clamp(0.0, 1.0),
      isSupportive: wordCount >= 50,
      description: wordCount < 50
          ? 'Short passage (< 50 words) has high statistical variance.'
          : 'Sufficient text length ($wordCount words) for robust statistical inference.',
    ));

    if (!isFallback) {
      final agreement = 1.0 - (neuralScore01 - forensicScore01).abs();
      factors.add(ConfidenceFactor(
        name: 'Dual-Stream Consensus',
        score: agreement.clamp(0.0, 1.0),
        isSupportive: agreement >= 0.70,
        description: agreement >= 0.70
            ? 'Neural Transformer and Forensic Stylometry strongly agree.'
            : 'Moderate divergence between deep transformer attention and surface stylometry.',
      ));
    }

    final calculatedConf = confidenceCalculator.calculateConfidence(
      wordCount: wordCount,
      neuralProbability: neuralScore01,
      neuralUncertainty: neuralResult.uncertainty,
      forensicProbability: forensicScore01,
      forensicUncertainty: forensicEvidence.uncertainty,
      isNeuralFallback: isFallback,
    );

    ForensicConfidenceLevel level;
    if (wordCount < 40) {
      level = ForensicConfidenceLevel.insufficient;
    } else if (calculatedConf < 0.45) {
      level = ForensicConfidenceLevel.low;
    } else if (calculatedConf < 0.75) {
      level = ForensicConfidenceLevel.moderate;
    } else {
      level = ForensicConfidenceLevel.high;
    }

    final confidenceAssessment = ConfidenceAssessment(
      level: level,
      score: calculatedConf,
      uncertainty: 1.0 - calculatedConf,
      factors: factors,
      summary: level.badge,
    );

    // 7. Authorship Classification
    double aiUpper = config.aiThreshold * 100.0;
    double aiLower = config.humanThreshold * 100.0;
    if (!isFallback) {
      // Calibrated neural stack: operating points from FusionConfig, shifted by sensitivity.
      aiUpper = config.neuralAiThreshold * 100.0;
      aiLower = config.neuralHumanThreshold * 100.0;
      if (sensitivity == ForensicSensitivity.strict) {
        aiUpper -= 10.0;
        aiLower -= 5.0;
      } else if (sensitivity == ForensicSensitivity.lenient) {
        aiUpper = (aiUpper + 5.0).clamp(0.0, 99.0);
        aiLower += 10.0;
      }
    } else if (sensitivity == ForensicSensitivity.strict) {
      aiUpper = 55.0;
      aiLower = 28.0;
    } else if (sensitivity == ForensicSensitivity.lenient) {
      aiUpper = 75.0;
      aiLower = 42.0;
    }

    AuthorshipClass authorshipClass = forensicEvidence.authorshipClass;
    if (calibratedAiProb >= aiUpper && authorshipClass != AuthorshipClass.inconclusive) {
      authorshipClass = AuthorshipClass.likelyAi;
    } else if (calibratedAiProb <= aiLower && authorshipClass != AuthorshipClass.inconclusive) {
      authorshipClass = AuthorshipClass.likelyHuman;
    } else if (windowResult.isMixedOrEdited &&
        level != ForensicConfidenceLevel.insufficient &&
        calibratedAiProb > aiLower &&
        calibratedAiProb < (aiUpper + 5.0)) {
      authorshipClass = AuthorshipClass.mixedOrEdited;
    } else if (authorshipClass != AuthorshipClass.inconclusive) {
      authorshipClass = AuthorshipClass.uncertain;
    }

    // 8. Executive Summary Generation
    final summary = _generateSummary(
      calibratedAiProb: calibratedAiProb,
      authorshipClass: authorshipClass,
      neuralWeight: neuralWeight,
      isFallback: isFallback,
      sourceEvidence: sourceEvidence,
      repetitionEvidence: repetitionEvidence,
      wordCount: wordCount,
      mode: mode,
    );

    return FusionResult(
      calibratedAiProbability: calibratedAiProb,
      calibratedAuthorshipClass: authorshipClass,
      confidence: confidenceAssessment,
      executiveSummary: summary,
      neuralWeight: neuralWeight,
      forensicWeight: forensicWeight,
      evidence: evidenceList,
      isNeuralFallback: isFallback,
    );
  }

  /// Backward-compatible synchronous fusion method for existing tests and engine callers.
  FusionResult fuse({
    required SegmentedDocument document,
    required AiAuthorshipEvidence aiEvidence,
    required SourceSimilarityEvidence sourceEvidence,
    required InternalRepetitionEvidence repetitionEvidence,
    required SlidingWindowAnalysisResult windowResult,
    double structuralScore = 0.0,
    TokenPredictabilityReport? tokenPredictability,
    SentenceConsensusSummary? sentenceConsensus,
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
  }) {
    return fuseDualStream(
      document: document,
      neuralResult: NeuralDetectionResult.fallback(
        error: 'Synchronous forensic mode without neural model',
      ),
      forensicEvidence: aiEvidence,
      sourceEvidence: sourceEvidence,
      repetitionEvidence: repetitionEvidence,
      windowResult: windowResult,
      structuralScore: structuralScore,
      tokenPredictability: tokenPredictability,
      sentenceConsensus: sentenceConsensus,
      mode: mode,
      sensitivity: sensitivity,
    );
  }

  String _generateSummary({
    required double calibratedAiProb,
    required AuthorshipClass authorshipClass,
    required double neuralWeight,
    required bool isFallback,
    required SourceSimilarityEvidence sourceEvidence,
    required InternalRepetitionEvidence repetitionEvidence,
    required int wordCount,
    required ForensicScanMode mode,
  }) {
    final buffer = StringBuffer();
    if (mode == ForensicScanMode.sourceScan) {
      buffer.write('[Source & Literature Plagiarism Audit] ');
    } else {
      buffer.write('[Dual-Stream Forensic Audit] ');
    }

    if (authorshipClass == AuthorshipClass.likelyAi) {
      buffer.write('The available signals indicate a higher likelihood of AI-assisted authorship (${calibratedAiProb.toStringAsFixed(0)}%), ');
      buffer.write('exhibiting characteristic autoregressive syntactic patterns and low burstiness. ');
    } else if (authorshipClass == AuthorshipClass.mixedOrEdited) {
      buffer.write('Scan indicates mixed-origin or human-edited composition with localized authorial shifts. ');
    } else if (authorshipClass == AuthorshipClass.likelyHuman) {
      buffer.write('The available signals strongly support authentic human authorship (${(100.0 - calibratedAiProb).toStringAsFixed(0)}% human likelihood), ');
      buffer.write('with natural stylistic variance and rich vocabulary. ');
    } else if (authorshipClass == AuthorshipClass.uncertain) {
      buffer.write('The available evidence is insufficient for a reliable determination (${calibratedAiProb.toStringAsFixed(0)}% borderline signals). ');
    } else {
      buffer.write('The submitted text has insufficient length for reliable forensic stylometric inference. ');
    }

    if (sourceEvidence.overallSimilarityScore >= 20.0) {
      final uncited = sourceEvidence.matches.where((m) => m.citationStatus == CitationStatus.uncited).length;
      if (uncited > 0) {
        buffer.write('Concurrently, $uncited uncited verbatim external source match(es) were identified. ');
      }
    }

    if (repetitionEvidence.flaggedBoilerplates.isNotEmpty) {
      buffer.write('Contains ${repetitionEvidence.flaggedBoilerplates.length} formulaic boilerplate phrase(s).');
    }

    return buffer.toString().trim();
  }
}
