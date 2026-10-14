import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../ai/neural/ort_neural_runner.dart' show ensureOrtEnvironment;
import 't5_backend.dart';

/// Opens the encoder/decoder ONNX graphs through the app's `onnxruntime`
/// plugin (ORT 1.15.1 on device). Throws [T5UnavailableException] when the
/// native library or a model file cannot be loaded.
Future<T5Backend> openOrtT5Backend({
  required String encoderPath,
  required String decoderPath,
  int threads = 3,
}) async {
  if (!ensureOrtEnvironment()) {
    throw const T5UnavailableException('ONNX Runtime native library unavailable');
  }
  OrtSession? enc;
  OrtSession? dec;
  try {
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    enc = OrtSession.fromFile(File(encoderPath), options);
    dec = OrtSession.fromFile(File(decoderPath), options);
    options.release();
    return _OrtT5Backend(enc, dec);
  } catch (e) {
    enc?.release();
    dec?.release();
    throw T5UnavailableException('T5 ONNX sessions failed to load: $e');
  }
}

class _OrtT5Backend implements T5Backend {
  final OrtSession _encoder;
  final OrtSession _decoder;

  // The encoder output and mask are constant across a sequence's decoder steps.
  OrtValueTensor? _hiddenTensor;
  OrtValueTensor? _maskTensor;
  T5EncoderOutput? _cachedFor;

  _OrtT5Backend(this._encoder, this._decoder);

  void _releaseCache() {
    _hiddenTensor?.release();
    _maskTensor?.release();
    _hiddenTensor = null;
    _maskTensor = null;
    _cachedFor = null;
  }

  @override
  Future<T5EncoderOutput> encode(List<int> inputIds) async {
    _releaseCache();
    final len = inputIds.length;
    final ids = OrtValueTensor.createTensorWithDataList(Int64List.fromList(inputIds), [1, len]);
    final mask = OrtValueTensor.createTensorWithDataList(Int64List.fromList(List<int>.filled(len, 1)), [1, len]);
    final runOptions = OrtRunOptions();
    List<OrtValue?> outputs = const [];
    try {
      outputs = _encoder.run(runOptions, {'input_ids': ids, 'attention_mask': mask});
      final rows = ((outputs.first!.value as List).first as List); // [srcLen][dModel]
      final dModel = (rows.first as List).length;
      final hidden = Float32List(len * dModel);
      for (var i = 0; i < len; i++) {
        final r = rows[i] as List;
        for (var j = 0; j < dModel; j++) {
          hidden[i * dModel + j] = (r[j] as num).toDouble();
        }
      }
      return T5EncoderOutput(hidden: hidden, srcLen: len, dModel: dModel);
    } finally {
      ids.release();
      mask.release();
      runOptions.release();
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  @override
  Future<Float32List> nextTokenLogits(T5EncoderOutput encoder, List<int> decoderIds) async {
    if (!identical(_cachedFor, encoder)) {
      _releaseCache();
      _hiddenTensor = OrtValueTensor.createTensorWithDataList(encoder.hidden, [1, encoder.srcLen, encoder.dModel]);
      _maskTensor = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(List<int>.filled(encoder.srcLen, 1)),
        [1, encoder.srcLen],
      );
      _cachedFor = encoder;
    }
    final decIds = OrtValueTensor.createTensorWithDataList(Int64List.fromList(decoderIds), [1, decoderIds.length]);
    final runOptions = OrtRunOptions();
    List<OrtValue?> outputs = const [];
    try {
      outputs = _decoder.run(runOptions, {
        'decoder_input_ids': decIds,
        'encoder_hidden_states': _hiddenTensor!,
        'encoder_attention_mask': _maskTensor!,
      });
      // [1][tgt_len][vocab]; only the last position is needed. (The
      // last-position decoder variant returns tgt_len == 1.)
      final positions = (outputs.first!.value as List).first as List;
      final last = positions.last as List;
      final logits = Float32List(last.length);
      for (var i = 0; i < last.length; i++) {
        logits[i] = (last[i] as num).toDouble();
      }
      return logits;
    } finally {
      decIds.release();
      runOptions.release();
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  @override
  void dispose() {
    _releaseCache();
    _encoder.release();
    _decoder.release();
  }
}
