import 'dart:math';
import '../../../models/forensic/source_similarity_evidence.dart';
import 'match_tokenizer.dart';
import 'source_repository.dart';

/// Detailed result of shingle and contiguous match analysis against a source.
class ShingleMatchDetail {
  final SourceCorpusDocument source;
  final int matchedTokenCount;
  final double documentCoverage;
  final double sourceCoverage;
  final int longestContiguousRun;
  final List<SourceMatchSegment> segments;

  /// Inclusive query-token index range of each entry in [segments], in the
  /// same order. Lets callers take the union of coverage across several
  /// sources without double-counting tokens matched by more than one.
  final List<({int start, int end})> segmentTokenSpans;

  const ShingleMatchDetail({
    required this.source,
    required this.matchedTokenCount,
    required this.documentCoverage,
    required this.sourceCoverage,
    required this.longestContiguousRun,
    required this.segments,
    this.segmentTokenSpans = const [],
  });
}

/// Seed-and-extend source aligner (the approach used by BLAST-style and
/// winnowing-based plagiarism systems such as MOSS/Sherlock, adapted to word
/// tokens).
///
/// 1. **Seed**: stemmed word trigrams shared by query and source, found via a
///    hash index of source positions — O(query + source) instead of the
///    previous O(query × source) scan.
/// 2. **Extend**: from each seed, walk forward in both texts, tolerating up
///    to [maxGap] consecutive inserted, deleted, or substituted tokens as long
///    as matching resumes immediately after. This catches the dominant
///    real-world evasion — light word swaps and inflection changes on an
///    otherwise copied passage — which strict contiguous matching misses
///    entirely because any single change splits the run below threshold.
/// 3. **Filter**: a segment must contain at least [minMatchedTokens] aligned
///    tokens, [minContentTokens] of them content words, and keep an edit
///    density below [maxEditRatio]. Runs made of stock function-word phrasing
///    ("one of the most important") are ordinary English, not copying.
///
/// Character offsets come straight from the tokenizer, so highlights land on
/// the actual matched occurrence even when its first/last words also appear
/// earlier in the document.
class ShingleMatchingEngine {
  final int seedSize;
  final int maxGap;
  final int minMatchedTokens;
  final int minContentTokens;
  final double maxEditRatio;

  const ShingleMatchingEngine({
    this.seedSize = 3,
    this.maxGap = 2,
    this.minMatchedTokens = 5,
    this.minContentTokens = 3,
    this.maxEditRatio = 0.34,
  });

  /// Compares the query document against a specific [SourceCorpusDocument].
  ///
  /// [queryTokens] is accepted for API compatibility; tokens and offsets are
  /// derived from [queryText] so indices and highlights are always consistent.
  ShingleMatchDetail matchDocument({
    required String queryText,
    required List<String> queryTokens,
    required SourceCorpusDocument source,
  }) {
    final q = MatchTokenizer.tokenize(queryText);
    final s = source.matchTokens;
    if (q.isEmpty || s.isEmpty) {
      return ShingleMatchDetail(
        source: source,
        matchedTokenCount: 0,
        documentCoverage: 0.0,
        sourceCoverage: 0.0,
        longestContiguousRun: 0,
        segments: const [],
      );
    }

    // 1. Hash index of source seed positions.
    final seedIndex = <int, List<int>>{};
    for (int j = 0; j + seedSize <= s.length; j++) {
      seedIndex.putIfAbsent(_seedKey(s, j), () => <int>[]).add(j);
    }

    final segments = <SourceMatchSegment>[];
    final spans = <({int start, int end})>[];
    final matchedIndices = <int>{};
    int longestExactRun = 0;

    int i = 0;
    while (i + seedSize <= q.length) {
      final positions = seedIndex[_seedKey(q, i)];
      if (positions == null) {
        i++;
        continue;
      }

      _Alignment? best;
      for (final j in positions) {
        if (q[i].stem != s[j].stem) continue; // 32-bit hash collision
        final a = _extend(q, s, i, j);
        if (best == null || a.matched > best.matched) best = a;
      }

      if (best != null && _isSignificant(best)) {
        final qStart = best.qStart;
        final qEnd = best.qEnd;
        final spanTokens = qEnd - qStart + 1;
        final sourceSpan = best.sEnd - best.sStart + 1;
        final similarity = best.matched / max(spanTokens, sourceSpan);
        final startChar = q[qStart].start;
        final endChar = q[qEnd].end;

        segments.add(SourceMatchSegment(
          documentStartOffset: startChar,
          documentEndOffset: endChar,
          matchedText: queryText.substring(startChar, endChar),
          sourceTitle: source.title,
          sourceUrl: source.url,
          tokenCount: spanTokens,
          similarityPercent: (similarity * 100.0).clamp(0.0, 100.0),
          matchType: best.edits == 0 ? SourceMatchType.exact : SourceMatchType.shingleOverlap,
        ));
        spans.add((start: qStart, end: qEnd));
        for (int k = qStart; k <= qEnd; k++) {
          matchedIndices.add(k);
        }
        longestExactRun = max(longestExactRun, best.longestExactRun);
        i = max(i + 1, qEnd + 1);
      } else {
        i++;
      }
    }

    // Gap-tolerant segment chaining: merge proximal segments from the same source
    final mergedSegments = <SourceMatchSegment>[];
    final mergedSpans = <({int start, int end})>[];
    if (segments.isNotEmpty) {
      var curSeg = segments.first;
      var curSpan = spans.first;

      for (int k = 1; k < segments.length; k++) {
        final nextSeg = segments[k];
        final nextSpan = spans[k];
        final tokenGap = nextSpan.start - curSpan.end - 1;

        if (tokenGap >= 0 && tokenGap <= 4) {
          // Merge segments across small gap
          final combinedTokens = nextSpan.end - curSpan.start + 1;
          final combinedStartChar = curSeg.documentStartOffset;
          final combinedEndChar = nextSeg.documentEndOffset;
          final combinedText = queryText.substring(combinedStartChar, combinedEndChar);
          final avgSim = (curSeg.similarityPercent + nextSeg.similarityPercent) / 2.0;

          curSeg = SourceMatchSegment(
            documentStartOffset: combinedStartChar,
            documentEndOffset: combinedEndChar,
            matchedText: combinedText,
            sourceTitle: source.title,
            sourceUrl: source.url,
            tokenCount: combinedTokens,
            similarityPercent: avgSim,
            matchType: (curSeg.matchType == SourceMatchType.exact && nextSeg.matchType == SourceMatchType.exact && tokenGap == 0)
                ? SourceMatchType.exact
                : SourceMatchType.shingleOverlap,
          );
          curSpan = (start: curSpan.start, end: nextSpan.end);
        } else {
          mergedSegments.add(curSeg);
          mergedSpans.add(curSpan);
          curSeg = nextSeg;
          curSpan = nextSpan;
        }
      }
      mergedSegments.add(curSeg);
      mergedSpans.add(curSpan);
    }

    final finalSegments = mergedSegments.isNotEmpty ? mergedSegments : segments;
    final finalSpans = mergedSpans.isNotEmpty ? mergedSpans : spans;

    final matchedCount = matchedIndices.length;
    final docCoverage = (matchedCount / q.length) * 100.0;
    final srcCoverage = (matchedCount / s.length) * 100.0;

    return ShingleMatchDetail(
      source: source,
      matchedTokenCount: matchedCount,
      documentCoverage: docCoverage.clamp(0.0, 100.0),
      sourceCoverage: srcCoverage.clamp(0.0, 100.0),
      longestContiguousRun: longestExactRun,
      segments: finalSegments,
      segmentTokenSpans: finalSpans,
    );
  }

  int _seedKey(List<MatchToken> t, int at) {
    final buf = StringBuffer();
    for (int k = at; k < at + seedSize; k++) {
      if (k > at) buf.write(' ');
      buf.write(t[k].stem);
    }
    return MatchTokenizer.fnv1a(buf.toString());
  }

  /// Bidirectional greedy gap-tolerant extension from aligned seed (qi, sj).
  _Alignment _extend(List<MatchToken> q, List<MatchToken> s, int qi0, int sj0) {
    // 1. Forward extension
    int qi = qi0, sj = sj0;
    int matched = 0, content = 0, edits = 0;
    int lastQ = qi0 - 1, lastS = sj0 - 1;
    int run = 0, longestRun = 0;

    while (qi < q.length && sj < s.length) {
      if (q[qi].stem == s[sj].stem) {
        matched++;
        if (!q[qi].isStopword) content++;
        run++;
        longestRun = max(longestRun, run);
        lastQ = qi;
        lastS = sj;
        qi++;
        sj++;
        continue;
      }

      // Mismatch: try to resynchronise within maxGap tokens.
      bool resynced = false;
      for (int d = 1; d <= maxGap && !resynced; d++) {
        if (qi + d < q.length && sj + d < s.length && q[qi + d].stem == s[sj + d].stem) {
          qi += d;
          sj += d;
          resynced = true;
        } else if (qi + d < q.length && q[qi + d].stem == s[sj].stem) {
          qi += d;
          resynced = true;
        } else if (sj + d < s.length && q[qi].stem == s[sj + d].stem) {
          sj += d;
          resynced = true;
        }
      }
      if (!resynced) break;
      edits++;
      run = 0;
    }

    // 2. Backward extension (recovers words preceding the seed)
    int firstQ = qi0, firstS = sj0;
    int bQi = qi0 - 1, bSj = sj0 - 1;
    while (bQi >= 0 && bSj >= 0) {
      if (q[bQi].stem == s[bSj].stem) {
        matched++;
        if (!q[bQi].isStopword) content++;
        firstQ = bQi;
        firstS = bSj;
        bQi--;
        bSj--;
        continue;
      }
      bool resynced = false;
      for (int d = 1; d <= maxGap && !resynced; d++) {
        if (bQi - d >= 0 && bSj - d >= 0 && q[bQi - d].stem == s[bSj - d].stem) {
          bQi -= d;
          bSj -= d;
          resynced = true;
        } else if (bQi - d >= 0 && q[bQi - d].stem == s[bSj].stem) {
          bQi -= d;
          resynced = true;
        } else if (bSj - d >= 0 && q[bQi].stem == s[bSj - d].stem) {
          bSj -= d;
          resynced = true;
        }
      }
      if (!resynced) break;
      edits++;
    }

    return _Alignment(
      qStart: firstQ,
      qEnd: lastQ,
      sStart: firstS,
      sEnd: lastS,
      matched: matched,
      contentMatched: content,
      edits: edits,
      longestExactRun: longestRun,
    );
  }

  bool _isSignificant(_Alignment a) {
    if (a.matched < minMatchedTokens) return false;
    if (a.contentMatched < minContentTokens) return false;
    return a.edits / a.matched <= maxEditRatio;
  }
}

class _Alignment {
  final int qStart;
  final int qEnd;
  final int sStart;
  final int sEnd;
  final int matched;
  final int contentMatched;
  final int edits;
  final int longestExactRun;

  const _Alignment({
    required this.qStart,
    required this.qEnd,
    required this.sStart,
    required this.sEnd,
    required this.matched,
    required this.contentMatched,
    required this.edits,
    required this.longestExactRun,
  });
}
