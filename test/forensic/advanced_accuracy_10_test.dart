import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/sources/online/source_query_generator.dart';
import 'package:lauriva/constants/app_prompts.dart';

void main() {
  group('10/10 Accuracy Upgrades - Forensic & Humanizer Engines', () {
    const humanizer = AlgorithmicHumanizerService();
    final verifier = SemanticPreservationVerifier();

    test('SourceQueryGenerator de-weights generic AI buzzwords in token weighting', () {
      const generator = SourceQueryGenerator(maxQueries: 2);
      // Text with one sentence full of generic AI words and one with concrete domain facts
      const doc = 'In today\'s fast-paced world, delving into the multifaceted landscape plays a pivotal role in fostering synergy. '
          'Dr. Jennifer Doudna developed CRISPR-Cas9 genome editing at UC Berkeley in 2012.';
      final queries = generator.generate(doc);

      expect(queries, isNotEmpty);
      // The selected query must prioritize the substantive domain sentence with CRISPR and Doudna
      final allQueryText = queries.map((q) => q.text.toLowerCase()).join(' ');
      expect(allQueryText.contains('crispr') || allQueryText.contains('doudna') || allQueryText.contains('berkeley'), isTrue);
    });

    test('SemanticPreservationVerifier matches ordinal figures with spelled-out words', () {
      final report = verifier.verify(
        originalText: 'We achieved 1st place in the 2nd annual robotics competition.',
        humanizedText: 'We achieved first place in the second annual robotics competition.',
      );

      expect(report.missingNumbers, isEmpty);
      expect(report.hasNumericalDrift, isFalse);
      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
    });

    test('SemanticPreservationVerifier extracts and protects camelCase/branded entities', () {
      final report = verifier.verify(
        originalText: 'The team deployed the backend on macOS and integrated ChatGPT with OpenAI APIs.',
        humanizedText: 'The team deployed the backend on macOS and connected ChatGPT with OpenAI APIs.',
      );

      expect(report.preservedEntities, containsAll(['macOS', 'ChatGPT', 'OpenAI']));
      expect(report.missingEntities, isEmpty);
      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
    });

    test('SemanticPreservationVerifier detects subtle modal/polarity drift', () {
      final report = verifier.verify(
        originalText: 'The clinical team was unable to verify the efficacy of the trial drug.',
        humanizedText: 'The clinical team verified the efficacy of the trial drug.',
      );

      expect(report.hasPolarityDrift, isTrue);
      expect(report.verdict, isNot(equals(SemanticPreservationVerdict.excellent)));
    });

    test('AlgorithmicHumanizerService detoxifies modern AI tropes and padding', () {
      const text = 'Renewable power is a vital component of clean energy and plays an instrumental role in '
          'the fight against climate change. We must take a deep dive into the holistic framework.';
      final result = humanizer.postProcess(text);

      expect(result.contains('vital component of'), isFalse);
      expect(result.contains('plays an instrumental role in'), isFalse);
      expect(result.contains('deep dive into'), isFalse);
      expect(result.contains('holistic framework'), isFalse);

      expect(result.contains('key part of'), isTrue);
      expect(result.contains('is key to'), isTrue);
      expect(result.contains('detailed look at'), isTrue);
      expect(result.contains('comprehensive framework'), isTrue);
    });

    test('AlgorithmicHumanizerService dissolves extended contrast formulas', () {
      const text1 = 'It is not just about speed, but about reliability.';
      final res1 = humanizer.dissolveContrastAndStaging(text1);
      expect(res1, contains('rather than'));

      const text2 = 'The system is not simply an update, but an overhaul.';
      final res2 = humanizer.dissolveContrastAndStaging(text2);
      expect(res2, contains('an overhaul rather than an update'));
    });

    test('AlgorithmicHumanizerService dissolves extended participial tail verbs', () {
      const text = 'The experiment yielded positive results, demonstrating the viability of the treatment.';
      final res = humanizer.dissolveParticipialTails(text);

      expect(res, contains('. This demonstrates the viability'));
      expect(res.contains(', demonstrating'), isFalse);
    });

    test('AlgorithmicHumanizerService cleans duplicate function words', () {
      const input = 'The report showed that that the the system was stable.';
      final res = humanizer.cleanPunctuationAndSpacing(input);
      expect(res, equals('The report showed that the system was stable.'));
    });

    test('AppPrompts features updated anti-detection directives and tone calibration', () {
      final humanizePrompt = AppPrompts.getFeatureInstruction('Humanize');
      expect(humanizePrompt, contains('Wikipedia Signs of AI Writing'));
      expect(humanizePrompt, contains('Unpredictable Token Distributions'));
      expect(humanizePrompt, contains('deep dive'));
      expect(humanizePrompt, contains('catalyst for change'));

      final surgicalPrompt = AppPrompts.getFeatureInstruction('SurgicalHumanize');
      expect(surgicalPrompt, contains('Natural human register'));
    });
  });
}
