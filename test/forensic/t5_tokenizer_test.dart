import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/humanizer/t5_tokenizer.dart';

import 't5_tokenizer_parity_goldens.dart';

/// Parity of the Dart T5 tokenizer with HF `t5-small`
/// (goldens: tool/humanizer_release/gen_t5_tokenizer_goldens.py).
void main() {
  final vocabFile = File('tool/humanizer_release/t5_spm_unigram.txt');
  final skip = vocabFile.existsSync() ? null : 'tool/humanizer_release/t5_spm_unigram.txt missing';
  late T5Tokenizer tok;

  setUpAll(() {
    if (skip == null) tok = T5Tokenizer.fromVocabString(vocabFile.readAsStringSync());
  });

  test('vocab loads with the T5 layout', () {
    expect(tok.vocabSize, 32100);
    expect(T5Tokenizer.padId, 0);
    expect(T5Tokenizer.eosId, 1);
    expect(T5Tokenizer.unkId, 2);
  }, skip: skip);

  group('encode parity with HF', () {
    for (var i = 0; i < t5EncodeGoldens.length; i++) {
      final g = t5EncodeGoldens[i];
      final text = g['text']! as String;
      final label = text.length > 48 ? '${text.substring(0, 48)}…' : text;
      test('#$i ${label.replaceAll('\n', '\\n')}', () {
        final expected = (g['ids']! as List).cast<int>();
        expect(tok.encode(text), equals(expected));
      }, skip: skip);
    }
  });

  group('decode parity with HF', () {
    for (var i = 0; i < t5EncodeGoldens.length; i++) {
      final g = t5EncodeGoldens[i];
      test('round-trip #$i', () {
        final ids = (g['ids']! as List).cast<int>();
        expect(tok.decode(ids), equals(g['decoded']! as String));
      }, skip: skip);
    }
    for (var i = 0; i < t5DecodeGoldens.length; i++) {
      final g = t5DecodeGoldens[i];
      test('decode-only #$i ${g['ids']}', () {
        expect(tok.decode((g['ids']! as List).cast<int>()), equals(g['decoded']! as String));
      }, skip: skip);
    }
  });

  test('encode truncates to 256 ids and keeps </s> last', () {
    final ids = tok.encode('word ' * 600);
    expect(ids.length, 256);
    expect(ids.last, T5Tokenizer.eosId);
  }, skip: skip);

  test('empty input encodes to just </s>', () {
    expect(tok.encode(''), [T5Tokenizer.eosId]);
  }, skip: skip);

  test('shrinking maxLength truncates', () {
    final ids = tok.encode('humanize: ${'alpha beta gamma ' * 50}', maxLength: 16);
    expect(ids.length, 16);
    expect(ids.last, T5Tokenizer.eosId);
  }, skip: skip);
}
