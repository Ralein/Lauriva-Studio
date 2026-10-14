import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SemanticPreservationVerifier Tests', () {
    late SemanticPreservationVerifier verifier;

    setUp(() {
      verifier = SemanticPreservationVerifier();
    });

    test('detects high fidelity when facts and numbers are maintained', () {
      const original =
          'In 2024, ACME Corp reduced operating expenses by 18% across 3 European offices (Smith et al., 2023).';
      const humanized =
          'During 2024, ACME Corp cut its operational overhead by 18% in 3 offices located in Europe (Smith et al., 2023).';

      final report = verifier.verify(
        originalText: original,
        humanizedText: humanized,
        aiProbabilityBefore: 0.85,
        aiProbabilityAfter: 0.15,
        burstinessBefore: 0.20,
        burstinessAfter: 0.65,
      );

      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
      expect(report.preservationScore, greaterThanOrEqualTo(0.75));
      expect(report.preservedNumbers, containsAll(['2024', '18%', '3']));
      expect(report.missingNumbers, isEmpty);
      expect(report.preservedCitations, contains('(Smith et al., 2023)'));
      expect(report.aiReduction, closeTo(0.70, 0.01));
      expect(report.burstinessGain, closeTo(0.45, 0.01));
    });

    test('flags factual drift when numbers/figures are dropped or hallucinated', () {
      const original =
          'The battery lasts 14 hours and costs \$250, saving 35% over competitor devices.';
      // Humanizer rewrote and accidentally omitted 14 hours and $250, introducing 8 hours
      const humanized =
          'The device provides around 8 hours of runtime while keeping prices modest and saving 35%.';

      final report = verifier.verify(
        originalText: original,
        humanizedText: humanized,
        aiProbabilityBefore: 0.80,
        aiProbabilityAfter: 0.20,
      );

      expect(report.verdict, equals(SemanticPreservationVerdict.factualDriftAlert));
      expect(report.missingNumbers, anyOf(contains('14'), contains('\$250')));
      expect(report.introducedNumbers, contains('8'));
      expect(report.hasNumericalDrift, isTrue);
    });

    test('tracks preserved vs missing citations', () {
      const original =
          'Attention mechanisms revolutionized machine translation [1] and natural language processing (Vaswani et al., 2017).';
      // Humanizer kept [1] but dropped the Vaswani citation
      const humanized =
          'Attention structures completely changed neural translation [1] and general computational linguistics.';

      final report = verifier.verify(
        originalText: original,
        humanizedText: humanized,
        aiProbabilityBefore: 0.90,
        aiProbabilityAfter: 0.10,
      );

      expect(report.preservedCitations, contains('[1]'));
      expect(report.missingCitations, contains('(Vaswani et al., 2017)'));
      expect(report.hasCitationLoss, isTrue);
    });

    test('enforces length floor guard (<80% triggers hasLengthUnderflow and divergent verdict)', () {
      const original =
          'The research team spent four years collecting extensive field observations '
          'across twelve different marine ecosystems to establish baseline biodiversity metrics.';
      // Output dropped clauses below 80%
      const humanized =
          'The research team collected field observations.';

      final report = verifier.verify(
        originalText: original,
        humanizedText: humanized,
      );

      expect(report.lengthRatio, lessThan(0.80));
      expect(report.hasLengthUnderflow, isTrue);
      expect(report.verdict, equals(SemanticPreservationVerdict.divergent));
      expect(report.summary, contains('Output dropped below 80%'));
    });

    test('enforces negation guard (rejects change in negation count)', () {
      const original =
          'The preliminary trials showed that the experimental drug did not cause liver toxicity.';
      // Output inverted claim by omitting "not"
      const humanized =
          'The initial tests indicated that the experimental drug caused significant liver toxicity.';

      final report = verifier.verify(
        originalText: original,
        humanizedText: humanized,
      );

      expect(report.negationsBefore, equals(1));
      expect(report.negationsAfter, equals(0));
      expect(report.hasPolarityDrift, isTrue);
      expect(report.summary, contains('Negation count changed'));
    });

    test('verifies static countNegations helper accurately handles rhetorical vs true negations', () {
      expect(SemanticPreservationVerifier.countNegations('This is not only useful, but also fast.'), equals(0));
      expect(SemanticPreservationVerifier.countNegations('This is not just simple, it is essential.'), equals(0));
      expect(SemanticPreservationVerifier.countNegations('The system never fails and has no downtime.'), equals(2));
      expect(SemanticPreservationVerifier.countNegations('We cannot proceed without confirmation.'), equals(2));
    });
  });
}
