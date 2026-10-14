import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/adversarial_obfuscation_detector.dart';
import 'package:lauriva/services/forensic/fusion/evidence_fusion_engine.dart';

void main() {
  group('Adversarial Hardening Advanced Tests (Phase 6)', () {
    late AdversarialObfuscationDetector detector;

    setUp(() {
      detector = AdversarialObfuscationDetector();
    });

    test('fragmentationScore detects consecutive short repetitive fragments', () {
      final sentences = [
        'The quick brown fox jumps.',
        'The quick brown fox leaps.',
        'The quick brown dog sits.',
        'The quick brown dog sleeps.',
      ];

      final score = detector.fragmentationScore(sentences);
      expect(score, greaterThan(0.2));
    });

    test('fragmentationScore returns 0 for natural diverse sentences', () {
      final sentences = [
        'Artificial intelligence has transformed modern computational linguistics across all domains.',
        'Researchers frequently encounter complex mathematical formulations in academic publications.',
        'The autumn leaves drifted softly across the cobblestone pathway leading to the library.',
      ];

      final score = detector.fragmentationScore(sentences);
      expect(score, equals(0.0));
    });

    test('computeDynamicWeights in EvidenceFusionEngine balances classifiers by certainty', () {
      final outputs = [
        (score: 85.0, uncertainty: 0.10), // High confidence
        (score: 40.0, uncertainty: 0.80), // Low confidence
      ];

      final weights = EvidenceFusionEngine.computeDynamicWeights(outputs);

      expect(weights.length, equals(2));
      expect(weights[0], greaterThan(weights[1])); // High confidence classifier gets more weight
      expect((weights[0] + weights[1] - 1.0).abs(), lessThan(1e-5)); // Sums to 1.0
    });
  });
}
