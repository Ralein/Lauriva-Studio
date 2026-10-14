import 'document_segmenter.dart';

/// Represents a contiguous, sentence-bounded partition of a document for
/// scalable, progressive chunk-based forensic analysis across any document length.
class DocumentChunk {
  final int chunkIndex;
  final int totalChunks;
  final int startSentenceIndex;
  final int endSentenceIndex; // exclusive
  final int rawStartOffset;
  final int rawEndOffset;
  final int normStartOffset;
  final int normEndOffset;
  final String text;
  final int wordCount;
  final int charCount;
  final List<SegmentedSentence> sentences;
  final SegmentedDocument chunkDocument;

  const DocumentChunk({
    required this.chunkIndex,
    required this.totalChunks,
    required this.startSentenceIndex,
    required this.endSentenceIndex,
    required this.rawStartOffset,
    required this.rawEndOffset,
    required this.normStartOffset,
    required this.normEndOffset,
    required this.text,
    required this.wordCount,
    required this.charCount,
    required this.sentences,
    required this.chunkDocument,
  });

  @override
  String toString() =>
      'DocumentChunk(index: $chunkIndex/$totalChunks, words: $wordCount, sentences: ${sentences.length}, span: [$rawStartOffset, $rawEndOffset])';
}
