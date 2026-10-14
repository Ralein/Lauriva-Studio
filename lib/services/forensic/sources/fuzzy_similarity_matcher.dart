import 'dart:math';
import '../../../models/forensic/source_similarity_evidence.dart';
import 'match_tokenizer.dart';

/// Context evaluation for citations, references, and quotations.
class CitationContextAnalysis {
  final CitationStatus status;
  final String? citationMarker;
  final bool isQuoted;

  const CitationContextAnalysis({
    required this.status,
    this.citationMarker,
    required this.isQuoted,
  });
}

/// Paraphrase and fuzzy matching engine with academic citation suppression.
class FuzzySimilarityMatcher {
  static final RegExp _citationRegex = RegExp(
    r'(?:\((?:[Ii]bid|op\.\s*cit|loc\.\s*cit)\b\.?(?:,\s*p(?:p)?\.\s*[\d–\-]+)?\)|\((?:(?:e\.g\.,?|see\s+also|cf\.|ibid\.?,?|op\.\s*cit\.)\s+)?(?:[A-Z][a-zA-Z\s\.\-&,]+(?:et\s+al\.?)?,?\s*(?:19|20)?\d{2,4}[a-z]?(?::\s*[\d–\-]+|,\s*p(?:p)?\.\s*[\d–\-]+)?|[A-Z][a-zA-Z\s\.\-&,]+\s+\d{1,4}|\d+(?:[–\-,\s]+\d+)*)\)|\[\^?[A-Za-z0-9]+(?:[\s,\-–][A-Za-z0-9]+)*\]|(?:[A-Z][a-zA-Z]+(?:\s+et\s+al\.)?\s*\((?:19|20)?\d{4}[a-z]?(?::\s*[\d–\-]+|,\s*p(?:p)?\.\s*[\d–\-]+)?\))|[\u00B9\u00B2\u00B3\u2070-\u2079]+(?:[,\-–][\u00B9\u00B2\u00B3\u2070-\u2079]+)*|(?:(?:doi|DOI):\s*10\.\d{4,9}/[-._;()/:A-Za-z0-9]+|(?:arXiv|ARXIV):\s*\d{4}\.\d{4,5}(?:v\d+)?|(?:PMID|pmid):\s*\d+)|\b\d+\s+U\.S\.\s+\d+\b|\b\d+\s+F\.(?:2d|3d)\s+\d+\b|\\cite(?:\[[^\]]*\])?\{[^}]+\}|\b(?:Ibid|op\.\s*cit|loc\.\s*cit)\b\.?(?:,\s*p(?:p)?\.\s*[\d–\-]+)?)',
  );

  /// Calculates token Jaccard similarity between two lists of tokens.
  double tokenJaccardSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final setA = a.map((t) => t.toLowerCase()).toSet();
    final setB = b.map((t) => t.toLowerCase()).toSet();

    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;

    return union > 0 ? (intersection / union) : 0.0;
  }

  /// Calculates Sorensen-Dice similarity coefficient between token collections.
  double sorensenDiceSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final setA = a.map((t) => t.toLowerCase()).toSet();
    final setB = b.map((t) => t.toLowerCase()).toSet();
    final intersection = setA.intersection(setB).length;
    final total = setA.length + setB.length;
    return total > 0 ? (2.0 * intersection) / total : 0.0;
  }

  /// Calculates character 3-gram cosine similarity between two sentences.
  double characterNgramCosineSimilarity(String a, String b) {
    final ngramsA = _extractCharNgrams(a.toLowerCase(), 3);
    final ngramsB = _extractCharNgrams(b.toLowerCase(), 3);

    if (ngramsA.isEmpty || ngramsB.isEmpty) return 0.0;

    final freqA = <String, int>{};
    final freqB = <String, int>{};

    for (final ng in ngramsA) {
      freqA[ng] = (freqA[ng] ?? 0) + 1;
    }
    for (final ng in ngramsB) {
      freqB[ng] = (freqB[ng] ?? 0) + 1;
    }

    double dot = 0.0;
    freqA.forEach((ng, countA) {
      final countB = freqB[ng];
      if (countB != null) {
        dot += countA * countB;
      }
    });

    double magA = 0.0;
    for (final c in freqA.values) {
      magA += c * c;
    }
    double magB = 0.0;
    for (final c in freqB.values) {
      magB += c * c;
    }

    final denominator = sqrt(magA) * sqrt(magB);
    return denominator > 0 ? (dot / denominator) : 0.0;
  }

  /// Analyzes whether a matched segment is enclosed in quotes or adjacent to academic citation markers.
  CitationContextAnalysis analyzeCitationContext({
    required String fullDocumentText,
    required int matchStartOffset,
    required int matchEndOffset,
  }) {
    // 1. Is the match enclosed by an open quotation within its paragraph?
    final isQuoted = isEnclosedInQuotes(fullDocumentText, matchStartOffset, matchEndOffset);

    // 2. Check academic citation markers within 80 characters after or before match
    final citationSearchWindow = fullDocumentText.substring(
      max(0, matchStartOffset - 40),
      min(fullDocumentText.length, matchEndOffset + 80),
    );

    final citationMatch = _citationRegex.firstMatch(citationSearchWindow);
    final hasCitation = citationMatch != null;
    final marker = citationMatch?.group(0);

    CitationStatus status;
    if (isQuoted && hasCitation) {
      status = CitationStatus.quotedAndCited;
    } else if (isQuoted) {
      status = CitationStatus.quoted;
    } else if (hasCitation) {
      status = CitationStatus.cited;
    } else {
      status = CitationStatus.uncited;
    }

    return CitationContextAnalysis(
      status: status,
      citationMarker: marker,
      isQuoted: isQuoted,
    );
  }

  /// Whether [start, end) lies inside a quotation that opens before it and
  /// closes at or after it, within the same paragraph.
  ///
  /// Handles matches deep inside long quotations (the old ±5-character
  /// boundary check only fired when the match happened to start at the quote
  /// mark) and ignores apostrophes in contractions/possessives ("don't",
  /// "Turing's"), which previously counted as quote marks.
  static bool isEnclosedInQuotes(String text, int start, int end) {
    if (start < 0 || end > text.length || start >= end) return false;
    final paraStart = max(0, text.lastIndexOf(RegExp(r'\n\s*\n'), start) );
    var paraEnd = text.indexOf(RegExp(r'\n\s*\n'), end);
    if (paraEnd == -1) paraEnd = text.length;
    final before = text.substring(paraStart, start);
    final after = text.substring(end, paraEnd);
    // A quotation may end a few characters after the match (e.g. `rights."`)
    // or the match may swallow the closing mark itself.
    final tail = text.substring(max(start, end - 2), min(text.length, end + 3));

    bool curly(String open, String close) {
      final o = before.lastIndexOf(open);
      if (o == -1 || before.lastIndexOf(close) > o) return false;
      return after.contains(close) || tail.contains(close);
    }

    // Markdown blockquote check: match is inside a line/paragraph starting with '>'
    final lineStart = text.lastIndexOf('\n', start);
    final linePrefix = text.substring(lineStart == -1 ? 0 : lineStart + 1, start);
    if (RegExp(r'^\s*>').hasMatch(linePrefix)) return true;
    final paraPrefix = text.substring(paraStart, start);
    if (RegExp(r'(?:^|\n)\s*>').hasMatch(paraPrefix)) return true;

    if (curly('\u201C', '\u201D') || curly('\u00AB', '\u00BB')) return true;

    // Straight double quotes: inside iff an odd number precede the match.
    final straightBefore = '"'.allMatches(before).length;
    if (straightBefore.isOdd && (after.contains('"') || tail.contains('"'))) return true;

    // Single quotes only count when not flanked by letters on both sides.
    int singleOpens(String t) {
      int n = 0;
      for (int k = 0; k < t.length; k++) {
        final c = t[k];
        if (c != "'" && c != '\u2018') continue;
        final prevIsLetter = k > 0 && RegExp(r'[A-Za-z0-9]').hasMatch(t[k - 1]);
        final nextIsLetter = k + 1 < t.length && RegExp(r'[A-Za-z0-9]').hasMatch(t[k + 1]);
        if (!(prevIsLetter && nextIsLetter)) n++;
      }
      return n;
    }

    return singleOpens(before).isOdd && (singleOpens(after) > 0 || singleOpens(tail) > 0);
  }

  /// Sentence-level paraphrase similarity in [0, 1] between [query] and
  /// [source], robust to inflection, reordering and function-word changes.
  ///
  /// Combines (a) containment of the query's stemmed content words in the
  /// source — how much of what the writer said is the source's vocabulary —
  /// weighted toward longer, more specific words, and (b) character-trigram
  /// cosine, which rewards shared morphology even when stems differ
  /// ("computation" / "computational"). Pure lexical: it cannot see
  /// synonym-level rewrites with no shared vocabulary, so it errs toward
  /// precision rather than recall.
  ({double score, double containment, int sharedContent}) paraphraseSimilarity(String query, String source) {
    final qStems = _contentStems(query);
    final sStems = _contentStems(source);
    if (qStems.isEmpty || sStems.isEmpty) {
      return (score: 0.0, containment: 0.0, sharedContent: 0);
    }
    double shared = 0.0, total = 0.0;
    int sharedCount = 0;
    for (final w in qStems) {
      final weight = w.length >= 7 ? 1.5 : (w.length >= 5 ? 1.0 : 0.6);
      total += weight;
      if (sStems.contains(w) || (w.length >= 5 && sStems.any((s) => _isNearMatch(w, s)))) {
        shared += weight;
        sharedCount++;
      }
    }
    final containment = total > 0 ? shared / total : 0.0;
    final charCos = characterNgramCosineSimilarity(query, source);
    return (
      score: (0.6 * containment + 0.4 * charCos).clamp(0.0, 1.0),
      containment: containment,
      sharedContent: sharedCount,
    );
  }

  /// Fast Damerau-Levenshtein distance <= 1 check for single character substitution,
  /// transposition, insertion or deletion in content words.
  static bool _isNearMatch(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    if (a.length < 5 || b.length < 5) return false;
    int diff = 0;
    int i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (a.codeUnitAt(i) != b.codeUnitAt(j)) {
        diff++;
        if (diff > 1) return false;
        if (i + 1 < a.length && j + 1 < b.length &&
            a.codeUnitAt(i) == b.codeUnitAt(j + 1) &&
            a.codeUnitAt(i + 1) == b.codeUnitAt(j)) {
          i += 2;
          j += 2;
          continue;
        }
        if (a.length > b.length) {
          i++;
        } else if (b.length > a.length) {
          j++;
        } else {
          i++;
          j++;
        }
      } else {
        i++;
        j++;
      }
    }
    if (i < a.length || j < b.length) diff++;
    return diff <= 1;
  }

  Set<String> _contentStems(String text) {
    return MatchTokenizer.tokenize(text)
        .where((t) => !t.isStopword && t.surface.length > 2)
        .map((t) => t.stem)
        .toSet();
  }

  List<String> _extractCharNgrams(String s, int n) {
    if (s.length < n) return const [];
    final ngrams = <String>[];
    for (int i = 0; i <= s.length - n; i++) {
      ngrams.add(s.substring(i, i + n));
    }
    return ngrams;
  }
}
