import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/humanizer_tone.dart';
import 'package:lauriva/services/forensic/humanizer/lauvira_humanize_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LauviraHumanizeService Pipeline Tests', () {
    late LauviraHumanizeService service;

    setUp(() {
      service = LauviraHumanizeService();
    });

    test('transforms generic LLM essay with AI tells into authentic human prose',
        () async {
      const llmDraft =
          'Furthermore, it is crucial to remember that remote work plays a pivotal role '
          'in modern society. Moreover, it is not merely a convenience, but rather a profound shift '
          'that fosters organizational synergy.';

      final humanized = await service.humanizeLlmOutput(
        llmDraft,
        tone: HumanizerTone.casual,
      );

      // Verify AI buzzwords and robotic openers are stripped
      expect(humanized.contains('Furthermore,'), isFalse);
      expect(humanized.contains('Moreover,'), isFalse);
      expect(humanized.contains('crucial'), isFalse);
      expect(humanized.contains('pivotal role'), isFalse);
      expect(humanized.contains('not merely'), isFalse);
      expect(humanized.isNotEmpty, isTrue);
    });

    test('preserves numeric data, citations, and critical facts across humanization',
        () async {
      const llmTechnicalDraft =
          'Additionally, in 2026, the NASA rover reached 42.5 kilometers per hour on Mars (Smith et al., 2024). '
          'Delving into this achievement, it stands as a testament to robotic engineering.';

      final humanized = await service.humanizeLlmOutput(
        llmTechnicalDraft,
        tone: HumanizerTone.academic,
      );

      // Verify factual invariants remain intact
      expect(humanized.contains('2026'), isTrue);
      expect(humanized.contains('42.5'), isTrue);
      expect(humanized.contains('NASA'), isTrue);
      expect(humanized.contains('Mars'), isTrue);
      expect(humanized.contains('Smith et al., 2024'), isTrue);

      // Verify AI markers are cleaned
      expect(humanized.contains('Additionally,'), isFalse);
      expect(humanized.contains('Delving into'), isFalse);
      expect(humanized.contains('testament to'), isFalse);
    });

    test('handles empty and whitespace input safely', () async {
      final resEmpty = await service.humanizeLlmOutput('');
      expect(resEmpty, equals(''));

      final resWhitespace = await service.humanizeLlmOutput('   ');
      expect(resWhitespace, equals(''));
    });

    test('preserves bracketed citations and numbered references without corruption', () async {
      const draft =
          'Recent advancements in quantum computing [1] indicate that superconducting qubits have reached 99.9% fidelity [2, 3]. '
          'Furthermore, this achievement stands as a testament to the ever-evolving nature of modern physics.';

      final humanized = await service.humanizeLlmOutput(draft, tone: HumanizerTone.academic);

      expect(humanized.contains('[1]'), isTrue);
      expect(humanized.contains('[2, 3]'), isTrue);
      expect(humanized.contains('99.9%'), isTrue);
      expect(humanized.contains('superconducting qubits'), isTrue);
      expect(humanized.contains('Furthermore,'), isFalse);
      expect(humanized.contains('stands as a testament'), isFalse);
    });

    test('maintains coherence and polarity while dissolving staged contrasts', () async {
      const draft =
          'The discovery was not merely an accident, but rather a deliberate outcome of a five-year experiment. '
          'Researchers evaluated 1,200 biological samples, but observed no cell degradation.';

      final humanized = await service.humanizeLlmOutput(draft, tone: HumanizerTone.professional);

      expect(humanized.contains('deliberate outcome'), isTrue);
      expect(humanized.contains('five-year'), isTrue);
      expect(humanized.contains('1,200'), isTrue);
      expect(humanized.contains('no cell degradation'), isTrue);
      expect(humanized.contains('not merely'), isFalse);
      expect(humanized.contains('rather than'), isFalse);
    });
  });
}
