import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/sentencepiece_tokenizer.dart';

import 'sentencepiece_parity_goldens.dart';

/// The multilingual detector will be fed XLM-R SentencePiece ids; any drift
/// from the HF fast tokenizer silently degrades on-device accuracy, so the
/// Dart port must match it id-for-id in every Studio language.
///
/// The vocab is not bundled yet; generate it with
/// `python3 tool/export_sentencepiece_vocab.py`.
void main() {
  const vocabPath = 'tool/checkpoints/multilingual_tokenizer/sentencepiece_unigram.txt';
  final vocabFile = File(vocabPath);
  final skip = vocabFile.existsSync()
      ? false
      : 'SentencePiece vocab missing at $vocabPath; run python3 tool/export_sentencepiece_vocab.py';

  late SentencePieceTokenizer tokenizer;
  setUpAll(() {
    if (skip != false) return;
    final sw = Stopwatch()..start();
    tokenizer = SentencePieceTokenizer.fromVocabBytes(vocabFile.readAsBytesSync());
    // ignore: avoid_print
    print('SentencePiece vocab (${tokenizer.vocabSize} pieces) loaded in ${sw.elapsedMilliseconds} ms');
  });

  group('HF XLM-R parity', () {
    for (final golden in sentencePieceParityGoldens) {
      final label = golden.text.length > 40 ? golden.text.substring(0, 40) : golden.text;
      test('[${golden.lang}] ${label.replaceAll('\n', ' ')}', () {
        final res = tokenizer.tokenize(text: golden.text);
        final validLength = res.attentionMask.where((m) => m == 1).length;
        final ids = res.inputIds.sublist(0, validLength);

        expect(validLength, golden.length, reason: 'sequence length after truncation');
        expect(ids.take(golden.ids.length).toList(), equals(golden.ids));
        expect(ids.sublist(validLength - golden.tail.length), equals(golden.tail));

        // HF reports (0, 0) for <s> and </s>; compare content tokens only.
        for (int i = 1; i < golden.ids.length && i < validLength - 1; i++) {
          final span = res.tokenSpans[i];
          expect(
            [span.startOffset, span.endOffset],
            [golden.offsets[2 * i], golden.offsets[2 * i + 1]],
            reason: 'offsets of token $i (id ${golden.ids[i]})',
          );
        }
      }, skip: skip);
    }
  });

  test('pads to 512 with <pad>=1, zero token types, <s>=0 … </s>=2', () {
    final res = tokenizer.tokenize(text: 'Hello world');
    expect(res.inputIds.length, 512);
    expect(res.inputIds.take(4), [0, 35378, 8999, 2]);
    expect(res.inputIds.skip(4).every((id) => id == 1), isTrue);
    expect(res.attentionMask.where((m) => m == 1).length, 4);
    expect(res.tokenTypeIds.every((t) => t == 0), isTrue);
  }, skip: skip);

  test('tokenizes a 512-token text well under 50 ms', () {
    final text = sentencePieceParityGoldens.where((g) => g.lang == 'long').first.text;
    for (int i = 0; i < 5; i++) {
      tokenizer.tokenize(text: text); // warm up the JIT
    }
    const runs = 50;
    final sw = Stopwatch()..start();
    for (int i = 0; i < runs; i++) {
      tokenizer.tokenize(text: text);
    }
    final perCallMs = sw.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('512-token tokenize: ${perCallMs.toStringAsFixed(2)} ms/call');
    expect(tokenizer.tokenize(text: text).attentionMask.every((m) => m == 1), isTrue);
    expect(perCallMs, lessThan(50));
  }, skip: skip);
}
