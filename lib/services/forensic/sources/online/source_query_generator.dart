import '../../../text_forensics_lexicons.dart';
import '../match_tokenizer.dart';
import 'source_retriever.dart';

/// Picks the few excerpts of a document worth sending to online source
/// search.
///
/// **This is the privacy boundary of online source checking.** Nothing else
/// from the document leaves the device: third-party APIs receive at most
/// [maxQueries] excerpts of at most [maxWordsPerQuery] words each (plus a
/// five-keyword subset of the same excerpts), with emails, URLs, @handles
/// and long digit runs (phone / student / account numbers) redacted before
/// selection. For a typical 1,500-word essay that is ≤ 200 words, ~13%.
///
/// Why these excerpts: search APIs rank by term overlap, so the query that
/// finds a copied source is the one made of that source's *distinctive*
/// words. Each candidate sentence is scored by the densest [maxWordsPerQuery]
/// window of content words, weighting longer words (a cheap, dictionary-free
/// proxy for rarity), mid-sentence capitalised terms (names, methods), and
/// numbers. Selection is **stratified**: the document is cut into
/// [maxQueries] equal bands of sentences and the best sentence of each band
/// is used, because copied passages can sit anywhere and a global top-K
/// would cluster on one dense technical paragraph.
class SourceQueryGenerator {
  final int maxQueries;
  final int maxWordsPerQuery;
  final int minWordsPerSentence;
  final int keywordsPerQuery;

  const SourceQueryGenerator({
    this.maxQueries = 8,
    this.maxWordsPerQuery = 14,
    this.minWordsPerSentence = 7,
    this.keywordsPerQuery = 5,
  });

  static final RegExp _redact = RegExp(
    r'[\w.+-]+@[\w-]+\.[\w.-]+' // email
    r'|https?://\S+|www\.\S+' // url
    r'|@\w+' // handle
    r'|\+?\d[\d\s().-]{5,}\d', // phone / id numbers (≥ 7 digits incl. separators)
  );

  /// Removes personal identifiers that must never be sent to a third party
  /// and carry no source-matching signal anyway.
  static String redact(String text) => text.replaceAll(_redact, ' ');

  List<SourceQuery> generate(String text) {
    final sentences = TextForensicsLexicons.splitSentences(text);
    final candidates = <_Candidate>[];
    for (int i = 0; i < sentences.length; i++) {
      final c = _scoreSentence(redact(sentences[i]), i);
      if (c != null) candidates.add(c);
    }
    if (candidates.isEmpty) return const [];

    final paragraphs = text.split(RegExp(r'\n\s*\n+')).where((p) => p.trim().isNotEmpty).toList();
    final picked = <_Candidate>[];

    // 1. If text has multiple paragraphs, ensure each paragraph contributes at least one distinctive query
    if (paragraphs.length >= 2 && candidates.length >= paragraphs.length) {
      int sentenceOffset = 0;
      for (final p in paragraphs) {
        if (picked.length >= maxQueries) break;
        final pSentences = TextForensicsLexicons.splitSentences(p);
        final pCand = candidates.where((c) =>
          c.sentenceIndex >= sentenceOffset &&
          c.sentenceIndex < sentenceOffset + pSentences.length
        ).toList();
        sentenceOffset += pSentences.length;

        if (pCand.isNotEmpty) {
          pCand.sort((a, b) => b.score.compareTo(a.score));
          for (final c in pCand) {
            if (!picked.any((prev) => _overlap(prev.keywordStems, c.keywordStems) > 0.6)) {
              picked.add(c);
              break;
            }
          }
        }
      }
    }

    // 2. Fill remaining query budget with stratified global band candidates
    if (picked.length < maxQueries) {
      final k = candidates.length < maxQueries ? candidates.length : maxQueries;
      for (int band = 0; band < k && picked.length < maxQueries; band++) {
        final from = band * candidates.length ~/ k;
        final to = (band + 1) * candidates.length ~/ k;
        _Candidate? best;
        for (final c in candidates.sublist(from, to)) {
          if (picked.any((p) => p.sentenceIndex == c.sentenceIndex || _overlap(p.keywordStems, c.keywordStems) > 0.6)) continue;
          if (best == null || c.score > best.score) best = c;
        }
        if (best != null) picked.add(best);
      }
    }

    picked.sort((a, b) => a.sentenceIndex.compareTo(b.sentenceIndex));

    return [
      for (final c in picked)
        SourceQuery(
          text: c.text,
          keywords: c.keywords,
          sentenceIndex: c.sentenceIndex,
          exactPhrase: c.exactPhrase,
        ),
    ];
  }

  _Candidate? _scoreSentence(String sentence, int index) {
    final tokens = MatchTokenizer.tokenize(sentence);
    if (tokens.length < minWordsPerSentence) return null;

    final weights = [for (int t = 0; t < tokens.length; t++) _tokenWeight(tokens[t], t == 0)];
    final window = tokens.length < maxWordsPerQuery ? tokens.length : maxWordsPerQuery;
    int bestStart = 0;
    double windowSum = 0.0;
    for (int t = 0; t < window; t++) {
      windowSum += weights[t];
    }
    double bestSum = windowSum;
    for (int s = 1; s + window <= tokens.length; s++) {
      windowSum += weights[s + window - 1] - weights[s - 1];
      if (windowSum > bestSum) {
        bestSum = windowSum;
        bestStart = s;
      }
    }

    // Trim edge function words so queries begin and end on strong content anchors
    int spanStart = bestStart;
    int spanEnd = bestStart + window;
    while (spanStart < spanEnd && _isFunction(tokens[spanStart])) {
      spanStart++;
    }
    while (spanEnd > spanStart && _isFunction(tokens[spanEnd - 1])) {
      spanEnd--;
    }
    if (spanEnd - spanStart < 4) {
      spanStart = bestStart;
      spanEnd = bestStart + window;
    }

    final span = tokens.sublist(spanStart, spanEnd);
    final content = span.where((t) => !_isFunction(t)).toList();
    if (content.length < 3 || content.length / span.length < 0.35) return null;

    final ranked = [
      for (int t = spanStart; t < spanEnd; t++)
        if (!_isFunction(tokens[t]) && tokens[t].surface.length >= 4) t,
    ]..sort((a, b) => weights[b].compareTo(weights[a]));
    final keywordIdx = <int>[];
    final seenStems = <String>{};
    for (final t in ranked) {
      if (seenStems.add(tokens[t].stem)) keywordIdx.add(t);
      if (keywordIdx.length == keywordsPerQuery) break;
    }
    keywordIdx.sort();

    // Extract distinctive 5-8 token verbatim sequence for quoted phrase search,
    // prioritizing named entities and distinctive domain terminology.
    String? exactPhrase;
    if (span.length >= 5) {
      final phraseLen = span.length >= 7 ? 7 : 5;
      int bestPhraseStart = 0;
      double bestPhraseScore = 0.0;
      for (int p = 0; p + phraseLen <= span.length; p++) {
        double pScore = 0.0;
        final sub = span.sublist(p, p + phraseLen);
        for (int i = 0; i < sub.length; i++) {
          final tok = sub[i];
          if (!_isFunction(tok)) {
            pScore += 1.0;
            // High boost for capitalized non-initial words (named entities)
            if (tok.surface[0].toUpperCase() == tok.surface[0] && RegExp(r'^[A-Z]').hasMatch(tok.surface)) {
              pScore += 0.8;
            }
            // Boost for long technical content terms
            if (tok.surface.length >= 7) pScore += 0.4;
          }
        }
        if (pScore > bestPhraseScore) {
          bestPhraseScore = pScore;
          bestPhraseStart = p;
        }
      }
      if (bestPhraseScore >= 3.0) {
        exactPhrase = span.sublist(bestPhraseStart, bestPhraseStart + phraseLen).map((t) => t.surface).join(' ');
      }
    }

    return _Candidate(
      text: span.map((t) => t.surface).join(' '),
      keywords: [for (final t in keywordIdx) tokens[t].surface.toLowerCase()],
      keywordStems: {for (final t in keywordIdx) tokens[t].stem},
      sentenceIndex: index,
      score: bestSum * (content.length / span.length),
      exactPhrase: exactPhrase,
    );
  }

  static bool _isFunction(MatchToken t) {
    final lower = t.surface.toLowerCase();
    return t.isStopword || TextForensicsLexicons.functionWords.contains(lower);
  }

  static double _tokenWeight(MatchToken t, bool sentenceInitial) {
    if (_isFunction(t)) return 0.0;
    final lower = t.surface.toLowerCase();
    if (TextForensicsLexicons.aiStockWords.contains(lower)) {
      return 0.15; // Heavily de-weight generic AI filler/buzzwords
    }
    final len = t.surface.length;
    var w = 1.0 + ((len - 4).clamp(0, 6)) * 0.25;
    if (!sentenceInitial && t.surface[0].toUpperCase() == t.surface[0] && RegExp(r'^[A-Z]').hasMatch(t.surface)) {
      w += 0.5;
    }
    if (RegExp(r'\d').hasMatch(t.surface)) w += 0.3;
    return w;
  }

  static double _overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final inter = a.intersection(b).length;
    return inter / (a.length < b.length ? a.length : b.length);
  }
}

class _Candidate {
  final String text;
  final List<String> keywords;
  final Set<String> keywordStems;
  final int sentenceIndex;
  final double score;
  final String? exactPhrase;

  const _Candidate({
    required this.text,
    required this.keywords,
    required this.keywordStems,
    required this.sentenceIndex,
    required this.score,
    this.exactPhrase,
  });
}
