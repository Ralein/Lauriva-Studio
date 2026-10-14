import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';
import 'package:lauriva/services/forensic/ai/neural/ort_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';

import 'onnx_parity_goldens.dart';

/// End-to-end check that the shipped ONNX detector, run through
/// [OrtNeuralRunner] and the Dart tokenizer, reproduces Python onnxruntime.
///
/// Needs the ONNX Runtime native library, which `flutter test` does not load
/// by default. On macOS:
///   DYLD_LIBRARY_PATH=~/.pub-cache/hosted/pub.dev/onnxruntime-1.4.1/macos \
///     flutter test test/forensic/onnx_runtime_parity_test.dart
void main() {
  final config = NeuralModelRegistry.getConfig(ForensicCoordinatorService.bundledModelVersion)!;
  final runner = OrtNeuralRunner(
    config: config,
    modelBytesLoader: () async => File(config.modelAsset).readAsBytesSync(),
  );

  String? skipReason;
  setUpAll(() async {
    try {
      await runner.initialize();
    } catch (e) {
      skipReason = 'ONNX Runtime native library unavailable: $e';
    }
  });

  final detector = NeuralDetectorService(
    runner: runner,
    tokenizer: PureDartTokenizer.fromVocabString(File(config.vocabularyAsset).readAsStringSync()),
    config: config,
  );

  for (final golden in onnxParityGoldens) {
    test('matches Python onnxruntime (p=${golden.aiProbability.toStringAsFixed(3)})', () async {
      if (skipReason != null) {
        markTestSkipped(skipReason!);
        return;
      }
      final result = await detector.analyze(text: golden.text);
      expect(result.isFallback, isFalse, reason: result.error);
      expect(result.aiProbability, closeTo(golden.aiProbability, 0.02));
    });
  }
}
