import 'dart:io';
import 'model_delivery_service.dart';
import 'neural_model_config.dart';
import 'onnx_neural_runner.dart';
import 'ort_runner_factory.dart';
import 'neural_tokenizer.dart';
import 'pure_dart_tokenizer.dart';
import 'bpe_tokenizer.dart';
import 'sentencepiece_tokenizer.dart';

/// Registry for managing multi-version neural model configurations and warm session caches.
class NeuralModelRegistry {
  /// Registry version of the detector bundled in assets/models.
  static const String bundledModelVersion = 'omni_p3_int8';

  // Only Omni (bundled) and v6 are supported; all older detectors were removed.
  static final Map<String, NeuralModelConfig> _registeredConfigs = {
    'plagiarism_v6': NeuralModelConfig.v6Sota,
    'plagiarism_v6_sota': NeuralModelConfig.v6Sota,
    'omni_p3_int8': NeuralModelConfig.v7Omni,
  };

  static String _activeModelVersion = bundledModelVersion;
  static final Map<String, NeuralTokenizer> _tokenizerCache = {};
  static final Map<String, NeuralInferenceRunner> _runnerCache = {};
  static ModelDeliveryService? _deliveryService;

  static ModelDeliveryService get deliveryService =>
      _deliveryService ??= ModelDeliveryService();

  static void setDeliveryService(ModelDeliveryService service) {
    _deliveryService = service;
  }

  static String get activeModelVersion => _activeModelVersion;

  static void setActiveModel(String modelVersion) {
    if (_registeredConfigs.containsKey(modelVersion)) {
      _activeModelVersion = modelVersion;
    }
  }

  static void registerModel(NeuralModelConfig config) {
    _registeredConfigs[config.modelVersion] = config;
  }

  static NeuralModelConfig get activeConfig {
    return _registeredConfigs[_activeModelVersion] ?? const NeuralModelConfig();
  }

  static NeuralModelConfig? getConfig(String version) {
    return _registeredConfigs[version];
  }

  /// Config of the bundled detector (independent of [setActiveModel]).
  static NeuralModelConfig get bundledConfig => getConfig(bundledModelVersion) ?? const NeuralModelConfig();

  static List<String> get availableVersions => _registeredConfigs.keys.toList();

  /// Builds the tokenizer [config] was trained with from raw vocab content
  /// (`vocab.txt` for WordPiece, the exported Unigram vocab for SentencePiece,
  /// `tokenizer.json` for BPE).
  static NeuralTokenizer buildTokenizer(NeuralModelConfig config, String vocabContent) {
    switch (config.tokenizerType) {
      case NeuralTokenizerType.wordpiece:
        return PureDartTokenizer.fromVocabString(vocabContent, config: config);
      case NeuralTokenizerType.sentencepiece:
        return SentencePieceTokenizer.fromVocabString(
          vocabContent,
          maxSequenceLength: config.maxSequenceLength,
        );
      case NeuralTokenizerType.bpe:
        return BpeTokenizer.fromJsonString(vocabContent, maxSequenceLength: config.maxSequenceLength);
    }
  }

  /// Loads the tokenizer for [config] from its bundled [NeuralModelConfig.vocabularyAsset].
  static Future<NeuralTokenizer> loadTokenizer(NeuralModelConfig config) async {
    switch (config.tokenizerType) {
      case NeuralTokenizerType.wordpiece:
        return PureDartTokenizer.loadFromAsset(config.vocabularyAsset, config: config);
      case NeuralTokenizerType.sentencepiece:
        return SentencePieceTokenizer.loadFromAsset(
          config.vocabularyAsset,
          maxSequenceLength: config.maxSequenceLength,
        );
      case NeuralTokenizerType.bpe:
        return BpeTokenizer.loadFromAsset(config.vocabularyAsset, maxSequenceLength: config.maxSequenceLength);
    }
  }

  /// Special-tokens-only tokenizer of the right type, used when the vocab
  /// asset cannot be loaded (e.g. unit tests without bundled assets).
  static NeuralTokenizer fallbackTokenizer(NeuralModelConfig config) {
    switch (config.tokenizerType) {
      case NeuralTokenizerType.wordpiece:
        return PureDartTokenizer.fromVocabString('[PAD]\n[UNK]\n[CLS]\n[SEP]', config: config);
      case NeuralTokenizerType.sentencepiece:
        return SentencePieceTokenizer.fromVocabString(
          '#lauriva-spm-unigram v1\n#unk_id 3\n#pieces 4\n<s>\t0\n<pad>\t0\n</s>\t0\n<unk>\t0',
          maxSequenceLength: config.maxSequenceLength,
        );
      case NeuralTokenizerType.bpe:
        return BpeTokenizer.fromJsonString(
          '{"model":{"type":"BPE","vocab":{},"merges":[]},"added_tokens":['
          '{"id":0,"content":"[PAD]"},{"id":1,"content":"[UNK]"},'
          '{"id":2,"content":"[CLS]"},{"id":3,"content":"[SEP]"}]}',
          maxSequenceLength: config.maxSequenceLength,
        );
    }
  }

  /// Gets or creates a cached tokenizer for the specified or active model configuration.
  static Future<NeuralTokenizer> getTokenizer({String? modelVersion}) async {
    final version = modelVersion ?? _activeModelVersion;
    if (_tokenizerCache.containsKey(version)) {
      return _tokenizerCache[version]!;
    }

    final config = getConfig(version) ?? activeConfig;
    NeuralTokenizer tokenizer;
    try {
      tokenizer = await loadTokenizer(config);
    } catch (_) {
      // Fallback in-memory tokenizer
      tokenizer = fallbackTokenizer(config);
    }
    _tokenizerCache[version] = tokenizer;
    return tokenizer;
  }

  /// Gets or creates a cached inference runner for the specified model version.
  static Future<NeuralInferenceRunner> getRunner({String? modelVersion}) async {
    final version = modelVersion ?? _activeModelVersion;
    if (_runnerCache.containsKey(version)) {
      return _runnerCache[version]!;
    }

    var config = getConfig(version) ?? activeConfig;

    // Decide synchronously when ONNX Runtime is absent so no model I/O is
    // attempted (and nothing is awaited) on platforms that cannot use it.
    if (createOrtRunner(config) == null) {
      final runner = FallbackNeuralRunner(reason: 'ONNX Runtime unavailable on this platform');
      _runnerCache[version] = runner;
      return runner;
    }

    // Check if downloaded locally via on-demand model delivery
    var localPath = await deliveryService.getModelLocalPath(modelVersion: version);
    if (localPath == null && !Platform.environment.containsKey('FLUTTER_TEST')) {
      // First launch: extract the bundled model (SHA-256 checked against the pinned digest).
      if (await deliveryService.extractBundledModel(modelVersion: version)) {
        localPath = await deliveryService.getModelLocalPath(modelVersion: version);
      }
    }
    if (localPath != null) {
      config = config.copyWith(localFilePath: localPath);
    } else {
      // Not bundled/extractable: fetch it in the background (unmetered network only) and
      // answer with the statistical engine now. The fallback is not cached, so the next
      // scan picks the model up once it lands.
      deliveryService.ensureInBackground(modelVersion: version);
      return FallbackNeuralRunner(reason: 'detector model not available yet');
    }

    // The trained ONNX model via ONNX Runtime. When the runtime cannot load
    // (web, unit tests without the native library, missing asset) the
    // fallback runner makes callers use the statistical engine alone rather
    // than a heuristic masquerading as the neural model.
    NeuralInferenceRunner runner;
    final ortRunner = createOrtRunner(config);
    if (ortRunner == null) {
      runner = FallbackNeuralRunner(reason: 'ONNX Runtime unavailable on this platform');
    } else {
      try {
        await ortRunner.initialize();
        runner = ortRunner;
      } catch (e) {
        runner = FallbackNeuralRunner(reason: 'ONNX model failed to load: $e');
      }
    }
    _runnerCache[version] = runner;
    return runner;
  }

  /// Clears runner and tokenizer caches when reclaiming memory.
  static void clearCache() {
    for (final runner in _runnerCache.values) {
      runner.dispose();
    }
    _runnerCache.clear();
    _tokenizerCache.clear();
  }
}
