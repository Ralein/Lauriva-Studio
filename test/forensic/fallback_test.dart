import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';

void main() {
  group('Dual-Stream Fallback & Resilience Tests', () {
    test('ForensicEngine gracefully falls back when neural model throws', () async {
      final fallbackRunner = FallbackNeuralRunner(reason: 'GPU out of memory simulation');
      const vocab = '[PAD]\n[UNK]\n[CLS]\n[SEP]';
      final tokenizer = PureDartTokenizer.fromVocabString(vocab);
      final neuralService = NeuralDetectorService(
        runner: fallbackRunner,
        tokenizer: tokenizer,
      );

      final engine = ForensicEngine(neuralDetector: neuralService);
      final text = 'This is a resilient test document analyzed under simulated neural fallback.';

      final report = await engine.analyzeWithNeural(text);

      expect(report.wordCount, greaterThan(0));
      expect(report.aiAuthorship.aiProbability, inInclusiveRange(0.0, 100.0));
      expect(report.sentences.isNotEmpty, isTrue);
    });
  });
}
