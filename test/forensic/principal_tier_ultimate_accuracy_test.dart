import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/sources/dense_semantic_matcher.dart';
import 'package:lauriva/services/forensic/sources/fuzzy_similarity_matcher.dart';
import 'package:lauriva/services/forensic/sources/match_tokenizer.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/services/forensic/humanizer/surgical_humanizer_bridge.dart';

void main() {
  group('Principal Senior Dev Ultimate Accuracy Tests', () {
    test('MatchTokenizer neutralizes Cyrillic homoglyph attacks and zero-width spaces', () {
      // "network" with Cyrillic 'е' (U+0435) and 'о' (U+043E)
      final obfuscated = 'Deep neural n\u0435tw\u043Erks learn r\u0435pr\u0435s\u0435ntations.';
      final tokens = MatchTokenizer.tokenize(obfuscated);

      expect(tokens, isNotEmpty);
      final stems = tokens.map((t) => t.stem).toList();
      // Should stem to "network" and "represent", exactly like the clean Latin version
      expect(stems, contains('network'));
      expect(stems, contains('representation'));

      // Zero-width space attack: "con\u200Bnected"
      final zeroWidthText = 'Fully con\u200Bnected artificial neurons.';
      final zwTokens = MatchTokenizer.tokenize(zeroWidthText);
      final zwStems = zwTokens.map((t) => t.stem).toList();
      expect(zwStems, contains('connect'));
    });

    test('FuzzySimilarityMatcher recognizes Vancouver citations, DOIs, and arXiv identifiers', () {
      final matcher = FuzzySimilarityMatcher();

      // Check match near Vancouver citation (1, 2)
      const vancouverDoc = 'Recent breakthroughs demonstrate high fidelity in neural training (1, 2).';
      final vancouverAnalysis = matcher.analyzeCitationContext(
        fullDocumentText: vancouverDoc,
        matchStartOffset: 0,
        matchEndOffset: 45,
      );
      expect(vancouverAnalysis.status, equals(CitationStatus.cited));
      expect(vancouverAnalysis.citationMarker, contains('(1, 2)'));

      // Check match near DOI
      const doiDoc = 'According to reports, the catalyst operates efficiently doi:10.1038/s41586-020-2649-2.';
      final doiAnalysis = matcher.analyzeCitationContext(
        fullDocumentText: doiDoc,
        matchStartOffset: 0,
        matchEndOffset: 50,
      );
      expect(doiAnalysis.status, equals(CitationStatus.cited));
      expect(doiAnalysis.citationMarker, contains('doi:10.1038'));
    });

    test('SemanticPreservationVerifier flags temporal and causal sequence inversion', () {
      final verifier = SemanticPreservationVerifier();

      // Temporal inversion: "prior to" -> "following"
      final temporalReport = verifier.verify(
        originalText: 'The team completed testing prior to the final production deployment.',
        humanizedText: 'The team completed testing following the final production deployment.',
      );
      expect(temporalReport.hasPolarityDrift, isTrue);
      expect(temporalReport.verdict, isNot(equals(SemanticPreservationVerdict.excellent)));

      // Causal inversion: "caused by" -> "leads to"
      final causalReport = verifier.verify(
        originalText: 'System latency was caused by excessive database connection spikes.',
        humanizedText: 'System latency leads to excessive database connection spikes.',
      );
      expect(causalReport.hasPolarityDrift, isTrue);
    });

    test('SemanticPreservationVerifier guards engineering units and international currencies', () {
      final verifier = SemanticPreservationVerifier();
      final report = verifier.verify(
        originalText: 'The hydraulic valve withstood 150 MPa and the server transferred 40 Gbps at a cost of 50000 JPY.',
        humanizedText: 'The hydraulic valve withstood 150 MPa and the server transferred 40 Gbps at a cost of 50000 JPY.',
      );

      expect(report.missingUnits, isEmpty);
      expect(report.preservedUnits, containsAll(['150 mpa', '40 gbps', 'jpy']));
      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
    });

    test('AlgorithmicHumanizerService detoxifies modern AI tropes cleanly', () {
      const humanizer = AlgorithmicHumanizerService();
      const input = 'The software acts as a vital cog in modern supply chains. '
          'Furthermore, in sum, it is clear that orchestrating a delicate balance is a testament to the fact that '
          'we are approaching the dawn of a new era with a plethora of options.';
      final result = humanizer.postProcess(input);

      expect(result.contains('acts as a vital cog in'), isFalse);
      expect(result.contains('vital cog'), isFalse);
      expect(result.contains('orchestrating a delicate balance'), isFalse);
      expect(result.contains('the dawn of a new era'), isFalse);
      expect(result.contains('plethora of options'), isFalse);
      expect(result.contains('a testament to the fact that'), isFalse);
    });

    test('FuzzySimilarityMatcher recognizes Markdown blockquotes as cited material', () {
      final matcher = FuzzySimilarityMatcher();
      const doc = '> Machines will take us all by surprise with what they do (Turing, 1950).\n\nProse continues here.';
      final analysis = matcher.analyzeCitationContext(
        fullDocumentText: doc,
        matchStartOffset: 2,
        matchEndOffset: 55,
      );
      expect(analysis.isQuoted, isTrue);
      expect(analysis.status, equals(CitationStatus.quotedAndCited));
    });

    test('AlgorithmicHumanizerService shields code blocks, inline code, LaTeX, and URLs from modification', () {
      const humanizer = AlgorithmicHumanizerService();
      const technicalDoc = r'We must examine the architecture. '
          r'Visit https://github.com/project/delve-into-ai to review the repository. '
          r'Execute `delve_into_layers()` in the terminal. '
          r'$$\sum_{i=1}^n \text{vital_component}(x_i)$$' '\n\n'
          '```python\n# Delve into the data\ndef calculate_vital_component():\n    return 42\n```\n\n'
          'Furthermore, it is important to note that this is efficient.';

      final humanized = humanizer.postProcess(technicalDoc);

      // Verify URLs and code are untouched
      expect(humanized.contains('https://github.com/project/delve-into-ai'), isTrue);
      expect(humanized.contains('`delve_into_layers()`'), isTrue);
      expect(humanized.contains(r'$$\sum_{i=1}^n \text{vital_component}(x_i)$$'), isTrue);
      expect(humanized.contains('# Delve into the data'), isTrue);
      expect(humanized.contains('def calculate_vital_component():'), isTrue);

      // Verify prose outside was humanized
      expect(humanized.contains('it is important to note that'), isFalse);
    });

    test('SemanticPreservationVerifier penalizes dropped code blocks and display LaTeX math', () {
      final verifier = SemanticPreservationVerifier();
      const orig = 'Here is the algorithm:\n```python\nprint("hello")\n```\n' r'$$\alpha + \beta = \gamma$$';
      const dropped = 'Here is the algorithm without details.';

      final report = verifier.verify(originalText: orig, humanizedText: dropped);
      expect(report.verdict, isNot(equals(SemanticPreservationVerdict.excellent)));
      expect(report.preservationScore, lessThan(0.5));
    });

    test('DenseSemanticMatcher aligns scientific and technical cognates with expanded prefixes', () {
      final matcher = DenseSemanticMatcher();
      const sentenceA = 'Researchers identified submicroscopic intracellular anomalies in the trial sample.';
      const sentenceB = 'Researchers analyzed microscopic cellular anomalies in the trial sample.';

      final sim = matcher.similarity(sentenceA, sentenceB);
      // Even with prefix variations (sub-, intra-), semantic similarity exceeds the 0.75 paraphrase threshold
      expect(sim, greaterThan(0.75));
    });

    test('FuzzySimilarityMatcher recognizes Chicago Ibid and Harvard multi-author page citations', () {
      final matcher = FuzzySimilarityMatcher();

      const chicagoDoc = 'The primary results remained consistent (Ibid., p. 45).';
      final chicagoAnalysis = matcher.analyzeCitationContext(
        fullDocumentText: chicagoDoc,
        matchStartOffset: 0,
        matchEndOffset: 35,
      );
      expect(chicagoAnalysis.status, equals(CitationStatus.cited));
      expect(chicagoAnalysis.citationMarker, contains('Ibid'));

      const harvardDoc = 'As established previously (Smith, Jones & Brown, 2024: 12-15), performance scales quadratically.';
      final harvardAnalysis = matcher.analyzeCitationContext(
        fullDocumentText: harvardDoc,
        matchStartOffset: 60,
        matchEndOffset: 95,
      );
      expect(harvardAnalysis.status, equals(CitationStatus.cited));
      expect(harvardAnalysis.citationMarker, contains('Smith, Jones & Brown'));
    });

    test('FuzzySimilarityMatcher near-match catches adversarial typo injection in content words', () {
      final matcher = FuzzySimilarityMatcher();

      // "transform" vs typo "trnasform"
      final result = matcher.paraphraseSimilarity(
        'The algorithm can trnasform input distributions effectively.',
        'The algorithm can transform input distributions effectively.',
      );
      expect(result.score, greaterThanOrEqualTo(0.85));
    });

    test('SurgicalHumanizerBridge parseRewriteArray recovers arrays with unescaped internal double quotes', () {
      const malformedJson = '["The speaker declared "Eureka!" to the auditorium.", "The experiment was officially concluded."]';
      final parsed = SurgicalHumanizerBridge.parseRewriteArray(malformedJson);

      expect(parsed, isNotNull);
      expect(parsed!.length, equals(2));
      expect(parsed.first, contains('Eureka'));
    });

    test('SemanticPreservationVerifier guards extended SI units and international currencies', () {
      final verifier = SemanticPreservationVerifier();
      const text = 'The 100 THz oscillator generated 50 TW under 25 GPa pressure with an investment of 4000 SGD.';
      final report = verifier.verify(
        originalText: text,
        humanizedText: text,
      );

      expect(report.missingUnits, isEmpty);
      expect(report.preservedUnits, containsAll(['100 thz', '50 tw', '25 gpa', 'sgd']));
      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
    });

    test('AlgorithmicHumanizerService shields footnotes and email addresses while detoxifying prose', () {
      const humanizer = AlgorithmicHumanizerService();
      const input = 'Furthermore, contact lead_researcher@mit.edu for details[^1]. '
          'We must delve deep into this game-changer in the realm of computing.';
      final output = humanizer.postProcess(input);

      expect(output.contains('lead_researcher@mit.edu'), isTrue);
      expect(output.contains('[^1]'), isTrue);
      expect(output.contains('Furthermore,'), isFalse);
      expect(output.contains('delve deep into'), isFalse);
      expect(output.contains('game-changer in the realm of'), isFalse);
    });
  });
}
