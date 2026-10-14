import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/sources/dense_semantic_matcher.dart';
import 'package:lauriva/services/forensic/sources/fuzzy_similarity_matcher.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';
import 'package:lauriva/services/text_forensics_lexicons.dart';

void main() {
  group('Ultimate Tier 10/10 Forensic Engine Backend Upgrades', () {
    test('FuzzySimilarityMatcher accurately recognizes Harvard, Chicago, narrative, and alphanumeric citations', () {
      final matcher = FuzzySimilarityMatcher();

      // 1. Harvard / Chicago style with prefix and page range
      const text1 = 'Recent findings confirm the stability of neural representations (e.g., Smith & Wesson, 2019, pp. 24–26).';
      final analysis1 = matcher.analyzeCitationContext(
        fullDocumentText: text1,
        matchStartOffset: 0,
        matchEndOffset: 55,
      );
      expect(analysis1.status, equals(CitationStatus.cited));
      expect(analysis1.citationMarker, contains('Smith & Wesson, 2019'));

      // 2. Chicago style with colon page notation
      const text2 = 'The paradigm shift occurred gradually (see also Johnson et al., 2022: 45).';
      final analysis2 = matcher.analyzeCitationContext(
        fullDocumentText: text2,
        matchStartOffset: 0,
        matchEndOffset: 38,
      );
      expect(analysis2.status, equals(CitationStatus.cited));

      // 3. Narrative in-text citation
      const text3 = 'According to Turing (1950), computing machinery can simulate human thought.';
      final analysis3 = matcher.analyzeCitationContext(
        fullDocumentText: text3,
        matchStartOffset: 25,
        matchEndOffset: 70,
      );
      expect(analysis3.status, equals(CitationStatus.cited));
      expect(analysis3.citationMarker, contains('Turing (1950)'));

      // 4. Alphanumeric bracket citation
      const text4 = 'Information entropy provides an upper bound on compression efficiency [Knu84].';
      final analysis4 = matcher.analyzeCitationContext(
        fullDocumentText: text4,
        matchStartOffset: 0,
        matchEndOffset: 50,
      );
      expect(analysis4.status, equals(CitationStatus.cited));
      expect(analysis4.citationMarker, equals('[Knu84]'));
    });

    test('DenseSemanticMatcher detects active-to-passive voice transformation and cognate prefixes', () {
      final matcher = DenseSemanticMatcher();

      // Active vs Passive voice inversion
      const active = 'Stanford researchers designed the novel transformer architecture for genome analysis.';
      const passive = 'The novel transformer architecture was designed by Stanford researchers for genome analysis.';

      final sim = matcher.similarity(active, passive);
      expect(sim, greaterThan(0.80));

      // Cross-lingual / prefix cognate matching
      const s1 = 'The team implemented multidisciplinary computational workflows.';
      const s2 = 'The team implemented interdisciplinary computational workflows.';

      final prefixSim = matcher.similarity(s1, s2);
      expect(prefixSim, greaterThan(0.85));
    });

    test('SourceSimilarityService multi-tier retrieval detects Bitcoin whitepaper via Winnowing fingerprints', () {
      final repository = SourceRepository();
      final similarityService = SourceSimilarityService(repository: repository);

      const bitcoinExcerpt = 'A purely peer-to-peer version of electronic cash would allow online payments to be sent '
          'directly from one party to another without going through a financial institution.';

      final evidence = similarityService.analyzeDocument(bitcoinExcerpt);
      expect(evidence.matches.isNotEmpty, isTrue);
      expect(evidence.matches.any((m) => m.sourceTitle.contains('Bitcoin')), isTrue);
      expect(evidence.longestContiguousTokenMatch, greaterThanOrEqualTo(15));
    });

    test('SemanticPreservationVerifier alerts on medical/scientific unit drift', () {
      final verifier = SemanticPreservationVerifier();

      const original = 'The clinical subject received 50 mg of the pharmaceutical compound every 12 hours.';
      const rewritten = 'The subject took 50 kg of the pharmaceutical compound every 12 hours.';

      final report = verifier.verify(originalText: original, humanizedText: rewritten);

      expect(report.hasUnitDrift, isTrue);
      expect(report.missingUnits, contains('50 mg'));
      expect(report.verdict, equals(SemanticPreservationVerdict.factualDriftAlert));
    });

    test('SemanticPreservationVerifier detects relational direction polarity drift (increase vs decrease)', () {
      final verifier = SemanticPreservationVerifier();

      const original = 'Quarterly operating revenue increased by 20% in the second quarter of 2024.';
      const inverted = 'Quarterly operating revenue decreased by 20% in the second quarter of 2024.';

      final report = verifier.verify(originalText: original, humanizedText: inverted);

      expect(report.hasRelationalDrift, isTrue);
      expect(report.hasPolarityDrift, isTrue);
      expect(report.verdict, equals(SemanticPreservationVerdict.factualDriftAlert));
    });

    test('AlgorithmicHumanizerService detoxifies modern AI tropes and preserves facts', () {
      const humanizer = AlgorithmicHumanizerService();

      const input = 'This watershed moment at the precipice of change is a profound testament to the resilience of our community. '
          'The initiative plays an indispensable role in progress, from a holistic perspective.';

      final output = humanizer.replaceAiStockPhrases(input);

      expect(output.toLowerCase(), isNot(contains('watershed moment')));
      expect(output.toLowerCase(), isNot(contains('at the precipice of')));
      expect(output.toLowerCase(), isNot(contains('profound testament to')));
      expect(output.toLowerCase(), isNot(contains('plays an indispensable role in')));
      expect(output.toLowerCase(), isNot(contains('from a holistic perspective')));

      expect(output, contains('turning point'));
      expect(output, contains('on the verge of'));
      expect(output, contains('shows the resilience of'));
      expect(output, contains('is vital to'));
      expect(output, contains('overall'));
    });

    test('AlgorithmicHumanizerService diversifies consecutive pronoun sentence starters', () {
      const humanizer = AlgorithmicHumanizerService();

      const input = 'He developed the algorithm. He verified the mathematical proof in 2024.';
      final result = humanizer.diversifyConsecutiveSentenceStarters(input);

      expect(result, equals('He developed the algorithm. Later, he verified the mathematical proof in 2024.'));
    });

    test('AlgorithmicHumanizerService elevates burstiness variance across compound sentences', () {
      const humanizer = AlgorithmicHumanizerService();

      const input = 'The platform provides streaming audio analysis, which accelerates forensic detection across the documents. '
          'The framework ensures resilient data processing pipelines for all incoming documents.';

      final bursty = humanizer.optimizeBurstiness(input, minCv: 0.35);
      final sentences = TextForensicsLexicons.splitSentences(bursty);
      expect(sentences.length, greaterThan(2));
    });
  });
}
