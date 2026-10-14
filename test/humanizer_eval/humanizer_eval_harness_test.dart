import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/neural_detection_result.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/models/plagiarism_report.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_chunk_engine.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_model.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';
import 'package:lauriva/services/llm_service.dart';
import 'package:lauriva/services/plagiarism_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';

/// Humanizer evaluation harness. Skipped unless HUMANIZER_EVAL_OUT is set.
///
/// Runs held-out AI samples (modern_test + modern_frontier_test, first
/// HUMANIZER_EVAL_PER_GENERATOR per generator) through the humanizer and scores
/// every stage with the Detector screen's fused detector. The ONNX runtime is
/// unavailable under `flutter test`, so window probabilities come from
/// tool/eval/neural_score_server.py; the same scorer drives the pipeline's
/// detector-guided retry, as it does in the app.
///
///   python3 tool/eval/neural_score_server.py &
///   HUMANIZER_EVAL_OUT=/tmp/h.jsonl flutter test test/humanizer_eval
///   python3 tool/eval/summarize_humanizer_eval.py /tmp/h.jsonl
///
/// Without a cloud model the rewrite step is the identity, which isolates the
/// on-device stages. To include the cloud rewrite, also set
/// HUMANIZER_EVAL_PROVIDER (an LlmProvider id), HUMANIZER_EVAL_MODEL and
/// HUMANIZER_EVAL_KEY_FILE (a file containing only the API key).
class _IdentityModel implements HumanizerModel {
  @override
  String get name => 'identity';

  @override
  int get maxContextTokens => 8192;

  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async => context.targetChunk;
}

/// Fetches window probabilities from tool/eval/neural_score_server.py.
class _HttpNeuralRunner implements NeuralInferenceRunner {
  final Uri endpoint;
  final HttpClient _client = HttpClient();

  _HttpNeuralRunner(this.endpoint);

  @override
  NeuralModelState get state => NeuralModelState.ready;

  @override
  Future<void> initialize() async {}

  @override
  void dispose() => _client.close();

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async {
    final request = await _client.postUrl(endpoint);
    final body = utf8.encode(jsonEncode({'text': text}));
    request.headers.contentType = ContentType.json;
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    final p = ((jsonDecode(await response.transform(utf8.decoder).join()) as Map)['p'] as num).toDouble();
    return NeuralDetectionResult(
      aiProbability: p,
      uncertainty: StandardNeuralRunner.binaryEntropy(p),
      sentences: const [],
      tokens: const [],
      isFallback: false,
      modelVersion: '${ForensicCoordinatorService.bundledModelVersion} (served)',
      inferenceTime: Duration.zero,
    );
  }
}

/// flutter_test replaces HttpClient with a mock that answers 400; the harness
/// needs real HTTP for the score server and cloud LLMs.
class _RealHttpOverrides extends HttpOverrides {}

const _placeholderProvider = LlmProvider(
  id: 'identity',
  name: 'Identity',
  tag: 'identity',
  baseUrl: 'https://invalid',
  keyPortalUrl: 'https://invalid',
  keyHint: '',
  description: '',
  defaultModel: 'identity',
  requiresKey: false,
  curatedModels: [],
);

void main() {
  final env = Platform.environment;
  final outPath = env['HUMANIZER_EVAL_OUT'];

  test(
    'humanizer evaluation dump',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final perGenerator = int.tryParse(env['HUMANIZER_EVAL_PER_GENERATOR'] ?? '') ?? 20;
      final providerId = env['HUMANIZER_EVAL_PROVIDER'];
      final cloud = providerId != null;
      final provider = cloud ? LlmProvider.allProviders.firstWhere((p) => p.id == providerId) : _placeholderProvider;
      final apiKey = cloud ? File(env['HUMANIZER_EVAL_KEY_FILE']!).readAsStringSync().trim() : '';
      final modelId = env['HUMANIZER_EVAL_MODEL'] ?? provider.defaultModel;
      final llm = LlmService();

      final samples = <Map<String, dynamic>>[];
      for (final split in ['modern_test.jsonl', 'modern_frontier_test.jsonl']) {
        final taken = <String, int>{};
        for (final line in File('tool/eval/data/$split').readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
          final row = jsonDecode(line) as Map<String, dynamic>;
          if (row['label'] != 1) continue;
          final gen = (row['generator'] ?? '?') as String;
          if ((taken[gen] ?? 0) >= perGenerator) continue;
          taken[gen] = (taken[gen] ?? 0) + 1;
          samples.add({...row, 'split': split, 'id': '$split#$gen#${taken[gen]}'});
        }
      }

      final engine = ForensicEngine();
      final neural = NeuralDetectorService(
        runner: _HttpNeuralRunner(Uri.parse(env['NEURAL_SCORE_URL'] ?? 'http://127.0.0.1:8765/score')),
        tokenizer: PureDartTokenizer.fromVocabString(File('assets/models/vocab.txt').readAsStringSync()),
        config: NeuralModelRegistry.getConfig(ForensicCoordinatorService.bundledModelVersion)!,
      );
      final detector = PlagiarismDetectorService(
        coordinator: ForensicCoordinatorService(engine: engine, neuralLoader: () async => neural),
      );
      Future<PlagiarismReport> scorer(String text) async {
        final report = await detector.analyzeForensic(text, enableOnlineSearch: false);
        // The coordinator silently falls back to stylometry if the neural
        // stream fails; a harness scored that way would be meaningless.
        if (!report.aiAuthorship.detectedSignals.any((s) => s.family == 'Neural')) {
          throw StateError('Neural stream unavailable; is tool/eval/neural_score_server.py running?');
        }
        return report.toLegacyPlagiarismReport();
      }

      const algorithmic = AlgorithmicHumanizerService();
      final chunkEngine = HumanizerChunkEngine();
      final out = File(outPath!).openWrite();
      final pipelineStage = cloud ? 'pipeline_cloud' : 'pipeline_identity';

      Future<void> emit(
        Map<String, dynamic> s,
        String stage,
        String text, [
        Map<String, dynamic> extra = const {},
      ]) async {
        out.writeln(
          jsonEncode({
            'id': s['id'],
            'split': s['split'],
            'generator': s['generator'],
            'stage': stage,
            'text': text,
            'ai': (await scorer(text)).overallScore / 100.0,
            ...extra,
          }),
        );
      }

      for (final s in samples) {
        final text = s['text'] as String;
        await emit(s, 'original', text);
        await emit(s, 'algorithmic', algorithmic.postProcess(text));

        final result = await chunkEngine.processDocument(
          rawText: text,
          tone: WritingToneProfile.professional,
          llmService: llm,
          activeProvider: provider,
          activeApiKey: apiKey,
          activeModel: modelId,
          customModel: cloud ? null : _IdentityModel(),
          throwOnLlmError: cloud,
          documentScorer: scorer,
        );
        final p = result.preservationReport;
        await emit(s, pipelineStage, result.humanizedText, {
          'preservation': p.preservationScore,
          'verdict': p.verdict.name,
          'missingNumbers': p.missingNumbers.length,
          'introducedNumbers': p.introducedNumbers.length,
          'missingCitations': p.missingCitations.length,
        });
      }
      await out.close();
    }, _RealHttpOverrides()),
    skip: outPath == null ? 'set HUMANIZER_EVAL_OUT to run' : false,
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
