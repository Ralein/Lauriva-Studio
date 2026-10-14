import 'dart:math';
import '../../../models/forensic/ai_authorship_evidence.dart';
import '../../../models/forensic/forensic_span.dart';
import '../../../models/forensic/style_fingerprint.dart';
import '../../ai_forensic_service.dart';
import '../document/document_segmenter.dart';
import '../normalization/text_normalizer.dart';
import 'stylometric_feature_extractor.dart';

/// Result container for sliding window forensic analysis.
class SlidingWindowAnalysisResult {
  final List<AiWindowAssessment> windows;
  final List<StyleFingerprint> windowFingerprints;
  final List<StyleShift> styleShifts;
  final List<ForensicSpan> mixedSpans;
  final bool isMixedOrEdited;
  final double windowAiVariance;
  final double minWindowScore;
  final double maxWindowScore;
  final double meanWindowScore;
  final double topHalfWindowScore;
  final String summary;

  const SlidingWindowAnalysisResult({
    required this.windows,
    required this.windowFingerprints,
    required this.styleShifts,
    required this.mixedSpans,
    required this.isMixedOrEdited,
    required this.windowAiVariance,
    required this.minWindowScore,
    required this.maxWindowScore,
    this.meanWindowScore = 50.0,
    this.topHalfWindowScore = 50.0,
    required this.summary,
  });
}

/// Sliding window analyzer for multi-section documents.
/// Dissects documents into overlapping 100-150 word windows with 30-50 word overlap
/// to detect localized AI generation, human-edited AI drafts, and authorial shifts.
class SlidingWindowAnalyzer {
  final StylometricFeatureExtractor _featureExtractor;
  final AiForensicService _aiService;
  final int windowSizeWords;
  final int stepSizeWords;

  SlidingWindowAnalyzer({
    StylometricFeatureExtractor? featureExtractor,
    AiForensicService? aiService,
    this.windowSizeWords = 120,
    this.stepSizeWords = 60,
  })  : _featureExtractor = featureExtractor ?? StylometricFeatureExtractor(),
        _aiService = aiService ?? AiForensicService();

  /// Analyzes a [SegmentedDocument] through overlapping windows.
  SlidingWindowAnalysisResult analyze(SegmentedDocument doc) {
    final sentences = doc.sentences;
    final totalWords = doc.totalWordCount;

    // For very short documents (< 65 words or <= 2 sentences), evaluate as a single window
    if (totalWords < 65 || sentences.length <= 2) {
      final text = doc.normalizedDocument.normalizedText;
      final aiRes = _aiService.auditText(text);
      final ext = _featureExtractor.extract(doc);

      final singleWindow = AiWindowAssessment(
        windowIndex: 0,
        startToken: 0,
        endToken: totalWords,
        startOffset: 0,
        endOffset: text.length,
        aiProbability: aiRes.aiProbability,
        uncertainty: aiRes.uncertainty,
        summary: 'Single window assessment (${aiRes.authorshipClass.badge}).',
      );

      return SlidingWindowAnalysisResult(
        windows: [singleWindow],
        windowFingerprints: [ext.fingerprint],
        styleShifts: const [],
        mixedSpans: const [],
        isMixedOrEdited: false,
        windowAiVariance: 0.0,
        minWindowScore: aiRes.aiProbability,
        maxWindowScore: aiRes.aiProbability,
        meanWindowScore: aiRes.aiProbability,
        topHalfWindowScore: aiRes.aiProbability,
        summary: 'Document evaluated in a single window.',
      );
    }

    // Adapt window and step words for shorter vs multi-paragraph documents
    final effectiveWindowWords = totalWords >= 200 ? windowSizeWords : max(40, (totalWords * 0.55).round());
    final effectiveStepWords = totalWords >= 200 ? stepSizeWords : max(20, (effectiveWindowWords * 0.45).round());

    // Partition sentences into overlapping sliding windows
    final windowAssessments = <AiWindowAssessment>[];
    final fingerprints = <StyleFingerprint>[];
    final spans = <ForensicSpan>[];

    int windowIdx = 0;
    int sentStart = 0;

    while (sentStart < sentences.length) {
      int sentEnd = sentStart;
      int accumulatedWords = 0;

      while (sentEnd < sentences.length && accumulatedWords < effectiveWindowWords) {
        accumulatedWords += sentences[sentEnd].wordCount;
        sentEnd++;
      }

      final windowSentences = sentences.sublist(sentStart, sentEnd);
      final firstSent = windowSentences.first;
      final lastSent = windowSentences.last;

      final startOffset = firstSent.normStartOffset;
      final endOffset = lastSent.normEndOffset;
      final windowText = doc.normalizedDocument.normalizedText.substring(startOffset, endOffset).trim();

      // Mini segmented document for window stylometrics
      final miniNorm = NormalizedDocument(
        rawText: windowText,
        normalizedText: windowText,
        mapper: doc.normalizedDocument.mapper,
        metadata: doc.normalizedDocument.metadata,
      );
      final miniDoc = SegmentedDocument(
        normalizedDocument: miniNorm,
        sentences: windowSentences,
        paragraphs: doc.paragraphs.where((p) => p.rawStartOffset >= firstSent.rawStartOffset && p.rawEndOffset <= lastSent.rawEndOffset).toList(),
        totalWordCount: accumulatedWords,
        totalCharCount: windowText.length,
      );

      final windowAi = _aiService.auditText(windowText);
      final windowExt = _featureExtractor.extract(miniDoc);

      fingerprints.add(windowExt.fingerprint);

      final assessment = AiWindowAssessment(
        windowIndex: windowIdx,
        startToken: sentStart,
        endToken: sentEnd,
        startOffset: startOffset,
        endOffset: endOffset,
        aiProbability: windowAi.aiProbability,
        uncertainty: windowAi.uncertainty,
        summary: 'Window $windowIdx: ${windowAi.aiProbability.toStringAsFixed(1)}% AI (${windowAi.authorshipClass.badge})',
      );
      windowAssessments.add(assessment);

      // If window is strongly AI-like, create a suspicious span
      if (windowAi.aiProbability >= 65.0) {
        spans.add(
          ForensicSpan(
            id: 'window_span_$windowIdx',
            startOffset: doc.normalizedDocument.mapper.toRawOffset(startOffset),
            endOffset: doc.normalizedDocument.mapper.toRawOffset(endOffset),
            text: windowText,
            type: SpanForensicType.aiPattern,
            severity: windowAi.aiProbability >= 85.0 ? SpanSeverity.high : SpanSeverity.moderate,
            confidence: (1.0 - windowAi.uncertainty).clamp(0.0, 1.0),
            label: 'Sliding Window #$windowIdx (${windowAi.authorshipClass.badge})',
            explanation: 'High AI density region (${windowAi.aiProbability.toStringAsFixed(0)}% AI likelihood) with compressed syntactic variance.',
          ),
        );
      }

      // Advance by effectiveStepWords
      int advancedWords = 0;
      int nextSentStart = sentStart + 1;
      while (nextSentStart < sentences.length && advancedWords < effectiveStepWords) {
        advancedWords += sentences[nextSentStart].wordCount;
        nextSentStart++;
      }

      if (nextSentStart <= sentStart) {
        nextSentStart = sentStart + 1;
      }
      sentStart = nextSentStart;
      windowIdx++;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Track Style Shifts Between Adjacent Windows
    // ─────────────────────────────────────────────────────────────────────────
    final styleShifts = <StyleShift>[];
    for (int i = 0; i < windowAssessments.length - 1; i++) {
      final wA = windowAssessments[i];
      final wB = windowAssessments[i + 1];
      final fpA = fingerprints[i];
      final fpB = fingerprints[i + 1];

      final dist = fpA.distanceTo(fpB);
      final aiDiff = wB.aiProbability - wA.aiProbability;

      if (dist >= 0.40 || aiDiff.abs() >= 35.0) {
        StyleShiftType type = StyleShiftType.mixedTurbulence;
        String desc = 'Substantial stylistic distance (${dist.toStringAsFixed(2)}) between sections.';

        if (wA.aiProbability < 35.0 && wB.aiProbability >= 65.0) {
          type = StyleShiftType.humanToAi;
          desc = 'Transition detected: natural human prose shifts into formulaic AI generation.';
        } else if (wA.aiProbability >= 65.0 && wB.aiProbability < 35.0) {
          type = StyleShiftType.aiToHuman;
          desc = 'Transition detected: formulaic AI prose shifts into authentic human pacing.';
        }

        styleShifts.add(
          StyleShift(
            fromWindow: i,
            toWindow: i + 1,
            distance: dist,
            type: type,
            description: desc,
          ),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Determine Mixed / Human-Edited Classification
    // ─────────────────────────────────────────────────────────────────────────
    final aiScores = windowAssessments.map((w) => w.aiProbability).toList();
    final minScore = aiScores.reduce(min);
    final maxScore = aiScores.reduce(max);
    final meanScore = aiScores.reduce((a, b) => a + b) / aiScores.length;

    final sortedScores = List<double>.of(aiScores)..sort((a, b) => b.compareTo(a));
    final topHalfCount = max(1, (sortedScores.length / 2).ceil());
    final topHalfMean = sortedScores.take(topHalfCount).reduce((a, b) => a + b) / topHalfCount;

    double variance = 0.0;
    for (final s in aiScores) {
      final d = s - meanScore;
      variance += d * d;
    }
    variance /= aiScores.length;
    final stdDev = sqrt(variance);

    // Mixed condition: wide gap between min and max window, or elevated stdDev with both human & AI sections
    final hasHumanRegion = minScore < 35.0;
    final hasAiRegion = maxScore > 65.0;
    final isMixed = (hasHumanRegion && hasAiRegion) || (stdDev > 22.0 && styleShifts.isNotEmpty);

    String summary;
    if (isMixed) {
      summary = 'Document exhibits mixed authorship origin. Detected disparate sections with sharp stylistic transitions.';
    } else if (meanScore >= 65.0) {
      summary = 'Consistently uniform AI-generated characteristics across all ${windowAssessments.length} document windows.';
    } else if (meanScore <= 35.0) {
      summary = 'Consistently natural human stylometrics across all ${windowAssessments.length} document windows.';
    } else {
      summary = 'Moderate stylometric patterns distributed across ${windowAssessments.length} document windows.';
    }

    return SlidingWindowAnalysisResult(
      windows: windowAssessments,
      windowFingerprints: fingerprints,
      styleShifts: styleShifts,
      mixedSpans: spans,
      isMixedOrEdited: isMixed,
      windowAiVariance: variance,
      minWindowScore: minScore,
      maxWindowScore: maxScore,
      meanWindowScore: meanScore,
      topHalfWindowScore: topHalfMean,
      summary: summary,
    );
  }
}
