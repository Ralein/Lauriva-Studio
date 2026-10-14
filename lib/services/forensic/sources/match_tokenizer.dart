/// A word token with its exact character span in the text it came from.
class MatchToken {
  final String surface;
  final String stem;
  final int start;
  final int end;
  final bool isStopword;

  const MatchToken({
    required this.surface,
    required this.stem,
    required this.start,
    required this.end,
    required this.isStopword,
  });
}

/// Tokenization shared by every source-matching stage (candidate retrieval,
/// seed-and-extend alignment, paraphrase scoring) so they agree exactly on
/// what a "token" is and where it sits in the original text.
///
/// Matching runs on light stems rather than surface forms: plagiarists and
/// paraphrasing tools routinely inflect words ("networks" → "network",
/// "trained" → "training") which breaks exact n-gram matching while leaving
/// the copied passage obvious to a human reader.
class MatchTokenizer {
  MatchTokenizer._();

  /// Canonical homoglyph dictionary mapping visually indistinguishable
  /// Cyrillic, Greek, and Unicode lookalikes to their ASCII equivalents.
  static const Map<int, String> _homoglyphs = {
    // Cyrillic lowercase
    0x0430: 'a', 0x0435: 'e', 0x043E: 'o', 0x0440: 'p', 0x0441: 'c',
    0x0443: 'y', 0x0445: 'x', 0x0456: 'i', 0x0458: 'j', 0x0455: 's',
    0x0432: 'b', 0x043C: 'm', 0x0442: 't', 0x043D: 'n', 0x0438: 'u',
    // Cyrillic uppercase
    0x0410: 'A', 0x0412: 'B', 0x0415: 'E', 0x041A: 'K', 0x041C: 'M',
    0x041D: 'H', 0x041E: 'O', 0x0420: 'P', 0x0421: 'C', 0x0422: 'T',
    0x0425: 'X', 0x04AE: 'Y',
    // Greek lowercase
    0x03B1: 'a', 0x03B2: 'b', 0x03B5: 'e', 0x03B9: 'i', 0x03BA: 'k',
    0x03BD: 'v', 0x03BF: 'o', 0x03C1: 'p', 0x03C4: 't', 0x03C5: 'u',
    0x03C7: 'x', 0x03C9: 'w',
    // Greek uppercase
    0x0391: 'A', 0x0392: 'B', 0x0395: 'E', 0x0396: 'Z', 0x0397: 'H',
    0x0399: 'I', 0x039A: 'K', 0x039C: 'M', 0x039D: 'N', 0x039F: 'O',
    0x03A1: 'P', 0x03A4: 'T', 0x03A5: 'Y', 0x03A7: 'X',
  };

  /// Normalizes obfuscated text by mapping homoglyphs and stripping invisible characters.
  static String normalizeHomoglyphs(String input) {
    if (input.isEmpty) return input;
    final sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      // Strip zero-width and invisible formatting characters
      if (code == 0x200B || code == 0x200C || code == 0x200D || code == 0xFEFF || code == 0x00AD) {
        continue;
      }
      // Full-width ASCII conversion (0xFF01 to 0xFF5E)
      if (code >= 0xFF01 && code <= 0xFF5E) {
        sb.writeCharCode(code - 0xFEE0);
        continue;
      }
      final mapped = _homoglyphs[code];
      if (mapped != null) {
        sb.write(mapped);
      } else {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  /// Word pattern supporting ASCII, homoglyph blocks (Cyrillic, Greek, full-width),
  /// and zero-width evasion artifacts.
  static final RegExp _wordPattern = RegExp(
    r"[a-zA-Z0-9\u0400-\u04FF\u0370-\u03FF\uFF01-\uFF5E\u200B\u200C\u200D\uFEFF\u00AD]+(?:['’][a-zA-Z0-9\u0400-\u04FF\u0370-\u03FF\uFF01-\uFF5E\u200B\u200C\u200D\uFEFF\u00AD]+)?",
  );

  /// High-frequency function words. Runs made only of these ("one of the most
  /// important") are common English, not evidence of copying.
  static const Set<String> stopwords = {
    'a', 'about', 'above', 'after', 'again', 'all', 'also', 'am', 'an', 'and',
    'any', 'are', 'as', 'at', 'be', 'because', 'been', 'before', 'being',
    'between', 'both', 'but', 'by', 'can', 'could', 'did', 'do', 'does',
    'doing', 'down', 'during', 'each', 'either', 'few', 'for', 'from',
    'further', 'had', 'has', 'have', 'having', 'he', 'her', 'here', 'hers',
    'him', 'his', 'how', 'i', 'if', 'in', 'into', 'is', 'it', 'its', 'itself',
    'just', 'may', 'me', 'might', 'more', 'most', 'must', 'my', 'no', 'nor',
    'not', 'now', 'of', 'off', 'on', 'once', 'one', 'only', 'or', 'other',
    'our', 'out', 'over', 'own', 'same', 'shall', 'she', 'should', 'so',
    'some', 'such', 'than', 'that', 'the', 'their', 'them', 'then', 'there',
    'these', 'they', 'this', 'those', 'through', 'to', 'too', 'under',
    'until', 'up', 'us', 'very', 'was', 'we', 'were', 'what', 'when', 'where',
    'which', 'while', 'who', 'whom', 'why', 'will', 'with', 'would', 'you',
    'your',
  };

  /// Tokenizes [text] into stemmed tokens carrying their exact character offsets,
  /// with automatic homoglyph normalization and zero-width stripping.
  static List<MatchToken> tokenize(String text) {
    final tokens = <MatchToken>[];
    for (final m in _wordPattern.allMatches(text)) {
      final surface = m.group(0)!;
      final normalized = normalizeHomoglyphs(surface);
      final lower = normalized.toLowerCase();
      if (lower.isEmpty) continue;
      tokens.add(MatchToken(
        surface: surface,
        stem: stem(lower),
        start: m.start,
        end: m.end,
        isStopword: stopwords.contains(lower),
      ));
    }
    return tokens;
  }

  /// Conservative suffix-stripping stemmer (a small subset of Porter step 1).
  ///
  /// Deliberately under-stems: a false merge ("news" → "new") would create
  /// spurious matches, whereas a missed merge only costs a little recall that
  /// the gap-tolerant aligner recovers anyway.
  static String stem(String lower) {
    var w = lower;
    if (w.length <= 3) return w;
    if (w.endsWith("'s")) w = w.substring(0, w.length - 2);
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 5 && w.endsWith('ing')) {
      w = w.substring(0, w.length - 3);
      return _undouble(w);
    }
    if (w.length > 4 && w.endsWith('ed')) {
      w = w.substring(0, w.length - 2);
      return _undouble(w);
    }
    if (w.length > 5 && w.endsWith('ly')) return w.substring(0, w.length - 2);
    if (w.length > 4 && (w.endsWith('sses') || w.endsWith('xes') || w.endsWith('ches') || w.endsWith('shes'))) {
      return w.substring(0, w.length - 2);
    }
    if (w.length > 4 && w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us') && !w.endsWith('is')) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  // "stopped" → "stopp" → "stop"; keeps "ll"/"ss"/"zz" ("called" → "call").
  static String _undouble(String w) {
    if (w.length >= 3) {
      final last = w[w.length - 1];
      if (last == w[w.length - 2] && !'lsz'.contains(last) && !'aeiou'.contains(last)) {
        return w.substring(0, w.length - 1);
      }
    }
    return w;
  }

  /// Stable 32-bit FNV-1a hash. `String.hashCode` is not guaranteed to be
  /// identical across isolates, platforms, or SDK versions, which matters for
  /// anything cached or compared across the compute() boundary.
  static int fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      hash ^= s.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Stemmed word n-grams (space-joined) that contain at least one content
  /// word; all-stopword n-grams carry no retrieval signal.
  static Set<String> contentNgrams(List<MatchToken> tokens, int n) {
    final grams = <String>{};
    for (int i = 0; i + n <= tokens.length; i++) {
      bool hasContent = false;
      for (int k = i; k < i + n; k++) {
        if (!tokens[k].isStopword) {
          hasContent = true;
          break;
        }
      }
      if (!hasContent) continue;
      grams.add(tokens.sublist(i, i + n).map((t) => t.stem).join(' '));
    }
    return grams;
  }
}
