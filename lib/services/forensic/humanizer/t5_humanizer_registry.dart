import 'dart:io';

import 'package:flutter/foundation.dart';

import 'on_device_t5_humanizer_model.dart';
import 't5_backend.dart';
import 't5_backend_factory.dart';
import 't5_model_store.dart';
import 't5_tokenizer.dart';

/// Process-wide access to the optional on-device T5 humanizer.
///
/// [tryGet] returns the model only when its files are already downloaded and
/// verified and ONNX Runtime can load them; it never downloads and never
/// throws. Call [ensureHumanizerModels] (for example on Wi-Fi) to fetch the
/// files; a later [tryGet] picks them up without an app restart.
class T5HumanizerRegistry {
  static final T5HumanizerRegistry instance = T5HumanizerRegistry._(T5ModelStore());

  T5ModelStore store;
  OnDeviceT5HumanizerModel? _model;
  Future<OnDeviceT5HumanizerModel?>? _loading;
  bool _permanentlyUnavailable = false;
  OnDeviceT5HumanizerModel? _override;

  T5HumanizerRegistry._(this.store);

  @visibleForTesting
  factory T5HumanizerRegistry.forTesting(T5ModelStore store) = T5HumanizerRegistry._;

  /// Test hook: force a model (or null to clear).
  @visibleForTesting
  void overrideModel(OnDeviceT5HumanizerModel? model) => _override = model;

  /// Downloads/verifies the model files; see [T5ModelStore.ensureHumanizerModels].
  Future<T5DeliveryStatus> ensureHumanizerModels({
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) =>
      store.ensureHumanizerModels(onProgress: onProgress, isCancelled: isCancelled);

  /// The loaded model, or null when it is not available (files missing, ORT
  /// unavailable). Missing files are re-checked on every call (cheap); an ORT
  /// load failure is remembered for the process lifetime.
  Future<OnDeviceT5HumanizerModel?> tryGet() async {
    if (_override != null) return _override;
    if (_model != null) return _model;
    if (_permanentlyUnavailable) return null;
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<OnDeviceT5HumanizerModel?> _load() async {
    try {
      final enc = await store.encoderPath();
      final dec = await store.decoderPath();
      final vocab = await store.vocabPath();
      if (enc == null || dec == null || vocab == null) return null; // not downloaded (yet)
      final tokenizer = T5Tokenizer.fromVocabString(await File(vocab).readAsString());
      final backend = await openOrtT5Backend(encoderPath: enc, decoderPath: dec);
      return _model = OnDeviceT5HumanizerModel(tokenizer: tokenizer, backend: backend);
    } on T5UnavailableException catch (e) {
      debugPrint('[T5HumanizerRegistry] unavailable: ${e.reason}');
      _permanentlyUnavailable = true;
      return null;
    } catch (e) {
      debugPrint('[T5HumanizerRegistry] failed to load: $e');
      _permanentlyUnavailable = true;
      return null;
    }
  }

  /// Releases the ONNX sessions (e.g. under memory pressure); the next
  /// [tryGet] reloads them.
  void release() {
    _model?.dispose();
    _model = null;
  }
}
