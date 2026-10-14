import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/sentencepiece_tokenizer.dart';

import 'sentencepiece_parity_goldens.dart';
import 'sentencepiece_pruned_goldens.dart';

/// The multilingual detector ships a vocabulary-pruned Multilingual-MiniLM
/// (tool/prune_multilingual_vocab.py). The Dart tokenizer loaded with the
/// pruned vocab must emit exactly the ids of the pruned HF tokenizer, and those
/// ids must map back (via id_remap.tsv) to the full-vocab ids whenever no
/// piece was dropped.
///
/// Generate the vocab with `python3 tool/prune_multilingual_vocab.py`.
void main() {
  const dir = 'tool/checkpoints/multilingual_tokenizer_pruned';
  final vocabFile = File('$dir/sentencepiece_unigram.txt');
  final remapFile = File('$dir/id_remap.tsv');
  final skip = vocabFile.existsSync() && remapFile.existsSync()
      ? false
      : 'Pruned SentencePiece vocab missing in $dir; run python3 tool/prune_multilingual_vocab.py';

  late SentencePieceTokenizer tokenizer;
  late List<int> originalId;
  setUpAll(() {
    if (skip != false) return;
    tokenizer = SentencePieceTokenizer.fromVocabBytes(vocabFile.readAsBytesSync());
    originalId = [
      for (final line in remapFile.readAsLinesSync())
        if (line.isNotEmpty) int.parse(line.split('\t')[1]),
    ];
    // ignore: avoid_print
    print('Pruned SentencePiece vocab: ${tokenizer.vocabSize} pieces');
  });

  final fullIdsByText = {
    for (final g in sentencePieceParityGoldens) g.text: g.ids,
  };

  test('remap covers the vocab and keeps special ids', () {
    expect(originalId.length, tokenizer.vocabSize);
    expect(originalId.take(4), [0, 1, 2, 3]);
    expect(
        [tokenizer.bosTokenId, tokenizer.padTokenId, tokenizer.eosTokenId, tokenizer.unkTokenId], [0, 1, 2, 3]);
    for (int i = 1; i < originalId.length; i++) {
      expect(originalId[i], greaterThan(originalId[i - 1]));
    }
  }, skip: skip);

  group('HF pruned tokenizer parity', () {
    for (final golden in sentencePiecePrunedGoldens) {
      final label = golden.text.length > 40 ? golden.text.substring(0, 40) : golden.text;
      test('[${golden.lang}] ${label.replaceAll('\n', ' ')}', () {
        final res = tokenizer.tokenize(text: golden.text);
        final validLength = res.attentionMask.where((m) => m == 1).length;
        final ids = res.inputIds.sublist(0, validLength);

        expect(validLength, golden.length, reason: 'sequence length after truncation');
        expect(ids.take(golden.ids.length).toList(), equals(golden.ids));
        expect(ids.sublist(validLength - golden.tail.length), equals(golden.tail));
        for (int i = 1; i < golden.ids.length && i < validLength - 1; i++) {
          final span = res.tokenSpans[i];
          expect(
            [span.startOffset, span.endOffset],
            [golden.offsets[2 * i], golden.offsets[2 * i + 1]],
            reason: 'offsets of token $i (id ${golden.ids[i]})',
          );
        }

        final fullIds = fullIdsByText[golden.text];
        if (golden.sameAsFull && fullIds != null) {
          final mapped = [for (final id in ids.take(fullIds.length)) originalId[id]];
          expect(mapped, equals(fullIds), reason: 'pruned ids mapped back to the full vocab');
        }
      }, skip: skip);
    }
  });
}
