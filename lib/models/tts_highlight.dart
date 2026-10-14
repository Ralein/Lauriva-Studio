import 'package:flutter/foundation.dart';

/// Represents a single tokenized word with its exact character boundaries
/// in the source document.
@immutable
class TtsWordToken {
  final int index;
  final String word;
  final int charStart;
  final int charEnd;

  const TtsWordToken({
    required this.index,
    required this.word,
    required this.charStart,
    required this.charEnd,
  });

  int get length => charEnd - charStart;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsWordToken &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          word == other.word &&
          charStart == other.charStart &&
          charEnd == other.charEnd;

  @override
  int get hashCode => Object.hash(index, word, charStart, charEnd);

  @override
  String toString() => 'TtsWordToken(#$index "$word" [$charStart..$charEnd])';

  /// Tokenizes [text] into discrete word tokens while preserving exact
  /// character indices in the source string. Outer punctuation is stripped
  /// from the highlighted word token so only the spoken word lights up.
  static List<TtsWordToken> tokenize(String text) {
    if (text.isEmpty) return const [];

    final tokens = <TtsWordToken>[];
    final regex = RegExp(r'\S+');
    final matches = regex.allMatches(text);
    int index = 0;

    for (final m in matches) {
      final rawToken = m.group(0)!;
      final matchStart = m.start;
      final matchEnd = m.end;

      // Find boundaries excluding outer punctuation
      int startOffset = 0;
      while (startOffset < rawToken.length &&
          _isOuterPunctuation(rawToken.codeUnitAt(startOffset))) {
        startOffset++;
      }

      int endOffset = rawToken.length;
      while (endOffset > startOffset &&
          _isOuterPunctuation(rawToken.codeUnitAt(endOffset - 1))) {
        endOffset--;
      }

      final int actualStart;
      final int actualEnd;
      final String word;

      if (startOffset < endOffset) {
        actualStart = matchStart + startOffset;
        actualEnd = matchStart + endOffset;
        word = rawToken.substring(startOffset, endOffset);
      } else {
        // Fallback: token was pure punctuation or symbols (e.g. "---", "...")
        actualStart = matchStart;
        actualEnd = matchEnd;
        word = rawToken;
      }

      tokens.add(TtsWordToken(
        index: index++,
        word: word,
        charStart: actualStart,
        charEnd: actualEnd,
      ));
    }

    return List.unmodifiable(tokens);
  }

  static bool _isOuterPunctuation(int codeUnit) {
    // Standard ASCII punctuation & common typographic quotes/dashes:
    // . , ! ? : ; " ' ( ) [ ] { } < > / \ | * ~ ` - _
    // Quotes: “ (0x201C), ” (0x201D), ‘ (0x2018), ’ (0x2019)
    // Dashes: – (0x2013), — (0x2014)
    if (codeUnit == 0x2E || // .
        codeUnit == 0x2C || // ,
        codeUnit == 0x21 || // !
        codeUnit == 0x3F || // ?
        codeUnit == 0x3A || // :
        codeUnit == 0x3B || // ;
        codeUnit == 0x22 || // "
        codeUnit == 0x27 || // '
        codeUnit == 0x28 || // (
        codeUnit == 0x29 || // )
        codeUnit == 0x5B || // [
        codeUnit == 0x5D || // ]
        codeUnit == 0x7B || // {
        codeUnit == 0x7D || // }
        codeUnit == 0x3C || // <
        codeUnit == 0x3E || // >
        codeUnit == 0x2F || // /
        codeUnit == 0x5C || // \
        codeUnit == 0x7C || // |
        codeUnit == 0x2A || // *
        codeUnit == 0x7E || // ~
        codeUnit == 0x60 || // `
        codeUnit == 0x2D || // -
        codeUnit == 0x5F || // _
        codeUnit == 0x201C || // “
        codeUnit == 0x201D || // ”
        codeUnit == 0x2018 || // ‘
        codeUnit == 0x2019 || // ’
        codeUnit == 0x2013 || // –
        codeUnit == 0x2014) { // —
      return true;
    }
    return false;
  }
}

/// Represents an exact substring chunk for TTS execution that strictly obeys
/// platform synthesizer limits without modifying underlying characters.
@immutable
class TtsChunkSpan {
  final String text;
  final int charStart;
  final int charEnd;

  const TtsChunkSpan({
    required this.text,
    required this.charStart,
    required this.charEnd,
  });

  int get length => charEnd - charStart;

  @override
  String toString() => 'TtsChunkSpan([$charStart..$charEnd], length: $length)';

  /// Creates character-accurate chunks strictly slicing [fullText] on natural
  /// sentence or paragraph boundaries without modifying a single character.
  /// If [baseOffset] is supplied, all chunk spans are offset relative to the
  /// source document's global character coordinates (essential for pause/resume).
  static List<TtsChunkSpan> createChunks(
    String fullText, {
    int baseOffset = 0,
    int maxChunkLength = 1200,
  }) {
    if (fullText.trim().isEmpty) return <TtsChunkSpan>[];
    if (fullText.length <= maxChunkLength) {
      return [
        TtsChunkSpan(
          text: fullText,
          charStart: baseOffset,
          charEnd: baseOffset + fullText.length,
        ),
      ];
    }

    final chunks = <TtsChunkSpan>[];
    int start = 0;
    final totalLength = fullText.length;

    while (start < totalLength) {
      if (start + maxChunkLength >= totalLength) {
        chunks.add(TtsChunkSpan(
          text: fullText.substring(start),
          charStart: baseOffset + start,
          charEnd: baseOffset + totalLength,
        ));
        break;
      }

      final limit = start + maxChunkLength;
      int splitIndex = -1;

      // 1. Paragraph boundary (\n\n)
      final paraIdx = fullText.lastIndexOf('\n\n', limit);
      if (paraIdx > start + 150) {
        splitIndex = paraIdx + 2;
      }

      // 2. Sentence boundary (. ! ? followed by space/newline)
      if (splitIndex == -1) {
        final sentenceRegex = RegExp(r'[.!?](\s|\n)');
        final searchSlice = fullText.substring(start, limit);
        final matches = sentenceRegex.allMatches(searchSlice).toList();
        if (matches.isNotEmpty) {
          final last = matches.last;
          if (last.end > 100) {
            splitIndex = start + last.end;
          }
        }
      }

      // 3. Clause boundary (, ; : followed by space)
      if (splitIndex == -1) {
        final clauseRegex = RegExp(r'[,;:](\s|\n)');
        final searchSlice = fullText.substring(start, limit);
        final matches = clauseRegex.allMatches(searchSlice).toList();
        if (matches.isNotEmpty) {
          final last = matches.last;
          if (last.end > 100) {
            splitIndex = start + last.end;
          }
        }
      }

      // 4. Word boundary (space or newline)
      if (splitIndex == -1) {
        final spaceIdx = fullText.lastIndexOf(' ', limit);
        if (spaceIdx > start + 50) {
          splitIndex = spaceIdx + 1;
        }
      }

      // 5. Hard slice fallback
      if (splitIndex <= start) {
        splitIndex = limit;
      }

      chunks.add(TtsChunkSpan(
        text: fullText.substring(start, splitIndex),
        charStart: baseOffset + start,
        charEnd: baseOffset + splitIndex,
      ));

      start = splitIndex;
    }

    return List.unmodifiable(chunks);
  }
}

/// High-precision highlight state model emitted whenever the voice system
/// advances to a new word in the spoken document.
@immutable
class TtsHighlight {
  /// The full document string currently being read.
  final String fullText;

  /// Absolute character start index in [fullText] (0-indexed).
  final int charStart;

  /// Absolute character end index in [fullText] (0-indexed, exclusive).
  final int charEnd;

  /// The exact word or token being spoken.
  final String word;

  /// Ordinal position of the word in the document (0-indexed).
  final int wordIndex;

  /// Total number of words in the document.
  final int totalWords;

  /// Overall reading completion percentage from 0.0 to 1.0.
  final double progress;

  /// The active chunk index (0-indexed).
  final int chunkIndex;

  /// Total chunks being spoken.
  final int totalChunks;

  const TtsHighlight({
    required this.fullText,
    required this.charStart,
    required this.charEnd,
    required this.word,
    required this.wordIndex,
    required this.totalWords,
    required this.progress,
    this.chunkIndex = 0,
    this.totalChunks = 1,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsHighlight &&
          runtimeType == other.runtimeType &&
          charStart == other.charStart &&
          charEnd == other.charEnd &&
          word == other.word &&
          wordIndex == other.wordIndex &&
          chunkIndex == other.chunkIndex;

  @override
  int get hashCode => Object.hash(charStart, charEnd, word, wordIndex, chunkIndex);

  @override
  String toString() =>
      'TtsHighlight(#$wordIndex "$word" [$charStart..$charEnd], ${(progress * 100).toStringAsFixed(1)}%)';
}
