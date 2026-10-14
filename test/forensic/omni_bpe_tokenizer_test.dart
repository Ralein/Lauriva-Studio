import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/bpe_tokenizer.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';

import 'omni_bpe_parity_goldens.dart';

/// The Omni detector is fed ModernBERT BPE ids; any drift from the HF fast
/// tokenizer it was trained with silently destroys on-device accuracy (the
/// bundled BERT WordPiece vocab scored at chance), so the Dart port must match
/// id-for-id. Regenerate goldens with `python3 tool/gen_omni_bpe_goldens.py`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const path = 'assets/models/omni_tokenizer.json';
  late BpeTokenizer tokenizer;

  setUpAll(() {
    tokenizer = BpeTokenizer.fromJsonString(
      File(path).readAsStringSync(),
      maxSequenceLength: omniBpeGoldenMaxLength,
    );
  });

  group('HF ModernBERT parity', () {
    for (final g in omniBpeGoldens) {
      final label = g.text.length > 40 ? '${g.text.substring(0, 40)}…' : g.text;
      test('ids match for ${label.replaceAll('\n', '\\n')}', () {
        final out = tokenizer.tokenize(text: g.text);
        final n = g.ids.length;
        expect(out.inputIds.sublist(0, n), equals(g.ids));
        expect(out.inputIds.sublist(n).every((id) => id == tokenizer.padTokenId), isTrue);
        expect(out.attentionMask.sublist(0, n).every((m) => m == 1), isTrue);
        expect(out.attentionMask.sublist(n).every((m) => m == 0), isTrue);
      });
    }
  });

  group('tensor contract', () {
    test('always exactly maxSequenceLength long and truncated with [SEP] last', () {
      final out = tokenizer.tokenize(text: 'word ' * 500);
      expect(out.inputIds.length, omniBpeGoldenMaxLength);
      expect(out.attentionMask.every((m) => m == 1), isTrue);
      expect(out.inputIds.first, tokenizer.clsTokenId);
      expect(out.inputIds.last, tokenizer.sepTokenId);
    });

    test('vocab covers the ONNX embedding (50368 ids)', () {
      expect(tokenizer.vocabSize, 50368);
    });

    test('spans are UTF-16 offsets that stay inside the text', () {
      const text = 'Café 😀 naïve text';
      final out = tokenizer.tokenize(text: text);
      for (final s in out.tokenSpans) {
        expect(s.startOffset, inInclusiveRange(0, text.length));
        expect(s.endOffset, inInclusiveRange(s.startOffset, text.length));
      }
      final word = out.tokenSpans.firstWhere((s) => s.startOffset == 0 && s.endOffset > 0);
      expect(text.substring(word.startOffset, word.endOffset), isNotEmpty);
    });
  });

  group('registry wiring', () {
    test('registry loads the bundled asset as a BPE tokenizer', () async {
      NeuralModelRegistry.clearCache();
      final t = await NeuralModelRegistry.getTokenizer(modelVersion: NeuralModelRegistry.bundledModelVersion);
      expect(t, isA<BpeTokenizer>());
      expect((t as BpeTokenizer).vocabSize, 50368);
      expect(t.tokenize(text: 'Hello world.').inputIds.take(5), [50281, 12092, 1533, 15, 50282]);
    });

    test('Omni config builds a BPE tokenizer', () {
      final config = NeuralModelRegistry.bundledConfig;
      final built = NeuralModelRegistry.buildTokenizer(config, File(path).readAsStringSync());
      expect(built, isA<BpeTokenizer>());
      expect(built.maxSequenceLength, config.maxSequenceLength);
      expect(NeuralModelRegistry.fallbackTokenizer(config), isA<BpeTokenizer>());
    });
  });
}
