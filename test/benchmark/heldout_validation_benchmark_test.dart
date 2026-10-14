import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';

import 'recorded_neural_runner.dart';

/// Held-out HC3/RAID validation split (never used to train the transformer):
/// the production dual-stream detector must clearly beat the stylometric
/// engine alone, which is what shipped before the ONNX model was wired in.
void main() {
  test('dual-stream fusion beats stylometry on held-out HC3/RAID validation', () async {
    final rows = File('tool/eval/data/val.jsonl')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();

    final engine = ForensicEngine();
    final neural = NeuralDetectorService(
      runner: RecordedNeuralRunner(),
      tokenizer: PureDartTokenizer.fromVocabString(File('assets/models/vocab.txt').readAsStringSync()),
      config: NeuralModelRegistry.getConfig(ForensicCoordinatorService.bundledModelVersion)!,
    );

    final stat = <({double p, bool ai})>[];
    final fused = <({double p, bool ai})>[];
    // Set FUSION_SCORES_OUT to export per-sample stream scores for tool/fit_fusion_stack.py.
    final scoresOut = Platform.environment['FUSION_SCORES_OUT'];
    final exported = StringBuffer();
    for (final row in rows) {
      final text = row['text'] as String;
      final isAi = row['label'] == 1;
      final base = engine.analyze(text, enableOnlineSearch: false);
      final neuralResult = await neural.analyze(text: text);
      final report = engine.fuseWithNeural(base, neuralResult);
      exported.writeln(jsonEncode({
        'label': isAi ? 1 : 0,
        'stat': base.aiAuthorship.aiProbability / 100.0,
        'neural': neuralResult.aiProbability,
      }));
      stat.add((p: base.aiAuthorship.aiProbability / 100.0, ai: isAi));
      fused.add((p: report.aiAuthorship.aiProbability / 100.0, ai: isAi));
    }

    if (scoresOut != null) File(scoresOut).writeAsStringSync(exported.toString());

    double accuracy(List<({double p, bool ai})> xs) => xs.where((x) => (x.p >= 0.5) == x.ai).length / xs.length;
    double fpr(List<({double p, bool ai})> xs) =>
        xs.where((x) => !x.ai && x.p >= 0.5).length / xs.where((x) => !x.ai).length;
    double brier(List<({double p, bool ai})> xs) =>
        xs.map((x) => (x.p - (x.ai ? 1 : 0)) * (x.p - (x.ai ? 1 : 0))).reduce((a, b) => a + b) / xs.length;

    // ignore: avoid_print
    print('held-out n=${rows.length} | stylometric acc ${accuracy(stat).toStringAsFixed(3)} '
        'FPR ${fpr(stat).toStringAsFixed(3)} Brier ${brier(stat).toStringAsFixed(3)} | '
        'fused acc ${accuracy(fused).toStringAsFixed(3)} FPR ${fpr(fused).toStringAsFixed(3)} '
        'Brier ${brier(fused).toStringAsFixed(3)}');

    expect(accuracy(fused), greaterThanOrEqualTo(0.90));
    expect(fpr(fused), lessThanOrEqualTo(0.10));
    expect(accuracy(fused), greaterThan(accuracy(stat) + 0.20));
    expect(brier(fused), lessThan(brier(stat)));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
