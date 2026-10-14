import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../../../models/forensic/neural_detection_result.dart';
import '../../segmentation/sentence_segmenter.dart';
import 'neural_tokenizer.dart';
import 'omni_nfc_data.dart';

/// Pure-Dart byte-level BPE tokenizer reproducing the HF fast tokenizer of the
/// Omni (ModernBERT) detector from its `tokenizer.json`.
///
/// Pipeline, mirroring tokenizer.json:
///  1. NFC normalizer (canonical composition table in omni_nfc_data.dart;
///     Hangul jamo are recomposed algorithmically);
///  2. added tokens (`[CLS]`, `[SEP]`, `|||EMAIL_ADDRESS|||`, space runs, ...)
///     are split out leftmost-longest before pre-tokenization;
///  3. ByteLevel pre-tokenizer with the GPT-2 split regex, bytes mapped to the
///     printable GPT-2 alphabet;
///  4. BPE merges by rank;
///  5. `[CLS] … [SEP]`, truncated to [maxSequenceLength] and padded with `[PAD]`.
///
/// Token spans are UTF-16 offsets into the text passed to [tokenize].
class BpeTokenizer implements NeuralTokenizer {
  final int clsTokenId;
  final int sepTokenId;
  @override
  final int padTokenId;
  @override
  final int unkTokenId;
  @override
  final int maxSequenceLength;

  final Map<String, int> _vocab;
  final Map<String, int> _mergeRanks;
  final Map<String, List<int>> _bpeCache = {};

  /// Added tokens bucketed by first UTF-16 unit, longest first.
  final Map<int, List<({String text, int id, bool lstrip})>> _added;

  static final RegExp _split = RegExp(
    r"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+",
    unicode: true,
  );

  static final List<int> _byteToChar = _buildByteToChar();

  BpeTokenizer._({
    required this.clsTokenId,
    required this.sepTokenId,
    required this.padTokenId,
    required this.unkTokenId,
    required this.maxSequenceLength,
    required Map<String, int> vocab,
    required Map<String, int> mergeRanks,
    required Map<int, List<({String text, int id, bool lstrip})>> added,
  })  : _vocab = vocab,
        _mergeRanks = mergeRanks,
        _added = added;

  /// Number of ids the tokenizer can emit (added tokens included).
  int get vocabSize {
    var max = _vocab.values.fold<int>(0, (m, v) => v > m ? v : m);
    for (final bucket in _added.values) {
      for (final t in bucket) {
        if (t.id > max) max = t.id;
      }
    }
    return max + 1;
  }

  static Future<BpeTokenizer> loadFromAsset(
    String assetPath, {
    int maxSequenceLength = 512,
  }) async {
    final content = await rootBundle.loadString(assetPath);
    return fromJsonString(content, maxSequenceLength: maxSequenceLength);
  }

  /// Parses a HF `tokenizer.json` (BPE model).
  static BpeTokenizer fromJsonString(
    String content, {
    int maxSequenceLength = 512,
  }) {
    final json = jsonDecode(content) as Map<String, dynamic>;
    final model = json['model'] as Map<String, dynamic>;
    if (model['type'] != 'BPE') {
      throw const FormatException('tokenizer.json is not a BPE model');
    }
    final vocab = (model['vocab'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    final mergeRanks = <String, int>{};
    final merges = model['merges'] as List;
    for (var i = 0; i < merges.length; i++) {
      final m = merges[i];
      final key = m is List ? '${m[0]} ${m[1]}' : m as String;
      mergeRanks.putIfAbsent(key, () => i);
    }

    final added = <int, List<({String text, int id, bool lstrip})>>{};
    final idByContent = <String, int>{};
    for (final a in (json['added_tokens'] as List).cast<Map<String, dynamic>>()) {
      final text = a['content'] as String;
      final id = a['id'] as int;
      idByContent[text] = id;
      if (text.isEmpty) continue;
      added.putIfAbsent(text.codeUnitAt(0), () => []).add((text: text, id: id, lstrip: a['lstrip'] == true));
    }
    for (final bucket in added.values) {
      bucket.sort((a, b) => b.text.length.compareTo(a.text.length));
    }

    int idOf(String token) {
      final id = idByContent[token] ?? vocab[token];
      if (id == null) throw FormatException('tokenizer.json lacks $token');
      return id;
    }

    return BpeTokenizer._(
      clsTokenId: idOf('[CLS]'),
      sepTokenId: idOf('[SEP]'),
      padTokenId: idOf('[PAD]'),
      unkTokenId: idOf('[UNK]'),
      maxSequenceLength: maxSequenceLength,
      vocab: vocab,
      mergeRanks: mergeRanks,
      added: added,
    );
  }

  /// GPT-2 bytes_to_unicode: printable bytes map to themselves, the rest to
  /// U+0100 upward in byte order.
  static List<int> _buildByteToChar() {
    final table = List<int>.filled(256, 0);
    var n = 0;
    for (var b = 0; b < 256; b++) {
      final printable = (b >= 0x21 && b <= 0x7E) || (b >= 0xA1 && b <= 0xAC) || (b >= 0xAE && b <= 0xFF);
      table[b] = printable ? b : 256 + n++;
    }
    return table;
  }

  @override
  TokenizedInput tokenize({
    required String text,
    List<SentenceBoundary>? sentences,
  }) {
    final sentenceList = sentences ?? const [];
    final maxContent = maxSequenceLength - 2;
    final norm = _nfc(text);
    final s = norm.text;
    final map = norm.origin; // normalized code unit i -> original [map[i], map[i+1])

    int orig(int i) => map == null ? i : map[i];

    final inputIds = <int>[clsTokenId];
    final tokenSpans = <TokenSpan>[
      TokenSpan(
        tokenIndex: clsTokenId,
        startOffset: 0,
        endOffset: 0,
        sentenceIndex: sentenceList.isNotEmpty ? sentenceList.first.index : 0,
      ),
    ];

    void emit(int id, int start, int end) {
      final os = orig(start);
      inputIds.add(id);
      tokenSpans.add(TokenSpan(
        tokenIndex: id,
        startOffset: os,
        endOffset: orig(end),
        sentenceIndex: _findSentenceIndex(os, sentenceList),
      ));
    }

    var segStart = 0;
    var pos = 0;
    while (pos <= s.length && inputIds.length - 1 < maxContent) {
      final hit = pos < s.length ? _matchAdded(s, pos) : null;
      if (hit == null && pos < s.length) {
        pos++;
        continue;
      }
      // An lstrip token (`[MASK]`) swallows the whitespace before it.
      var segEnd = pos;
      if (hit != null && hit.lstrip) {
        while (segEnd > segStart && _isSpace(s.codeUnitAt(segEnd - 1))) {
          segEnd--;
        }
      }
      if (segStart < segEnd) {
        _encodeSegment(s, segStart, segEnd, maxContent - (inputIds.length - 1), emit);
      }
      if (hit == null) break;
      if (inputIds.length - 1 < maxContent) emit(hit.id, segEnd, pos + hit.text.length);
      pos += hit.text.length;
      segStart = pos;
    }

    final lastEnd = tokenSpans.length > 1 ? tokenSpans.last.endOffset : 0;
    inputIds.add(sepTokenId);
    tokenSpans.add(TokenSpan(
      tokenIndex: sepTokenId,
      startOffset: lastEnd,
      endOffset: lastEnd,
      sentenceIndex: sentenceList.isNotEmpty ? sentenceList.last.index : 0,
    ));

    final actualLength = inputIds.length;
    final attentionMask = List<int>.filled(maxSequenceLength, 0);
    for (var i = 0; i < actualLength; i++) {
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

  static bool _isSpace(int c) => c == 0x20 || (c >= 0x9 && c <= 0xD) || c == 0xA0 || c == 0x3000;

  ({String text, int id, bool lstrip})? _matchAdded(String s, int pos) {
    final bucket = _added[s.codeUnitAt(pos)];
    if (bucket == null) return null;
    for (final t in bucket) {
      if (s.startsWith(t.text, pos)) return t;
    }
    return null;
  }

  /// Pre-tokenizes and BPE-encodes `s[start, end)`, emitting at most [budget] ids.
  void _encodeSegment(String s, int start, int end, int budget, void Function(int id, int start, int end) emit) {
    final segment = s.substring(start, end);
    var emitted = 0;
    for (final m in _split.allMatches(segment)) {
      final piece = m.group(0)!;
      final bytes = utf8.encode(piece);
      // byte index -> UTF-16 offset (in s) of the code point holding it
      final starts = List<int>.filled(bytes.length + 1, 0);
      final ends = List<int>.filled(bytes.length, 0);
      var b = 0;
      var u = start + m.start;
      for (final rune in piece.runes) {
        final len = rune < 0x80
            ? 1
            : rune < 0x800
                ? 2
                : rune < 0x10000
                    ? 3
                    : 4;
        final width = rune > 0xFFFF ? 2 : 1;
        for (var k = 0; k < len; k++) {
          starts[b + k] = u;
          ends[b + k] = u + width;
        }
        b += len;
        u += width;
      }

      final key = String.fromCharCodes(bytes.map((x) => _byteToChar[x]));
      final ids = _bpeCache[key] ??= _bpe(key);
      // Each id consumes a run of characters of the byte-alphabet string.
      var consumed = 0;
      final lengths = _lastLengths;
      for (var i = 0; i < ids.length; i++) {
        if (emitted >= budget) return;
        final len = lengths[key]![i];
        emit(ids[i], starts[consumed], ends[consumed + len - 1]);
        consumed += len;
        emitted++;
      }
    }
  }

  /// Token lengths (in byte-alphabet characters) per cached word.
  final Map<String, List<int>> _lastLengths = {};

  List<int> _bpe(String word) {
    var parts = word.split('').toList();
    while (parts.length > 1) {
      var bestRank = -1;
      var bestIdx = -1;
      for (var i = 0; i < parts.length - 1; i++) {
        final r = _mergeRanks['${parts[i]} ${parts[i + 1]}'];
        if (r != null && (bestRank == -1 || r < bestRank)) {
          bestRank = r;
          bestIdx = i;
        }
      }
      if (bestIdx < 0) break;
      final merged = parts[bestIdx] + parts[bestIdx + 1];
      parts = [...parts.sublist(0, bestIdx), merged, ...parts.sublist(bestIdx + 2)];
    }
    _lastLengths[word] = parts.map((p) => p.length).toList();
    return parts.map((p) => _vocab[p] ?? unkTokenId).toList();
  }

  int _findSentenceIndex(int offset, List<SentenceBoundary> sentences) {
    if (sentences.isEmpty) return 0;
    for (final s in sentences) {
      if (offset >= s.start && offset <= s.end) return s.index;
    }
    return sentences.last.index;
  }

  /// NFC via the generated composition table. Returns [origin] (normalized
  /// index -> original index, length + 1) only when the text changed.
  ({String text, List<int>? origin}) _nfc(String text) {
    var needs = false;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) >= 0x300) {
        needs = true;
        break;
      }
    }
    if (!needs) return (text: text, origin: null);

    final out = <int>[];
    final origin = <int>[];
    var changed = false;
    var i = 0;
    while (i < text.length) {
      var cp = text.codeUnitAt(i);
      var width = 1;
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < text.length) {
        final lo = text.codeUnitAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
          width = 2;
        }
      }
      final single = omniNfcSingletons[cp];
      if (single != null) {
        cp = single;
        changed = true;
      }
      // Compose with the previous starter when a pair exists (adjacent only).
      if (out.isNotEmpty) {
        final prev = out.last;
        int? composed = omniNfcPairs[(prev << 21) | cp];
        if (composed == null) {
          // Hangul: L + V -> LV, LV + T -> LVT (algorithmic composition).
          if (prev >= 0x1100 && prev <= 0x1112 && cp >= 0x1161 && cp <= 0x1175) {
            composed = 0xAC00 + ((prev - 0x1100) * 21 + (cp - 0x1161)) * 28;
          } else if (prev >= 0xAC00 && prev <= 0xD7A3 && (prev - 0xAC00) % 28 == 0 && cp > 0x11A7 && cp <= 0x11C2) {
            composed = prev + (cp - 0x11A7);
          }
        }
        if (composed != null) {
          out[out.length - 1] = composed;
          changed = true;
          i += width;
          continue;
        }
      }
      out.add(cp);
      origin.add(i);
      i += width;
    }
    if (!changed) return (text: text, origin: null);

    final sb = StringBuffer();
    final unitOrigin = <int>[];
    for (var k = 0; k < out.length; k++) {
      final cp = out[k];
      final start = origin[k];
      sb.writeCharCode(cp);
      unitOrigin.add(start);
      if (cp > 0xFFFF) unitOrigin.add(start);
    }
    unitOrigin.add(text.length);
    return (text: sb.toString(), origin: unitOrigin);
  }
}
