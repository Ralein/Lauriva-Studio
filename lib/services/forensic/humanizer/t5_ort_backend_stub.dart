import 't5_backend.dart';

/// ONNX Runtime is unavailable on this platform (web).
Future<T5Backend> openOrtT5Backend({
  required String encoderPath,
  required String decoderPath,
  int threads = 3,
}) async =>
    throw const T5UnavailableException('ONNX Runtime unavailable on this platform');
