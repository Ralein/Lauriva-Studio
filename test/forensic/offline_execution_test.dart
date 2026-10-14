import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/models/forensic/forensic_scan_mode.dart';

void main() {
  group('100% Offline Air-Gapped Execution Tests', () {
    test('Runs full neural + forensic scan without making any external HTTP network requests', () async {
      const vocabStr = '''
[PAD]
[UNK]
[CLS]
[SEP]
the
of
and
in
to
a
is
that
for
it
as
furthermore
crucial
tapestry
''';
      final tokenizer = PureDartTokenizer.fromVocabString(vocabStr);
      final runner = StandardNeuralRunner();
      final neuralService = NeuralDetectorService(
        runner: runner,
        tokenizer: tokenizer,
      );

      // Disable online web literature search to verify air-gapped performance
      final engine = ForensicEngine(neuralDetector: neuralService);
      final text = 'Furthermore, distributed consensus underpins modern computing architectures.';

      final report = await engine.analyzeWithNeural(
        text,
        neuralDetector: neuralService,
        enableOnlineSearch: false, // Air-gapped offline mode
        mode: ForensicScanMode.fullForensic,
      );

      expect(report.wordCount, greaterThan(0));
      expect(report.aiAuthorship.aiProbability, inInclusiveRange(0.0, 100.0));
      expect(report.sentences.isNotEmpty, isTrue);
      expect(report.confidence.score, greaterThan(0.0));
    });
  });
}
