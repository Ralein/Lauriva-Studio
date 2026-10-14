import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/evaluation/evaluation_dataset.dart';

void main() {
  test('dump', () {
    final engine = ForensicEngine();
    final out = File(Platform.environment['OUT']!).openSync(mode: FileMode.write);
    void emit(String split, String text, int label, String gen) {
      final r = engine.analyze(text, enableOnlineSearch: false);
      out.writeStringSync('${jsonEncode({'split': split, 'label': label, 'generator': gen, 'text': text, 'stat': r.aiAuthorship.aiProbability / 100.0})}\n');
    }
    for (final f in ['val.jsonl', 'modern_val.jsonl', 'modern_test.jsonl', 'modern_frontier_test.jsonl']) {
      for (final line in File('tool/eval/data/$f').readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
        final r = jsonDecode(line) as Map<String, dynamic>;
        emit(f, r['text'] as String, r['label'] as int, (r['generator'] ?? '?') as String);
      }
    }
    for (final ds in [EvaluationDataset.comprehensiveBenchmarkCorpus(), EvaluationDataset.curatedStandardCorpus()]) {
      for (final s in ds.samples) {
        emit('bench', s.text, s.isAi ? 1 : 0, s.generator);
      }
    }
    out.closeSync();
  }, skip: Platform.environment['OUT'] == null, timeout: const Timeout(Duration(minutes: 60)));
}
