import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/ai_authorship_evidence.dart';
import 'package:lauriva/models/forensic/internal_repetition_evidence.dart';
import 'package:lauriva/models/forensic/neural_detection_result.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/services/forensic/ai/sliding_window_analyzer.dart';
import 'package:lauriva/services/forensic/document/document_segmenter.dart';
import 'package:lauriva/services/forensic/fusion/evidence_fusion_engine.dart';
import 'package:lauriva/services/forensic/fusion/fusion_config.dart';
import 'package:lauriva/services/forensic/normalization/text_normalizer.dart';

void main() {
  group('EvidenceFusionEngine Dual-Stream Tests', () {
    late EvidenceFusionEngine fusionEngine;
    late DocumentSegmenter segmenter;
    late TextNormalizer normalizer;

    setUp(() {
      fusionEngine = EvidenceFusionEngine(
        config: const FusionConfig(
          neuralBaseWeight: 0.75,
          minimumNeuralWeight: 0.15,
          maximumNeuralWeight: 0.85,
          fullContextWordCount: 150,
        ),
      );
      segmenter = DocumentSegmenter();
      normalizer = TextNormalizer();
    });

    SegmentedDocument createDoc(String text) {
      return segmenter.segment(normalizer.normalize(text));
    }

    test('neural weight scales smoothly with word count', () {
      final docShort = createDoc('Short five word text here.');
      final wShort = fusionEngine.calculateNeuralWeight(
        wordCount: docShort.totalWordCount,
        neuralUncertainty: 0.2,
        isFallback: false,
      );

      final docLong = createDoc(List.generate(200, (i) => 'word').join(' '));
      final wLong = fusionEngine.calculateNeuralWeight(
        wordCount: docLong.totalWordCount,
        neuralUncertainty: 0.2,
        isFallback: false,
      );

      expect(wShort, lessThan(wLong));
      expect(wShort, greaterThanOrEqualTo(0.15));
      expect(wLong, lessThanOrEqualTo(0.85));
    });

    test('dual consensus AI results in high calibrated AI probability', () {
      final text = 'Furthermore, technological innovation accelerates dynamic digital landscapes.';
      final doc = createDoc(text);

      const neural = NeuralDetectionResult(
        aiProbability: 0.92,
        uncertainty: 0.15,
        sentences: [],
        tokens: [],
        isFallback: false,
        modelVersion: 'omni_p3_int8',
        inferenceTime: Duration(milliseconds: 10),
      );

      const forensic = AiAuthorshipEvidence(
        aiProbability: 88.0,
        humanProbability: 12.0,
        authorshipClass: AuthorshipClass.likelyAi,
        uncertainty: 0.15,
        detectedSignals: [],
        windows: [],
        featureVector: [0.9],
        defensibleSummary: 'High AI probability',
      );

      final result = fusionEngine.fuseDualStream(
        document: doc,
        neuralResult: neural,
        forensicEvidence: forensic,
        sourceEvidence: const SourceSimilarityEvidence.clean(),
        repetitionEvidence: const InternalRepetitionEvidence(
          repetitionScore: 0.0,
          lexicalRichness: 0.8,
          repeatedNgrams: [],
          flaggedBoilerplates: [],
          defensibleSummary: '',
        ),
        windowResult: SlidingWindowAnalysisResult(
          windows: const [],
          windowFingerprints: const [],
          meanWindowScore: 88.0,
          maxWindowScore: 88.0,
          minWindowScore: 88.0,
          topHalfWindowScore: 88.0,
          windowAiVariance: 0.0,
          styleShifts: const [],
          isMixedOrEdited: false,
          summary: '',
          mixedSpans: const [],
        ),
      );

      expect(result.calibratedAiProbability, greaterThan(80.0));
      expect(result.calibratedAuthorshipClass, equals(AuthorshipClass.likelyAi));
      expect(result.isNeuralFallback, isFalse);
    });

    test('dual consensus Human results in low calibrated AI probability', () {
      final text = 'I went to the garden and saw blooming flowers in the fresh morning air.';
      final doc = createDoc(text);

      const neural = NeuralDetectionResult(
        aiProbability: 0.08,
        uncertainty: 0.10,
        sentences: [],
        tokens: [],
        isFallback: false,
        modelVersion: 'omni_p3_int8',
        inferenceTime: Duration(milliseconds: 10),
      );

      const forensic = AiAuthorshipEvidence(
        aiProbability: 12.0,
        humanProbability: 88.0,
        authorshipClass: AuthorshipClass.likelyHuman,
        uncertainty: 0.10,
        detectedSignals: [],
        windows: [],
        featureVector: [0.1],
        defensibleSummary: 'Human authorship',
      );

      final result = fusionEngine.fuseDualStream(
        document: doc,
        neuralResult: neural,
        forensicEvidence: forensic,
        sourceEvidence: const SourceSimilarityEvidence.clean(),
        repetitionEvidence: const InternalRepetitionEvidence(
          repetitionScore: 0.0,
          lexicalRichness: 0.9,
          repeatedNgrams: [],
          flaggedBoilerplates: [],
          defensibleSummary: '',
        ),
        windowResult: SlidingWindowAnalysisResult(
          windows: const [],
          windowFingerprints: const [],
          meanWindowScore: 12.0,
          maxWindowScore: 12.0,
          minWindowScore: 12.0,
          topHalfWindowScore: 12.0,
          windowAiVariance: 0.0,
          styleShifts: const [],
          isMixedOrEdited: false,
          summary: '',
          mixedSpans: const [],
        ),
      );

      expect(result.calibratedAiProbability, lessThan(25.0));
      expect(result.calibratedAuthorshipClass, equals(AuthorshipClass.likelyHuman));
    });

    test('divergent neural and forensic signals reduce confidence', () {
      final text = 'Test passage with divergent multi-stream signals.';
      final doc = createDoc(text);

      const neural = NeuralDetectionResult(
        aiProbability: 0.90,
        uncertainty: 0.15,
        sentences: [],
        tokens: [],
        isFallback: false,
        modelVersion: 'omni_p3_int8',
        inferenceTime: Duration(milliseconds: 10),
      );

      const forensic = AiAuthorshipEvidence(
        aiProbability: 15.0,
        humanProbability: 85.0,
        authorshipClass: AuthorshipClass.likelyHuman,
        uncertainty: 0.15,
        detectedSignals: [],
        windows: [],
        featureVector: [0.2],
        defensibleSummary: '',
      );

      final result = fusionEngine.fuseDualStream(
        document: doc,
        neuralResult: neural,
        forensicEvidence: forensic,
        sourceEvidence: const SourceSimilarityEvidence.clean(),
        repetitionEvidence: const InternalRepetitionEvidence(
          repetitionScore: 0.0,
          lexicalRichness: 0.8,
          repeatedNgrams: [],
          flaggedBoilerplates: [],
          defensibleSummary: '',
        ),
        windowResult: SlidingWindowAnalysisResult(
          windows: const [],
          windowFingerprints: const [],
          meanWindowScore: 15.0,
          maxWindowScore: 15.0,
          minWindowScore: 15.0,
          topHalfWindowScore: 15.0,
          windowAiVariance: 0.0,
          styleShifts: const [],
          isMixedOrEdited: false,
          summary: '',
          mixedSpans: const [],
        ),
      );

      // Uncertainty should be reflected in the confidence score
      expect(result.confidence.score, lessThan(0.90));
    });
  });
}
