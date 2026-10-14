import '../../../../models/forensic/neural_detection_result.dart';
import '../../segmentation/document_segmenter.dart';
import '../../segmentation/sentence_segmenter.dart';
import '../../segmentation/text_window.dart';
import 'neural_model_config.dart';
import 'onnx_neural_runner.dart';
import 'neural_model_registry.dart';
import 'neural_tokenizer.dart';
import 'typography_normalizer.dart';

/// Master coordinator for on-device Neural Transformer AI Detection.
class NeuralDetectorService {
  final NeuralInferenceRunner runner;
  final NeuralTokenizer tokenizer;
  final DocumentSegmenter documentSegmenter;
  final SentenceSegmenter sentenceSegmenter;
  final NeuralModelConfig config;

  /// Upper bound on transformer passes per document; longer documents are
  /// sampled with evenly spaced windows so latency stays bounded.
  final int maxWindows;

  bool _initialized = false;

  NeuralDetectorService({
    required this.runner,
    required this.tokenizer,
    DocumentSegmenter? documentSegmenter,
    SentenceSegmenter? sentenceSegmenter,
    this.config = const NeuralModelConfig(),
    this.maxWindows = 24,
  })  : documentSegmenter = documentSegmenter ?? TokenAwareDocumentSegmenter(),
        sentenceSegmenter = sentenceSegmenter ?? RuleBasedSentenceSegmenter();

  /// Factory constructor loading default configuration & tokenizer vocabulary.
  static Future<NeuralDetectorService> withDefaults({
    NeuralModelConfig config = const NeuralModelConfig(),
    NeuralInferenceRunner? runner,
  }) async {
    NeuralTokenizer tokenizer;
    try {
      tokenizer = await NeuralModelRegistry.loadTokenizer(config);
    } catch (_) {
      // Fallback empty vocabulary if asset is not yet loaded in tests
      tokenizer = NeuralModelRegistry.fallbackTokenizer(config);
    }

    final activeRunner = runner ?? StandardNeuralRunner(config: config);
    return NeuralDetectorService(
      runner: activeRunner,
      tokenizer: tokenizer,
      config: config,
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await runner.initialize();
      _initialized = true;
    } catch (e) {
      // Runner failed to initialize — will operate in fallback mode
      _initialized = false;
    }
  }

  /// Runs neural detection on [text] across arbitrary lengths using window aggregation.
  Future<NeuralDetectionResult> analyze({
    required String text,
    List<SentenceBoundary>? sentences,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return NeuralDetectionResult.fallback(error: 'Empty document input');
    }
    // Length-preserving, so caller-supplied sentence offsets remain valid.
    final clean = config.normalizeTypography ? TypographyNormalizer.normalize(trimmed) : trimmed;

    await initialize();

    try {
      final sentenceList = sentences ?? sentenceSegmenter.segment(clean);
      final windows = _sampleWindows(documentSegmenter.segment(clean, sentences: sentenceList));

      if (windows.isEmpty) {
        return NeuralDetectionResult.fallback(error: 'Segmentation yielded zero windows');
      }

      final predictions = <WindowPrediction>[];
      final allSentenceEvidence = <SentenceNeuralEvidence>[];
      final allTokens = <TokenEvidence>[];
      final stopwatch = Stopwatch()..start();

      for (final window in windows) {
        // Filter sentences belonging to this window
        final windowSentences = sentenceList
            .where((s) => window.sentenceIndices.contains(s.index))
            .toList();

        final tokenized = tokenizer.tokenize(
          text: window.text,
          sentences: windowSentences,
        );

        final winResult = await runner.runInference(
          input: tokenized,
          sentences: windowSentences,
          text: window.text,
        );

        if (!winResult.isFallback) {
          predictions.add(WindowPrediction(
            window: window,
            aiProbability: winResult.aiProbability,
            uncertainty: winResult.uncertainty,
            weight: window.weight,
          ));
          allSentenceEvidence.addAll(winResult.sentences);
          allTokens.addAll(winResult.tokens);
        }
      }

      stopwatch.stop();

      if (predictions.isEmpty) {
        return NeuralDetectionResult.fallback(
          error: 'All windows executed in fallback mode',
        );
      }

      // Aggregate window scores using weighted average
      final aggregatedProb = aggregateWindowScores(predictions);
      final aggregatedUncertainty = aggregateWindowUncertainty(predictions);

      // Deduplicate sentence evidence by index
      final sentenceMap = <int, SentenceNeuralEvidence>{};
      for (final se in allSentenceEvidence) {
        sentenceMap[se.sentenceIndex] = se;
      }
      final sortedSentences = sentenceMap.values.toList()
        ..sort((a, b) => a.sentenceIndex.compareTo(b.sentenceIndex));

      return NeuralDetectionResult(
        aiProbability: aggregatedProb,
        uncertainty: aggregatedUncertainty,
        sentences: sortedSentences,
        tokens: allTokens,
        isFallback: false,
        modelVersion: config.modelVersion,
        inferenceTime: stopwatch.elapsed,
      );
    } catch (e) {
      // Preserve critical resilience: never crash on unexpected exceptions
      return NeuralDetectionResult.fallback(error: e.toString());
    }
  }

  List<TextWindow> _sampleWindows(List<TextWindow> windows) {
    if (windows.length <= maxWindows) return windows;
    final step = windows.length / maxWindows;
    return [for (int i = 0; i < maxWindows; i++) windows[(i * step).floor()]];
  }

  /// Computes weighted mean across window predictions.
  static double aggregateWindowScores(List<WindowPrediction> predictions) {
    if (predictions.isEmpty) return 0.5;
    double weightedSum = 0.0;
    double totalWeight = 0.0;

    for (final p in predictions) {
      weightedSum += p.aiProbability * p.weight;
      totalWeight += p.weight;
    }

    return totalWeight > 0 ? (weightedSum / totalWeight).clamp(0.0, 1.0) : 0.5;
  }

  /// Computes uncertainty across windows factoring score variance.
  static double aggregateWindowUncertainty(List<WindowPrediction> predictions) {
    if (predictions.isEmpty) return 1.0;
    double weightedUncertainty = 0.0;
    double totalWeight = 0.0;

    for (final p in predictions) {
      weightedUncertainty += p.uncertainty * p.weight;
      totalWeight += p.weight;
    }

    return totalWeight > 0 ? (weightedUncertainty / totalWeight).clamp(0.0, 1.0) : 1.0;
  }

  void dispose() {
    runner.dispose();
  }
}
