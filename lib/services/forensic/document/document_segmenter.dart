import '../../text_forensics_lexicons.dart';
import '../normalization/position_mapper.dart';
import '../normalization/text_normalizer.dart';
import 'document_chunk.dart';

/// A segmented paragraph with character ranges mapped to raw source text.
class SegmentedParagraph {
  final int index;
  final int rawStartOffset;
  final int rawEndOffset;
  final String text;
  final int sentenceCount;

  const SegmentedParagraph({
    required this.index,
    required this.rawStartOffset,
    required this.rawEndOffset,
    required this.text,
    required this.sentenceCount,
  });
}

/// A segmented sentence with boundary metadata and raw source offsets.
class SegmentedSentence {
  final int index;
  final int paragraphIndex;
  final int normStartOffset;
  final int normEndOffset;
  final int rawStartOffset;
  final int rawEndOffset;
  final String text;
  final int wordCount;
  final int charCount;

  const SegmentedSentence({
    required this.index,
    required this.paragraphIndex,
    required this.normStartOffset,
    required this.normEndOffset,
    required this.rawStartOffset,
    required this.rawEndOffset,
    required this.text,
    required this.wordCount,
    required this.charCount,
  });
}

/// Result of hierarchical document segmentation.
class SegmentedDocument {
  final NormalizedDocument normalizedDocument;
  final List<SegmentedParagraph> paragraphs;
  final List<SegmentedSentence> sentences;
  final int totalWordCount;
  final int totalCharCount;

  const SegmentedDocument({
    required this.normalizedDocument,
    required this.paragraphs,
    required this.sentences,
    required this.totalWordCount,
    required this.totalCharCount,
  });
}

/// Boundary-aware document segmenter handling sentence splits, abbreviations, and paragraph structure.
class DocumentSegmenter {
  static final Set<String> _abbreviations = {
    'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'gen', 'col', 'rep', 'sen',
    'eg', 'ie', 'etc', 'vs', 'al', 'cf', 'viz', 'approx', 'dept',
    'us', 'uk', 'eu', 'un', 'usa', 'ai', 'jan', 'feb', 'mar', 'apr', 'aug', 'sept', 'oct', 'nov', 'dec',
  };

  /// Segments [normalizedDoc] into structural paragraphs and sentences with exact position tracking.
  SegmentedDocument segment(NormalizedDocument normalizedDoc) {
    final normText = normalizedDoc.normalizedText;
    final mapper = normalizedDoc.mapper;

    if (normText.trim().isEmpty) {
      return SegmentedDocument(
        normalizedDocument: normalizedDoc,
        paragraphs: const [],
        sentences: const [],
        totalWordCount: 0,
        totalCharCount: 0,
      );
    }

    final rawParagraphBlocks = normText.split(RegExp(r'\n{2,}'));
    final paragraphs = <SegmentedParagraph>[];
    final allSentences = <SegmentedSentence>[];

    int currentNormOffset = 0;
    int sentenceIndex = 0;
    int totalWords = 0;

    for (int pIdx = 0; pIdx < rawParagraphBlocks.length; pIdx++) {
      final pText = rawParagraphBlocks[pIdx];
      final pNormStart = normText.indexOf(pText, currentNormOffset);
      final pNormEnd = pNormStart + pText.length;
      currentNormOffset = pNormEnd;

      final (pRawStart, pRawEnd) = mapper.mapSpan(pNormStart, pNormEnd);

      // Sentence segmentation within paragraph
      final sentenceSpans = _splitSentences(pText, pNormStart);
      final paragraphSentences = <SegmentedSentence>[];

      for (final span in sentenceSpans) {
        final sText = normText.substring(span.start, span.end).trim();
        if (sText.isEmpty) continue;

        // Whitespace tokens; Han/kana characters count individually because
        // Chinese and Japanese are written without spaces.
        final wordCount = TextForensicsLexicons.countWordUnits(sText);
        final (sRawStart, sRawEnd) = mapper.mapSpan(span.start, span.end);

        final sentence = SegmentedSentence(
          index: sentenceIndex++,
          paragraphIndex: pIdx,
          normStartOffset: span.start,
          normEndOffset: span.end,
          rawStartOffset: sRawStart,
          rawEndOffset: sRawEnd,
          text: sText,
          wordCount: wordCount,
          charCount: sText.length,
        );

        paragraphSentences.add(sentence);
        allSentences.add(sentence);
        totalWords += wordCount;
      }

      paragraphs.add(
        SegmentedParagraph(
          index: pIdx,
          rawStartOffset: pRawStart,
          rawEndOffset: pRawEnd,
          text: pText.trim(),
          sentenceCount: paragraphSentences.length,
        ),
      );
    }

    return SegmentedDocument(
      normalizedDocument: normalizedDoc,
      paragraphs: paragraphs,
      sentences: allSentences,
      totalWordCount: totalWords,
      totalCharCount: normText.length,
    );
  }

  /// Splits paragraph text into sentence spans `[start, end]` within global normalized space.
  List<({int start, int end})> _splitSentences(String pText, int pGlobalOffset) {
    final spans = <({int start, int end})>[];
    final len = pText.length;

    int sentStart = 0;

    for (int i = 0; i < len; i++) {
      final char = pText[i];

      // CJK full-width terminators end a sentence without a following space.
      if (char == '。' || char == '！' || char == '？') {
        int nextIdx = i + 1;
        while (nextIdx < len && _closers.contains(pText[nextIdx])) {
          nextIdx++;
        }
        final spanText = pText.substring(sentStart, nextIdx).trim();
        if (spanText.isNotEmpty) {
          final leadingWhitespace = pText.substring(sentStart, nextIdx).indexOf(spanText);
          final realStart = pGlobalOffset + sentStart + leadingWhitespace;
          spans.add((start: realStart, end: realStart + spanText.length));
        }
        sentStart = nextIdx;
        i = nextIdx - 1;
        continue;
      }

      // Latin terminators plus the Indic danda (।, ॥) and Arabic/Urdu
      // question mark and full stop (؟, ۔), which are followed by a space.
      if (char == '.' || char == '!' || char == '?' || char == '।' || char == '॥' || char == '؟' || char == '۔') {
        // Check for decimal number (e.g. "3.14")
        if (char == '.' && i > 0 && i + 1 < len) {
          final isPrevDigit = RegExp(r'\d').hasMatch(pText[i - 1]);
          final isNextDigit = RegExp(r'\d').hasMatch(pText[i + 1]);
          if (isPrevDigit && isNextDigit) {
            continue;
          }
        }

        // Check for abbreviations (e.g. "Dr.", "e.g.", "vs.")
        if (char == '.') {
          final wordBefore = _getWordBefore(pText, i).toLowerCase().replaceAll('.', '');
          if (_abbreviations.contains(wordBefore)) {
            continue;
          }
        }

        // Check if punctuation is followed by whitespace, quote, or end of paragraph
        bool isTerminal = false;
        int nextIdx = i + 1;

        // Skip any closing quotes or brackets attached to the terminal punctuation
        while (nextIdx < len && (pText[nextIdx] == '"' || pText[nextIdx] == "'" || pText[nextIdx] == ')' || pText[nextIdx] == '”')) {
          nextIdx++;
        }

        if (nextIdx >= len) {
          isTerminal = true;
        } else if (pText[nextIdx] == ' ' || pText[nextIdx] == '\n' || pText[nextIdx] == '\t') {
          isTerminal = true;
        }

        if (isTerminal) {
          final spanText = pText.substring(sentStart, nextIdx).trim();
          if (spanText.isNotEmpty) {
            final leadingWhitespace = pText.substring(sentStart, nextIdx).indexOf(spanText);
            final realStart = pGlobalOffset + sentStart + leadingWhitespace;
            final realEnd = realStart + spanText.length;
            spans.add((start: realStart, end: realEnd));
          }
          sentStart = nextIdx;
          i = nextIdx - 1; // Advance loop
        }
      }
    }

    // Trailing fragment without terminal punctuation
    if (sentStart < len) {
      final tail = pText.substring(sentStart).trim();
      if (tail.isNotEmpty) {
        final leadingWhitespace = pText.substring(sentStart).indexOf(tail);
        final realStart = pGlobalOffset + sentStart + leadingWhitespace;
        final realEnd = realStart + tail.length;
        spans.add((start: realStart, end: realEnd));
      }
    }

    return spans;
  }

  /// Closing quotes and brackets that stay attached to a CJK terminator.
  static const Set<String> _closers = {'」', '』', '）', '】', '》', '〉', '”', '"', ')'};

  String _getWordBefore(String text, int dotIndex) {
    int start = dotIndex - 1;
    while (start >= 0 && RegExp(r'[a-zA-Z.]').hasMatch(text[start])) {
      start--;
    }
    return text.substring(start + 1, dotIndex);
  }

  /// Partitions [doc] into contiguous, sentence-bounded [DocumentChunk]s
  /// targeting approximately [targetWordsPerChunk] words per chunk.
  ///
  /// Works reliably with ANY document size (from 15 words to 50,000+ words).
  List<DocumentChunk> partitionIntoChunks(
    SegmentedDocument doc, {
    int targetWordsPerChunk = 300,
    int minWordsPerChunk = 120,
  }) {
    final sentences = doc.sentences;
    if (sentences.isEmpty) {
      return [
        DocumentChunk(
          chunkIndex: 0,
          totalChunks: 1,
          startSentenceIndex: 0,
          endSentenceIndex: 0,
          rawStartOffset: 0,
          rawEndOffset: 0,
          normStartOffset: 0,
          normEndOffset: 0,
          text: doc.normalizedDocument.normalizedText,
          wordCount: doc.totalWordCount,
          charCount: doc.totalCharCount,
          sentences: const [],
          chunkDocument: doc,
        ),
      ];
    }

    if (doc.totalWordCount <= targetWordsPerChunk || sentences.length <= 3) {
      return [
        DocumentChunk(
          chunkIndex: 0,
          totalChunks: 1,
          startSentenceIndex: 0,
          endSentenceIndex: sentences.length,
          rawStartOffset: sentences.first.rawStartOffset,
          rawEndOffset: sentences.last.rawEndOffset,
          normStartOffset: sentences.first.normStartOffset,
          normEndOffset: sentences.last.normEndOffset,
          text: doc.normalizedDocument.normalizedText,
          wordCount: doc.totalWordCount,
          charCount: doc.totalCharCount,
          sentences: sentences,
          chunkDocument: doc,
        ),
      ];
    }

    // Multi-chunk partition
    final chunkSlices = <List<SegmentedSentence>>[];
    var currentSlice = <SegmentedSentence>[];
    int currentWords = 0;

    for (int i = 0; i < sentences.length; i++) {
      final s = sentences[i];
      currentSlice.add(s);
      currentWords += s.wordCount;

      final remainingSentences = sentences.length - (i + 1);
      final isParagraphEnd = (i + 1 < sentences.length) && (s.paragraphIndex != sentences[i + 1].paragraphIndex);

      // Trigger boundary when target word limit reached and at paragraph or natural boundary
      final shouldSplit = (currentWords >= targetWordsPerChunk && remainingSentences >= 2) ||
          (currentWords >= (targetWordsPerChunk * 0.75).round() && isParagraphEnd && remainingSentences >= 2);

      if (shouldSplit) {
        chunkSlices.add(List.from(currentSlice));
        currentSlice.clear();
        currentWords = 0;
      }
    }

    // Residual sentences: merge into last chunk if too small, otherwise create final chunk
    if (currentSlice.isNotEmpty) {
      if (chunkSlices.isNotEmpty && currentWords < minWordsPerChunk) {
        chunkSlices.last.addAll(currentSlice);
      } else {
        chunkSlices.add(currentSlice);
      }
    }

    final totalChunks = chunkSlices.length;
    final chunks = <DocumentChunk>[];

    int sentenceOffset = 0;
    for (int cIdx = 0; cIdx < totalChunks; cIdx++) {
      final cSentences = chunkSlices[cIdx];
      final startSentIdx = sentenceOffset;
      final endSentIdx = startSentIdx + cSentences.length;
      sentenceOffset = endSentIdx;

      final rawStart = cSentences.first.rawStartOffset;
      final rawEnd = cSentences.last.rawEndOffset;
      final normStart = cSentences.first.normStartOffset;
      final normEnd = cSentences.last.normEndOffset;

      final chunkNormText = doc.normalizedDocument.normalizedText.substring(
        normStart.clamp(0, doc.normalizedDocument.normalizedText.length),
        normEnd.clamp(0, doc.normalizedDocument.normalizedText.length),
      );

      final chunkWords = cSentences.fold<int>(0, (sum, s) => sum + s.wordCount);

      // Create isolated sub-document representation for chunk
      final chunkDoc = SegmentedDocument(
        normalizedDocument: NormalizedDocument(
          rawText: chunkNormText,
          normalizedText: chunkNormText,
          mapper: PositionMapper.identity(chunkNormText.length),
          metadata: doc.normalizedDocument.metadata,
        ),
        paragraphs: doc.paragraphs.where((p) => p.rawStartOffset >= rawStart && p.rawEndOffset <= rawEnd).toList(),
        sentences: cSentences,
        totalWordCount: chunkWords,
        totalCharCount: chunkNormText.length,
      );

      chunks.add(
        DocumentChunk(
          chunkIndex: cIdx,
          totalChunks: totalChunks,
          startSentenceIndex: startSentIdx,
          endSentenceIndex: endSentIdx,
          rawStartOffset: rawStart,
          rawEndOffset: rawEnd,
          normStartOffset: normStart,
          normEndOffset: normEnd,
          text: chunkNormText,
          wordCount: chunkWords,
          charCount: chunkNormText.length,
          sentences: cSentences,
          chunkDocument: chunkDoc,
        ),
      );
    }

    return chunks;
  }
}

