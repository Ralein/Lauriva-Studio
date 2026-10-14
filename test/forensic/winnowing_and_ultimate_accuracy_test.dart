import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/sources/match_tokenizer.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/winnowing_engine.dart';
import 'package:lauriva/services/source_plagiarism_service.dart';

void main() {
  group('10/10 Winnowing & Ultimate Plagiarism & Humanize Verification Tests', () {
    const winnowing = WinnowingEngine(k: 4, w: 4);
    const humanizer = AlgorithmicHumanizerService();
    final repository = SourceRepository();
    final sourceService = SourcePlagiarismService(repository: repository);
    final verifier = SemanticPreservationVerifier();

    test('WinnowingEngine provides mathematically guaranteed match detection', () {
      expect(winnowing.guaranteedDetectionThreshold, equals(7));

      const docA = 'The quick brown fox jumps over the lazy dog in the sunny afternoon.';
      const docB = 'Yesterday a quick brown fox jumps over the lazy dog near the river.';

      final queryTokens = MatchTokenizer.tokenize(docA);
      final sourceTokens = MatchTokenizer.tokenize(docB);

      final fpsA = winnowing.fingerprintTokens(queryTokens);
      final fpsB = winnowing.fingerprintTokens(sourceTokens);

      expect(fpsA.isNotEmpty, isTrue);
      expect(fpsB.isNotEmpty, isTrue);

      // Sparse footprint: fingerprints should be significantly fewer than total tokens
      expect(fpsA.length, lessThanOrEqualTo(queryTokens.length));

      // Shared fingerprint on the identical 9-word span
      final shared = fpsA.map((f) => f.hash).toSet().intersection(fpsB.map((f) => f.hash).toSet());
      expect(shared.isNotEmpty, isTrue);
    });

    test('SourceRepository has expanded seminal corpus with 24+ foundational papers', () {
      expect(repository.getDocument('academic_einstein_relativity'), isNotNull);
      expect(repository.getDocument('academic_bert_devlin'), isNotNull);
      expect(repository.getDocument('academic_mapreduce_dean'), isNotNull);
      expect(repository.getDocument('academic_darwin_species'), isNotNull);
      expect(repository.getDocument('literature_pride_and_prejudice'), isNotNull);
      expect(repository.documentCount, greaterThanOrEqualTo(24));
    });

    test('findCandidatesByWinnowing retrieves Einstein paper from sparse fingerprints', () {
      const excerpt = 'We will raise this conjecture to the status of a postulate, and also introduce another postulate, '
          'which is only apparently irreconcilable with the former, namely, that light is always propagated in empty space.';
      final tokens = MatchTokenizer.tokenize(excerpt);
      final fps = winnowing.fingerprintTokens(tokens);

      final candidates = repository.findCandidatesByWinnowing(fps, minShared: 1);
      expect(candidates.isNotEmpty, isTrue);
      expect(candidates.any((c) => c.documentId == 'academic_einstein_relativity'), isTrue);
    });

    test('SourcePlagiarismService detects verbatim copy from BERT and MapReduce', () {
      const bertExcerpt = 'Unlike recent language representation models, BERT is designed to pre-train deep bidirectional '
          'representations from unlabeled text by jointly conditioning on both left and right context in all layers. '
          'We evaluate this model across several NLP benchmarks.';
      final bertResult = sourceService.analyzeText(bertExcerpt);
      expect(bertResult.sourceMatches.isNotEmpty, isTrue);
      expect(bertResult.sourceMatches.any((m) => m.sourceTitle.contains('BERT')), isTrue);
      expect(bertResult.plagiarismRiskScore, greaterThanOrEqualTo(75.0));

      const mapReduceExcerpt = 'Users specify a map function that processes a key/value pair to generate a set of intermediate key/value pairs, '
          'and a reduce function that merges all intermediate values associated with the same intermediate key. '
          'This framework simplifies large-scale data engineering.';
      final mrResult = sourceService.analyzeText(mapReduceExcerpt);
      expect(mrResult.sourceMatches.isNotEmpty, isTrue);
      expect(mrResult.sourceMatches.any((m) => m.sourceTitle.contains('MapReduce')), isTrue);
      expect(mrResult.plagiarismRiskScore, greaterThanOrEqualTo(75.0));
    });

    test('AlgorithmicHumanizerService detoxifies extended 2026 AI tropes seamlessly', () {
      const input = 'In an effort to advance research, the team was spearheading the initiative. '
          'In the wake of recent developments, it is crucial to bear in mind that the overarching goal '
          'of the project marks a pivotal moment and has a profound impact on future research.';

      final detoxed = humanizer.replaceAiStockPhrases(input);
      expect(detoxed.contains('in an effort to'), isFalse);
      expect(detoxed.contains('spearheading the initiative'), isFalse);
      expect(detoxed.contains('in the wake of'), isFalse);
      expect(detoxed.contains('it is crucial to bear in mind that'), isFalse);
      expect(detoxed.contains('the overarching goal'), isFalse);
      expect(detoxed.contains('marks a pivotal moment'), isFalse);
      expect(detoxed.contains('a profound impact on'), isFalse);

      expect(detoxed.contains('leading the project'), isTrue);
      expect(detoxed.contains('After recent developments'), isTrue);
      expect(detoxed.contains('remember that'), isTrue);
      expect(detoxed.contains('the main goal'), isTrue);
      expect(detoxed.contains('marks a key moment'), isTrue);
      expect(detoxed.contains('a strong effect on'), isTrue);
    });

    test('SemanticPreservationVerifier rigorously protects equations, statistics, and citations', () {
      const original = 'According to Devlin et al. (2018), BERT achieved 80.5% GLUE score on 24 layers with 340M parameters.';
      const humanized = 'Devlin et al. (2018) showed that BERT reached 80.5% on the GLUE benchmark using 24 layers and 340M parameters.';

      final report = verifier.verify(originalText: original, humanizedText: humanized);
      expect(report.hasNumericalDrift, isFalse);
      expect(report.missingNumbers, isEmpty);
      expect(report.hasCitationLoss, isFalse);
      expect(report.missingCitations, isEmpty);
      expect(report.preservedEntities.contains('BERT'), isTrue);
      expect(report.preservedEntities.contains('GLUE'), isTrue);
      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
    });
  });
}
