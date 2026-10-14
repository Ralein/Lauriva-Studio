import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../../../models/forensic/neural_detection_result.dart';
import 'neural_model_config.dart';
import 'neural_tokenizer.dart';
import '../../segmentation/sentence_segmenter.dart';

/// Zero-dependency, pure-Dart WordPiece Tokenizer with exact character span tracking.
class PureDartTokenizer implements NeuralTokenizer {
  final Map<String, int> vocab;
  final int clsTokenId;
  final int sepTokenId;
  @override
  final int padTokenId;
  @override
  final int unkTokenId;
  @override
  final int maxSequenceLength;
  final String unkToken;
  final String clsToken;
  final String sepToken;
  final String padToken;

  const PureDartTokenizer({
    required this.vocab,
    required this.clsTokenId,
    required this.sepTokenId,
    required this.padTokenId,
    required this.unkTokenId,
    this.maxSequenceLength = 512,
    this.unkToken = '[UNK]',
    this.clsToken = '[CLS]',
    this.sepToken = '[SEP]',
    this.padToken = '[PAD]',
  });

  /// Loads vocabulary from asset or string content.
  static Future<PureDartTokenizer> loadFromAsset(
    String vocabAssetPath, {
    NeuralModelConfig config = const NeuralModelConfig(),
  }) async {
    final vocabStr = await rootBundle.loadString(vocabAssetPath);
    return fromVocabString(vocabStr, config: config);
  }

  /// Constructs tokenizer directly from raw lines of vocabulary.
  static PureDartTokenizer fromVocabString(
    String vocabContent, {
    NeuralModelConfig config = const NeuralModelConfig(),
  }) {
    final vocabMap = <String, int>{};
    final lines = const LineSplitter().convert(vocabContent);
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        vocabMap[token] = i;
      }
    }

    final unkId = vocabMap[config.unkToken] ?? 1;
    final clsId = vocabMap[config.clsToken] ?? 2;
    final sepId = vocabMap[config.sepToken] ?? 3;
    final padId = vocabMap[config.padToken] ?? 0;

    return PureDartTokenizer(
      vocab: vocabMap,
      clsTokenId: clsId,
      sepTokenId: sepId,
      padTokenId: padId,
      unkTokenId: unkId,
      maxSequenceLength: config.maxSequenceLength,
      unkToken: config.unkToken,
      clsToken: config.clsToken,
      sepToken: config.sepToken,
      padToken: config.padToken,
    );
  }

  /// Tokenizes [text] preserving token spans and sentence associations.
  @override
  TokenizedInput tokenize({
    required String text,
    List<SentenceBoundary>? sentences,
  }) {
    final sentenceList = sentences ?? const [];
    final inputIds = <int>[clsTokenId];
    final tokenSpans = <TokenSpan>[];

    // [CLS] span
    tokenSpans.add(TokenSpan(
      tokenIndex: clsTokenId,
      startOffset: 0,
      endOffset: 0,
      sentenceIndex: sentenceList.isNotEmpty ? sentenceList.first.index : 0,
    ));

    if (text.trim().isNotEmpty) {
      // Fast subword decomposition on words
      final wordsWithOffsets = _extractWordsAndOffsets(text);

      for (final wordItem in wordsWithOffsets) {
        if (inputIds.length >= maxSequenceLength - 1) {
          // Reserve space for [SEP]
          break;
        }

        final word = wordItem.word;
        final startOffset = wordItem.start;
        final endOffset = wordItem.end;
        final sentIdx = _findSentenceIndex(startOffset, sentenceList);

        final wordTokens = _tokenizeWord(word);
        for (final tokenPiece in wordTokens) {
          if (inputIds.length >= maxSequenceLength - 1) {
            break;
          }
          final tid = vocab[tokenPiece] ?? unkTokenId;
          inputIds.add(tid);
          tokenSpans.add(TokenSpan(
            tokenIndex: tid,
            startOffset: startOffset,
            endOffset: endOffset,
            sentenceIndex: sentIdx,
          ));
        }
      }
    }

    // Append [SEP]
    final lastEnd = tokenSpans.isNotEmpty ? tokenSpans.last.endOffset : text.length;
    final lastSentIdx = sentenceList.isNotEmpty ? sentenceList.last.index : 0;
    inputIds.add(sepTokenId);
    tokenSpans.add(TokenSpan(
      tokenIndex: sepTokenId,
      startOffset: lastEnd,
      endOffset: lastEnd,
      sentenceIndex: lastSentIdx,
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

    final tokenTypeIds = List<int>.filled(maxSequenceLength, 0);

    return TokenizedInput(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: tokenTypeIds,
      tokenSpans: tokenSpans,
    );
  }

  /// WordPiece over an already-normalized (lowercased, accent-stripped) word,
  /// matching HF `WordPiece`: greedy longest-match-first, and the whole word
  /// becomes [UNK] if any piece is unmatched or it exceeds 100 characters.
  List<String> _tokenizeWord(String word) {
    final chars = word.runes.map(String.fromCharCode).toList();
    if (chars.length > _maxInputCharsPerWord) return [unkToken];
    if (vocab.containsKey(word)) return [word];

    final subwords = <String>[];
    int start = 0;
    while (start < chars.length) {
      int end = chars.length;
      String? curSubstr;
      while (start < end) {
        var substr = chars.sublist(start, end).join();
        if (start > 0) substr = '##$substr';
        if (vocab.containsKey(substr)) {
          curSubstr = substr;
          break;
        }
        end--;
      }
      if (curSubstr == null) return [unkToken];
      subwords.add(curSubstr);
      start = end;
    }
    return subwords;
  }

  static const int _maxInputCharsPerWord = 100;

  /// Splits [text] exactly like HF `BertNormalizer` + `BertPreTokenizer`
  /// (clean_text, handle_chinese_chars, lowercase, strip_accents), keeping raw
  /// character offsets so token spans still map back onto the original text.
  List<({String word, int start, int end})> _extractWordsAndOffsets(String text) {
    final result = <({String word, int start, int end})>[];
    final buf = StringBuffer();
    int wordStart = -1;
    int wordEnd = -1;

    void flush() {
      if (buf.isNotEmpty) {
        result.add((word: buf.toString(), start: wordStart, end: wordEnd));
        buf.clear();
      }
      wordStart = -1;
    }

    int offset = 0;
    for (final rune in text.runes) {
      final width = rune > 0xFFFF ? 2 : 1;
      final charStart = offset;
      offset += width;

      if (rune == 0 || rune == 0xFFFD || _isControl(rune)) continue;
      if (_isWhitespace(rune)) {
        flush();
        continue;
      }
      if (_isChineseChar(rune) || _isPunctuation(rune)) {
        flush();
        result.add((word: _normalizeChar(rune), start: charStart, end: offset));
        continue;
      }
      final normalized = _normalizeChar(rune);
      if (normalized.isEmpty) continue;
      if (wordStart < 0) wordStart = charStart;
      wordEnd = offset;
      buf.write(normalized);
    }
    flush();
    return result;
  }

  /// Lowercases and strips accents (NFD + drop combining marks) for one code point.
  static String _normalizeChar(int rune) {
    final lowered = String.fromCharCode(rune).toLowerCase();
    final out = StringBuffer();
    for (final r in lowered.runes) {
      if (r >= 0x0300 && r <= 0x036F) continue; // combining diacritical marks
      final folded = _accentFold[r];
      out.write(folded ?? String.fromCharCode(r));
    }
    return out.toString();
  }

  static bool _isWhitespace(int r) =>
      r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D || r == 0xA0 || r == 0x1680 ||
      (r >= 0x2000 && r <= 0x200A) || r == 0x202F || r == 0x205F || r == 0x3000;

  static bool _isControl(int r) {
    if (r == 0x09 || r == 0x0A || r == 0x0D) return false;
    return r < 0x20 || (r >= 0x7F && r < 0xA0) || r == 0xAD ||
        (r >= 0x200B && r <= 0x200F) || (r >= 0x202A && r <= 0x202E) ||
        (r >= 0x2060 && r <= 0x2064) || r == 0xFEFF;
  }

  static final RegExp _unicodePunct = RegExp(r'^\p{P}$', unicode: true);

  static bool _isPunctuation(int r) {
    if ((r >= 33 && r <= 47) || (r >= 58 && r <= 64) || (r >= 91 && r <= 96) || (r >= 123 && r <= 126)) {
      return true;
    }
    return r > 127 && _unicodePunct.hasMatch(String.fromCharCode(r));
  }

  static bool _isChineseChar(int r) =>
      (r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF) ||
      (r >= 0x20000 && r <= 0x2A6DF) || (r >= 0x2A700 && r <= 0x2B73F) ||
      (r >= 0x2B740 && r <= 0x2B81F) || (r >= 0x2B820 && r <= 0x2CEAF) ||
      (r >= 0xF900 && r <= 0xFAFF) || (r >= 0x2F800 && r <= 0x2FA1F);

  /// Precomposed Latin letters whose NFD decomposition is base letter + marks.
  static final Map<int, String> _accentFold = () {
    const groups = {
      'a': 'àáâãäåāăą', 'c': 'çćĉċč', 'd': 'ď', 'e': 'èéêëēĕėęě',
      'g': 'ĝğġģ', 'h': 'ĥ', 'i': 'ìíîïĩīĭįı', 'j': 'ĵ', 'k': 'ķ',
      'l': 'ĺļľ', 'n': 'ñńņňǹ', 'o': 'òóôõöōŏő', 'r': 'ŕŗř',
      's': 'śŝşšș', 't': 'ţťț', 'u': 'ùúûüũūŭůűų', 'w': 'ŵ',
      'y': 'ýÿŷ', 'z': 'źżž',
    };
    final map = <int, String>{};
    groups.forEach((base, variants) {
      for (final r in variants.runes) {
        map[r] = base;
      }
    });
    // NFD leaves dotless i unchanged; keep BERT parity.
    map.remove(0x0131);
    return map;
  }();

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
