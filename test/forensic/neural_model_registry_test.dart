import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_config.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NeuralModelRegistry Tests', () {
    tearDown(() {
      NeuralModelRegistry.clearCache();
    });

    test('retrieves default active model configuration', () {
      final config = NeuralModelRegistry.activeConfig;
      expect(config.modelVersion, equals('omni_p3_int8'));
      expect(config.normalizeTypography, isTrue);
      expect(config.quantization, equals('int4_awp_sota'));
      expect(config.maxSequenceLength, equals(512));
    });

    test('v6 config matches its SentencePiece tokenizer and ONNX inputs', () {
      final config = NeuralModelRegistry.getConfig('plagiarism_v6_sota')!;
      expect(NeuralModelRegistry.getConfig('plagiarism_v6'), same(config));
      expect(config.tokenizerType, equals(NeuralTokenizerType.sentencepiece));
      expect(config.expectedVocabularySize, equals(250002));
      expect(config.maxSequenceLength, equals(256));
      expect(config.vocabularyAsset, isNot(endsWith('vocab.txt')));
      expect(config.inputNames.keys, unorderedEquals(['input_ids', 'attention_mask']));
      expect(config.outputNames.keys, unorderedEquals(['logits', 'attribution_logits']));
    });

    test('v6 tokenizer built from the exported vocab stays inside the vocab', () {
      const path = 'tool/checkpoints/multilingual_tokenizer/sentencepiece_unigram.txt';
      if (!File(path).existsSync()) {
        markTestSkipped('vocab export not present');
        return;
      }
      final config = NeuralModelRegistry.getConfig('plagiarism_v6_sota')!;
      final tok = NeuralModelRegistry.buildTokenizer(config, File(path).readAsStringSync());
      final enc = tok.tokenize(text: 'The quick brown fox jumps over the lazy dog.');
      expect(enc.inputIds.first, equals(0)); // <s>
      expect(enc.inputIds.length, equals(config.maxSequenceLength));
      expect(enc.inputIds.every((id) => id >= 0 && id < config.expectedVocabularySize), isTrue);
    });

    test('switches active model version', () {
      NeuralModelRegistry.registerModel(const NeuralModelConfig(
        modelVersion: 'candidate_switch',
        architecture: 'modernbert-distilled',
      ));
      NeuralModelRegistry.setActiveModel('candidate_switch');
      expect(NeuralModelRegistry.activeModelVersion, equals('candidate_switch'));
      expect(NeuralModelRegistry.activeConfig.architecture, equals('modernbert-distilled'));

      // Unknown versions are ignored.
      NeuralModelRegistry.setActiveModel('plagiarism_v_unknown');
      expect(NeuralModelRegistry.activeModelVersion, equals('candidate_switch'));

      NeuralModelRegistry.setActiveModel('omni_p3_int8');
      expect(NeuralModelRegistry.activeModelVersion, equals('omni_p3_int8'));
    });

    test('registers custom candidate model', () {
      const customConfig = NeuralModelConfig(
        modelVersion: 'student_custom_v3',
        modelAsset: 'assets/models/custom_v3.onnx',
        vocabularyAsset: 'assets/models/vocab.txt',
        maxSequenceLength: 256,
        expectedVocabularySize: 10000,
        architecture: 'tiny-transformer',
        quantization: 'int4',
      );

      NeuralModelRegistry.registerModel(customConfig);
      expect(NeuralModelRegistry.availableVersions.contains('student_custom_v3'), isTrue);
      expect(NeuralModelRegistry.getConfig('student_custom_v3')?.quantization, equals('int4'));
    });

    test('caches tokenizer and runner instances across repeated requests', () async {
      final t1 = await NeuralModelRegistry.getTokenizer(modelVersion: 'omni_p3_int8');
      final t2 = await NeuralModelRegistry.getTokenizer(modelVersion: 'omni_p3_int8');
      expect(identical(t1, t2), isTrue);

      final r1 = await NeuralModelRegistry.getRunner(modelVersion: 'omni_p3_int8');
      final r2 = await NeuralModelRegistry.getRunner(modelVersion: 'omni_p3_int8');
      expect(identical(r1, r2), isTrue);
    });
  });
}
