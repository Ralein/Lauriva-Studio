import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show StringCharacters;

import '../../../../models/forensic/neural_detection_result.dart';
import '../../segmentation/sentence_segmenter.dart';
import 'neural_tokenizer.dart';

/// Zero-dependency, pure-Dart SentencePiece Unigram tokenizer reproducing the
/// HF fast tokenizer of XLM-R / `microsoft/Multilingual-MiniLM-L12-H384`
/// (250,002 ids) exactly, with character span tracking.
///
/// Pipeline, mirroring tokenizer.json:
///  1. special tokens (`<s>` `</s>` `<pad>` `<unk>` `<mask>`) are split out of
///     the raw text before anything else (HF added tokens, normalized: false);
///  2. `Precompiled` charsmap normalizer (sentencepiece nmt_nfkc), applied per
///     grapheme cluster exactly as HF does;
///  3. `WhitespaceSplit` + `Metaspace(▁, add_prefix_space: true)`;
///  4. Unigram Viterbi over piece scores, consecutive unknowns fused into one
///     `<unk>` (fuse_unk);
///  5. `<s> … </s>`, truncated to [maxSequenceLength] and padded with `<pad>`.
///
/// The vocab file comes from tool/export_sentencepiece_vocab.py.
class SentencePieceTokenizer implements NeuralTokenizer {
  final int bosTokenId;
  final int eosTokenId;
  @override
  final int padTokenId;
  @override
  final int unkTokenId;
  @override
  final int maxSequenceLength;

  /// Piece scores by id (f64, exactly as HF compares them).
  final Float64List _scores;

  /// Flat trie over UTF-16 code units; children of a node are contiguous and
  /// sorted by label so lookup is a binary search.
  final Uint16List _label;
  final Int32List _firstChild;
  final Int32List _childCount;
  final Int32List _pieceId;

  /// Root fan-out indexed directly by code unit (-1 when absent).
  final Int32List _rootChild;

  /// Reachable Precompiled charsmap entries (keys < 6 UTF-8 bytes).
  final Map<String, String> _charsMap;

  /// Special pieces matched on raw text, longest first.
  final List<({String text, int id})> _specialTokens;

  /// HF Unigram: unknown characters score `min_score - 10`.
  final double _unkScore;

  SentencePieceTokenizer._({
    required this.bosTokenId,
    required this.eosTokenId,
    required this.padTokenId,
    required this.unkTokenId,
    required this.maxSequenceLength,
    required Float64List scores,
    required Uint16List label,
    required Int32List firstChild,
    required Int32List childCount,
    required Int32List pieceId,
    required Int32List rootChild,
    required Map<String, String> charsMap,
    required List<({String text, int id})> specialTokens,
    required double unkScore,
  })  : _scores = scores,
        _label = label,
        _firstChild = firstChild,
        _childCount = childCount,
        _pieceId = pieceId,
        _rootChild = rootChild,
        _charsMap = charsMap,
        _specialTokens = specialTokens,
        _unkScore = unkScore;

  static const String _magic = '#lauriva-spm-unigram v1';
  static const int _metaspace = 0x2581; // ▁
  static const double _unkPenalty = 10.0;

  /// Number of pieces in the loaded (possibly pruned) vocabulary.
  int get vocabSize => _scores.length;

  /// Loads the exported vocab from a bundled asset.
  static Future<SentencePieceTokenizer> loadFromAsset(
    String assetPath, {
    int maxSequenceLength = 512,
  }) async {
    final content = await rootBundle.loadString(assetPath);
    return fromVocabString(content, maxSequenceLength: maxSequenceLength);
  }

  /// Loads the exported vocab from raw UTF-8 bytes.
  static SentencePieceTokenizer fromVocabBytes(
    List<int> bytes, {
    int maxSequenceLength = 512,
  }) =>
      fromVocabString(utf8.decode(bytes), maxSequenceLength: maxSequenceLength);

  /// Parses the text format written by tool/export_sentencepiece_vocab.py.
  /// Token ids are line indices, so a pruned export loads unchanged.
  static SentencePieceTokenizer fromVocabString(
    String content, {
    int maxSequenceLength = 512,
  }) {
    // Split on '\n' only: pieces may legitimately contain '\r'-like code points.
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first != _magic) {
      throw const FormatException('Not a lauriva SentencePiece Unigram vocab');
    }

    int li = 1;
    int? unkId;
    int pieceCount = -1;
    while (li < lines.length && lines[li].startsWith('#')) {
      final header = lines[li++];
      if (header.startsWith('#unk_id ')) unkId = int.parse(header.substring(8));
      if (header.startsWith('#pieces ')) {
        pieceCount = int.parse(header.substring(8));
        break;
      }
    }
    if (pieceCount < 0) throw const FormatException('Missing #pieces header');

    final pieces = List<String>.filled(pieceCount, '');
    final scores = Float64List(pieceCount);
    var minScore = double.infinity;
    for (int i = 0; i < pieceCount; i++) {
      final line = lines[li++];
      final tab = line.lastIndexOf('\t');
      pieces[i] = line.substring(0, tab);
      final score = double.parse(line.substring(tab + 1));
      scores[i] = score;
      if (score < minScore) minScore = score;
    }

    final charsMap = <String, String>{};
    if (li < lines.length && lines[li].startsWith('#charsmap ')) {
      final count = int.parse(lines[li++].substring(10));
      for (int i = 0; i < count; i++) {
        final line = lines[li++];
        final tab = line.indexOf('\t');
        charsMap[_fromHexCodePoints(line.substring(0, tab))] =
            _fromHexCodePoints(line.substring(tab + 1));
      }
    }

    final trie = _buildTrie(pieces);
    final ids = {
      for (final s in const ['<s>', '<pad>', '</s>', '<unk>', '<mask>'])
        s: _lookupIn(trie, s),
    };
    final specials = [
      for (final e in ids.entries)
        if (e.value >= 0) (text: e.key, id: e.value),
    ]..sort((a, b) => b.text.length.compareTo(a.text.length));

    return SentencePieceTokenizer._(
      bosTokenId: ids['<s>']! >= 0 ? ids['<s>']! : 0,
      eosTokenId: ids['</s>']! >= 0 ? ids['</s>']! : 2,
      padTokenId: ids['<pad>']! >= 0 ? ids['<pad>']! : 1,
      unkTokenId: unkId ?? (ids['<unk>']! >= 0 ? ids['<unk>']! : 3),
      maxSequenceLength: maxSequenceLength,
      scores: scores,
      label: trie.label,
      firstChild: trie.firstChild,
      childCount: trie.childCount,
      pieceId: trie.pieceId,
      rootChild: trie.rootChild,
      charsMap: charsMap,
      specialTokens: specials,
      unkScore: minScore - _unkPenalty,
    );
  }

  /// Tokenizes [text] preserving token spans and sentence associations.
  /// Offsets are UTF-16 indices into [text].
  @override
  TokenizedInput tokenize({
    required String text,
    List<SentenceBoundary>? sentences,
  }) {
    final sentenceList = sentences ?? const [];
    final maxContent = maxSequenceLength - 2;
    final inputIds = <int>[bosTokenId];
    final tokenSpans = <TokenSpan>[
      TokenSpan(
        tokenIndex: bosTokenId,
        startOffset: 0,
        endOffset: 0,
        sentenceIndex: sentenceList.isNotEmpty ? sentenceList.first.index : 0,
      ),
    ];

    void emit(int id, int start, int end) {
      inputIds.add(id);
      tokenSpans.add(TokenSpan(
        tokenIndex: id,
        startOffset: start,
        endOffset: end,
        sentenceIndex: _findSentenceIndex(start, sentenceList),
      ));
    }

    int segStart = 0;
    int pos = 0;
    while (pos <= text.length && inputIds.length - 1 < maxContent) {
      final special = pos < text.length ? _matchSpecial(text, pos) : null;
      if (special == null && pos < text.length) {
        pos++;
        continue;
      }
      if (segStart < pos) {
        _encodeSegment(text, segStart, pos, maxContent - (inputIds.length - 1), emit);
      }
      if (special == null) break;
      if (inputIds.length - 1 < maxContent) emit(special.id, pos, pos + special.text.length);
      pos += special.text.length;
      segStart = pos;
    }

    // Append </s>
    final lastEnd = tokenSpans.length > 1 ? tokenSpans.last.endOffset : 0;
    inputIds.add(eosTokenId);
    tokenSpans.add(TokenSpan(
      tokenIndex: eosTokenId,
      startOffset: lastEnd,
      endOffset: lastEnd,
      sentenceIndex: sentenceList.isNotEmpty ? sentenceList.last.index : 0,
    ));

    // Pad to maxSequenceLength
    final actualLength = inputIds.length;
    final attentionMask = List<int>.filled(maxSequenceLength, 0);
    for (int i = 0; i < actualLength; i++) {
      attentionMask[i] = 1;
    }
    while (inputIds.length < maxSequenceLength) {
      inputIds.add(padTokenId);
    }

    return TokenizedInput(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: List<int>.filled(maxSequenceLength, 0),
      tokenSpans: tokenSpans,
    );
  }

  ({String text, int id})? _matchSpecial(String text, int pos) {
    if (text.codeUnitAt(pos) != 0x3C) return null; // '<'
    for (final s in _specialTokens) {
      if (text.startsWith(s.text, pos)) return s;
    }
    return null;
  }

  /// Normalizes, pre-tokenizes and segments `text[start, end)`, emitting at
  /// most [budget] tokens.
  void _encodeSegment(
    String text,
    int start,
    int end,
    int budget,
    void Function(int id, int start, int end) emit,
  ) {
    final norm = _normalize(text, start, end);
    final units = norm.units;
    int emitted = 0;
    int i = 0;
    while (i < units.length && emitted < budget) {
      // WhitespaceSplit
      while (i < units.length && _isWhitespace(units[i])) {
        i++;
      }
      if (i >= units.length) break;
      final wordStart = i;
      while (i < units.length && !_isWhitespace(units[i])) {
        i++;
      }

      // Metaspace: prepend ▁ unless present, then split before every ▁.
      // The prepended ▁ borrows the first character's origin, like HF.
      final word = <int>[];
      final wordFrom = <int>[];
      final wordTo = <int>[];
      if (units[wordStart] != _metaspace) {
        word.add(_metaspace);
        wordFrom.add(norm.from[wordStart]);
        wordTo.add(norm.to[wordStart]);
      }
      for (int k = wordStart; k < i; k++) {
        word.add(units[k]);
        wordFrom.add(norm.from[k]);
        wordTo.add(norm.to[k]);
      }
      int p = 0;
      while (p < word.length && emitted < budget) {
        int q = p + 1;
        while (q < word.length && word[q] != _metaspace) {
          q++;
        }
        emitted += _viterbi(word, p, q, wordFrom, wordTo, budget - emitted, emit);
        p = q;
      }
    }
  }

  /// HF `Unigram::encode_optimized` over `units[lo, hi)`. Returns tokens emitted.
  int _viterbi(
    List<int> units,
    int lo,
    int hi,
    List<int> from,
    List<int> to,
    int budget,
    void Function(int id, int start, int end) emit,
  ) {
    final n = hi - lo;
    final bestScore = Float64List(n + 1);
    final startsAt = Int32List(n + 1)..fillRange(1, n + 1, -1);
    final bestId = Int32List(n + 1);

    int s = 0;
    while (s < n) {
      final base = bestScore[s];
      final charLen = _isHighSurrogate(units[lo + s]) && s + 1 < n ? 2 : 1;
      var hasSingleNode = false;

      int node = _rootChild[units[lo + s]];
      int e = s + 1;
      while (node >= 0) {
        final id = _pieceId[node];
        if (id >= 0) {
          final candidate = base + _scores[id];
          if (startsAt[e] < 0 || candidate > bestScore[e]) {
            bestScore[e] = candidate;
            startsAt[e] = s;
            bestId[e] = id;
          }
          if (e - s == charLen) hasSingleNode = true;
        }
        if (e >= n) break;
        node = _child(node, units[lo + e]);
        e++;
      }

      if (!hasSingleNode) {
        final e2 = s + charLen;
        final candidate = base + _unkScore;
        if (startsAt[e2] < 0 || candidate > bestScore[e2]) {
          bestScore[e2] = candidate;
          startsAt[e2] = s;
          bestId[e2] = unkTokenId;
        }
      }
      s += charLen;
    }

    // Backtrack, fusing consecutive unknowns into one token.
    final ids = <int>[];
    final starts = <int>[];
    final ends = <int>[];
    int end = n;
    while (end > 0) {
      final start = startsAt[end];
      final id = bestId[end];
      if (id == unkTokenId && ids.isNotEmpty && ids.last == -1) {
        starts[starts.length - 1] = start;
      } else if (id == unkTokenId) {
        ids.add(-1); // placeholder resolved below
        starts.add(start);
        ends.add(end);
      } else {
        ids.add(id);
        starts.add(start);
        ends.add(end);
      }
      end = start;
    }

    int emitted = 0;
    for (int t = ids.length - 1; t >= 0 && emitted < budget; t--) {
      var id = ids[t];
      if (id == -1) {
        // HF looks the fused string up again before falling back to <unk>.
        final found = _lookupUnits(units, lo + starts[t], lo + ends[t]);
        id = found >= 0 ? found : unkTokenId;
      }
      emit(id, from[lo + starts[t]], to[lo + ends[t] - 1]);
      emitted++;
    }
    return emitted;
  }

  int _child(int node, int unit) {
    int a = _firstChild[node];
    int b = a + _childCount[node] - 1;
    while (a <= b) {
      final m = (a + b) >> 1;
      final l = _label[m];
      if (l == unit) return m;
      if (l < unit) {
        a = m + 1;
      } else {
        b = m - 1;
      }
    }
    return -1;
  }

  int _lookupUnits(List<int> units, int start, int end) {
    int node = 0;
    for (int i = start; i < end && node >= 0; i++) {
      node = node == 0 ? _rootChild[units[i]] : _child(node, units[i]);
    }
    return node > 0 ? _pieceId[node] : -1;
  }

  /// HF `Precompiled` normalizer over `text[start, end)`: a grapheme shorter
  /// than 6 UTF-8 bytes is replaced by the value of its *shortest* matching
  /// key prefix (dropping the rest of the cluster, as sentencepiece does);
  /// otherwise each code point is mapped on its own. Returns normalized code
  /// units with the UTF-16 origin range of each.
  ({List<int> units, List<int> from, List<int> to}) _normalize(String text, int start, int end) {
    final units = <int>[];
    final from = <int>[];
    final to = <int>[];

    void write(String s, int a, int b) {
      for (int k = 0; k < s.length; k++) {
        units.add(s.codeUnitAt(k));
        from.add(a);
        to.add(b);
      }
    }

    int offset = start;
    for (final grapheme in text.substring(start, end).characters) {
      final gStart = offset;
      final gEnd = offset + grapheme.length;
      offset = gEnd;

      if (_utf8Length(grapheme) < 6) {
        final replaced = _transformPrefix(grapheme);
        if (replaced != null) {
          // HF aligns output code points positionally with the cluster's
          // code points: surplus outputs reuse the last one, surplus inputs
          // (dropped marks) get no span.
          final origin = <int>[];
          for (int c = 0; c < grapheme.length;) {
            origin.add(gStart + c);
            c += _isHighSurrogate(grapheme.codeUnitAt(c)) && c + 1 < grapheme.length ? 2 : 1;
          }
          origin.add(gEnd);
          int j = 0;
          for (final r in replaced.runes) {
            final k = j < origin.length - 1 ? j : origin.length - 2;
            write(String.fromCharCode(r), origin[k], origin[k + 1]);
            j++;
          }
          continue;
        }
      }
      int c = 0;
      while (c < grapheme.length) {
        final w = _isHighSurrogate(grapheme.codeUnitAt(c)) && c + 1 < grapheme.length ? 2 : 1;
        final ch = grapheme.substring(c, c + w);
        write(_charsMap[ch] ?? ch, gStart + c, gStart + c + w);
        c += w;
      }
    }
    return (units: units, from: from, to: to);
  }

  /// Shortest key prefix of [chunk] in the charsmap (darts common-prefix
  /// search returns matches shortest first and HF takes the first).
  String? _transformPrefix(String chunk) {
    int c = 0;
    while (c < chunk.length) {
      c += _isHighSurrogate(chunk.codeUnitAt(c)) && c + 1 < chunk.length ? 2 : 1;
      final hit = _charsMap[c == chunk.length ? chunk : chunk.substring(0, c)];
      if (hit != null) return hit;
    }
    return null;
  }

  static int _utf8Length(String s) {
    int bytes = 0;
    for (final r in s.runes) {
      bytes += r < 0x80 ? 1 : r < 0x800 ? 2 : r < 0x10000 ? 3 : 4;
    }
    return bytes;
  }

  static bool _isHighSurrogate(int u) => u >= 0xD800 && u <= 0xDBFF;

  /// Rust `char::is_whitespace` (Unicode White_Space; all in the BMP).
  static bool _isWhitespace(int u) =>
      (u >= 0x09 && u <= 0x0D) || u == 0x20 || u == 0x85 || u == 0xA0 || u == 0x1680 ||
      (u >= 0x2000 && u <= 0x200A) || u == 0x2028 || u == 0x2029 || u == 0x202F ||
      u == 0x205F || u == 0x3000;

  static String _fromHexCodePoints(String hex) {
    if (hex.isEmpty) return '';
    return String.fromCharCodes(hex.split(' ').map((h) => int.parse(h, radix: 16)));
  }

  /// Builds the flat trie breadth-first from pieces sorted by code units, so
  /// each node's children occupy one contiguous, label-sorted block.
  static _Trie _buildTrie(List<String> pieces) {
    final order = List<int>.generate(pieces.length, (i) => i)
      ..sort((a, b) => pieces[a].compareTo(pieces[b]));

    final label = <int>[0];
    final firstChild = <int>[0];
    final childCount = <int>[0];
    final pieceId = <int>[-1];
    // Work items: node, [lo, hi) range in `order`, depth.
    final queue = <int>[0, 0, order.length, 0];
    for (int qi = 0; qi < queue.length; qi += 4) {
      final node = queue[qi];
      var lo = queue[qi + 1];
      final hi = queue[qi + 2];
      final depth = queue[qi + 3];
      if (lo < hi && pieces[order[lo]].length == depth) {
        pieceId[node] = order[lo];
        lo++;
      }
      firstChild[node] = label.length;
      int i = lo;
      while (i < hi) {
        final unit = pieces[order[i]].codeUnitAt(depth);
        int j = i + 1;
        while (j < hi && pieces[order[j]].codeUnitAt(depth) == unit) {
          j++;
        }
        final child = label.length;
        label.add(unit);
        firstChild.add(0);
        childCount.add(0);
        pieceId.add(-1);
        queue.addAll([child, i, j, depth + 1]);
        i = j;
      }
      childCount[node] = label.length - firstChild[node];
    }

    final rootChild = Int32List(0x10000)..fillRange(0, 0x10000, -1);
    for (int c = firstChild[0]; c < firstChild[0] + childCount[0]; c++) {
      rootChild[label[c]] = c;
    }
    return _Trie(
      label: Uint16List.fromList(label),
      firstChild: Int32List.fromList(firstChild),
      childCount: Int32List.fromList(childCount),
      pieceId: Int32List.fromList(pieceId),
      rootChild: rootChild,
    );
  }

  static int _lookupIn(_Trie trie, String piece) {
    int node = 0;
    for (int i = 0; i < piece.length; i++) {
      int a = trie.firstChild[node];
      int b = a + trie.childCount[node] - 1;
      int found = -1;
      while (a <= b) {
        final m = (a + b) >> 1;
        final l = trie.label[m];
        if (l == piece.codeUnitAt(i)) {
          found = m;
          break;
        }
        if (l < piece.codeUnitAt(i)) {
          a = m + 1;
        } else {
          b = m - 1;
        }
      }
      if (found < 0) return -1;
      node = found;
    }
    return trie.pieceId[node];
  }

  int _findSentenceIndex(int offset, List<SentenceBoundary> sentences) {
    if (sentences.isEmpty) return 0;
    for (final s in sentences) {
      if (offset >= s.start && offset <= s.end) {
        return s.index;
      }
    }
    return sentences.last.index;
  }
}

class _Trie {
  final Uint16List label;
  final Int32List firstChild;
  final Int32List childCount;
  final Int32List pieceId;
  final Int32List rootChild;

  const _Trie({
    required this.label,
    required this.firstChild,
    required this.childCount,
    required this.pieceId,
    required this.rootChild,
  });
}
