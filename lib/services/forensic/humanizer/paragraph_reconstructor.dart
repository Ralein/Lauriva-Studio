import '../../text_forensics_lexicons.dart';

/// Result of paragraph-level reconstruction and transition smoothing.
class ReconstructedParagraphResult {
  final String text;
  final bool smoothed;
  final List<String> adjustedTransitions;
  final double transitionDiversityScore;

  const ReconstructedParagraphResult({
    required this.text,
    required this.smoothed,
    required this.adjustedTransitions,
    required this.transitionDiversityScore,
  });
}

/// ParagraphReconstructor assembles rewritten chunks into a coherent paragraph unit,
/// detects and repairs repetitive formulaic sentence openers ("Furthermore", "Moreover",
/// "This highlights", "Notably"), and ensures natural sentence rhythm and pronoun continuity.
class ParagraphReconstructor {
  static const Map<String, List<String>> _transitionSubstitutes = {
    'furthermore': ['beyond this,', 'equally significant,', 'additionally,', ''],
    'moreover': ['at the same time,', 'in tandem with this,', 'what is more,', ''],
    'additionally': ['in parallel,', 'further,', 'on a related note,', ''],
    'however': ['yet,', 'conversely,', 'in contrast,', 'still,'],
    'notably': ['interestingly,', 'significantly,', 'in particular,', ''],
    'overall': ['taken together,', 'on balance,', 'in broad terms,', ''],
    'this highlights': ['such dynamics underscore', 'this observation points to', 'these findings indicate'],
    'this demonstrates': ['the evidence clarifies that', 'this illustrates that', 'in effect, this shows that'],
    'this suggests': ['this hints at', 'one inference is that', 'this points toward'],
  };

  /// Reconstructs a paragraph from its rewritten chunks, smoothing cross-chunk seams.
  ReconstructedParagraphResult reconstruct({
    required List<String> rewrittenChunks,
    required String originalParagraph,
  }) {
    if (rewrittenChunks.isEmpty) {
      return ReconstructedParagraphResult(
        text: originalParagraph,
        smoothed: false,
        adjustedTransitions: const [],
        transitionDiversityScore: 1.0,
      );
    }

    // Join chunks respecting natural spacing
    final rawJoined = rewrittenChunks
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .join(' ');

    final sentences = TextForensicsLexicons.splitSentences(rawJoined);
    if (sentences.length <= 1) {
      return ReconstructedParagraphResult(
        text: rawJoined,
        smoothed: false,
        adjustedTransitions: const [],
        transitionDiversityScore: 1.0,
      );
    }

    final adjustedSentences = <String>[];
    final adjustedTransitions = <String>[];
    final seenOpeners = <String, int>{};
    bool wasSmoothed = false;

    for (int i = 0; i < sentences.length; i++) {
      var s = sentences[i].trim();
      final words = TextForensicsLexicons.extractWords(s);
      if (words.isEmpty) continue;

      final firstWord = words.first.toLowerCase();
      final firstTwoWords = words.length >= 2 ? '${words[0].toLowerCase()} ${words[1].toLowerCase()}' : '';

      // Check for repeated openers
      String? keyToReplace;
      if (_transitionSubstitutes.containsKey(firstTwoWords)) {
        keyToReplace = firstTwoWords;
      } else if (_transitionSubstitutes.containsKey(firstWord)) {
        keyToReplace = firstWord;
      }

      if (keyToReplace != null) {
        final count = (seenOpeners[keyToReplace] ?? 0) + 1;
        seenOpeners[keyToReplace] = count;

        // If repeated or if previous sentence started with the same transition family
        if (count > 1 || (i > 0 && _isConsecutiveTransitionConflict(sentences[i - 1], s))) {
          final substitutes = _transitionSubstitutes[keyToReplace]!;
          final subIdx = (count - 1) % substitutes.length;
          final replacement = substitutes[subIdx];

          s = _replaceSentenceOpener(s, keyToReplace, replacement);
          adjustedTransitions.add('$keyToReplace -> ${replacement.isEmpty ? "(removed)" : replacement}');
          wasSmoothed = true;
        }
      }

      // Check for dangling "This [verb]" formula
      if (s.startsWith(RegExp(r'\bThis\s+(?:highlights|demonstrates|suggests|proves|illustrates)\b', caseSensitive: false))) {
        if (i == 0 && rewrittenChunks.length > 1) {
          // If the first sentence of a reconstructed chunk starts with dangling "This", ground it
          s = s.replaceFirst(RegExp(r'\bThis\s+', caseSensitive: false), 'These considerations ');
          wasSmoothed = true;
        }
      }

      adjustedSentences.add(s);
    }

    // Calculate transition diversity score
    final uniqueOpeners = seenOpeners.keys.length;
    final totalOpeners = seenOpeners.values.fold<int>(0, (a, b) => a + b);
    final diversity = totalOpeners == 0 ? 1.0 : (uniqueOpeners / totalOpeners).clamp(0.0, 1.0);

    return ReconstructedParagraphResult(
      text: adjustedSentences.join(' '),
      smoothed: wasSmoothed,
      adjustedTransitions: adjustedTransitions,
      transitionDiversityScore: diversity,
    );
  }

  bool _isConsecutiveTransitionConflict(String prevSentence, String currentSentence) {
    final prevWords = TextForensicsLexicons.extractWords(prevSentence);
    final currWords = TextForensicsLexicons.extractWords(currentSentence);
    if (prevWords.isEmpty || currWords.isEmpty) return false;

    final pFirst = prevWords.first.toLowerCase();
    final cFirst = currWords.first.toLowerCase();

    // Check if both sentences start with transitional adverbs
    const formalTransitions = {'furthermore', 'moreover', 'additionally', 'however', 'notably', 'consequently'};
    return formalTransitions.contains(pFirst) && formalTransitions.contains(cFirst);
  }

  String _replaceSentenceOpener(String sentence, String targetOpener, String replacement) {
    final pattern = RegExp('^${RegExp.escape(targetOpener)}[,]?\\s*', caseSensitive: false);
    if (replacement.isEmpty) {
      final stripped = sentence.replaceFirst(pattern, '');
      if (stripped.isNotEmpty) {
        return stripped[0].toUpperCase() + stripped.substring(1);
      }
      return sentence;
    }
    final stripped = sentence.replaceFirst(pattern, '');
    final repCapitalized = replacement[0].toUpperCase() + replacement.substring(1);
    return '$repCapitalized ${stripped.isNotEmpty ? stripped[0].toLowerCase() + stripped.substring(1) : ""}';
  }
}
