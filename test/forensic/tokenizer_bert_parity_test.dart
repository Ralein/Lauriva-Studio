import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';

import 'tokenizer_bert_parity_goldens.dart';

/// The ONNX detector was trained with the HF BertTokenizer; any id drift here
/// silently degrades on-device accuracy, so the Dart tokenizer must match it exactly.
void main() {
  final tokenizer = PureDartTokenizer.fromVocabString(
    File('assets/models/vocab.txt').readAsStringSync(),
  );

  for (final golden in bertParityGoldens) {
    test('matches HF BertTokenizer ids: ${golden.text.length > 40 ? golden.text.substring(0, 40) : golden.text}', () {
      final res = tokenizer.tokenize(text: golden.text);
      final validLength = res.attentionMask.where((m) => m == 1).length;
      expect(res.inputIds.sublist(0, validLength), equals(golden.ids));
    });
  }
}
