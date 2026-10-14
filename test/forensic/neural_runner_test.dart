import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';

void main() {
  group('NeuralInferenceRunner Tests', () {
    test('softmaxAiProbability computes mathematically correct ratio', () {
      expect(StandardNeuralRunner.softmaxAiProbability(0.0, 0.0), closeTo(0.5, 0.001));
      expect(StandardNeuralRunner.softmaxAiProbability(-2.0, 2.0), greaterThan(0.95));
      expect(StandardNeuralRunner.softmaxAiProbability(2.0, -2.0), lessThan(0.05));
    });

    test('binaryEntropy is 0 at certainty and 1 at 0.5 probability', () {
      expect(StandardNeuralRunner.binaryEntropy(0.5), closeTo(1.0, 0.001));
      expect(StandardNeuralRunner.binaryEntropy(0.9999), lessThan(0.02));
      expect(StandardNeuralRunner.binaryEntropy(0.0001), lessThan(0.02));
    });

    test('FallbackNeuralRunner returns fallback result', () async {
      final runner = FallbackNeuralRunner(reason: 'Test fallback');
      await runner.initialize();

      const vocab = '[PAD]\n[UNK]\n[CLS]\n[SEP]';
      final tokenizer = PureDartTokenizer.fromVocabString(vocab);
      final tokenized = tokenizer.tokenize(text: 'sample');

      final result = await runner.runInference(input: tokenized, sentences: const []);
      expect(result.isFallback, isTrue);
      expect(result.error, equals('Test fallback'));
    });

    test('StandardNeuralRunner lifecycle and inference', () async {
      final runner = StandardNeuralRunner();
      expect(runner.state, equals(NeuralModelState.uninitialized));

      await runner.initialize();
      expect(runner.state, equals(NeuralModelState.ready));

      const vocab = '[PAD]\n[UNK]\n[CLS]\n[SEP]\nsample\ntext';
      final tokenizer = PureDartTokenizer.fromVocabString(vocab);
      final sentenceSegmenter = RuleBasedSentenceSegmenter();
      final text = 'Sample text for neural run.';
      final sents = sentenceSegmenter.segment(text);
      final tokenized = tokenizer.tokenize(text: text, sentences: sents);

      final result = await runner.runInference(
        input: tokenized,
        sentences: sents,
        text: text,
      );

      expect(result.isFallback, isFalse);
      expect(result.aiProbability, inInclusiveRange(0.0, 1.0));
      expect(result.uncertainty, inInclusiveRange(0.0, 1.0));
      expect(result.sentences.length, equals(sents.length));

      runner.dispose();
      expect(runner.state, equals(NeuralModelState.disposed));
    });
  });
}
