import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/services/ai_forensic_service.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/sources/dense_semantic_matcher.dart';
import 'package:lauriva/services/forensic/sources/fuzzy_similarity_matcher.dart';
import 'package:lauriva/services/forensic/sources/online/source_query_generator.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';

void main() {
  group('SSS-Tier 10/10 Backend Upgrades', () {
    test('SourceQueryGenerator extracts exact quoted phrases for web search queries', () {
      const generator = SourceQueryGenerator(maxQueries: 2);
      const text = 'Photosynthesis converts solar energy into chemical sugars through complex chlorophyll cellular pathways. '
          'Researchers at Stanford University designed novel semiconductor transistors for quantum processing in 2025.';

      final queries = generator.generate(text);
      expect(queries, isNotEmpty);
      expect(queries.any((q) => q.exactPhrase != null && q.exactPhrase!.trim().isNotEmpty), isTrue);
    });

    test('DenseSemanticMatcher provides angular subword and SimHash semantic similarity', () {
      final matcher = DenseSemanticMatcher();
      const sentence1 = 'The automated system evaluates document text to detect unoriginal sources.';
      const sentence2 = 'The automated system evaluates document passages to detect unoriginal sources.';

      final similarity = matcher.similarity(sentence1, sentence2);
      expect(similarity, greaterThan(0.65));
    });

    test('FuzzySimilarityMatcher recognizes APA, IEEE ranges, and superscripts in citation context', () {
      final matcher = FuzzySimilarityMatcher();

      const apaText = 'Previous findings confirmed the hypothesis (Smith & Johnson, 2021).';
      final apaAnalysis = matcher.analyzeCitationContext(
        fullDocumentText: apaText,
        matchStartOffset: 0,
        matchEndOffset: 45,
      );
      expect(apaAnalysis.status, equals(CitationStatus.cited));

      const ieeeText = 'This methodology has been validated across multiple clinical trials [1–4].';
      final ieeeAnalysis = matcher.analyzeCitationContext(
        fullDocumentText: ieeeText,
        matchStartOffset: 0,
        matchEndOffset: 50,
      );
      expect(ieeeAnalysis.status, equals(CitationStatus.cited));

      const superscriptText = 'Recent advances in quantum annealing¹² have demonstrated polynomial speedup.';
      final superAnalysis = matcher.analyzeCitationContext(
        fullDocumentText: superscriptText,
        matchStartOffset: 0,
        matchEndOffset: 35,
      );
      expect(superAnalysis.status, equals(CitationStatus.cited));
    });

    test('SourceSimilarityService incorporates dense semantic matcher for spun paraphrasing', () {
      final repository = SourceRepository();
      final similarityService = SourceSimilarityService(repository: repository);

      const bitcoinSpun = 'A completely decentralized peer-to-peer form of electronic currency would enable online transactions to be dispatched directly from one party to another without passing through any banking institution.';
      final evidence = similarityService.analyzeDocument(bitcoinSpun);

      expect(evidence.matches.isNotEmpty, isTrue);
      expect(evidence.matches.any((m) => m.sourceTitle.contains('Bitcoin')), isTrue);
    });

    test('AlgorithmicHumanizerService dissolves faux-candor openers and passive copulas', () {
      const humanizer = AlgorithmicHumanizerService();

      const candorInput = "Here's the thing: we need to deliver results quickly. Honestly, the team is ready.";
      final candorResult = humanizer.dissolveFauxCandorOpeners(candorInput);
      expect(candorResult.contains("Here's the thing:"), isFalse);
      expect(candorResult.contains("Honestly,"), isFalse);
      expect(candorResult.startsWith('We need to deliver'), isTrue);

      const copulaInput = 'The benchmark serves as an indicator of performance and acts as a catalyst for optimization.';
      final copulaResult = humanizer.dissolvePassiveCopulas(copulaInput);
      expect(copulaResult.contains('indicates performance'), isTrue);
      expect(copulaResult.contains('drives optimization'), isTrue);
    });

    test('AlgorithmicHumanizerService postProcessWithQualityLoop verifies meaning guard and lowers AI risk', () {
      const humanizer = AlgorithmicHumanizerService();
      final forensic = AiForensicService();
      final verifier = SemanticPreservationVerifier();

      const aiText = 'Furthermore, the implementation of renewable energy plays a crucial role in combating climate change. '
          'By harnessing solar and wind power, communities can delve into sustainable practices that bolster economic resilience. '
          'It is important to note that Dr. Alice Smith oversaw 45 installations in 2024.';

      final result = humanizer.postProcessWithQualityLoop(
        aiText,
        originalText: aiText,
        forensicService: forensic,
        verifier: verifier,
      );

      final audit = forensic.auditText(result);
      expect(audit.aiProbability, lessThan(35.0));

      final guard = verifier.verify(originalText: aiText, humanizedText: result);
      expect(guard.missingNumbers, isEmpty);
      expect(guard.preservedEntities, contains('Smith'));
      expect(guard.hasPolarityDrift, isFalse);
    });
  });
}
