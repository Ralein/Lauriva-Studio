import 'dart:math';
import 'forensic/sources/match_tokenizer.dart';
import 'forensic/sources/shingle_matching_engine.dart';
import 'forensic/sources/source_repository.dart';
import 'forensic/sources/winnowing_engine.dart';
import 'text_forensics_lexicons.dart';

/// Representation of an external literature or web match.
class PlagiarismSourceMatch {
  final String sourceTitle;
  final String? url;
  final double similarityPercent;
  final String matchedText;

  const PlagiarismSourceMatch({
    required this.sourceTitle,
    this.url,
    required this.similarityPercent,
    required this.matchedText,
  });
}

/// Result of source plagiarism analysis and verbatim n-gram shingling.
class SourcePlagiarismResult {
  final double plagiarismRiskScore; // 0.0 to 100.0
  final double ngramOverlapScore; // 0.0 to 100.0
  final double lexicalRichness; // 0.0 to 100.0
  final List<String> repeatedNgrams;
  final List<String> flaggedBoilerplates;
  final List<PlagiarismSourceMatch> sourceMatches;

  const SourcePlagiarismResult({
    required this.plagiarismRiskScore,
    required this.ngramOverlapScore,
    required this.lexicalRichness,
    required this.repeatedNgrams,
    required this.flaggedBoilerplates,
    this.sourceMatches = const [],
  });
}

/// Service dedicated to detecting verbatim copying, repeated n-gram sequences,
/// formulaic academic scaffolding, and web/literature similarity.
///
/// Decoupled from [AiForensicService] to clearly separate source plagiarism
/// from AI-authorship stylometrics.
class SourcePlagiarismService {
  final SourceRepository _repository;
  final ShingleMatchingEngine _shingleEngine;

  SourcePlagiarismService({
    SourceRepository? repository,
    ShingleMatchingEngine? shingleEngine,
  })  : _repository = repository ?? SourceRepository.baselineLiterature,
        _shingleEngine = shingleEngine ?? const ShingleMatchingEngine();

  SourceRepository get repository => _repository;
  ShingleMatchingEngine get shingleEngine => _shingleEngine;

  /// Analyzes text for verbatim sequence repetition, formulaic academic boilerplates,
  /// and lexical richness.
  SourcePlagiarismResult analyzeText(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const SourcePlagiarismResult(
        plagiarismRiskScore: 0.0,
        ngramOverlapScore: 0.0,
        lexicalRichness: 100.0,
        repeatedNgrams: [],
        flaggedBoilerplates: [],
        sourceMatches: [],
      );
    }

    final words = TextForensicsLexicons.extractWords(text);
    final totalWords = max(words.length, 1);

    // 1. Shingling & repeated n-grams
    final trigrams = TextForensicsLexicons.extractNgrams(words, 3);
    final fourGrams = TextForensicsLexicons.extractNgrams(words, 4);
    final fiveGrams = TextForensicsLexicons.extractNgrams(words, 5);

    final candidateGrams = fiveGrams.isNotEmpty ? fiveGrams : (fourGrams.isNotEmpty ? fourGrams : trigrams);
    final repeatedNgrams = TextForensicsLexicons.findRepeatedNgrams(candidateGrams);

    final repeatedCount = repeatedNgrams.length;
    final ngramOverlapRatio = (repeatedCount * 4.0) / totalWords;
    final ngramOverlapScore = (ngramOverlapRatio * 100.0).clamp(0.0, 100.0);

    // 2. Lexical Richness & Unique root tokens
    final uniqueWords = words.map((w) => w.toLowerCase()).toSet();
    final ttr = (uniqueWords.length / totalWords) * 100.0;
    final guiraudR = uniqueWords.length / sqrt(totalWords);
    final lexicalRichness = ((ttr * 0.5) + (min(guiraudR * 10.0, 100.0) * 0.5)).clamp(0.0, 100.0);

    // 3. Academic & Formulaic Boilerplate detection
    final lowerText = text.toLowerCase();
    final flaggedBoilerplates = <String>[];
    for (final bp in TextForensicsLexicons.academicBoilerplates) {
      if (lowerText.contains(bp)) {
        flaggedBoilerplates.add(bp);
      }
    }

    // 4. Source Literature Alignment (Fast Shingle Indexing)
    final matches = <PlagiarismSourceMatch>[];
    double maxSourceSimilarity = 0.0;

    final exact5 = fiveGrams.toSet();
    final candidateDocs = _repository.findCandidates(exact5, minShared: 1);
    final allCandidates = <SourceMatchCandidate>[...candidateDocs];

    if (allCandidates.length < 8) {
      final queryTokens = MatchTokenizer.tokenize(text);
      final stem3 = MatchTokenizer.contentNgrams(queryTokens, 3);
      final stemCandidates = _repository.findCandidatesByStemTrigrams(stem3, minShared: 2);
      for (final sc in stemCandidates) {
        if (!allCandidates.any((c) => c.documentId == sc.documentId)) {
          allCandidates.add(sc);
        }
      }

      // Stanford Winnowing fingerprint candidate lookup
      const winnowingEngine = WinnowingEngine();
      final queryFps = winnowingEngine.fingerprintTokens(queryTokens);
      final winnowingCandidates = _repository.findCandidatesByWinnowing(queryFps, minShared: 1);
      for (final wc in winnowingCandidates) {
        if (!allCandidates.any((c) => c.documentId == wc.documentId)) {
          allCandidates.add(wc);
        }
      }
    }

    final checkedDocIds = <String>{};
    for (final candidate in allCandidates.take(16)) {
      if (!checkedDocIds.add(candidate.documentId)) continue;
      final doc = _repository.getDocument(candidate.documentId);
      if (doc == null) continue;

      final detail = _shingleEngine.matchDocument(
        queryText: text,
        queryTokens: words,
        source: doc,
      );

      for (final seg in detail.segments) {
        if (seg.similarityPercent >= 28.0 || seg.tokenCount >= 6) {
          matches.add(
            PlagiarismSourceMatch(
              sourceTitle: seg.sourceTitle,
              url: seg.sourceUrl,
              similarityPercent: seg.similarityPercent,
              matchedText: seg.matchedText,
            ),
          );
          if (seg.similarityPercent > maxSourceSimilarity) {
            maxSourceSimilarity = seg.similarityPercent;
          }
        }
      }

      // Verbatim contiguous run multiplier: an undeniable consecutive run of tokens
      // is direct verbatim copying (Turnitin/MOSS standard).
      final runRisk = detail.longestContiguousRun >= 15
          ? 94.0
          : (detail.longestContiguousRun >= 10
              ? 82.0
              : (detail.longestContiguousRun >= 7 ? 62.0 : 0.0));
      if (runRisk > maxSourceSimilarity) {
        maxSourceSimilarity = runRisk;
      }

      // Winnowing containment check: catches scattered verbatim excerpts that
      // might be separated by slight filler words
      final winnowingComp = const WinnowingEngine().compare(queryText: text, source: doc);
      if (winnowingComp.containmentQueryInSource >= 0.35) {
        final winnowingScore = (winnowingComp.containmentQueryInSource * 100.0).clamp(0.0, 95.0);
        if (winnowingScore > maxSourceSimilarity) {
          maxSourceSimilarity = winnowingScore;
        }
      }
    }

    // 5. Plagiarism Risk Composite Score
    final boilerplatePenalty = min(flaggedBoilerplates.length * 15.0, 45.0);
    final lowRichnessPenalty = (100.0 - lexicalRichness).clamp(0.0, 100.0) * 0.25;

    final baseRiskScore = (ngramOverlapScore * 0.50) + boilerplatePenalty + lowRichnessPenalty;
    final plagiarismRiskScore = max(baseRiskScore, maxSourceSimilarity).clamp(0.0, 100.0);

    return SourcePlagiarismResult(
      plagiarismRiskScore: plagiarismRiskScore,
      ngramOverlapScore: ngramOverlapScore,
      lexicalRichness: lexicalRichness,
      repeatedNgrams: repeatedNgrams,
      flaggedBoilerplates: flaggedBoilerplates,
      sourceMatches: matches,
    );
  }
}
