import 'neural_model_config.dart';
import 'onnx_neural_runner.dart';

/// ONNX Runtime is unavailable on this platform.
NeuralInferenceRunner? createOrtRunner(NeuralModelConfig config) => null;
