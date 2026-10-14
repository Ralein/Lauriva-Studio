import 'dart:typed_data';

import 't5_backend.dart';
import 't5_tokenizer.dart';

/// Greedy autoregressive decoding with HF-equivalent `no_repeat_ngram_size`.
///
/// Greedy (not beam 4) because the decoder graph has no KV cache: every step
/// re-runs the whole prefix, so beam search would multiply an already
/// quadratic cost by the beam width on a phone. See tool/humanizer_release.
class T5GreedyDecoder {
  final T5Backend backend;
  final int noRepeatNgramSize;

  /// Hard cap on generated tokens (HF used 256; the caller usually passes a
  /// tighter, source-length-based cap).
  final int maxNewTokens;

  /// T5 decoder start id (`<pad>`).
  static const int startId = T5Tokenizer.padId;

  const T5GreedyDecoder({
    required this.backend,
    this.noRepeatNgramSize = 3,
    this.maxNewTokens = 256,
  });

  /// Generates ids for [inputIds] (ending in `</s>`); the result excludes the
  /// decoder start id and the terminating `</s>`.
  Future<List<int>> generate(List<int> inputIds, {int? maxNewTokensOverride}) async {
    final cap = maxNewTokensOverride ?? maxNewTokens;
    final enc = await backend.encode(inputIds);
    final seq = <int>[startId];
    for (var step = 0; step < cap; step++) {
      final logits = await backend.nextTokenLogits(enc, seq);
      final banned = bannedTokens(seq, noRepeatNgramSize);
      final next = _argmax(logits, banned);
      if (next == T5Tokenizer.eosId) break;
      seq.add(next);
    }
    return seq.sublist(1);
  }

  /// `NoRepeatNGramLogitsProcessor`: tokens that would complete an n-gram that
  /// already occurred in [prefix] (the prefix includes the start id, like HF).
  static Set<int> bannedTokens(List<int> prefix, int n) {
    if (n <= 0 || prefix.length + 1 < n) return const {};
    final tail = prefix.sublist(prefix.length - (n - 1));
    final banned = <int>{};
    for (var i = 0; i + n <= prefix.length; i++) {
      var match = true;
      for (var k = 0; k < n - 1; k++) {
        if (prefix[i + k] != tail[k]) {
          match = false;
          break;
        }
      }
      if (match) banned.add(prefix[i + n - 1]);
    }
    return banned;
  }

  static int _argmax(Float32List logits, Set<int> banned) {
    var best = -1;
    var bestVal = double.negativeInfinity;
    for (var i = 0; i < logits.length; i++) {
      if (banned.contains(i)) continue;
      final v = logits[i];
      if (v > bestVal) {
        bestVal = v;
        best = i;
      }
    }
    return best;
  }
}
