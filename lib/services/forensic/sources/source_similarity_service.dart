import 'dart:math';
import '../../../models/forensic/source_similarity_evidence.dart';
import '../../text_forensics_lexicons.dart';
import 'compact_corpus_index.dart';
import 'dense_semantic_matcher.dart';
import 'fuzzy_similarity_matcher.dart';
import 'match_tokenizer.dart';
import 'shingle_matching_engine.dart';
import 'source_repository.dart';
import 'winnowing_engine.dart';

/// Full source similarity forensic service: two-tier candidate retrieval,
/// gap-tolerant verbatim alignment, sentence-level paraphrase alignment, and
/// citation-aware scoring.
class SourceSimilarityService {
  final SourceRepository _repository;
  final ShingleMatchingEngine _shingleEngine;
  final FuzzySimilarityMatcher _fuzzyMatcher;
  final DenseSemanticMatcher _denseSemanticMatcher;

  /// Minimum combined paraphrase similarity for a sentence-level match.
  static const double paraphraseThreshold = 0.62;

  /// Minimum contiguous token run length required for online Wikipedia or
  /// Hacker News sources when there is only a single matching run. Matches
  /// below this length on those two platforms are commonly definition leads
  /// or forum thread titles and are ignored unless supported by a second run.
  static const int minOnlineWikiHnRunLength = 27;

  static bool _isWikiOrHnSource(SourceCorpusDocument doc) {
    if (!doc.id.startsWith('online_')) return false;
    if (doc.id.startsWith('online_wikipedia_') || doc.id.startsWith('online_hackernews_')) {
      return true;
    }
    final url = doc.url?.toLowerCase() ?? '';
    if (url.contains('wikipedia.org') || url.contains('news.ycombinator.com')) {
      return true;
    }
    final title = doc.title.toLowerCase();
    if (title.startsWith('wikipedia:') || title.contains('hacker news')) {
      return true;
    }
    return false;
  }

  SourceSimilarityService({
    SourceRepository? repository,
    ShingleMatchingEngine? shingleEngine,
    FuzzySimilarityMatcher? fuzzyMatcher,
    DenseSemanticMatcher? denseSemanticMatcher,
  })  : // Default to the shared repository: CorpusLoader and user-added
        // sources register there, and a private SourceRepository() would
        // silently see only the built-in seed corpus.
        _repository = repository ?? SourceRepository.baselineLiterature,
        _shingleEngine = shingleEngine ?? const ShingleMatchingEngine(),
        _fuzzyMatcher = fuzzyMatcher ?? FuzzySimilarityMatcher(),
        _denseSemanticMatcher = denseSemanticMatcher ?? DenseSemanticMatcher();

  SourceRepository get repository => _repository;

  static double _citationWeight(CitationStatus status) {
    switch (status) {
      case CitationStatus.uncited:
        return 1.0;
      case CitationStatus.cited:
        return 0.6;
      case CitationStatus.quoted:
        return 0.4;
      case CitationStatus.quotedAndCited:
        return 0.0;
    }
  }

  /// Evaluates phrase length and uniqueness against academic commonalities.
  /// 1-3 common words: negligible
  /// 4-7 words: low/moderate depending on boilerplate status
  /// 8-15 words: stronger evidence
  /// >15 words / distinctive sequences: very strong evidence
  static double _phraseWeight(int tokenCount, String phrase) {
    final lower = phrase.toLowerCase().trim();
    for (final bp in TextForensicsLexicons.academicBoilerplates) {
      if (lower == bp || lower.contains(bp) || bp.contains(lower)) {
        return 0.05;
      }
    }
    if (tokenCount <= 3) return 0.05;
    if (tokenCount <= 7) return 0.35;
    if (tokenCount <= 15) return 0.75;
    return 1.0;
  }

  /// Analyzes text for external source similarity across indexed repositories.
  SourceSimilarityEvidence analyzeDocument(String text) {
    final queryTokens = MatchTokenizer.tokenize(text);
    if (queryTokens.isEmpty) {
      return const SourceSimilarityEvidence.clean();
    }
    final words = queryTokens.map((t) => t.surface).toList();

    // 1. Multi-tier candidate retrieval: Winnowing fingerprints (MOSS-tier),
    //    exact 5-grams (precise), stemmed content trigrams (survives edits),
    //    and dense semantic vector projection fallback.
    final exact5 = TextForensicsLexicons.extractNgrams(
      words.map((w) => w.toLowerCase()).toList(),
      5,
    ).toSet();
    final stem3 = MatchTokenizer.contentNgrams(queryTokens, 3);
    final winnowingFPs = const WinnowingEngine().fingerprintTokens(queryTokens);

    final ranked = <String, int>{};
    for (final c in _repository.findCandidatesByWinnowing(winnowingFPs, minShared: 1)) {
      ranked[c.documentId] = (ranked[c.documentId] ?? 0) + c.sharedShingleCount * 4;
    }
    for (final c in _repository.findCandidates(exact5, minShared: 1)) {
      ranked[c.documentId] = (ranked[c.documentId] ?? 0) + c.sharedShingleCount * 3;
    }
    for (final c in _repository.findCandidatesByStemTrigrams(stem3, minShared: 1)) {
      ranked[c.documentId] = (ranked[c.documentId] ?? 0) + c.sharedShingleCount;
    }

    // 1b. Offline fingerprint-only corpus (no source text): only sources that pass its conservative
    //     decision rule (consecutive shared fingerprints + minimum span + minimum coverage) are reported.
    final compact = CompactCorpusIndex.current;
    final compactFps = compact == null ? const <WinnowingFingerprint>[] : compact.queryFingerprints(queryTokens);
    final compactReports = compact == null
        ? const <CompactSourceReport>[]
        : compact.reportSources(compactFps, queryTokens.length).take(5).toList();

    if (ranked.isEmpty && compactReports.isEmpty) {
      // Fast candidate fallback for heavily spun documents: sample up to 14 representative sentences
      final querySentences = TextForensicsLexicons.splitSentences(text);
      for (final doc in _repository.documents) {
        for (final qSent in querySentences.take(14)) {
          if (qSent.trim().length < 15) continue;
          for (final sent in doc.sentences.take(25)) {
            final sim = _denseSemanticMatcher.similarity(qSent, sent);
            if (sim >= paraphraseThreshold) {
              ranked[doc.id] = (ranked[doc.id] ?? 0) + (sim * 10).round();
              break;
            }
          }
        }
      }
    }

    if (ranked.isEmpty && compactReports.isEmpty) {
      return SourceSimilarityEvidence(
        overallSimilarityScore: 0.0,
        documentCoveragePercent: 0.0,
        matchedTokenCount: 0,
        longestContiguousTokenMatch: 0,
        uniqueSourceCount: 0,
        matches: const [],
        defensibleSummary: 'No meaningful external source similarity detected.',
        confidenceLevel: queryTokens.length < 40 ? 'INSUFFICIENT EVIDENCE' : 'HIGH CONFIDENCE',
      );
    }
    final candidateIds = ranked.keys.toList()..sort((a, b) => ranked[b]!.compareTo(ranked[a]!));

    final allMatches = <SourceMatchSegment>[];
    final matchedSources = <String>{};
    // Per query token: highest attribution-weighted evidence covering it.
    final tokenWeight = List<double>.filled(queryTokens.length, 0.0);
    final verbatimCovered = List<bool>.filled(queryTokens.length, false);
    int maxUncitedRun = 0;

    // 2. Verbatim / near-verbatim alignment on the strongest candidates.
    final topCandidates = candidateIds.take(8).toList();
    for (final docId in topCandidates) {
      final doc = _repository.getDocument(docId);
      if (doc == null) continue;

      final detail = _shingleEngine.matchDocument(queryText: text, queryTokens: words, source: doc);
      if (detail.segments.isEmpty) continue;

      final isWikiOrHn = _isWikiOrHnSource(doc);
      final hasSecondRun = detail.segments.length >= 2;

      // Filter short single-run matches on online Wikipedia and Hacker News
      // to eliminate false-positives on definition-style text.
      // If the match covers the predominant portion of a short query (>= 60%),
      // it is a verbatim copied excerpt, not an isolated definition lead.
      final validIndices = <int>[];
      for (int k = 0; k < detail.segments.length; k++) {
        final segment = detail.segments[k];
        final isShortSingleRun = isWikiOrHn && !hasSecondRun && segment.tokenCount < minOnlineWikiHnRunLength;
        final isDominantCoverage = segment.tokenCount >= (queryTokens.length * 0.6);
        if (isShortSingleRun && !isDominantCoverage) {
          continue;
        }
        validIndices.add(k);
      }
      if (validIndices.isEmpty) continue;
      matchedSources.add(docId);

      for (final k in validIndices) {
        final segment = detail.segments[k];
        final span = detail.segmentTokenSpans[k];
        final citation = _fuzzyMatcher.analyzeCitationContext(
          fullDocumentText: text,
          matchStartOffset: segment.documentStartOffset,
          matchEndOffset: segment.documentEndOffset,
        );
        final phraseW = _phraseWeight(segment.tokenCount, segment.matchedText);
        final matchType = segment.tokenCount <= 7 ? SourceMatchType.phraseMatch : SourceMatchType.exact;
        final resolvedSegment = SourceMatchSegment(
          documentStartOffset: segment.documentStartOffset,
          documentEndOffset: segment.documentEndOffset,
          matchedText: segment.matchedText,
          sourceTitle: segment.sourceTitle,
          sourceUrl: segment.sourceUrl,
          tokenCount: segment.tokenCount,
          similarityPercent: segment.similarityPercent,
          matchType: matchType,
          citationStatus: citation.status,
        );
        allMatches.add(resolvedSegment);

        final w = _citationWeight(citation.status) * phraseW;
        for (int t = span.start; t <= span.end; t++) {
          verbatimCovered[t] = true;
          tokenWeight[t] = max(tokenWeight[t], w);
        }
        if (citation.status == CitationStatus.uncited) {
          // Aligned (not merely spanned) tokens of this segment.
          final aligned = (segment.tokenCount * segment.similarityPercent / 100.0).round();
          maxUncitedRun = max(maxUncitedRun, aligned);
        }
      }
    }

    // 2b. Segments from the offline compact corpus. Matched text always comes from the QUERY
    //     (the index stores no source text); title/URL come from the index's doc table.
    for (final report in compactReports) {
      final info = compact!.docInfo(report.docId);
      matchedSources.add('compact:${report.docId}');
      for (final run in report.runs) {
        final firstTok = compactFps[run.firstFp].tokenIndex;
        final lastTok = min(compactFps[run.lastFp].tokenIndex + compact.k - 1, queryTokens.length - 1);
        final docStart = queryTokens[firstTok].start;
        final docEnd = queryTokens[lastTok].end;
        final fpsInRun = run.lastFp - run.firstFp + 1;
        final similarity = (run.matchedFps / fpsInRun * 100.0).clamp(0.0, 100.0);
        final matchedText = text.substring(docStart, docEnd);
        final citation = _fuzzyMatcher.analyzeCitationContext(
          fullDocumentText: text,
          matchStartOffset: docStart,
          matchEndOffset: docEnd,
        );
        final tokenCount = lastTok - firstTok + 1;
        final phraseW = _phraseWeight(tokenCount, matchedText);
        final matchType = tokenCount <= 7
            ? SourceMatchType.phraseMatch
            : (similarity >= 85.0 ? SourceMatchType.exact : SourceMatchType.lexical);
        allMatches.add(SourceMatchSegment(
          documentStartOffset: docStart,
          documentEndOffset: docEnd,
          matchedText: matchedText,
          sourceTitle: info.title,
          sourceUrl: info.url,
          tokenCount: tokenCount,
          similarityPercent: similarity,
          matchType: matchType,
          citationStatus: citation.status,
        ));
        final weight = _citationWeight(citation.status) * phraseW;
        for (int t = firstTok; t <= lastTok; t++) {
          verbatimCovered[t] = true;
          tokenWeight[t] = max(tokenWeight[t], weight);
        }
        if (citation.status == CitationStatus.uncited) {
          maxUncitedRun = max(maxUncitedRun, (tokenCount * similarity / 100.0).round());
        }
      }
    }

    // 3. Paraphrase alignment for sentences verbatim matching did not cover.
    _alignParaphrases(
      text: text,
      queryTokens: queryTokens,
      verbatimCovered: verbatimCovered,
      tokenWeight: tokenWeight,
      candidateIds: topCandidates,
      matches: allMatches,
      matchedSources: matchedSources,
    );

    if (allMatches.isEmpty) {
      return SourceSimilarityEvidence(
        overallSimilarityScore: 0.0,
        documentCoveragePercent: 0.0,
        matchedTokenCount: 0,
        longestContiguousTokenMatch: 0,
        uniqueSourceCount: 0,
        matches: const [],
        defensibleSummary: 'No meaningful external source similarity detected.',
        confidenceLevel: queryTokens.length < 40 ? 'INSUFFICIENT EVIDENCE' : 'HIGH CONFIDENCE',
      );
    }
    allMatches.sort((a, b) => a.documentStartOffset.compareTo(b.documentStartOffset));

    // 4. Hierarchical Sentence & Document Metrics.
    final docSentences = TextForensicsLexicons.splitSentences(text);
    final totalSentenceCount = docSentences.isEmpty ? 1 : docSentences.length;
    int matchedSentenceCount = 0;
    int searchCursor = 0;
    for (final sent in docSentences) {
      final sStart = text.indexOf(sent, searchCursor);
      if (sStart == -1) continue;
      final sEnd = sStart + sent.length;
      searchCursor = sEnd;
      final overlaps = allMatches.any((m) =>
          max(m.documentStartOffset, sStart) < min(m.documentEndOffset, sEnd));
      if (overlaps) matchedSentenceCount++;
    }
    final matchedSentencePercent = (matchedSentenceCount / totalSentenceCount * 100.0).clamp(0.0, 100.0);

    String longestPhrase = '';
    int maxPhraseLen = 0;
    int distinctivePhrasesCount = 0;
    for (final m in allMatches) {
      if (m.tokenCount > maxPhraseLen) {
        maxPhraseLen = m.tokenCount;
        longestPhrase = m.matchedText;
      }
      if (m.tokenCount >= 6 && _phraseWeight(m.tokenCount, m.matchedText) >= 0.5) {
        distinctivePhrasesCount++;
      }
    }
    final distinctivePhraseDensity = (distinctivePhrasesCount / max(docSentences.length, 1)).clamp(0.0, 1.0);

    // Source concentration (percentage of matches from dominant source)
    final sourceCounts = <String, int>{};
    for (final m in allMatches) {
      sourceCounts[m.sourceTitle] = (sourceCounts[m.sourceTitle] ?? 0) + 1;
    }
    double sourceConcentration = 0.0;
    if (allMatches.isNotEmpty && sourceCounts.isNotEmpty) {
      final maxCount = sourceCounts.values.reduce(max);
      sourceConcentration = (maxCount / allMatches.length * 100.0).clamp(0.0, 100.0);
    }

    final totalWords = queryTokens.length;
    final weightedCovered = tokenWeight.fold<double>(0.0, (a, b) => a + b);
    final coveredTokens = tokenWeight.where((w) => w > 0).length;
    final documentCoverage = (weightedCovered / totalWords * 100.0).clamp(0.0, 100.0);

    final runWeight = (maxUncitedRun / 30.0).clamp(0.0, 1.0) * 35.0;
    final coverageWeight = (documentCoverage * 0.65).clamp(0.0, 65.0);
    double overallScore = (runWeight + coverageWeight).clamp(0.0, 100.0);

    final uncitedMatches = allMatches.where((m) => m.citationStatus == CitationStatus.uncited).toList();
    if (uncitedMatches.isEmpty) {
      overallScore = min(overallScore, 10.0); // academic citation credit
    }

    // Adaptive confidence calibration
    String confidenceLevel;
    if (documentCoverage > 50.0 || maxUncitedRun >= 12) {
      confidenceLevel = 'HIGH CONFIDENCE';
    } else if (totalWords < 40) {
      confidenceLevel = 'INSUFFICIENT EVIDENCE';
    } else if (allMatches.isEmpty) {
      confidenceLevel = 'HIGH CONFIDENCE';
    } else if (documentCoverage > 25.0 || maxUncitedRun >= 10 || matchedSentencePercent > 35.0) {
      confidenceLevel = 'HIGH CONFIDENCE';
    } else if (documentCoverage > 8.0 || maxUncitedRun >= 6 || matchedSentencePercent > 15.0) {
      confidenceLevel = 'MEDIUM CONFIDENCE';
    } else {
      confidenceLevel = 'LOW CONFIDENCE';
    }

    final sourceCount = matchedSources.length;
    final String summary;
    if (overallScore < 5.0) {
      summary = 'Negligible similarity to external sources (minor common phrasing).';
    } else if (uncitedMatches.isEmpty) {
      summary = 'Matched passages are properly quoted and/or cited ($sourceCount source(s)).';
    } else {
      final paraphrased = allMatches.where((m) => m.matchType == SourceMatchType.fuzzyParaphrase).length;
      summary = 'Identified $sourceCount external source match(es) covering '
          '${documentCoverage.toStringAsFixed(1)}% of the document (attribution-weighted; '
          'longest uncited verbatim run: $maxUncitedRun tokens'
          '${paraphrased > 0 ? '; $paraphrased paraphrased sentence(s)' : ''}). '
          'Confidence: $confidenceLevel.';
    }

    final exactCount = allMatches.where((m) => m.matchType == SourceMatchType.exact).length;
    final paraphraseCount = allMatches.where((m) => m.matchType == SourceMatchType.fuzzyParaphrase).length;

    return SourceSimilarityEvidence(
      overallSimilarityScore: overallScore,
      documentCoveragePercent: documentCoverage,
      matchedTokenCount: coveredTokens,
      longestContiguousTokenMatch: maxUncitedRun,
      uniqueSourceCount: sourceCount,
      matches: allMatches,
      defensibleSummary: summary,
      matchedSentenceCount: matchedSentenceCount,
      totalSentenceCount: totalSentenceCount,
      matchedSentencePercent: matchedSentencePercent,
      longestMatchingPhrase: longestPhrase,
      distinctivePhraseDensity: distinctivePhraseDensity,
      sourceConcentration: sourceConcentration,
      confidenceLevel: confidenceLevel,
      exactMatchCount: exactCount,
      paraphraseMatchCount: paraphraseCount,
    );
  }

  void _alignParaphrases({
    required String text,
    required List<MatchToken> queryTokens,
    required List<bool> verbatimCovered,
    required List<double> tokenWeight,
    required List<String> candidateIds,
    required List<SourceMatchSegment> matches,
    required Set<String> matchedSources,
  }) {
    if (candidateIds.isEmpty) return;
    final docs = candidateIds.map(_repository.getDocument).whereType<SourceCorpusDocument>().toList();

    int cursor = 0;
    for (final sentence in TextForensicsLexicons.splitSentences(text)) {
      final start = text.indexOf(sentence, cursor);
      if (start == -1) continue;
      final end = start + sentence.length;
      cursor = end;

      // Token index range of this sentence.
      int first = -1, last = -1;
      for (int t = 0; t < queryTokens.length; t++) {
        if (queryTokens[t].start >= start && queryTokens[t].end <= end) {
          if (first == -1) first = t;
          last = t;
        } else if (queryTokens[t].start >= end) {
          break;
        }
      }
      if (first == -1 || last - first + 1 < 8) continue;

      final covered = List.generate(last - first + 1, (k) => verbatimCovered[first + k]).where((c) => c).length;
      if (covered / (last - first + 1) >= 0.5) continue; // already explained verbatim

      double bestScore = 0.0;
      SourceCorpusDocument? bestDoc;
      for (final doc in docs) {
        for (final src in doc.sentences) {
          final sim = _fuzzyMatcher.paraphraseSimilarity(sentence, src);
          if (sim.score > bestScore && sim.containment >= 0.5 && sim.sharedContent >= 4) {
            bestScore = sim.score;
            bestDoc = doc;
          }
        }
      }

      // Multi-tier fallback: Dense 256-D subword/SimHash vector projection
      // catches spun or synonym-substituted paraphrases where stem containment is lower.
      if (bestDoc == null || bestScore < paraphraseThreshold) {
        for (final doc in docs) {
          for (final src in doc.sentences) {
            final semSim = _denseSemanticMatcher.similarity(sentence, src);
            if (semSim > bestScore && semSim >= paraphraseThreshold) {
              bestScore = semSim;
              bestDoc = doc;
            }
          }
        }
      }

      if (bestDoc == null || bestScore < paraphraseThreshold) continue;

      final isWikiOrHn = _isWikiOrHnSource(bestDoc);
      final tokenCount = last - first + 1;
      final isDominantCoverage = tokenCount >= (queryTokens.length * 0.6);
      if (isWikiOrHn && !matchedSources.contains(bestDoc.id) && tokenCount < minOnlineWikiHnRunLength && !isDominantCoverage) {
        continue;
      }

      final citation = _fuzzyMatcher.analyzeCitationContext(
        fullDocumentText: text,
        matchStartOffset: start,
        matchEndOffset: end,
      );
      matches.add(SourceMatchSegment(
        documentStartOffset: start,
        documentEndOffset: end,
        matchedText: sentence,
        sourceTitle: bestDoc.title,
        sourceUrl: bestDoc.url,
        tokenCount: last - first + 1,
        similarityPercent: (bestScore * 100.0).clamp(0.0, 100.0),
        matchType: SourceMatchType.fuzzyParaphrase,
        citationStatus: citation.status,
      ));
      matchedSources.add(bestDoc.id);
      final w = 0.6 * _citationWeight(citation.status);
      for (int t = first; t <= last; t++) {
        tokenWeight[t] = max(tokenWeight[t], w);
      }
    }
  }
}
