import 'dart:typed_data';

/// Raised when the on-device T5 humanizer cannot run (model files not
/// downloaded, ONNX Runtime unavailable on this platform, session failed).
/// The humanizer fallback chain catches this and moves to the next stage.
class T5UnavailableException implements Exception {
  final String reason;
  const T5UnavailableException(this.reason);

  @override
  String toString() => 'T5UnavailableException: $reason';
}

/// Encoder output kept between decoder steps (flattened `[1, srcLen, dModel]`).
class T5EncoderOutput {
  final Float32List hidden;
  final int srcLen;
  final int dModel;

  const T5EncoderOutput({required this.hidden, required this.srcLen, required this.dModel});
}

/// Minimal seam over the two ONNX graphs (encoder, no-KV-cache decoder) so the
/// decode loop, guards and chain wiring are testable without native ORT.
abstract class T5Backend {
  /// Runs the encoder for one source sequence (ids end with `</s>`, no padding).
  Future<T5EncoderOutput> encode(List<int> inputIds);

  /// Runs the decoder over the whole [decoderIds] prefix (the graph has no KV
  /// cache) and returns the logits of the LAST position (`[vocab]`).
  Future<Float32List> nextTokenLogits(T5EncoderOutput encoder, List<int> decoderIds);

  void dispose();
}
