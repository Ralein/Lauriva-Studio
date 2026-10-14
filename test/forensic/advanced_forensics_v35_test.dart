import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/plagiarism_report.dart';
import 'package:lauriva/services/forensic/ai/adversarial_obfuscation_detector.dart';
import 'package:lauriva/services/forensic/ai/token_predictability_analyzer.dart';
import 'package:lauriva/services/forensic/document/document_segmenter.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/normalization/text_normalizer.dart';
import 'package:lauriva/services/forensic/sources/dense_semantic_matcher.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';

void main() {
  group('Forensic Engine 3.5: Advanced Evasion, Token Map & Paraphrase Tests', () {
    late TextNormalizer normalizer;
    late DocumentSegmenter segmenter;
    late AdversarialObfuscationDetector detector;
    late TokenPredictabilityAnalyzer tokenAnalyzer;
    late DenseSemanticMatcher denseMatcher;
    late ForensicEngine engine;

    setUp(() {
      normalizer = TextNormalizer();
      segmenter = DocumentSegmenter();
      detector = AdversarialObfuscationDetector();
      tokenAnalyzer = TokenPredictabilityAnalyzer();
      denseMatcher = DenseSemanticMatcher();
      engine = ForensicEngine();
    });

    test('AdversarialObfuscationDetector detects Cyrillic homoglyphs and zero-width spaces', () {
      // "Artificial" with Cyrillic 'а' (U+0430) and zero-width space
      final obfuscated = '\u0430rtifici\u200Bal intelligence has experienced rapid growth.';
      final evidence = detector.inspect(obfuscated);

      expect(evidence.evasionAttemptDetected, isTrue);
      expect(evidence.homoglyphCount, greaterThanOrEqualTo(1));
      expect(evidence.hiddenCharacterCount, greaterThanOrEqualTo(1));
      expect(evidence.sanitizedText.startsWith('artifici'), isTrue);
      expect(evidence.techniquesDetected, contains(EvasionTechnique.homoglyphSubstitution));
      expect(evidence.techniquesDetected, contains(EvasionTechnique.zeroWidthInjection));
    });

    test('Clean prose reports zero adversarial evasion', () {
      const clean = 'This is a genuine, completely unadulterated essay written with authentic vocabulary.';
      final evidence = detector.inspect(clean);

      expect(evidence.evasionAttemptDetected, isFalse);
      expect(evidence.homoglyphCount, equals(0));
      expect(evidence.hiddenCharacterCount, equals(0));
    });

    test('TokenPredictabilityAnalyzer maps autoregressive LLM tokens into high Top-10 tier', () {
      const aiText = 'Artificial intelligence has experienced rapid proliferation in recent years, transforming numerous sectors across the globe. However, its widespread adoption has sparked intense debate regarding ethical considerations.';
      final norm = normalizer.normalize(aiText);
      final doc = segmenter.segment(norm);

      final report = tokenAnalyzer.analyze(doc);

      expect(report.tokens.isNotEmpty, isTrue);
      expect(report.top10Percentage, greaterThan(25.0));
      expect(report.top10Percentage + report.top100Percentage, greaterThanOrEqualTo(50.0));
      expect(report.predictabilityScore, greaterThan(35.0));
      expect(report.meanPerplexity, greaterThan(0.0));
    });

    test('DenseSemanticMatcher flags spun sentences with high cosine similarity', () {
      const spunPassage = 'In the domain of artificial intelligence, foundational models represent computational systems designed to generalize across divergent cognitive domains.';
      final norm = normalizer.normalize(spunPassage);
      final doc = segmenter.segment(norm);

      final customRepo = SourceRepository(loadDefaultCorpus: false);
      customRepo.addDocument(
        SourceCorpusDocument(
          id: 'test_doc_1',
          title: 'Foundational AI Architectures',
          category: SourceCategory.academic,
          content: 'In the domain of artificial intelligence, foundational models represent computational systems designed to generalize across divergent cognitive domains and tasks.',
        ),
      );

      final matches = denseMatcher.findParaphrases(
        document: doc,
        repository: customRepo,
        threshold: 0.80,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.similarityPercent, greaterThanOrEqualTo(80.0));
    });

    test('ForensicEngine produces unified report with tokenPredictability and adversarialEvidence', () {
      const text = 'Artificial intelligence has experienced unprecedented growth in recent years. However, its proliferation has sparked intense debate.';
      final report = engine.analyze(text);

      expect(report.tokenPredictability, isNotNull);
      expect(report.tokenPredictability!.tokens.length, greaterThan(10));
      expect(report.adversarialEvidence, isNotNull);
      expect(report.overallScore, greaterThan(65.0));
      expect(report.riskLevel, isIn([PlagiarismRiskLevel.high, PlagiarismRiskLevel.critical]));

      final legacy = report.toLegacyPlagiarismReport();
      expect(legacy.tokenPredictabilityReport, isNotNull);
      expect(legacy.adversarialEvidence, isNotNull);
    });
  });
}
