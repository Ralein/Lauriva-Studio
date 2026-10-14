import 'dart:convert';
import 'dart:isolate';
import '../../../../models/forensic/forensic_scan_mode.dart';
import '../../forensic_engine.dart';
import 'neural_detector_service.dart';
import 'neural_model_registry.dart';

/// Request payload sent to the neural forensic isolate worker.
class IsolateForensicJobRequest {
  final String text;
  final ForensicScanMode scanMode;
  final ForensicSensitivity sensitivity;
  final bool enableWatermark;
  final bool enableHomoglyph;
  final String? modelVersion;

  const IsolateForensicJobRequest({
    required this.text,
    this.scanMode = ForensicScanMode.fullForensic,
    this.sensitivity = ForensicSensitivity.balanced,
    this.enableWatermark = true,
    this.enableHomoglyph = true,
    this.modelVersion,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'scanMode': scanMode.name,
        'sensitivity': sensitivity.name,
        'enableWatermark': enableWatermark,
        'enableHomoglyph': enableHomoglyph,
        'modelVersion': modelVersion,
      };

  factory IsolateForensicJobRequest.fromJson(Map<String, dynamic> json) =>
      IsolateForensicJobRequest(
        text: json['text'] as String,
        scanMode: ForensicScanMode.fromName(json['scanMode'] as String?),
        sensitivity: ForensicSensitivity.fromName(json['sensitivity'] as String?),
        enableWatermark: json['enableWatermark'] as bool? ?? true,
        enableHomoglyph: json['enableHomoglyph'] as bool? ?? true,
        modelVersion: json['modelVersion'] as String?,
      );
}

/// Long-lived background isolate worker that maintains warm neural model weights and forensic engines.
class NeuralIsolateWorker {
  static ForensicEngine? _cachedEngine;
  static NeuralDetectorService? _cachedNeuralService;

  /// Entrypoint executed within the spawned background isolate.
  static void isolateEntrypoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) async {
      if (message is! String) return;

      try {
        final decoded = jsonDecode(message) as Map<String, dynamic>;
        final request = IsolateForensicJobRequest.fromJson(decoded);

        // Lazily initialize engine and neural service inside the worker isolate
        if (_cachedEngine == null) {
          final runner = await NeuralModelRegistry.getRunner(modelVersion: request.modelVersion);
          final tokenizer = await NeuralModelRegistry.getTokenizer(modelVersion: request.modelVersion);
          _cachedNeuralService = NeuralDetectorService(
            runner: runner,
            tokenizer: tokenizer,
            config: NeuralModelRegistry.getConfig(request.modelVersion ?? NeuralModelRegistry.activeModelVersion) ??
                NeuralModelRegistry.activeConfig,
          );
          _cachedEngine = ForensicEngine(neuralDetector: _cachedNeuralService);
        }

        final report = await _cachedEngine!.analyzeWithNeural(
          request.text,
          neuralDetector: _cachedNeuralService,
          mode: request.scanMode,
          sensitivity: request.sensitivity,
          enableWatermarkDetection: request.enableWatermark,
          enableHomoglyphDetection: request.enableHomoglyph,
        );

        sendPort.send(jsonEncode(report.toJson()));
      } catch (e) {
        sendPort.send(jsonEncode({'__error': e.toString()}));
      }
    });
  }
}
