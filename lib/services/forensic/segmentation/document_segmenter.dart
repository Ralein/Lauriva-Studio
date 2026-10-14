import 'sentence_segmenter.dart';
import 'text_window.dart';

abstract class DocumentSegmenter {
  List<TextWindow> segment(String text, {List<SentenceBoundary>? sentences});
}

/// Token and sentence aware document segmenter with configurable overlap.
class TokenAwareDocumentSegmenter implements DocumentSegmenter {
  final int targetTokenCount;
  final int overlapTokenCount;
  final SentenceSegmenter _sentenceSegmenter;

  TokenAwareDocumentSegmenter({
    this.targetTokenCount = 384,
    this.overlapTokenCount = 64,
    SentenceSegmenter? sentenceSegmenter,
  }) : _sentenceSegmenter = sentenceSegmenter ?? RuleBasedSentenceSegmenter();

  @override
  List<TextWindow> segment(String text, {List<SentenceBoundary>? sentences}) {
    final clean = text.trim();
    if (clean.isEmpty) return const [];

    final bounds = sentences ?? _sentenceSegmenter.segment(text);
    if (bounds.isEmpty) return const [];

    // If total sentences fit comfortably in one window, return single window
    final totalApproxTokens = _estimateTokenCount(clean);
    if (totalApproxTokens <= targetTokenCount || bounds.length <= 3) {
      return [
        TextWindow(
          index: 0,
          startOffset: bounds.first.start,
          endOffset: bounds.last.end,
          text: clean,
          sentenceIndices: List.generate(bounds.length, (i) => bounds[i].index),
          weight: 1.0,
        ),
      ];
    }

    final windows = <TextWindow>[];
    int currentSentIdx = 0;
    int windowIndex = 0;

    while (currentSentIdx < bounds.length) {
      int accumulatedTokens = 0;
      final includedSentIndices = <int>[];
      int windowStart = bounds[currentSentIdx].start;
      int windowEnd = bounds[currentSentIdx].end;

      int i = currentSentIdx;
      while (i < bounds.length) {
        final sent = bounds[i];
        final sentTokens = _estimateTokenCount(sent.text);
        if (accumulatedTokens + sentTokens > targetTokenCount && includedSentIndices.isNotEmpty) {
          break;
        }
        accumulatedTokens += sentTokens;
        includedSentIndices.add(sent.index);
        windowEnd = sent.end;
        i++;
      }

      final windowText = text.substring(windowStart, windowEnd);
      // Center windows or full windows get higher weight
      final weight = (accumulatedTokens / targetTokenCount).clamp(0.5, 1.0);

      windows.add(TextWindow(
        index: windowIndex++,
        startOffset: windowStart,
        endOffset: windowEnd,
        text: windowText,
        sentenceIndices: includedSentIndices,
        weight: weight,
      ));

      if (i >= bounds.length) {
        break;
      }

      // Calculate step-forward with overlap
      int overlapTokens = 0;
      int stepSentIdx = i;
      while (stepSentIdx > currentSentIdx + 1 && overlapTokens < overlapTokenCount) {
        stepSentIdx--;
        overlapTokens += _estimateTokenCount(bounds[stepSentIdx].text);
      }
      currentSentIdx = stepSentIdx;
    }

    return windows;
  }

  int _estimateTokenCount(String text) {
    // Fast estimation: 1 word ~ 1.33 tokens
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (words * 1.33).ceil().clamp(1, 999999);
  }
}
