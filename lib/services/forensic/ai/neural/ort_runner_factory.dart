// Native platforms get the real ONNX Runtime runner; web (no dart:ffi) gets null
// and the forensic engine continues in statistical-only mode.
export 'ort_runner_factory_stub.dart' if (dart.library.ffi) 'ort_neural_runner.dart';
