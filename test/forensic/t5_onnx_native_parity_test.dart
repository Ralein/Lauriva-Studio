import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/t5_backend.dart';
import 'package:lauriva/services/forensic/humanizer/t5_backend_factory.dart';
import 'package:lauriva/services/forensic/humanizer/t5_greedy_decoder.dart';
import 'package:lauriva/services/forensic/humanizer/t5_tokenizer.dart';

import 't5_onnx_greedy_goldens.dart';

/// End-to-end check of the Dart T5 path (tokenizer -> ORT encoder -> ORT
/// last-position decoder -> greedy + no_repeat_ngram -> detokenize) against
/// Python ONNX Runtime on the same int8 files
/// (goldens: tool/humanizer_release/gen_t5_greedy_goldens.py).
///
/// Needs the ONNX Runtime native library, which `flutter test` does not load
/// by default and the model files from tool/checkpoints. On macOS:
///   DYLD_LIBRARY_PATH=~/.pub-cache/hosted/pub.dev/onnxruntime-1.4.1/macos \
///     flutter test test/forensic/t5_onnx_native_parity_test.dart
void main() {
  const dir = 'tool/checkpoints/lauvira_humanize_v6';
  final enc = File('$dir/lauvira_humanize_v6_encoder_int8_pc.onnx');
  final dec = File('$dir/lauvira_humanize_v6_decoder_int8_pc_last.onnx');
  final vocab = File('tool/humanizer_release/t5_spm_unigram.txt');

  String? skipReason;
  T5Backend? backend;
  late T5Tokenizer tok;

  setUpAll(() async {
    if (!enc.existsSync() || !dec.existsSync() || !vocab.existsSync()) {
      skipReason = 'T5 ONNX files not present under $dir';
      return;
    }
    tok = T5Tokenizer.fromVocabString(vocab.readAsStringSync());
    try {
      backend = await openOrtT5Backend(encoderPath: enc.path, decoderPath: dec.path);
    } on T5UnavailableException catch (e) {
      skipReason = 'ONNX Runtime native library unavailable: ${e.reason}';
    }
  });

  tearDownAll(() => backend?.dispose());

  for (var i = 0; i < t5OnnxGreedyGoldens.length; i++) {
    final g = t5OnnxGreedyGoldens[i];
    test('golden #$i reproduces Python ORT greedy output', () async {
      if (skipReason != null) {
        markTestSkipped(skipReason!);
        return;
      }
      final source = g['source']! as String;
      final inputIds = tok.encode('humanize: $source');
      expect(inputIds, equals((g['inputIds']! as List).cast<int>()), reason: 'tokenizer parity');

      final cap = ((inputIds.length * 1.5).ceil() + 8).clamp(8, 256);
      final sw = Stopwatch()..start();
      final generated = await T5GreedyDecoder(backend: backend!).generate(inputIds, maxNewTokensOverride: cap);
      sw.stop();
      // ignore: avoid_print
      print('golden #$i: ${inputIds.length} src tokens -> ${generated.length} out tokens in ${sw.elapsedMilliseconds} ms '
          '(${(sw.elapsedMilliseconds / (generated.length + 1)).toStringAsFixed(1)} ms/step)');
      expect(generated, equals((g['generated']! as List).cast<int>()));
      expect(tok.decode(generated), equals(g['decoded']! as String));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
