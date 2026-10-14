import 'dart:convert';

import '../ai/neural/sentencepiece_tokenizer.dart';

/// T5 SentencePiece tokenizer for the on-device humanizer.
///
/// T5's `tokenizer.json` is the same Unigram + Precompiled-charsmap +
/// WhitespaceSplit/Metaspace design as XLM-R, so the Viterbi/normalizer engine
/// is reused from [SentencePieceTokenizer]. This wrapper only adapts what
/// differs: no `<s>` (ids are `[... , </s>]`), no padding, T5 special ids
/// (`<pad>`=0, `</s>`=1, `<unk>`=2, `<extra_id_N>`=32000..32099) and the HF
/// decode rules (Metaspace decoder + `clean_up_tokenization`).
///
/// The vocab is `tool/humanizer_release/t5_spm_unigram.txt` (written by
/// `export_t5_spm_vocab.py`; line index == token id). Parity with HF
/// `AutoTokenizer.from_pretrained('t5-small')` is asserted by
/// `test/forensic/t5_tokenizer_test.dart`.
class T5Tokenizer {
  static const int padId = 0;
  static const int eosId = 1;
  static const int unkId = 2;
  static const int _extraIdStart = 32000;
  static const int _extraIdEnd = 32099;
  static const String _metaspace = '▁';

  final SentencePieceTokenizer _spm;
  final List<String> _pieces;

  /// Default maximum source length used by the model (tokens, incl. `</s>`).
  final int maxLength;

  T5Tokenizer._(this._spm, this._pieces, this.maxLength);

  int get vocabSize => _pieces.length;

  /// Parses the exported vocab text (see class docs).
  static T5Tokenizer fromVocabString(String content, {int maxLength = 256}) {
    // Same sentinel the XLM-R engine uses; SentencePieceTokenizer validates it.
    final lines = content.split('\n');
    var li = 1;
    var pieceCount = -1;
    while (li < lines.length && lines[li].startsWith('#')) {
      final header = lines[li++];
      if (header.startsWith('#pieces ')) {
        pieceCount = int.parse(header.substring(8));
        break;
      }
    }
    if (pieceCount < 0) throw const FormatException('T5 vocab: missing #pieces header');
    final pieces = List<String>.filled(pieceCount, '');
    for (var i = 0; i < pieceCount; i++) {
      final line = lines[li++];
      pieces[i] = line.substring(0, line.lastIndexOf('\t'));
    }
    // Engine budget is `maxSequenceLength - 2` content tokens; we need
    // `maxLength - 1` (the final slot is `</s>`), hence +1.
    final spm = SentencePieceTokenizer.fromVocabString(content, maxSequenceLength: maxLength + 1);
    return T5Tokenizer._(spm, pieces, maxLength);
  }

  /// Encodes [text] to T5 ids ending in `</s>`, truncated to [maxLength] ids
  /// (truncation keeps `</s>` last, like HF `truncation=True`).
  List<int> encode(String text, {int? maxLength}) {
    // [maxLength] may only shrink the construction-time limit.
    final limit = (maxLength ?? this.maxLength).clamp(2, this.maxLength);
    final tokenized = _spm.tokenize(text: text);
    final attended = tokenized.attentionMask.where((m) => m == 1).length;
    // Layout from the engine: [<s>-fallback, ...pieces, </s>, pad...]; drop the
    // synthetic leading id, keep everything through `</s>`.
    final ids = tokenized.inputIds.sublist(1, attended);
    if (ids.length > limit) {
      return [...ids.sublist(0, limit - 1), eosId];
    }
    return ids;
  }

  /// Decodes [ids] like HF `decode(ids, skip_special_tokens=True)` including
  /// `clean_up_tokenization_spaces=True` (the t5-small default).
  String decode(List<int> ids, {bool skipSpecial = true}) {
    final buf = StringBuffer();
    for (final id in ids) {
      if (id < 0 || id >= _pieces.length) continue;
      if (skipSpecial && _isSpecial(id)) continue;
      buf.write(_pieces[id]);
    }
    var s = buf.toString().replaceAll(_metaspace, ' ');
    // Metaspace decoder (prepend_scheme: always) drops one leading space.
    if (s.startsWith(' ')) s = s.substring(1);
    return _cleanUpTokenization(s);
  }

  bool isSpecialId(int id) => _isSpecial(id);

  static bool _isSpecial(int id) =>
      id == padId || id == eosId || id == unkId || (id >= _extraIdStart && id <= _extraIdEnd);

  /// `PreTrainedTokenizerBase.clean_up_tokenization` (order matters).
  static String _cleanUpTokenization(String s) => s
      .replaceAll(' .', '.')
      .replaceAll(' ?', '?')
      .replaceAll(' !', '!')
      .replaceAll(' ,', ',')
      .replaceAll(" ' ", "'")
      .replaceAll(" n't", "n't")
      .replaceAll(" 'm", "'m")
      .replaceAll(" 's", "'s")
      .replaceAll(" 've", "'ve")
      .replaceAll(" 're", "'re");

  /// Convenience for tests/tools that read the vocab from bytes.
  static T5Tokenizer fromVocabBytes(List<int> bytes, {int maxLength = 256}) =>
      fromVocabString(utf8.decode(bytes), maxLength: maxLength);
}
