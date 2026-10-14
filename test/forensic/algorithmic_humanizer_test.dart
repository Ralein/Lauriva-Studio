import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/ai_forensic_service.dart';
import 'package:lauriva/services/text_forensics_lexicons.dart';

void main() {
  group('AlgorithmicHumanizerService', () {
    const humanizer = AlgorithmicHumanizerService();
    final forensicService = AiForensicService();

    test('strips transition openers and fixes capitalization', () {
      const input = 'Furthermore, renewable energy is cheap. Moreover, solar panels last for decades. In conclusion, adoption will grow.';
      final cleaned = humanizer.stripAiTransitions(input);
      expect(cleaned.contains('Furthermore,'), isFalse);
      expect(cleaned.contains('Moreover,'), isFalse);
      expect(cleaned.contains('In conclusion,'), isFalse);
      expect(cleaned.startsWith('Renewable energy'), isTrue);
      expect(cleaned.contains('Solar panels last'), isTrue);
    });

    test('detoxifies AI stock phrases and boilerplate', () {
      const input = 'This project stands as a testament to innovation and plays a pivotal role in the digital landscape. We delve into new solutions that foster community growth.';
      final detoxed = humanizer.replaceAiStockPhrases(input);
      expect(detoxed.contains('stands as a testament to'), isFalse);
      expect(detoxed.contains('pivotal'), isFalse);
      expect(detoxed.contains('delve into'), isFalse);
      expect(detoxed.contains('foster'), isFalse);
      expect(detoxed.contains('shows'), isTrue);
      expect(detoxed.contains('key'), isTrue);
      expect(detoxed.contains('explore'), isTrue);
    });

    test('dissolves contrast formulas', () {
      const input = 'The update not only fixes security flaws, but also improves runtime performance.';
      final dissolved = humanizer.dissolveContrastAndStaging(input);
      expect(dissolved.contains('not only'), isFalse);
      expect(dissolved, equals('The update fixes security flaws. It also improves runtime performance.'));
    });

    test('end-to-end postProcess drops AI detector score to human range', () {
      const syntheticInput = 'Furthermore, the implementation of renewable energy plays a crucial role in combating climate change. By harnessing solar and wind power, communities can delve into sustainable practices that bolster economic resilience. In conclusion, it is important to note that these initiatives not only reduce emissions, but also pave the way for a brighter future.';

      // Before humanization
      final beforeAudit = forensicService.auditText(syntheticInput);
      expect(beforeAudit.aiProbability, greaterThan(60.0));

      // Algorithmic humanization
      final humanized = humanizer.postProcess(syntheticInput);

      // Verify stock words and openers removed
      expect(humanized.contains('Furthermore,'), isFalse);
      expect(humanized.contains('In conclusion,'), isFalse);
      expect(humanized.contains('plays a crucial role in'), isFalse);
      expect(humanized.contains('delve into'), isFalse);
      expect(humanized.contains('harnessing'), isFalse);

      final afterAudit = forensicService.auditText(humanized);
      expect(afterAudit.aiProbability, lessThan(35.0));
      expect(afterAudit.authorshipClass, equals(AiAuthorshipClass.likelyHuman));
    });

    test('optimizes burstiness on metronomic uniform sentences', () {
      const uniformText = 'The team analyzed the telemetry data carefully. Each server reported normal memory usage levels. The network throughput remained within normal limits. Engineers monitored the primary database cluster continuously.';
      final result = humanizer.optimizeBurstiness(uniformText);
      final sentences = TextForensicsLexicons.splitSentences(result);
      expect(sentences.length, greaterThanOrEqualTo(4));
    });

    test('regulates excessive em-dashes down to human limits', () {
      const emDashOveruse = 'Modern software—which is inherently complex—requires constant testing—especially in production—where errors can occur—leading to downtime.';
      final regulated = humanizer.regulatePunctuation(emDashOveruse);
      final count = RegExp(r'—').allMatches(regulated).length;
      expect(count, lessThanOrEqualTo(1));
    });

    test('humanizes cognitive science passage into clean human-range prose', () {
      const input = 'During the sensorimotor stage, infants acquire basic understanding of the links between their own behaviour and the effects it produces cause and effect. During the preoperational stage, infants can form mental representations of the external world, but their thinking remains egocentric.';

      final beforeAudit = forensicService.auditText(input);
      expect(beforeAudit.aiProbability, greaterThan(80.0));

      final humanized = humanizer.postProcess(input);

      // Preserves key scientific concepts without distortion
      expect(humanized.contains('sensorimotor'), isTrue);
      expect(humanized.contains('preoperational'), isTrue);
      expect(humanized.contains('egocentric'), isTrue);

      // Repetitive openers diversified and contrast split
      expect(humanized.contains('During the preoperational'), isFalse);
      expect(humanized.contains('In the preoperational'), isTrue);
      expect(humanized.contains('Still, their thinking remains egocentric'), isTrue);

      final afterAudit = forensicService.auditText(humanized);
      expect(afterAudit.aiProbability, lessThan(25.0));
      expect(afterAudit.authorshipClass, equals(AiAuthorshipClass.likelyHuman));
    });

    test('dissolves Wikipedia AI tells: chatbot residue and cutoff disclaimers', () {
      const input = 'Certainly! Here is an overview of distributed computing. As of my knowledge cutoff in 2024, solar power serves as a cornerstone of sustainable development. I hope this helps! Feel free to ask if you have any questions.';
      final cleaned = humanizer.postProcess(input);
      expect(cleaned.contains('Certainly!'), isFalse);
      expect(cleaned.contains('Here is an overview'), isFalse);
      expect(cleaned.contains('knowledge cutoff'), isFalse);
      expect(cleaned.contains('I hope this helps'), isFalse);
      expect(cleaned.contains('Feel free to ask'), isFalse);
      expect(cleaned.contains('serves as a cornerstone'), isFalse);
    });

    test('dissolves Wikipedia AI tells: phantom arguments with polarity preservation', () {
      const input = 'To be clear, this is not to say that technology has no place in the arts. Don\'t get me wrong, artists will always matter.';
      final cleaned = humanizer.postProcess(input);
      expect(cleaned.contains('To be clear,'), isFalse);
      expect(cleaned.contains('Don\'t get me wrong,'), isFalse);
      expect(cleaned.contains('this is not to say that'), isFalse);
      // Polarity must be strictly preserved
      expect(cleaned.contains('This does not mean that technology has no place in the arts'), isTrue);
      expect(cleaned.contains('Artists will always matter'), isTrue);
    });

    test('dissolves Wikipedia AI tells: one-line closers and platitudes', () {
      const input = 'AlphaEvolve found better algorithms. Let that sink in.';
      final cleaned = humanizer.dissolveOneLineClosers(input);
      expect(cleaned, equals('AlphaEvolve found better algorithms.'));
    });

    test('dissolves stacked qualifiers and hyphenated predicate pairs', () {
      const input = 'The platform is cross-functional and could potentially possibly scale efficiently.';
      var cleaned = humanizer.dissolveStackedQualifiers(input);
      cleaned = humanizer.dissolveHyphenatedPredicatePairs(cleaned);
      expect(cleaned.contains('could potentially possibly'), isFalse);
      expect(cleaned.contains('could scale'), isTrue);
      expect(cleaned.contains('is cross-functional'), isFalse);
      expect(cleaned.contains('is cross functional'), isTrue);
    });

    test('splits consequence and explanatory clauses to raise burstiness', () {
      const input = 'The compiler optimizes memory allocation dynamically, leading to noticeable improvements in execution latency.';
      final split = humanizer.optimizeBurstiness(input);
      expect(split.contains('This leads to noticeable improvements in execution latency.'), isTrue);
    });

    test('dissolves Wikipedia AI tells: states claims directly without staged denials (§1)', () {
      const input1 = 'It is not merely a software update, but rather a complete rethinking of the workflow.';
      final res1 = humanizer.dissolveContrastAndStaging(input1);
      expect(res1, equals('It is a complete rethinking of the workflow.'));
      expect(res1.contains('rather than'), isFalse);

      const input2 = 'The initiative is not simply an experiment, but a permanent standard.';
      final res2 = humanizer.dissolveContrastAndStaging(input2);
      expect(res2, equals('The initiative is a permanent standard rather than an experiment.'));
    });

    test('preserves coherence: compound predicates without subjects are not split into headless fragments', () {
      const input = 'The physician examined the MRI scans thoroughly, but failed to identify the subtle fracture in the patient vertebrae.';
      final split = humanizer.optimizeBurstiness(input);
      // Must not create a headless fragment like "Still, failed to identify..."
      expect(split.contains('Still, failed'), isFalse);
    });

    test('detoxifies deeper AI clichés and stock framing', () {
      const input = 'This achievement is setting the stage for future research and continue their journey toward excellence. The center boasts over 50 laboratories and functions as a hub for innovation.';
      final detoxed = humanizer.replaceAiStockPhrases(input);
      expect(detoxed.contains('setting the stage for'), isFalse);
      expect(detoxed.contains('journey toward excellence'), isFalse);
      expect(detoxed.contains('boasts over'), isFalse);
      expect(detoxed.contains('functions as a'), isFalse);
      expect(detoxed.contains('preparing for'), isTrue);
      expect(detoxed.contains('work toward excellence'), isTrue);
      expect(detoxed.contains('has over'), isTrue);
      expect(detoxed.contains('is a hub'), isTrue);
    });

    test('dissolves shallow participle tails with plain human verbs instead of AI stock verbs', () {
      const input = 'The company open-sourced its models, underscoring its commitment to transparency and showcasing the speed.';
      final detoxed = humanizer.dissolveParticipialTails(input);
      // Must not re-inject top AI words like "underscores" or "showcases"
      expect(detoxed.contains('underscores'), isFalse);
      expect(detoxed.contains('showcases'), isFalse);
      expect(detoxed.contains('shows its commitment'), isTrue);
    });
  });
}
