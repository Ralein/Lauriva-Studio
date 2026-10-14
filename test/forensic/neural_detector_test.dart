import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';

void main() {
  group('NeuralDetectorService Tests', () {
    late NeuralDetectorService service;

    setUp(() {
      const vocabStr = '''
[PAD]
[UNK]
[CLS]
[SEP]
the
quick
brown
fox
jumps
over
lazy
dog
in
conclusion
technological
innovations
accelerate
''';
      final tokenizer = PureDartTokenizer.fromVocabString(vocabStr);
      final runner = StandardNeuralRunner();
      service = NeuralDetectorService(
        runner: runner,
        tokenizer: tokenizer,
      );
    });

    test('analyzes text across multiple sentences', () async {
      final text = 'The quick brown fox jumps over the lazy dog. In conclusion, technological innovations accelerate data.';
      final result = await service.analyze(text: text);

      expect(result.isFallback, isFalse);
      expect(result.aiProbability, inInclusiveRange(0.0, 1.0));
      expect(result.uncertainty, inInclusiveRange(0.0, 1.0));
      expect(result.sentences.length, greaterThanOrEqualTo(1));
    });

    test('empty text returns fallback result without crashing', () async {
      final result = await service.analyze(text: '');
      expect(result.isFallback, isTrue);
      expect(result.aiProbability, equals(0.5));
    });
  });
}
