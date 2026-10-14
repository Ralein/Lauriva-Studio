import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/source_plagiarism_service.dart';

void main() {
  group('10/10 Forensic Engine & Humanizer Benchmark Tests', () {
    const humanizer = AlgorithmicHumanizerService();
    final repository = SourceRepository();
    final sourceService = SourcePlagiarismService(repository: repository);
    final verifier = SemanticPreservationVerifier();

    test('SourceRepository contains expanded seminal baseline references', () {
      expect(repository.getDocument('academic_climate_change_ipcc'), isNotNull);
      expect(repository.getDocument('academic_dna_structure_watson_crick'), isNotNull);
      expect(repository.getDocument('literature_wealth_of_nations'), isNotNull);
      expect(repository.getDocument('academic_bitcoin_nakamoto'), isNotNull);
      expect(repository.getDocument('academic_cryptography_diffie_hellman'), isNotNull);
      expect(repository.getDocument('academic_millers_law'), isNotNull);
      expect(repository.getDocument('academic_crispr_cas9_doudna'), isNotNull);
      expect(repository.getDocument('literature_hamlet_soliloquy'), isNotNull);
      expect(repository.documentCount, greaterThanOrEqualTo(19));
    });

    test('SourcePlagiarismService flags verbatim excerpt from expanded corpus with high risk', () {
      const excerpt = 'It is unequivocal that human influence has warmed the atmosphere, ocean and land. '
          'Widespread and rapid changes in the atmosphere, ocean, cryosphere and biosphere have occurred. '
          'This presents a major challenge for contemporary environmental policy.';
      
      final result = sourceService.analyzeText(excerpt);
      expect(result.sourceMatches.isNotEmpty, isTrue);
      expect(result.sourceMatches.any((m) => m.sourceTitle.contains('Climate Change')), isTrue);
      expect(result.plagiarismRiskScore, greaterThanOrEqualTo(75.0));
    });

    test('SourcePlagiarismService flags Bitcoin whitepaper verbatim copy', () {
      const excerpt = 'A purely peer-to-peer version of electronic cash would allow online payments to be sent '
          'directly from one party to another without going through a financial institution. '
          'We evaluate this transaction framework in decentralized finance.';

      final result = sourceService.analyzeText(excerpt);
      expect(result.sourceMatches.isNotEmpty, isTrue);
      expect(result.sourceMatches.any((m) => m.sourceTitle.contains('Bitcoin')), isTrue);
      expect(result.plagiarismRiskScore, greaterThanOrEqualTo(75.0));
    });

    test('AlgorithmicHumanizerService detoxifies modern 2026 AI tropes seamlessly', () {
      const input = 'This discovery serves as a stark reminder that the technology lies at the intersection of '
          'science and society. It bears witness to human progress, in stark contrast to previous skepticism. '
          'The team plays an active role in development and has the capacity to innovate further.';

      final detoxed = humanizer.replaceAiStockPhrases(input);
      expect(detoxed.contains('serves as a stark reminder that'), isFalse);
      expect(detoxed.contains('reminds us that'), isTrue);
      expect(detoxed.contains('lies at the intersection of'), isFalse);
      expect(detoxed.contains('connects'), isTrue);
      expect(detoxed.contains('bears witness to'), isFalse);
      expect(detoxed.contains('shows'), isTrue);
      expect(detoxed.contains('in stark contrast to'), isFalse);
      expect(detoxed.contains('unlike'), isTrue);
      expect(detoxed.contains('plays an active role in'), isFalse);
      expect(detoxed.contains('actively helps'), isTrue);
      expect(detoxed.contains('has the capacity to'), isFalse);
      expect(detoxed.contains('can'), isTrue);
    });

    test('AlgorithmicHumanizerService strips "at the end of the day" and simplifies "with respect to"', () {
      const input = 'At the end of the day, we need clarity with respect to the new deployment guidelines.';
      final cleaned = humanizer.postProcess(input);
      expect(cleaned.toLowerCase().contains('at the end of the day'), isFalse);
      expect(cleaned.contains('regarding the new deployment'), isTrue);
    });

    test('SemanticPreservationVerifier safely preserves scientific numbers, ordinals, and camelCase brands', () {
      const original = 'On July 4th, OpenAI deployed GPT-4 to 15,000 beta users across 50 regions.';
      const humanized = 'On July fourth, OpenAI rolled out GPT-4 to 15000 beta testers in 50 areas.';

      final report = verifier.verify(originalText: original, humanizedText: humanized);
      expect(report.hasNumericalDrift, isFalse);
      expect(report.missingNumbers, isEmpty);
      expect(report.preservedEntities.contains('OpenAI'), isTrue);
      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
    });
  });
}
