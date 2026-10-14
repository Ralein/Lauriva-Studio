import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lauriva/models/forensic/neural_detection_result.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';

import 'recorded_neural_scores.dart';

/// Replays the shipped bundled detector model's probability
/// for each window text, so benchmarks measure the real neural stream without
/// the ONNX native library (unavailable under `flutter test`).
///
/// To refresh after retraining: run the benchmarks with
/// `RECORD_NEURAL_WINDOWS=<file>` set, then
/// `python3 tool/record_neural_scores.py <file>`.
class RecordedNeuralRunner implements NeuralInferenceRunner {
  static final String? _recordPath = Platform.environment['RECORD_NEURAL_WINDOWS'];

  @override
  NeuralModelState get state => NeuralModelState.ready;

  @override
  Future<void> initialize() async {}

  static String keyFor(String text) => sha256.convert(utf8.encode(text)).toString();

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async {
    final key = keyFor(text);
    final prob = recordedNeuralScores[key];
    if (prob == null) {
      final path = _recordPath;
      if (path == null) {
        throw StateError('No recorded ONNX score for window $key; re-record (see RecordedNeuralRunner docs).');
      }
      File(path).writeAsStringSync('${jsonEncode({'key': key, 'text': text})}\n', mode: FileMode.append);
      return NeuralDetectionResult.fallback(error: 'recording');
    }
    return NeuralDetectionResult(
      aiProbability: prob,
      uncertainty: StandardNeuralRunner.binaryEntropy(prob),
      sentences: const [],
      tokens: const [],
      isFallback: false,
      modelVersion: 'omni_p3_int8 (recorded)',
      inferenceTime: Duration.zero,
    );
  }

  @override
  void dispose() {}
}
