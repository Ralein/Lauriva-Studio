import '../../text_forensics_lexicons.dart';

/// Result of document-level inter-paragraph coherence pass.
class DocumentCoherenceResult {
  final String coherentText;
  final bool adjusted;
  final List<String> coherenceNotes;

  const DocumentCoherenceResult({
    required this.coherentText,
    required this.adjusted,
    required this.coherenceNotes,
  });
}

/// DocumentCoherencePass performs a lightweight, multi-paragraph inspection
/// to ensure inter-paragraph logical flow, terminology consistency, and smooth transitions
/// without requiring full-document regeneration.
class DocumentCoherencePass {
  static const List<String> _prematureConclusions = [
    'in conclusion',
    'to conclude',
    'in summary',
    'finally',
  ];

  static const List<String> _repetitiveParagraphStarters = [
    'furthermore',
    'moreover',
    'additionally',
    'consequently',
  ];

  /// Runs the coherence pass over segmented paragraphs [paragraphs].
  DocumentCoherenceResult harmonize(List<String> paragraphs) {
    if (paragraphs.length <= 1) {
      return DocumentCoherenceResult(
        coherentText: paragraphs.join('\n\n'),
        adjusted: false,
        coherenceNotes: const [],
      );
    }

    final adjustedParagraphs = <String>[];
    final notes = <String>[];
    bool wasAdjusted = false;
    final seenParagraphOpeners = <String, int>{};

    for (int p = 0; p < paragraphs.length; p++) {
      var pText = paragraphs[p].trim();
      if (pText.isEmpty) continue;

      final sentences = TextForensicsLexicons.splitSentences(pText);
      if (sentences.isNotEmpty) {
        var firstSentence = sentences.first.trim();
        final words = TextForensicsLexicons.extractWords(firstSentence);

        if (words.isNotEmpty) {
          final firstWord = words.first.toLowerCase();
          final firstTwo = words.length >= 2 ? '${words[0].toLowerCase()} ${words[1].toLowerCase()}' : '';

          // 1. Check for premature conclusion phrases before the final paragraph
          if (p < paragraphs.length - 1) {
            for (final concl in _prematureConclusions) {
              if (firstSentence.toLowerCase().startsWith(concl)) {
                firstSentence = firstSentence.replaceFirst(
                  RegExp('^${RegExp.escape(concl)}[,]?\\s*', caseSensitive: false),
                  '',
                );
                if (firstSentence.isNotEmpty) {
                  firstSentence = firstSentence[0].toUpperCase() + firstSentence.substring(1);
                }
                sentences[0] = firstSentence;
                pText = sentences.join(' ');
                notes.add('Removed premature "$concl" in paragraph ${p + 1}');
                wasAdjusted = true;
                break;
              }
            }
          }

          // 2. Check for repetitive paragraph openers across paragraphs
          String? starter;
          if (_repetitiveParagraphStarters.contains(firstWord)) {
            starter = firstWord;
          } else if (_repetitiveParagraphStarters.contains(firstTwo)) {
            starter = firstTwo;
          }

          if (starter != null) {
            final count = (seenParagraphOpeners[starter] ?? 0) + 1;
            seenParagraphOpeners[starter] = count;

            if (count > 1) {
              // Smooth repetitive opener at paragraph boundary
              firstSentence = firstSentence.replaceFirst(
                RegExp('^${RegExp.escape(starter)}[,]?\\s*', caseSensitive: false),
                '',
              );
              if (firstSentence.isNotEmpty) {
                firstSentence = firstSentence[0].toUpperCase() + firstSentence.substring(1);
              }
              sentences[0] = firstSentence;
              pText = sentences.join(' ');
              notes.add('Varied repetitive paragraph opener "$starter" in paragraph ${p + 1}');
              wasAdjusted = true;
            }
          }
        }
      }

      adjustedParagraphs.add(pText);
    }

    return DocumentCoherenceResult(
      coherentText: adjustedParagraphs.join('\n\n'),
      adjusted: wasAdjusted,
      coherenceNotes: notes,
    );
  }
}
