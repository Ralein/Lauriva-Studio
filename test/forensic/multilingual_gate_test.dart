import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/neural_detection_result.dart';
import 'package:lauriva/services/forensic/ai/multilingual_feature_profiles.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_config.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_tokenizer.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/ai/neural/sentencepiece_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';

/// Records every window it is asked to score, so tests can see which
/// languages actually reached the neural stream.
class _RecordingRunner implements NeuralInferenceRunner {
  final List<String> seen = [];

  @override
  NeuralModelState get state => NeuralModelState.ready;

  @override
  Future<void> initialize() async {}

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async {
    seen.add(text);
    return NeuralDetectionResult(
      aiProbability: 0.9,
      uncertainty: StandardNeuralRunner.binaryEntropy(0.9),
      sentences: const [],
      tokens: const [],
      isFallback: false,
      modelVersion: 'recording',
      inferenceTime: Duration.zero,
    );
  }

  @override
  void dispose() {}
}

const _multiConfig = NeuralModelConfig(
  modelVersion: 'multilingual_test',
  tokenizerType: NeuralTokenizerType.sentencepiece,
  vocabularyAsset: 'assets/models/does_not_exist_spm.txt',
  supportedLanguages: {'en', 'es', 'ja'},
);

NeuralDetectorService _service(_RecordingRunner runner, NeuralModelConfig config) => NeuralDetectorService(
      runner: runner,
      tokenizer: NeuralModelRegistry.fallbackTokenizer(config),
      config: config,
    );

void main() {
  final fixture = jsonDecode(File('test/forensic/fixtures/wiki_language_samples.json').readAsStringSync())
      as Map<String, dynamic>;
  final paragraphs = (fixture['paragraphs'] as Map<String, dynamic>)
      .map((lang, ps) => MapEntry(lang, (ps as List).cast<String>()));

  group('(a) default config keeps the English-only gate', () {
    test('shipped config is Omni byte-level BPE and English-only', () {
      final config = NeuralModelRegistry.getConfig(ForensicCoordinatorService.bundledModelVersion)!;
      expect(config.tokenizerType, NeuralTokenizerType.bpe);
      expect(config.supportedLanguages, {'en'});
      expect(ForensicCoordinatorService.bundledNeuralLanguages, {'en'});
      expect(ForensicEngine().neuralLanguages, {'en'});
    });

    test('neuralCovers with default languages equals LanguageDetector.isEnglish on every fixture', () {
      for (final entry in paragraphs.entries) {
        for (final p in entry.value) {
          final expected = LanguageDetector.isEnglish(p);
          expect(ForensicEngine.neuralCovers(p), expected, reason: entry.key);
          expect(ForensicEngine.neuralCovers(p, languages: const {'en'}), expected, reason: entry.key);
          expect(
            ForensicEngine.neuralCovers(p, languages: ForensicCoordinatorService.bundledNeuralLanguages),
            expected,
            reason: entry.key,
          );
        }
      }
    });

    test('non-English text never reaches a default-config detector', () async {
      final runner = _RecordingRunner();
      final engine = ForensicEngine();
      final report = await engine.analyzeWithNeural(paragraphs['es']!.first,
          neuralDetector: _service(runner, const NeuralModelConfig()), enableOnlineSearch: false);
      expect(runner.seen, isEmpty);
      expect(report.aiAuthorship.detectedSignals.firstWhere((s) => s.family == 'Language').description,
          contains('English only'));
    });
  });

  group('(b) config-driven languages', () {
    test('neuralCovers follows supportedLanguages', () {
      const langs = {'en', 'es', 'ja'};
      for (final lang in ['en', 'es', 'ja']) {
        for (final p in paragraphs[lang]!) {
          expect(ForensicEngine.neuralCovers(p, languages: langs), isTrue, reason: lang);
        }
      }
      for (final p in paragraphs['ta']!) {
        expect(ForensicEngine.neuralCovers(p, languages: langs), isFalse);
      }
      // English is not covered by a model that was not trained on it.
      expect(ForensicEngine.neuralCovers(paragraphs['en']!.first, languages: const {'es'}), isFalse);
    });

    test('analyzeWithNeural lets Spanish and Japanese reach the runner but not Tamil', () async {
      final engine = ForensicEngine();
      for (final lang in ['es', 'ja', 'ta']) {
        final runner = _RecordingRunner();
        final report = await engine.analyzeWithNeural(paragraphs[lang]!.first,
            neuralDetector: _service(runner, _multiConfig), enableOnlineSearch: false);
        final signals = report.aiAuthorship.detectedSignals;
        final language = signals.firstWhere((s) => s.family == 'Language').description;
        expect(language, isNot(contains('English only')), reason: lang);
        if (lang == 'ta') {
          expect(runner.seen, isEmpty);
          expect(signals.any((s) => s.family == 'Neural'), isFalse);
          expect(language, contains('does not cover Tamil'));
        } else {
          expect(runner.seen, isNotEmpty, reason: lang);
          expect(signals.any((s) => s.family == 'Neural'), isTrue, reason: lang);
          expect(language, isNot(contains('stylometry alone')), reason: lang);
        }
      }
    });

    test('coordinator gates on its neural languages before loading the model', () async {
      for (final lang in ['es', 'ja', 'ta']) {
        final runner = _RecordingRunner();
        var loaded = 0;
        final coordinator = ForensicCoordinatorService(
          neuralLanguages: _multiConfig.supportedLanguages,
          neuralLoader: () async {
            loaded++;
            return _service(runner, _multiConfig);
          },
        );
        await coordinator.coordinate(text: paragraphs[lang]!.first, enableOnlineSearch: false);
        if (lang == 'ta') {
          expect(loaded, 0);
          expect(runner.seen, isEmpty);
        } else {
          expect(loaded, 1, reason: lang);
          expect(runner.seen, isNotEmpty, reason: lang);
        }
      }
    });
  });

  group('(c) NeuralModelConfig JSON', () {
    test('round-trips tokenizerType and supportedLanguages', () {
      final back = NeuralModelConfig.fromJson(jsonDecode(jsonEncode(_multiConfig.toJson())) as Map<String, dynamic>);
      expect(back.tokenizerType, NeuralTokenizerType.sentencepiece);
      expect(back.supportedLanguages, {'en', 'es', 'ja'});
      expect(back.modelVersion, 'multilingual_test');
    });

    test('missing or unknown fields default to the shipped WordPiece/English config', () {
      final legacy = NeuralModelConfig.fromJson(const {});
      expect(legacy.tokenizerType, NeuralTokenizerType.wordpiece);
      expect(legacy.supportedLanguages, {'en'});
      expect(NeuralModelConfig.fromJson(const {'tokenizerType': 'unknown-tokenizer'}).tokenizerType, NeuralTokenizerType.wordpiece);
      final json = const NeuralModelConfig().toJson();
      expect(json['tokenizerType'], 'wordpiece');
      expect(json['supportedLanguages'], ['en']);
    });

    test('copyWith carries the new fields', () {
      final c = const NeuralModelConfig().copyWith(
        tokenizerType: NeuralTokenizerType.sentencepiece,
        supportedLanguages: {'en', 'fr'},
      );
      expect(c.tokenizerType, NeuralTokenizerType.sentencepiece);
      expect(c.supportedLanguages, {'en', 'fr'});
      expect(c.copyWith(modelVersion: 'x').supportedLanguages, {'en', 'fr'});
    });
  });

  group('(d) registry tokenizer type', () {
    tearDown(NeuralModelRegistry.clearCache);

    test('wordpiece configs still build a PureDartTokenizer', () {
      final t = NeuralModelRegistry.buildTokenizer(const NeuralModelConfig(), '[PAD]\n[UNK]\n[CLS]\n[SEP]\nthe');
      expect(t, isA<PureDartTokenizer>());
    });

    test('a sentencepiece config without its asset falls back to a SentencePieceTokenizer', () async {
      NeuralModelRegistry.registerModel(_multiConfig);
      final NeuralTokenizer t = await NeuralModelRegistry.getTokenizer(modelVersion: _multiConfig.modelVersion);
      expect(t, isA<SentencePieceTokenizer>());
      final res = t.tokenize(text: 'hola');
      expect(res.inputIds.length, t.maxSequenceLength);
      expect(res.inputIds.first, (t as SentencePieceTokenizer).bosTokenId);
    });

    const vocabPath = 'tool/checkpoints/multilingual_tokenizer/sentencepiece_unigram.txt';
    final vocabFile = File(vocabPath);
    test('builds a SentencePieceTokenizer from the exported vocab', () {
      final t = NeuralModelRegistry.buildTokenizer(_multiConfig, vocabFile.readAsStringSync());
      expect(t, isA<SentencePieceTokenizer>());
      final res = t.tokenize(text: 'Hola mundo, esto es una prueba.');
      expect(res.attentionMask.where((m) => m == 1).length, greaterThan(3));
      expect(res.inputIds.length, _multiConfig.maxSequenceLength);
    }, skip: vocabFile.existsSync() ? false : '$vocabPath absent (gitignored)');
  });
}
