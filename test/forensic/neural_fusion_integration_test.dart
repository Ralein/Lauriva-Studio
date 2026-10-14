import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/neural_detection_result.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/fusion/evidence_fusion_engine.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';


class _FixedRunner implements NeuralInferenceRunner {
  final double probability;
  _FixedRunner(this.probability);

  @override
  NeuralModelState get state => NeuralModelState.ready;

  @override
  Future<void> initialize() async {}

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async =>
      NeuralDetectionResult(
        aiProbability: probability,
        uncertainty: StandardNeuralRunner.binaryEntropy(probability),
        sentences: const [],
        tokens: const [],
        isFallback: false,
        modelVersion: 'fixed',
        inferenceTime: Duration.zero,
      );

  @override
  void dispose() {}
}

NeuralDetectorService _neuralReturning(double p) => NeuralDetectorService(
      runner: _FixedRunner(p),
      tokenizer: PureDartTokenizer.fromVocabString('[PAD]\n[UNK]\n[CLS]\n[SEP]\nthe\na'),
    );

const _humanText = 'I forgot my umbrella on the subway yesterday morning, so I had to run four blocks '
    'through heavy rain to reach class on time. My shoes squelched all through the lecture and the '
    'professor kept glancing at the puddle under my desk. Next week I am buying a cheap backup umbrella '
    'and leaving it in my locker, because this keeps happening every single autumn.';

void main() {
  group('Stacked dual-stream fusion', () {
    final fusion = EvidenceFusionEngine();

    test('stylometry cannot overturn a confident human neural score', () {
      // The Omni stack is neural-only (stylometry AUC 0.64 adds nothing: see FusionConfig),
      // so a confident human neural score cannot be raised by any stylometric score.
      expect(fusion.stackedProbability(0.0, 0.99), closeTo(fusion.stackedProbability(0.0, 0.5), 1e-9));
      expect(fusion.stackedProbability(0.0, 0.99), lessThan(fusion.stackedProbability(0.98, 0.99) - 0.1));
    });

    test('both streams human yields a low AI probability', () {
      expect(fusion.stackedProbability(0.02, 0.20), lessThan(0.15));
    });

    test('both streams AI yields a high AI probability', () {
      expect(fusion.stackedProbability(0.98, 0.90), greaterThan(0.85));
    });

    test('is monotone in each stream', () {
      expect(fusion.stackedProbability(0.9, 0.4), greaterThan(fusion.stackedProbability(0.3, 0.4)));
      // Stylometry has zero weight in the Omni stack: non-decreasing, never inverted.
      expect(fusion.stackedProbability(0.4, 0.9), greaterThanOrEqualTo(fusion.stackedProbability(0.4, 0.3)));
    });
  });

  group('ForensicEngine.fuseWithNeural', () {
    final engine = ForensicEngine();

    test('returns the statistical report unchanged when the neural stream fell back', () {
      final base = engine.analyze(_humanText, enableOnlineSearch: false);
      final fused = engine.fuseWithNeural(base, NeuralDetectionResult.fallback(error: 'n/a'));
      expect(identical(fused, base), isTrue);
    });

    test('adds a Neural signal and re-derives sentence audits from the fused score', () async {
      final base = engine.analyze(_humanText, enableOnlineSearch: false);
      final result = await _neuralReturning(0.99).analyze(text: _humanText);
      final fused = engine.fuseWithNeural(base, result);
      expect(fused.aiAuthorship.detectedSignals.first.family, 'Neural');
      expect(fused.aiAuthorship.aiProbability, greaterThan(base.aiAuthorship.aiProbability));
      expect(fused.sentences.length, base.sentences.length);
    });
  });

  group('ForensicCoordinatorService neural wiring', () {
    test('fuses the loaded neural detector into full forensic scans', () async {
      final statOnly = ForensicCoordinatorService(
        neuralLoader: () async => null,
      );
      final withNeural = ForensicCoordinatorService(
        neuralLoader: () async => _neuralReturning(0.01),
      );
      final a = await statOnly.coordinate(text: _humanText, enableOnlineSearch: false);
      final b = await withNeural.coordinate(text: _humanText, enableOnlineSearch: false);
      expect(a.aiAuthorship.detectedSignals.any((s) => s.family == 'Neural'), isFalse);
      expect(b.aiAuthorship.detectedSignals.any((s) => s.family == 'Neural'), isTrue);
      expect(b.aiAuthorship.aiProbability, lessThan(35.0));
    });

    test('a failing neural loader leaves the statistical report intact', () async {
      final coordinator = ForensicCoordinatorService(
        neuralLoader: () async => throw StateError('boom'),
      );
      final report = await coordinator.coordinate(text: _humanText, enableOnlineSearch: false);
      expect(report.wordCount, greaterThan(0));
    });

    test('skips the English-only transformer for other languages', () async {
      var loaded = 0;
      final coordinator = ForensicCoordinatorService(
        neuralLoader: () async {
          loaded++;
          return _neuralReturning(0.99);
        },
      );
      final report = await coordinator.coordinate(text: _spanishText, enableOnlineSearch: false);
      final signals = report.aiAuthorship.detectedSignals;
      expect(loaded, 0);
      expect(signals.any((s) => s.family == 'Neural'), isFalse);
      expect(signals.firstWhere((s) => s.family == 'Language').description, contains('English only'));
    });

    test('analyzeWithNeural applies the same language gate', () async {
      final engine = ForensicEngine();
      final spanish = await engine.analyzeWithNeural(_spanishText,
          neuralDetector: _neuralReturning(0.99), enableOnlineSearch: false);
      final english = await engine.analyzeWithNeural(_humanText,
          neuralDetector: _neuralReturning(0.99), enableOnlineSearch: false);
      expect(spanish.aiAuthorship.detectedSignals.any((s) => s.family == 'Neural'), isFalse);
      expect(english.aiAuthorship.detectedSignals.any((s) => s.family == 'Neural'), isTrue);
      expect(ForensicEngine.neuralCovers(_humanText), isTrue);
      expect(ForensicEngine.neuralCovers(_spanishText), isFalse);
    });
  });
}

const _spanishText = 'Olvidé mi paraguas en el metro ayer por la mañana, así que tuve que correr cuatro cuadras '
    'bajo la lluvia para llegar a clase a tiempo. Mis zapatos chapoteaban durante toda la lección y el profesor '
    'no dejaba de mirar el charco que se formaba debajo de mi pupitre. La próxima semana voy a comprar un '
    'paraguas barato de repuesto y lo dejaré en mi casillero, porque esto me pasa todos los otoños.';
