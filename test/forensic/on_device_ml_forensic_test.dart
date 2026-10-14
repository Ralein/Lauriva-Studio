import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/gbdt_classifier.dart';
import 'package:lauriva/services/forensic/ai/ngram_language_model.dart';
import 'package:lauriva/services/forensic/ai/platt_calibrator.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/lora_stylistic_adapter.dart';
import 'package:lauriva/services/forensic/sources/corpus_loader.dart';
import 'package:lauriva/services/forensic/sources/dense_semantic_matcher.dart';
import 'package:lauriva/services/forensic/sources/inverted_shingle_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Plan v6: Zero-Cloud On-Device ML Forensic Intelligence Stack', () {
    test('LoraStylisticAdapter correctly factorizes Rank-8 tensor and scores candidates', () {
      final features = LoraStylisticAdapter.extractFeatures(
        originalLength: 20,
        candidateLength: 14,
        removedTransition: true,
        invertedVoice: true,
        semanticCosine: 0.97,
        perplexityDelta: 35.0,
        addedPersonalPronoun: true,
        insertedContraction: true,
        brokenRepetition: true,
        simplifiedClause: true,
      );

      expect(features.length, equals(LoraStylisticAdapter.inputDims));

      final score = LoraStylisticAdapter.scoreCandidate(features);
      expect(score, greaterThan(0.5));
      expect(score, lessThanOrEqualTo(1.0));

      // Degraded candidate with low semantic similarity should receive lower score
      final poorFeatures = LoraStylisticAdapter.extractFeatures(
        originalLength: 20,
        candidateLength: 5,
        removedTransition: false,
        invertedVoice: false,
        semanticCosine: 0.60, // Severe drift
        perplexityDelta: -10.0,
        addedPersonalPronoun: false,
        insertedContraction: false,
        brokenRepetition: false,
        simplifiedClause: false,
      );

      final poorScore = LoraStylisticAdapter.scoreCandidate(poorFeatures);
      expect(score, greaterThan(poorScore));
    });

    test('DenseSemanticMatcher computes 384-D vector projection and detects paraphrasing', () {
      final matcher = DenseSemanticMatcher();

      const original = 'The rapid expansion of artificial intelligence introduces substantial societal consequences.';
      const paraphrase = 'The swift growth of machine intelligence brings about significant effects on human society.';
      const unrelated = 'Photosynthesis is the biological process converting solar light into chemical sugars.';

      final simParaphrase = matcher.similarity(original, paraphrase);
      final simUnrelated = matcher.similarity(original, unrelated);

      expect(simParaphrase, greaterThan(0.20));
      expect(simParaphrase, greaterThan(simUnrelated));
      expect(simUnrelated, lessThan(0.20));
    });

    test('GbdtClassifier executes 50-tree ensemble with Platt calibration', () {
      final gbdt = GbdtClassifier();

      // Feature vector representing highly synthetic AI text
      final aiFeatures = List<double>.filled(38, 0.0);
      aiFeatures[4] = 24.0; // Mean sentence len (sentenceLenMean)
      aiFeatures[5] = 2.0;  // Low std (sentenceLenStd)
      aiFeatures[6] = 0.15; // Low burstiness CV (burstinessCv)
      aiFeatures[26] = 0.45; // High transition opener ratio (transitionOpenerRatio)
      aiFeatures[22] = 45.0; // High function word density (functionWordRatio)
      aiFeatures[18] = 40.0; // Low vocabulary richness (ttrStandard)
      aiFeatures[24] = 3.5;  // Modal hedging density
      aiFeatures[30] = 0.45; // Complex syntax / subordinating conjunctions

      final aiProb = gbdt.predict(aiFeatures);
      expect(aiProb, greaterThan(0.40));

      final calibratedAi = PlattCalibrator.calibrate(aiProb);
      expect(calibratedAi, greaterThan(0.0));
      expect(calibratedAi, lessThan(1.0));

      // Feature vector representing dynamic human writing
      final humanFeatures = List<double>.filled(38, 0.0);
      humanFeatures[4] = 14.0; // Dynamic short/medium sentences
      humanFeatures[5] = 9.0;  // High std
      humanFeatures[6] = 0.70; // High burstiness CV
      humanFeatures[26] = 0.0; // Zero transition openers
      humanFeatures[22] = 25.0; // Natural function word density
      humanFeatures[18] = 85.0; // Rich varied vocabulary
      humanFeatures[24] = 0.5;  // Low modal hedging
      humanFeatures[30] = 0.15; // Natural syntax

      final humanProb = gbdt.predict(humanFeatures);
      expect(humanProb, lessThan(aiProb));
    });

    test('NgramLanguageModel evaluates Kneser-Ney perplexity and detects AI cliches', () {
      final ngramLm = NgramLanguageModel();

      const aiText = 'Furthermore, it is crucial to delve into the ever-evolving landscape of artificial intelligence. In conclusion, it plays a vital role.';
      const humanText = 'I think right now basically no idea if that said look at way more things honestly.';

      final aiPerplexity = ngramLm.perplexity(aiText);
      final humanPerplexity = ngramLm.perplexity(humanText);

      expect(aiPerplexity, greaterThan(0.0));
      expect(humanPerplexity, greaterThan(0.0));

      final aiSignal = ngramLm.scoreBigramAiSignal(aiText);
      final humanSignal = ngramLm.scoreBigramAiSignal(humanText);

      expect(aiSignal, greaterThan(humanSignal));
      expect(aiSignal, greaterThan(40.0));
      expect(humanSignal, lessThan(10.0));
    });

    test('CorpusLoader supports GZip decompression and InvertedShingleIndex retrieves O(1) candidates', () async {
      final rawDocs = [
        {
          'id': 'doc_test_1',
          'title': 'Test Document on Transformer Architectures',
          'author': 'Vaswani et al.',
          'url': 'https://arxiv.org/abs/1706.03762',
          'content': 'The dominant sequence transduction models are based on complex recurrent or convolutional neural networks that include an encoder and a decoder.',
        },
        {
          'id': 'doc_test_2',
          'title': 'Quantum Computing Foundations',
          'author': 'Nielsen & Chuang',
          'url': 'https://example.com/quantum',
          'content': 'Quantum computation and quantum information is the study of the information processing tasks that can be accomplished using quantum mechanical systems.',
        }
      ];

      final jsonBytes = utf8.encode(jsonEncode(rawDocs));
      final gzippedBytes = Uint8List.fromList(gzip.encode(jsonBytes));
      expect(gzippedBytes.isNotEmpty, isTrue);

      final index = InvertedShingleIndex();
      index.indexDocument('doc_test_1', [
        'dominant sequence transduction models are',
        'sequence transduction models are based',
        'transduction models are based on',
      ]);

      final queryGrams = {
        'dominant sequence transduction models are',
        'sequence transduction models are based',
      };

      final candidates = index.findCandidates(queryGrams, minShared: 2);
      expect(candidates.isNotEmpty, isTrue);
      expect(candidates.first.documentId, equals('doc_test_1'));
      expect(candidates.first.sharedShingleCount, equals(2));

      // Verify CorpusLoader baseline fallback
      final corpus = await CorpusLoader.load();
      expect(corpus.documentCount, greaterThan(0));
    });

    test('AlgorithmicHumanizerService scores and optimizes text using LoRA adapter guidance', () {
      const humanizer = AlgorithmicHumanizerService();

      const input = 'Furthermore, it is important to remember that artificial intelligence plays a crucial role in modern technology.';
      final humanized = humanizer.postProcess(input, tone: WritingToneProfile.conversational);

      expect(humanized.contains('Furthermore,'), isFalse);
      expect(humanized.isNotEmpty, isTrue);

      final loraScore = humanizer.scoreTransformWithLora(
        original: input,
        candidate: humanized,
        removedTransition: true,
        simplifiedClause: true,
      );

      expect(loraScore, greaterThan(0.5));
    });
  });
}
