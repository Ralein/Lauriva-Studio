import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import '../../../../models/forensic/neural_detection_result.dart';
import '../../segmentation/sentence_segmenter.dart';
import 'neural_model_config.dart';
import 'onnx_neural_runner.dart';

/// Returns an ONNX runner, or null when the native runtime cannot be loaded
/// (e.g. `flutter test` without the plugin's library) so callers skip model
/// I/O entirely.
NeuralInferenceRunner? createOrtRunner(NeuralModelConfig config) =>
    ensureOrtEnvironment() ? OrtNeuralRunner(config: config) : null;

bool? _ortEnvReady;

/// Initializes the process-wide ONNX Runtime environment once; `OrtEnv.init`
/// allocates a new environment on every call.
bool ensureOrtEnvironment() {
  return _ortEnvReady ??= () {
    try {
      OrtEnv.instance.init();
      return true;
    } catch (_) {
      return false;
    }
  }();
}

/// Executes the trained `lauvira_plagiarism` encoder-classifier through ONNX Runtime.
///
/// Emits one document-level probability per window (softmax over the
/// `[human, ai]` logits). Initialization failures — a missing native library
/// in unit tests, an absent asset — surface as [NeuralModelState.failed] and
/// fallback results so callers can keep running the statistical engine.
class OrtNeuralRunner implements NeuralInferenceRunner {
  final NeuralModelConfig config;
  final Future<Uint8List> Function()? _modelBytesLoader;

  OrtSession? _session;
  NeuralModelState _state = NeuralModelState.uninitialized;
  Future<void>? _initFuture;

  OrtNeuralRunner({required this.config, Future<Uint8List> Function()? modelBytesLoader})
      : _modelBytesLoader = modelBytesLoader;

  @override
  NeuralModelState get state => _state;

  @override
  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    _state = NeuralModelState.loading;
    try {
      if (!ensureOrtEnvironment()) {
        throw StateError('ONNX Runtime native library unavailable');
      }
      final options = OrtSessionOptions()
        ..setIntraOpNumThreads(2)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
      final localPath = config.localFilePath;
      if (localPath != null && File(localPath).existsSync()) {
        _session = OrtSession.fromFile(File(localPath), options);
      } else {
        final bytes = await (_modelBytesLoader?.call() ?? _loadAsset());
        _session = OrtSession.fromBuffer(bytes, options);
      }
      options.release();
      _state = NeuralModelState.ready;
    } catch (e) {
      _state = NeuralModelState.failed;
      rethrow;
    }
  }

  Future<Uint8List> _loadAsset() async {
    final assetPath = config.modelAsset;
    try {
      final gzData = await rootBundle.load('$assetPath.gz');
      final rawGz = gzData.buffer.asUint8List(gzData.offsetInBytes, gzData.lengthInBytes);
      return Uint8List.fromList(gzip.decode(rawGz));
    } catch (_) {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
  }

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async {
    final session = _session;
    if (session == null || _state == NeuralModelState.failed || _state == NeuralModelState.disposed) {
      return NeuralDetectionResult.fallback(error: 'ONNX session unavailable');
    }

    // Padding carries no signal; run only the attended prefix.
    final length = input.attentionMask.where((m) => m == 1).length;
    if (length <= 2) {
      return NeuralDetectionResult.fallback(error: 'Insufficient tokens for inference');
    }

    final stopwatch = Stopwatch()..start();
    final shape = [1, length];
    final tensors = <String, OrtValueTensor>{
      config.inputNames['input_ids'] ?? 'input_ids':
          OrtValueTensor.createTensorWithDataList(Int64List.fromList(input.inputIds.sublist(0, length)), shape),
      config.inputNames['attention_mask'] ?? 'attention_mask':
          OrtValueTensor.createTensorWithDataList(Int64List.fromList(input.attentionMask.sublist(0, length)), shape),
      if (session.inputNames.contains(config.inputNames['token_type_ids'] ?? 'token_type_ids'))
        config.inputNames['token_type_ids'] ?? 'token_type_ids':
            OrtValueTensor.createTensorWithDataList(Int64List.fromList(input.tokenTypeIds.sublist(0, length)), shape),
    };
    final runOptions = OrtRunOptions();
    List<OrtValue?> outputs = const [];
    _state = NeuralModelState.running;
    try {
      outputs = await (session.runAsync(runOptions, tensors) ?? Future.value(session.run(runOptions, tensors)));
      final logits = (outputs.first!.value as List).first as List;
      final aiProb = StandardNeuralRunner.softmaxAiProbability(
        (logits[0] as num).toDouble(),
        (logits[1] as num).toDouble(),
      );
      stopwatch.stop();
      return NeuralDetectionResult(
        aiProbability: aiProb,
        uncertainty: StandardNeuralRunner.binaryEntropy(aiProb),
        sentences: const [],
        tokens: const [],
        isFallback: false,
        modelVersion: config.modelVersion,
        inferenceTime: stopwatch.elapsed,
      );
    } catch (e) {
      return NeuralDetectionResult.fallback(error: 'ONNX inference failed: $e');
    } finally {
      _state = NeuralModelState.ready;
      for (final t in tensors.values) {
        t.release();
      }
      runOptions.release();
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  @override
  void dispose() {
    _session?.release();
    _session = null;
    _state = NeuralModelState.disposed;
  }
}
