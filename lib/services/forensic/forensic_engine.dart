import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/forensic/ai_authorship_evidence.dart';
import '../../models/forensic/forensic_report.dart';
import '../../models/forensic/forensic_scan_mode.dart';
import '../../models/forensic/forensic_span.dart';
import '../../models/forensic/forensic_progress.dart';
import '../../models/forensic/internal_repetition_evidence.dart';
import '../../models/forensic/source_similarity_evidence.dart';
import '../../models/plagiarism_report.dart';
import '../ai_forensic_service.dart';
import '../source_plagiarism_service.dart';
import 'ai/adversarial_obfuscation_detector.dart';
import 'ai/cusum_drift_detector.dart';
import 'ai/domain_classifier.dart';
import 'ai/sentence_attribution_model.dart';
import 'ai/sliding_window_analyzer.dart';
import 'ai/structural_fingerprint_detector.dart';
import 'ai/stylometric_feature_extractor.dart';
import 'ai/token_predictability_analyzer.dart';
import 'document/document_segmenter.dart';
import 'fusion/evidence_fusion_engine.dart';
import 'fusion/fusion_config.dart';
import 'normalization/homoglyph_normalizer.dart';
import 'normalization/text_normalizer.dart';
import 'sources/dense_semantic_matcher.dart';
import 'sources/source_repository.dart';
import 'sources/source_similarity_service.dart';
import 'ai/multilingual_feature_profiles.dart';
import 'ai/neural/neural_detector_service.dart';
import 'ai/neural/neural_model_registry.dart';
import 'watermark/watermark_detector_service.dart';
import 'forensic_calibration.dart';
import '../../models/forensic/neural_detection_result.dart';

/// Lauriva Forensic Content Intelligence Engine 3.5 Core Orchestrator.
///
/// Implements a decoupled, evidence-backed forensic architecture:
/// 1. Canonical Normalization & Position Mapping
/// 2. Structural Document Segmentation
/// 3. AI Authorship Forensics (Stylometry, Syntax, Vocabulary, Anomaly)
/// 4. Sliding Window & Style Shift Analysis (Mixed / Human-Edited AI)
/// 5. Source Plagiarism Forensics (Shingle overlap, Verbatim Matching)
/// 6. Internal Repetition & Formulaic Boilerplate Forensics
/// 7. Evidence Fusion & Multi-factor Uncertainty Quantification
class ForensicEngine {
  final TextNormalizer _normalizer;
  final DocumentSegmenter _segmenter;
  final AiForensicService _aiService;
  final SourcePlagiarismService _sourceService;
  final StylometricFeatureExtractor _stylometricExtractor;
  final SlidingWindowAnalyzer _windowAnalyzer;
  final SourceSimilarityService _similarityService;
  final EvidenceFusionEngine _fusionEngine;
  final AdversarialObfuscationDetector _obfuscationDetector;
  final TokenPredictabilityAnalyzer _tokenPredictabilityAnalyzer;
  final DenseSemanticMatcher _denseSemanticMatcher;
  final CusumDriftDetector _cusumDetector;
  final DomainClassifier _domainClassifier;
  final StructuralFingerprintDetector _structuralDetector;
  final WatermarkDetectorService _watermarkDetector;
  final ForensicCalibrationConfig _calibration;
  final NeuralDetectorService? _neuralDetector;
  final Set<String> _neuralLanguages;
  final SentenceAttributionModel _sentenceModel = const SentenceAttributionModel();

  static final ForensicCalibrationConfig _defaultCalibration = ForensicCalibrationConfig.calibrated();

  ForensicCalibrationConfig get calibration => _calibration;
  NeuralDetectorService? get neuralDetector => _neuralDetector;

  /// Languages the neural stream covers: [neuralDetector]'s model, else the
  /// bundled model's `supportedLanguages`.
  Set<String> get neuralLanguages => _neuralLanguages;

  ForensicEngine({
    TextNormalizer? normalizer,
    DocumentSegmenter? segmenter,
    AiForensicService? aiService,
    SourcePlagiarismService? sourceService,
    StylometricFeatureExtractor? stylometricExtractor,
    SlidingWindowAnalyzer? windowAnalyzer,
    SourceSimilarityService? similarityService,
    EvidenceFusionEngine? fusionEngine,
    AdversarialObfuscationDetector? obfuscationDetector,
    TokenPredictabilityAnalyzer? tokenPredictabilityAnalyzer,
    DenseSemanticMatcher? denseSemanticMatcher,
    CusumDriftDetector? cusumDetector,
    DomainClassifier? domainClassifier,
    WatermarkDetectorService? watermarkDetector,
    ForensicCalibrationConfig? calibration,
    NeuralDetectorService? neuralDetector,
    Set<String>? neuralLanguages,
  })  : _normalizer = normalizer ?? TextNormalizer(),
        _segmenter = segmenter ?? DocumentSegmenter(),
        _aiService = aiService ?? AiForensicService(),
        _sourceService = sourceService ?? SourcePlagiarismService(),
        _stylometricExtractor = stylometricExtractor ?? StylometricFeatureExtractor(),
        _windowAnalyzer = windowAnalyzer ??
            SlidingWindowAnalyzer(
              featureExtractor: stylometricExtractor ?? StylometricFeatureExtractor(),
              aiService: aiService ?? AiForensicService(),
            ),
        _similarityService = similarityService ?? SourceSimilarityService(),
        _calibration = calibration ?? _defaultCalibration,
        _fusionEngine = fusionEngine ??
            EvidenceFusionEngine(
              calibrator: (calibration ?? _defaultCalibration).plattCalibrator,
              config: FusionConfig(
                aiThreshold: (calibration ?? _defaultCalibration).aiModerateThreshold / 100.0,
                humanThreshold: (calibration ?? _defaultCalibration).aiCleanThreshold / 100.0,
              ),
            ),
        _obfuscationDetector = obfuscationDetector ?? AdversarialObfuscationDetector(),
        _tokenPredictabilityAnalyzer = tokenPredictabilityAnalyzer ?? TokenPredictabilityAnalyzer(),
        _denseSemanticMatcher = denseSemanticMatcher ?? DenseSemanticMatcher(),
        _cusumDetector = cusumDetector ?? const CusumDriftDetector(),
        _domainClassifier = domainClassifier ?? DomainClassifier(),
        _structuralDetector = StructuralFingerprintDetector(),
        _watermarkDetector = watermarkDetector ?? WatermarkDetectorService(),
        _neuralDetector = neuralDetector,
        _neuralLanguages = neuralLanguages ??
            neuralDetector?.config.supportedLanguages ??
            NeuralModelRegistry.bundledConfig.supportedLanguages;

  SourcePlagiarismService get sourceService => _sourceService;

  /// Analyzes document synchronously with optional real-time chunk progress callback.
  ///
  /// [neuralLanguages] overrides [this.neuralLanguages] for the report's
  /// Language signal (whether the neural stream covers this text).
  ForensicReport analyze(
    String rawText, {
    Set<String>? neuralLanguages,
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
    bool enableOnlineSearch = true,
    bool enableWatermarkDetection = true,
    bool enableHomoglyphDetection = true,
    void Function(ForensicProgress)? onProgress,
  }) {
    final stopwatch = Stopwatch()..start();

    // 0. Adversarial hardening: homoglyph normalization (Phase 16).
    // Cyrillic lookalikes are an attack on Latin text only: genuine Russian
    // prose is Cyrillic throughout and must not be rewritten or flagged.
    final isCyrillicProse = LanguageDetector.detect(rawText) == 'ru';
    final homoResult = enableHomoglyphDetection && !isCyrillicProse
        ? HomoglyphNormalizer.normalize(rawText)
        : (normalized: rawText, replacements: 0);
    final hardenedText = homoResult.normalized;

    // 1. Canonical Normalization
    final normDoc = _normalizer.normalize(hardenedText);

    // 2. Structural Document Segmentation
    final segDoc = _segmenter.segment(normDoc);
    final chunks = _segmenter.partitionIntoChunks(segDoc);
    final totalChunks = chunks.length;
    final totalWords = segDoc.totalWordCount;

    // Report initial segmentation progress
    onProgress?.call(ForensicProgress(
      currentChunk: 0,
      totalChunks: totalChunks,
      progressRatio: 0.05,
      elapsed: stopwatch.elapsed,
      estimatedRemaining: Duration(milliseconds: totalChunks * 22),
      estimatedTotal: Duration(milliseconds: totalChunks * 22),
      stage: totalChunks > 1
          ? 'Segmented into $totalChunks chunks ($totalWords words)...'
          : 'Document segmented ($totalWords words)...',
      wordsProcessed: 0,
      totalWords: totalWords,
    ));

    // 3. Domain Classification (Phase 15: domain-aware thresholds)
    final textDomain = _domainClassifier.classify(normDoc.normalizedText);
    final aiThreshold = _domainClassifier.aiThreshold(textDomain);

    // 4. AI Authorship Stylometric Analysis
    final aiResult = _aiService.auditText(normDoc.normalizedText);
    _stylometricExtractor.extract(segDoc); // extract for side-effects on subfeatures

    // Progressive Chunk Status Update
    int processedWords = 0;
    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      processedWords += chunk.wordCount;
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final avgMsPerChunk = (i == 0) ? 22 : (elapsedMs / i).round().clamp(5, 500);
      final remainingChunks = totalChunks - (i + 1);
      final estRemainingMs = (remainingChunks * avgMsPerChunk).clamp(0, 100000);
      final estTotalMs = elapsedMs + estRemainingMs;

      onProgress?.call(ForensicProgress(
        currentChunk: i + 1,
        totalChunks: totalChunks,
        progressRatio: (i + 1) / (totalChunks + 0.3),
        elapsed: stopwatch.elapsed,
        estimatedRemaining: Duration(milliseconds: estRemainingMs),
        estimatedTotal: Duration(milliseconds: estTotalMs),
        stage: totalChunks > 1
            ? 'Analyzing chunk ${i + 1} of $totalChunks (${chunk.wordCount} words)...'
            : 'Auditing stylometric patterns...',
        wordsProcessed: processedWords,
        totalWords: totalWords,
      ));
    }

    // 5. Sliding Window Segmentation & Style Shift Analysis
    final windowResult = _windowAnalyzer.analyze(segDoc);

    // 6. Source & Repetition Analysis
    final sourceResult = _sourceService.analyzeText(normDoc.normalizedText);

    // Domain-aware threshold adjustment.
    final calibratedAiProb = domainCalibrate(aiResult.aiProbability, aiThreshold);

    // 7. Construct AI Authorship Evidence (with domain-calibrated probability)
    var authorshipClass = _mapAuthorshipClass(aiResult.authorshipClass);
    // Re-evaluate authorship class against domain-aware threshold
    if (segDoc.totalWordCount < 40) {
      authorshipClass = AuthorshipClass.inconclusive;
    } else if (calibratedAiProb >= _calibration.aiModerateThreshold) {
      authorshipClass = AuthorshipClass.likelyAi;
    } else if (calibratedAiProb <= _calibration.aiLowThreshold) {
      authorshipClass = AuthorshipClass.likelyHuman;
    } else if (windowResult.isMixedOrEdited && authorshipClass != AuthorshipClass.inconclusive) {
      authorshipClass = AuthorshipClass.mixedOrEdited;
    }

    final aiSignals = aiResult.detectedSignals.map((s) {
      return AiSignalItem(
        family: s.family,
        name: s.name,
        score: s.score,
        weight: 1.0,
        description: s.description,
      );
    }).toList();

    // Add domain-aware signal
    if (textDomain != TextDomain.generalProse) {
      aiSignals.insert(0, AiSignalItem(
        family: 'Domain',
        name: 'Domain: ${_domainClassifier.domainLabel(textDomain)}',
        score: calibratedAiProb,
        weight: 0.5,
        description: 'Domain-aware thresholds applied: ${_domainClassifier.domainLabel(textDomain)} text has higher formulaic baseline.',
      ));
    }

    // Phase 4: Multi-Language Forensics Profile
    final langCode = isCyrillicProse ? 'ru' : LanguageDetector.detect(hardenedText);
    final langProfile = MultilingualProfiles.forCode(langCode);
    if (langCode != 'en') {
      final languages = neuralLanguages ?? _neuralLanguages;
      final covered = languages.contains(langCode) && neuralCovers(rawText, languages: languages);
      aiSignals.insert(0, AiSignalItem(
        family: 'Language',
        name: 'Language Profile: ${langProfile.languageName}',
        score: langProfile.expectedAiThreshold,
        weight: 0.8,
        description: 'Multilingual baseline: ${langProfile.languageName} profile active with tailored stylometric thresholds.'
            '${covered ? '' : ' ${_neuralCoverageNote(languages, langProfile.languageName)}'}',
      ));
    }

    for (final shift in windowResult.styleShifts) {
      aiSignals.add(
        AiSignalItem(
          family: 'StyleShift',
          name: shift.type.label,
          score: (shift.distance * 100.0).clamp(0.0, 100.0),
          weight: _calibration.signalWeights['styleShift'] ?? 1.2,
          description: shift.description,
        ),
      );
    }

    // Phase 16: Structural fingerprint score (invariant to synonym substitution)
    final sentenceTexts = segDoc.sentences.map((s) => s.text).toList();
    final structuralScore = _structuralDetector.computeStructuralAiScore(sentenceTexts);
    final fragmentationScore = _structuralDetector.detectFragmentation(sentenceTexts);
    if (structuralScore > 30.0 || fragmentationScore > 0.2) {
      aiSignals.add(AiSignalItem(
        family: 'StructuralFingerprint',
        name: 'Structural AI Pattern',
        score: math.max(structuralScore, fragmentationScore * 100.0),
        weight: _calibration.signalWeights['structural'] ?? 1.1,
        description: 'Structural analysis detected uniform opener templates, '
            'length periodicity, or clause symmetry — invariant to synonym substitution.',
      ));
    }

    // Phase 16: Homoglyph signal
    if (homoResult.replacements > 0) {
      aiSignals.add(AiSignalItem(
        family: 'Adversarial',
        name: 'Unicode Homoglyph Substitution',
        score: 95.0,
        weight: _calibration.signalWeights['homoglyph'] ?? 2.0,
        description: '${homoResult.replacements} Unicode confusable character(s) detected and normalized. '
            'This pattern is strongly correlated with deliberate obfuscation attempts.',
      ));
    }

    // Pillar 4: Statistical LLM Watermark Detection (Kirchenbauer z-score & SynthID periodicity)
    if (enableWatermarkDetection) {
      final watermarkResult = _watermarkDetector.analyze(normDoc.normalizedText);
      if (watermarkResult.isSuspicious) {
        aiSignals.add(AiSignalItem(
          family: 'Watermark',
          name: watermarkResult.detectedType == WatermarkType.synthId
              ? 'Spectral Periodicity (SynthID)'
              : 'Green-List Statistical Watermark (z=${watermarkResult.kirchenbauerZScore.toStringAsFixed(1)})',
          score: (watermarkResult.watermarkProbability * 100.0).clamp(0.0, 100.0),
          weight: _calibration.signalWeights['watermark'] ?? 1.8,
          description: watermarkResult.interpretation,
        ));
      }
    }

    // Token Predictability & Perplexity Distribution (Autoregressive language modeling)
    final tokenPredictability = _tokenPredictabilityAnalyzer.analyze(segDoc);
    if (tokenPredictability.predictabilityScore > 50.0 || tokenPredictability.rareTailPercentage < 6.0) {
      aiSignals.add(AiSignalItem(
        family: 'Predictability',
        name: 'Autoregressive Token Distribution',
        score: tokenPredictability.predictabilityScore,
        weight: _calibration.signalWeights['predictability'] ?? 1.25,
        description: tokenPredictability.defensibleSummary,
      ));
    }

    final aiEvidence = AiAuthorshipEvidence(
      aiProbability: calibratedAiProb,
      humanProbability: (100.0 - calibratedAiProb).clamp(0.0, 100.0),
      authorshipClass: authorshipClass,
      uncertainty: aiResult.uncertainty,
      detectedSignals: aiSignals,
      windows: windowResult.windows,
      featureVector: aiResult.featureVector,
      defensibleSummary: windowResult.isMixedOrEdited
          ? '${aiResult.defensibleSummary} ${windowResult.summary}'
          : aiResult.defensibleSummary,
    );

    // 6. Construct Real External Source Similarity Evidence
    final realSourceEvidence = _similarityService.analyzeDocument(normDoc.normalizedText);
    final sourceEvidence = realSourceEvidence.matches.isNotEmpty
        ? realSourceEvidence
        : const SourceSimilarityEvidence.clean();

    // 7. Construct Internal Repetition Evidence
    final repetitionEvidence = InternalRepetitionEvidence(
      repetitionScore: sourceResult.ngramOverlapScore,
      lexicalRichness: sourceResult.lexicalRichness,
      repeatedNgrams: sourceResult.repeatedNgrams,
      flaggedBoilerplates: sourceResult.flaggedBoilerplates,
      defensibleSummary: sourceResult.flaggedBoilerplates.isNotEmpty
          ? 'Found ${sourceResult.flaggedBoilerplates.length} academic/formulaic boilerplate phrase(s).'
          : 'Natural sentence-to-sentence vocabulary progression.',
    );

    // 7.5 Compute Preliminary Sentence Attribution Consensus (Bottom-up evidence)
    SentenceConsensusSummary? sentenceConsensus;
    if (segDoc.sentences.length >= 2) {
      final prelimSentenceBuild = _buildSentenceAudits(
        segDoc: segDoc,
        documentAiProbability: calibratedAiProb,
        windows: windowResult.windows,
        burstiness: aiResult.featureVector.length > 6 ? aiResult.featureVector[6] : 0.5,
        uncertainty: aiResult.uncertainty,
      );
      final prelimProbs = prelimSentenceBuild.audits.map((a) => a.aiProbability).toList();
      final prelimTellsCount = prelimSentenceBuild.audits.where((a) => a.detectedTells.isNotEmpty).length;
      final meanScore = prelimProbs.reduce((a, b) => a + b) / prelimProbs.length;
      final tellDensity = prelimTellsCount / prelimProbs.length;
      final highCount = prelimProbs.where((p) => p >= 65.0).length / prelimProbs.length;
      final cleanCount = prelimProbs.where((p) => p < 35.0).length / prelimProbs.length;

      sentenceConsensus = SentenceConsensusSummary(
        meanAiProbability: meanScore,
        tellDensity: tellDensity,
        highConfidenceAiRatio: highCount,
        cleanSentenceRatio: cleanCount,
      );
    }

    // 8. Evidence Fusion & Calibrated Uncertainty Assessment
    final fusion = _fusionEngine.fuse(
      document: segDoc,
      aiEvidence: aiEvidence,
      sourceEvidence: sourceEvidence,
      repetitionEvidence: repetitionEvidence,
      windowResult: windowResult,
      structuralScore: structuralScore,
      tokenPredictability: tokenPredictability,
      sentenceConsensus: sentenceConsensus,
      mode: mode,
      sensitivity: sensitivity,
    );

    // 9. Build Forensic Spans, CUSUM analysis, and Sentence Audits
    final spans = <ForensicSpan>[];
    final sentenceBuild = _buildSentenceAudits(
      segDoc: segDoc,
      documentAiProbability: fusion.calibratedAiProbability,
      windows: windowResult.windows,
      burstiness: aiResult.featureVector.length > 6 ? aiResult.featureVector[6] : 0.5,
      uncertainty: aiResult.uncertainty,
    );
    final sentenceAudits = sentenceBuild.audits;
    final sentenceAiProbs = sentenceBuild.probabilities;
    spans.addAll(sentenceBuild.spans);

    // CUSUM: detect authorship drift changepoints (Phase 4)
    final changepoints = _cusumDetector.detectChangepoints(sentenceAiProbs);
    for (final cpIdx in changepoints) {
      if (cpIdx < segDoc.sentences.length) {
        final cpSent = segDoc.sentences[cpIdx];
        spans.add(ForensicSpan(
          id: 'cusum_drift_$cpIdx',
          startOffset: cpSent.rawStartOffset,
          endOffset: cpSent.rawEndOffset,
          text: cpSent.text,
          type: SpanForensicType.styleAnomaly,
          severity: SpanSeverity.moderate,
          confidence: 0.80,
          label: 'Authorship Style Drift',
          explanation: 'CUSUM analysis detected a stylometric shift at this sentence — likely an authorship mode transition.',
        ));
      }
    }

    // Mixed authorship boost from CUSUM
    final cusumMixedConfidence = _cusumDetector.mixedAuthorshipConfidence(sentenceAiProbs);
    if (cusumMixedConfidence > 0.5 && authorshipClass != AuthorshipClass.inconclusive) {
      // CUSUM confirms mixed authorship — override if not already set
      if (authorshipClass == AuthorshipClass.likelyAi) {
        // Leave as-is — could be uniformly AI
      }
    }

    // Include localized window spans for high AI concentration regions
    spans.addAll(windowResult.mixedSpans);

    // Include external source similarity spans
    for (final sm in sourceEvidence.matches) {
      spans.add(
        ForensicSpan(
          id: 'source_span_${spans.length}',
          startOffset: normDoc.mapper.toRawOffset(sm.documentStartOffset),
          endOffset: normDoc.mapper.toRawOffset(sm.documentEndOffset),
          text: sm.matchedText,
          type: sm.matchType == SourceMatchType.fuzzyParaphrase ||
                  sm.matchType == SourceMatchType.semantic ||
                  sm.citationStatus == CitationStatus.quotedAndCited ||
                  sm.citationStatus == CitationStatus.cited
              ? SpanForensicType.sourceParaphrase
              : SpanForensicType.sourceExact,
          severity: sm.citationStatus == CitationStatus.uncited
              ? SpanSeverity.critical
              : SpanSeverity.low,
          confidence: sm.similarityPercent / 100.0,
          label: sm.sourceTitle,
          explanation: sm.citationStatus == CitationStatus.uncited
              ? '${sm.matchType.label} (${sm.similarityPercent.toStringAsFixed(0)}% aligned) with an external source, without citation.'
              : 'External source matched with ${sm.citationStatus.label}.',
        ),
      );
    }

    // 10. Adversarial Evasion Inspection & De-cloaking
    final adversarialEvidence = _obfuscationDetector.inspect(rawText);
    if (adversarialEvidence.evasionAttemptDetected) {
      spans.add(
        ForensicSpan(
          id: 'adversarial_evasion_span',
          startOffset: 0,
          endOffset: rawText.length,
          text: rawText.length > 60 ? '${rawText.substring(0, 60)}...' : rawText,
          type: SpanForensicType.styleAnomaly,
          severity: SpanSeverity.critical,
          confidence: 0.96,
          label: 'Adversarial De-cloaking Alert',
          explanation: adversarialEvidence.defensibleSummary,
        ),
      );
    }

    // 11. Dense Semantic Vector Paraphrase Detection
    final denseMatches = _denseSemanticMatcher.findParaphrases(
      document: segDoc,
      repository: SourceRepository.baselineLiterature,
    );
    for (final dm in denseMatches) {
      if (dm.sentenceIndex < segDoc.sentences.length) {
        final sent = segDoc.sentences[dm.sentenceIndex];
        // Already explained by the aligned source evidence above.
        final alreadyCovered = sourceEvidence.matches.any((m) {
          final start = normDoc.mapper.toRawOffset(m.documentStartOffset);
          final end = normDoc.mapper.toRawOffset(m.documentEndOffset);
          return start < sent.rawEndOffset && end > sent.rawStartOffset;
        });
        if (alreadyCovered) continue;
        spans.add(
          ForensicSpan(
            id: 'dense_paraphrase_${dm.sentenceIndex}',
            startOffset: sent.rawStartOffset,
            endOffset: sent.rawEndOffset,
            text: sent.text,
            type: SpanForensicType.sourceParaphrase,
            severity: dm.similarityPercent > 85.0 ? SpanSeverity.high : SpanSeverity.moderate,
            confidence: dm.similarityPercent / 100.0,
            label: 'Paraphrase: ${dm.sourceTitle}',
            explanation: 'Dense semantic alignment (${dm.similarityPercent.toStringAsFixed(1)}%) with "${dm.sourceTitle}".',
          ),
        );
      }
    }

    stopwatch.stop();

    // 13. Generate text hash & metadata
    final textHash = sha256.convert(utf8.encode(rawText)).toString();
    final metadata = ForensicReportMetadata(
      analysisId: 'forensic_${DateTime.now().millisecondsSinceEpoch}_${textHash.substring(0, 8)}',
      textHash: textHash,
      analyzedAt: DateTime.now(),
      engineVersion: '3.5.0',
      featureSchemaVersion: '3.5',
      executionDuration: stopwatch.elapsed,
      scanMode: mode,
      sensitivity: sensitivity,
    );

    final finalAiEvidence = AiAuthorshipEvidence(
      aiProbability: fusion.calibratedAiProbability,
      humanProbability: (100.0 - fusion.calibratedAiProbability).clamp(0.0, 100.0),
      authorshipClass: segDoc.totalWordCount < 40
          ? AuthorshipClass.inconclusive
          : fusion.calibratedAuthorshipClass,
      uncertainty: aiEvidence.uncertainty,
      detectedSignals: aiEvidence.detectedSignals,
      windows: aiEvidence.windows,
      featureVector: aiEvidence.featureVector,
      defensibleSummary: aiEvidence.defensibleSummary,
    );

    onProgress?.call(ForensicProgress(
      currentChunk: totalChunks,
      totalChunks: totalChunks,
      progressRatio: 1.0,
      elapsed: stopwatch.elapsed,
      estimatedRemaining: Duration.zero,
      estimatedTotal: stopwatch.elapsed,
      stage: 'Forensic audit completed',
      wordsProcessed: totalWords,
      totalWords: totalWords,
    ));

    return ForensicReport(
      metadata: metadata,
      rawText: rawText,
      normalizedText: normDoc.normalizedText,
      wordCount: segDoc.totalWordCount,
      charCount: segDoc.totalCharCount,
      sentenceCount: segDoc.sentences.length,
      paragraphCount: segDoc.paragraphs.length,
      aiAuthorship: finalAiEvidence,
      sourceSimilarity: sourceEvidence,
      internalRepetition: repetitionEvidence,
      confidence: fusion.confidence,
      adversarialEvidence: adversarialEvidence,
      tokenPredictability: tokenPredictability,
      spans: spans,
      sentences: sentenceAudits,
      summary: adversarialEvidence.evasionAttemptDetected
          ? '${adversarialEvidence.defensibleSummary} ${fusion.executiveSummary}'
          : fusion.executiveSummary,
    );
  }

  /// Runs asynchronous dual-stream forensic analysis combining the Neural Transformer
  /// detector with the 38-feature statistical engine and evidence fusion.
  /// Whether a transformer trained on [languages] (its config's
  /// `supportedLanguages`) can score [text]. On other languages its output is
  /// meaningless, so callers skip it and keep the language-profiled
  /// stylometric report.
  ///
  /// English is decided by the calibrated, conservative
  /// [LanguageDetector.isEnglish]; other languages by [LanguageDetector.detect].
  /// Text that `detect` calls English but `isEnglish` rejects is not covered.
  static bool neuralCovers(String text, {Set<String> languages = const {'en'}}) {
    if (LanguageDetector.isEnglish(text)) return languages.contains('en');
    if (languages.every((l) => l == 'en')) return false;
    final lang = LanguageDetector.detect(text);
    return lang != 'en' && languages.contains(lang);
  }

  static bool _englishOnly(Set<String> languages) => languages.length == 1 && languages.contains('en');

  static String _neuralCoverageNote(Set<String> languages, String languageName) => _englishOnly(languages)
      ? 'The neural transformer is trained on English only, so this text is scored by stylometry alone.'
      : 'The neural transformer does not cover $languageName, so this text is scored by stylometry alone.';

  Future<ForensicReport> analyzeWithNeural(
    String rawText, {
    NeuralDetectorService? neuralDetector,
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
    bool enableOnlineSearch = true,
    bool enableWatermarkDetection = true,
    bool enableHomoglyphDetection = true,
    void Function(ForensicProgress)? onProgress,
  }) async {
    final activeNeural = neuralDetector ?? _neuralDetector;
    NeuralDetectionResult neuralResult = NeuralDetectionResult.fallback(
      error: 'Neural detector service unconfigured',
    );

    final languages = activeNeural?.config.supportedLanguages ?? _neuralLanguages;
    if (activeNeural != null && !neuralCovers(rawText, languages: languages)) {
      neuralResult = NeuralDetectionResult.fallback(
        error: _englishOnly(languages)
            ? 'Neural detector covers English only'
            : 'Neural detector does not cover this language',
      );
    } else if (activeNeural != null) {
      try {
        neuralResult = await activeNeural.analyze(text: rawText);
      } catch (e) {
        neuralResult = NeuralDetectionResult.fallback(error: e.toString());
      }
    }

    // Run base analysis
    final syncReport = analyze(
      rawText,
      neuralLanguages: languages,
      mode: mode,
      sensitivity: sensitivity,
      enableOnlineSearch: enableOnlineSearch,
      enableWatermarkDetection: enableWatermarkDetection,
      enableHomoglyphDetection: enableHomoglyphDetection,
      onProgress: onProgress,
    );

    return fuseWithNeural(syncReport, neuralResult, mode: mode, sensitivity: sensitivity);
  }

  /// Re-fuses a statistical [baseReport] with a trained-model [neuralResult]
  /// via the stacked dual-stream fusion, re-deriving sentence audits from the
  /// fused probability. Returns [baseReport] unchanged when the neural stream
  /// fell back, so callers can apply it unconditionally.
  ForensicReport fuseWithNeural(
    ForensicReport baseReport,
    NeuralDetectionResult neuralResult, {
    ForensicScanMode mode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
  }) {
    if (neuralResult.isFallback) return baseReport;

    final normDoc = _normalizer.normalize(HomoglyphNormalizer.normalize(baseReport.rawText).normalized);
    final segDoc = _segmenter.segment(normDoc);
    final windowResult = _windowAnalyzer.analyze(segDoc);
    final base = baseReport.aiAuthorship;

    final fusion = _fusionEngine.fuseDualStream(
      document: segDoc,
      neuralResult: neuralResult,
      forensicEvidence: base,
      sourceEvidence: baseReport.sourceSimilarity,
      repetitionEvidence: baseReport.internalRepetition,
      windowResult: windowResult,
      structuralScore: _structuralDetector.computeStructuralAiScore(segDoc.sentences.map((s) => s.text).toList()),
      tokenPredictability: baseReport.tokenPredictability,
      mode: mode,
      sensitivity: sensitivity,
    );

    final signals = [
      AiSignalItem(
        family: 'Neural',
        name: 'Lauvira Transformer Classifier (${neuralResult.modelVersion})',
        score: neuralResult.percentage,
        weight: fusion.neuralWeight,
        description: 'On-device trained transformer scored ${neuralResult.percentage.toStringAsFixed(0)}% AI likelihood; '
            'fused with the ${base.aiProbability.toStringAsFixed(0)}% stylometric estimate by calibrated stacking.',
      ),
      ...base.detectedSignals,
    ];

    final finalAiEvidence = AiAuthorshipEvidence(
      aiProbability: fusion.calibratedAiProbability,
      humanProbability: (100.0 - fusion.calibratedAiProbability).clamp(0.0, 100.0),
      authorshipClass: segDoc.totalWordCount < 40 ? AuthorshipClass.inconclusive : fusion.calibratedAuthorshipClass,
      uncertainty: base.uncertainty,
      detectedSignals: signals,
      windows: base.windows,
      featureVector: base.featureVector,
      defensibleSummary: base.defensibleSummary,
    );

    final sentenceBuild = _buildSentenceAudits(
      segDoc: segDoc,
      documentAiProbability: fusion.calibratedAiProbability,
      windows: base.windows,
      burstiness: base.featureVector.length > 6 ? base.featureVector[6] : 0.5,
      uncertainty: base.uncertainty,
    );

    return ForensicReport(
      metadata: baseReport.metadata,
      rawText: baseReport.rawText,
      normalizedText: baseReport.normalizedText,
      wordCount: baseReport.wordCount,
      charCount: baseReport.charCount,
      sentenceCount: baseReport.sentenceCount,
      paragraphCount: baseReport.paragraphCount,
      aiAuthorship: finalAiEvidence,
      sourceSimilarity: baseReport.sourceSimilarity,
      internalRepetition: baseReport.internalRepetition,
      confidence: fusion.confidence,
      adversarialEvidence: baseReport.adversarialEvidence,
      tokenPredictability: baseReport.tokenPredictability,
      spans: baseReport.spans,
      sentences: sentenceBuild.audits,
      summary: fusion.executiveSummary,
    );
  }

  AuthorshipClass _mapAuthorshipClass(AiAuthorshipClass c) {
    switch (c) {
      case AiAuthorshipClass.likelyHuman:
        return AuthorshipClass.likelyHuman;
      case AiAuthorshipClass.mixedOrEdited:
        return AuthorshipClass.mixedOrEdited;
      case AiAuthorshipClass.likelyAi:
        return AuthorshipClass.likelyAi;
      case AiAuthorshipClass.inconclusive:
        return AuthorshipClass.inconclusive;
      case AiAuthorshipClass.uncertain:
        return AuthorshipClass.uncertain;
    }
  }

  /// Rebuilds sentence-level audits on the main thread from an isolate-deserialized
  /// [ForensicReport]. Sentences reference [PlagiarismRiskLevel] which contains Flutter
  /// [Color] objects and cannot cross isolate boundaries.
  ForensicReport rebuildSentences(ForensicReport isolateReport) {
    final normDoc = _normalizer.normalize(HomoglyphNormalizer.normalize(isolateReport.rawText).normalized);
    final segDoc = _segmenter.segment(normDoc);
    final ai = isolateReport.aiAuthorship;

    // Same attribution model as analyze(), so a document scores identically
    // whether or not it crossed the isolate boundary.
    final sentenceBuild = _buildSentenceAudits(
      segDoc: segDoc,
      documentAiProbability: ai.aiProbability,
      windows: ai.windows,
      burstiness: ai.featureVector.length > 6 ? ai.featureVector[6] : 0.5,
      uncertainty: ai.uncertainty,
    );

    return ForensicReport(
      metadata: isolateReport.metadata,
      rawText: isolateReport.rawText,
      normalizedText: isolateReport.normalizedText,
      wordCount: isolateReport.wordCount,
      charCount: isolateReport.charCount,
      sentenceCount: isolateReport.sentenceCount,
      paragraphCount: isolateReport.paragraphCount,
      aiAuthorship: isolateReport.aiAuthorship,
      sourceSimilarity: isolateReport.sourceSimilarity,
      internalRepetition: isolateReport.internalRepetition,
      confidence: isolateReport.confidence,
      // Not carried through the isolate JSON; both are cheap to recompute.
      adversarialEvidence: isolateReport.adversarialEvidence ?? _obfuscationDetector.inspect(isolateReport.rawText),
      tokenPredictability: isolateReport.tokenPredictability ?? _tokenPredictabilityAnalyzer.analyze(segDoc),
      spans: isolateReport.spans,
      sentences: sentenceBuild.audits,
      summary: isolateReport.summary,
    );
  }

  /// Monotone, continuous domain calibration.
  ///
  /// Maps the domain's own AI threshold onto the general-prose decision point
  /// (65) piecewise-linearly: [0, threshold] → [0, 65] and
  /// [threshold, 100] → [65, 100]. Formulaic domains (legal, medical) are
  /// pulled down, creative writing is pushed up, and — unlike the previous
  /// band-limited multiplier — a higher raw score can never produce a lower
  /// calibrated one.
  @visibleForTesting
  static double domainCalibrate(double raw, double domainThreshold) {
    const pivot = 65.0;
    final t = domainThreshold.clamp(1.0, 99.0);
    final x = raw.clamp(0.0, 100.0);
    if (x <= t) return x * pivot / t;
    return pivot + (x - t) * (100.0 - pivot) / (100.0 - t);
  }

  PlagiarismRiskLevel _sentenceRisk(double p) {
    if (p < _calibration.aiCleanThreshold) return PlagiarismRiskLevel.clean;
    if (p < _calibration.aiLowThreshold) return PlagiarismRiskLevel.low;
    if (p < _calibration.aiModerateThreshold) return PlagiarismRiskLevel.moderate;
    if (p < _calibration.aiHighThreshold) return PlagiarismRiskLevel.high;
    return PlagiarismRiskLevel.critical;
  }

  ({List<SentenceAudit> audits, List<double> probabilities, List<ForensicSpan> spans}) _buildSentenceAudits({
    required SegmentedDocument segDoc,
    required double documentAiProbability,
    required List<AiWindowAssessment> windows,
    required double burstiness,
    required double uncertainty,
  }) {
    final sentences = segDoc.sentences;
    // Local prior: mean probability of the sliding windows covering each
    // sentence (only meaningful when the document was actually windowed).
    final localPriors = <double?>[];
    for (final sent in sentences) {
      if (windows.length < 2) {
        localPriors.add(null);
        continue;
      }
      double sum = 0.0;
      int count = 0;
      for (final w in windows) {
        if (sent.normStartOffset >= w.startOffset && sent.normStartOffset < w.endOffset) {
          sum += w.aiProbability;
          count++;
        }
      }
      localPriors.add(count > 0 ? sum / count : null);
    }

    final attributions = _sentenceModel.score(
      sentences.map((s) => s.text).toList(),
      documentAiProbability: documentAiProbability,
      localPriors: localPriors,
      documentBurstiness: burstiness,
    );

    final audits = <SentenceAudit>[];
    final probs = <double>[];
    final spans = <ForensicSpan>[];
    for (int i = 0; i < sentences.length; i++) {
      final sent = sentences[i];
      final attr = attributions[i];
      probs.add(attr.aiProbability / 100.0);
      audits.add(SentenceAudit(
        index: sent.index,
        text: sent.text,
        aiProbability: attr.aiProbability,
        riskLevel: _sentenceRisk(attr.aiProbability),
        detectedTells: attr.tells,
        wordCount: sent.wordCount,
        burstinessDelta: 0.0,
      ));
      if (attr.tells.isNotEmpty) {
        spans.add(ForensicSpan(
          id: 'span_${sent.index}',
          startOffset: sent.rawStartOffset,
          endOffset: sent.rawEndOffset,
          text: sent.text,
          type: SpanForensicType.aiPattern,
          severity: attr.aiProbability > 65.0 ? SpanSeverity.high : SpanSeverity.moderate,
          confidence: (1.0 - uncertainty).clamp(0.0, 1.0),
          label: attr.tells.first,
          explanation: 'Sentence-level evidence (${attr.tells.take(3).join(', ')}) '
              'updates the surrounding passage estimate to ${attr.aiProbability.toStringAsFixed(0)}% AI likelihood.',
        ));
      }
    }
    return (audits: audits, probabilities: probs, spans: spans);
  }

  /// Returns a safe empty [ForensicReport] used when analysis cannot be run
  /// (empty input, isolate failure, or any unrecoverable engine error).
  ForensicReport emptyReport({
    ForensicScanMode scanMode = ForensicScanMode.fullForensic,
    ForensicSensitivity sensitivity = ForensicSensitivity.balanced,
  }) =>
      ForensicReport.empty();

}

