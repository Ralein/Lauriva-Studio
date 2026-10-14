import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/neural_detection_result.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_config.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/evaluation/evaluation_dataset.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';

import '../benchmark/recorded_neural_runner.dart';

/// Scratch: pass 1 (no SCORES file) collects windows into WINDOWS; pass 2
/// dumps {split,label,generator,stat,neural} rows into OUT.
class _FileRunner implements NeuralInferenceRunner {
  final Map<String, double> scores;
  final IOSink? windows;
  _FileRunner(this.scores, this.windows);

  @override
  NeuralModelState get state => NeuralModelState.ready;
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async {
    final key = RecordedNeuralRunner.keyFor(text);
    final p = scores[key];
    if (p == null) {
      windows?.writeln(jsonEncode({'key': key, 'text': text}));
      return NeuralDetectionResult.fallback(error: 'recording');
    }
    return NeuralDetectionResult(
      aiProbability: p,
      uncertainty: StandardNeuralRunner.binaryEntropy(p),
      sentences: const [],
      tokens: const [],
      isFallback: false,
      modelVersion: 'scratch',
      inferenceTime: Duration.zero,
    );
  }
}

void main() {
  test('dump', () async {
    final env = Platform.environment;
    final scoresPath = env['SCORES'];
    final scores = <String, double>{};
    if (scoresPath != null) {
      for (final l in File(scoresPath).readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
        final r = jsonDecode(l) as Map<String, dynamic>;
        scores[r['key'] as String] = (r['p'] as num).toDouble();
      }
    }
    final windows = scoresPath == null ? File(env['WINDOWS']!).openWrite() : null;
    final out = scoresPath != null ? File(env['OUT']!).openWrite() : null;

    final engine = ForensicEngine();
    final neural = NeuralDetectorService(
      runner: _FileRunner(scores, windows),
      tokenizer: PureDartTokenizer.fromVocabString(File('assets/models/vocab.txt').readAsStringSync()),
      config: NeuralModelConfig(normalizeTypography: env['NORMALIZE'] == '1'),
    );

    Future<void> emit(String split, String text, int label, String gen) async {
      if (out == null) {
        await neural.analyze(text: text);
        return;
      }
      final base = engine.analyze(text, enableOnlineSearch: false);
      final n = await neural.analyze(text: text);
      out.writeln(jsonEncode({
        'split': split,
        'label': label,
        'generator': gen,
        'stat': base.aiAuthorship.aiProbability / 100.0,
        'neural': n.aiProbability,
        'fallback': n.isFallback,
      }));
    }

    for (final f in ['val.jsonl', 'modern_val.jsonl', 'modern_test.jsonl', 'modern_frontier_test.jsonl', 'academic_val.jsonl', 'academic_test.jsonl', 'coverage_test.jsonl', 'diverse_val.jsonl', 'diverse_test.jsonl']) {
      for (final line in File('tool/eval/data/$f').readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
        final r = jsonDecode(line) as Map<String, dynamic>;
        await emit(f, r['text'] as String, r['label'] as int, (r['generator'] ?? '?') as String);
      }
    }
    for (final (name, ds) in [
      ('bench_comprehensive', EvaluationDataset.comprehensiveBenchmarkCorpus()),
      ('bench_curated', EvaluationDataset.curatedStandardCorpus()),
    ]) {
      for (final s in ds.samples) {
        await emit(name, s.text, s.isAi ? 1 : 0, s.generator);
      }
    }
    await windows?.close();
    await out?.close();
  }, skip: Platform.environment['WINDOWS'] == null && Platform.environment['SCORES'] == null, timeout: const Timeout(Duration(minutes: 90)));
}
