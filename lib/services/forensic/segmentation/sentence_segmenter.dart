/// Sentence boundary with exact character offsets.
class SentenceBoundary {
  final int index;
  final int start;
  final int end;
  final String text;

  const SentenceBoundary({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'start': start,
        'end': end,
        'text': text,
      };

  factory SentenceBoundary.fromJson(Map<String, dynamic> json) =>
      SentenceBoundary(
        index: json['index'] as int,
        start: json['start'] as int,
        end: json['end'] as int,
        text: json['text'] as String,
      );
}

abstract class SentenceSegmenter {
  List<SentenceBoundary> segment(String text);
}

/// Robust sentence segmenter with abbreviation handling and exact offset preservation.
class RuleBasedSentenceSegmenter implements SentenceSegmenter {
  static final RegExp _sentenceSplitRegex = RegExp(
    r'(?<=[.!?])\s+(?=[A-Z0-9])|(?<=\n\n+)|(?<=\n)(?=[A-Z0-9])',
  );

  static final Set<String> _knownAbbreviations = {
    'mr.', 'mrs.', 'ms.', 'dr.', 'prof.', 'sr.', 'jr.', 'vs.', 'e.g.', 'i.e.',
    'etc.', 'al.', 'fig.', 'vol.', 'no.', 'jan.', 'feb.', 'mar.', 'apr.', 'aug.',
    'sept.', 'oct.', 'nov.', 'dec.', 'dept.', 'u.s.', 'u.k.', 'e.u.', 'inc.', 'ltd.',
  };

  @override
  List<SentenceBoundary> segment(String text) {
    if (text.trim().isEmpty) return const [];

    final boundaries = <SentenceBoundary>[];
    int currentStart = 0;
    int index = 0;

    // Fast pass: scan text with regex candidates and filter false positives
    final matches = _sentenceSplitRegex.allMatches(text).toList();
    for (final match in matches) {
      final potentialEnd = match.start;
      final rawSub = text.substring(currentStart, potentialEnd).trim();
      
      // Check abbreviation on last word
      final words = rawSub.split(RegExp(r'\s+'));
      final lastWord = words.isNotEmpty ? words.last.toLowerCase() : '';
      if (_knownAbbreviations.contains(lastWord) && potentialEnd < text.length) {
        // Skip splitting if abbreviation
        continue;
      }

      if (rawSub.isNotEmpty) {
        // Find actual non-whitespace start and end
        final subStart = text.indexOf(rawSub, currentStart);
        final subEnd = subStart + rawSub.length;
        boundaries.add(SentenceBoundary(
          index: index++,
          start: subStart,
          end: subEnd,
          text: rawSub,
        ));
      }
      currentStart = match.end;
    }

    if (currentStart < text.length) {
      final remainder = text.substring(currentStart).trim();
      if (remainder.isNotEmpty) {
        final subStart = text.indexOf(remainder, currentStart);
        final subEnd = subStart + remainder.length;
        boundaries.add(SentenceBoundary(
          index: index++,
          start: subStart,
          end: subEnd,
          text: remainder,
        ));
      }
    }

    // Fallback if no boundary was detected (single sentence document)
    if (boundaries.isEmpty && text.trim().isNotEmpty) {
      final trimmed = text.trim();
      final subStart = text.indexOf(trimmed);
      boundaries.add(SentenceBoundary(
        index: 0,
        start: subStart,
        end: subStart + trimmed.length,
        text: trimmed,
      ));
    }

    return boundaries;
  }
}
