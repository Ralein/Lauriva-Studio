import 'dart:math';
import 'match_tokenizer.dart';
import 'source_repository.dart';

/// A fingerprint produced by the Stanford Winnowing algorithm.
///
/// Holds the 32-bit hash, the token index where the k-gram begins,
/// and the character offset in the source text.
class WinnowingFingerprint {
  final int hash;
  final int tokenIndex;
  final int charStart;
  final int charEnd;

  const WinnowingFingerprint({
    required this.hash,
    required this.tokenIndex,
    required this.charStart,
    required this.charEnd,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WinnowingFingerprint && runtimeType == other.runtimeType && hash == other.hash;

  @override
  int get hashCode => hash.hashCode;
}

/// Match segment discovered via winnowing fingerprint alignment.
class WinnowingMatchSegment {
  final int queryStartChar;
  final int queryEndChar;
  final int sourceStartChar;
  final int sourceEndChar;
  final String matchedText;
  final int matchedTokenCount;
  final String sourceTitle;
  final String? sourceUrl;

  const WinnowingMatchSegment({
    required this.queryStartChar,
    required this.queryEndChar,
    required this.sourceStartChar,
    required this.sourceEndChar,
    required this.matchedText,
    required this.matchedTokenCount,
    required this.sourceTitle,
    this.sourceUrl,
  });
}

/// Complete winnowing analysis result between query text and a source document.
class WinnowingMatchResult {
  final SourceCorpusDocument source;
  final double jaccardSimilarity;
  final double containmentQueryInSource;
  final int sharedFingerprints;
  final int totalQueryFingerprints;
  final int totalSourceFingerprints;
  final List<WinnowingMatchSegment> segments;

  const WinnowingMatchResult({
    required this.source,
    required this.jaccardSimilarity,
    required this.containmentQueryInSource,
    required this.sharedFingerprints,
    required this.totalQueryFingerprints,
    required this.totalSourceFingerprints,
    required this.segments,
  });
}

/// Stanford Winnowing Algorithm implementation (Schleimer, Wilkerson, Aiken, SIGMOD 2003).
///
/// Winnowing selects a sparse, deterministic subset of k-gram hashes such that:
/// 1. Any match of length >= t = (w + k - 1) tokens is mathematically GUARANTEED
///    to share at least one fingerprint.
/// 2. Matches shorter than noise threshold k are never detected.
/// 3. Fingerprint set is reduced by 70-85% compared to storing all n-grams,
///    making multi-document indexing instantaneous.
class WinnowingEngine {
  final int k; // k-gram size in tokens (default 4)
  final int w; // window size in hashes (default 4 -> guarantees detection of runs >= 7 tokens)

  const WinnowingEngine({
    this.k = 4,
    this.w = 4,
  });

  /// Guaranteed minimum match threshold (in tokens) for detection.
  int get guaranteedDetectionThreshold => w + k - 1;

  /// Generates winnowing fingerprints directly from raw text.
  List<WinnowingFingerprint> fingerprint(String text) {
    final tokens = MatchTokenizer.tokenize(text);
    return fingerprintTokens(tokens);
  }

  /// Generates winnowing fingerprints from pre-tokenized [MatchToken] list.
  List<WinnowingFingerprint> fingerprintTokens(List<MatchToken> tokens) {
    if (tokens.length < k) return const [];

    // 1. Compute k-gram hashes and their positions
    final nGramsCount = tokens.length - k + 1;
    final hashes = List<int>.filled(nGramsCount, 0);

    for (int i = 0; i < nGramsCount; i++) {
      final buf = StringBuffer();
      for (int j = i; j < i + k; j++) {
        if (j > i) buf.write(' ');
        buf.write(tokens[j].stem);
      }
      hashes[i] = MatchTokenizer.fnv1a(buf.toString());
    }

    if (hashes.length < w) {
      // If fewer hashes than window size w, pick the absolute minimum hash
      int minIdx = 0;
      for (int i = 1; i < hashes.length; i++) {
        if (hashes[i] <= hashes[minIdx]) {
          minIdx = i;
        }
      }
      return [
        WinnowingFingerprint(
          hash: hashes[minIdx],
          tokenIndex: minIdx,
          charStart: tokens[minIdx].start,
          charEnd: tokens[minIdx + k - 1].end,
        ),
      ];
    }

    // 2. Sliding window selection
    final fingerprints = <WinnowingFingerprint>[];
    int? lastSelectedIdx;

    for (int i = 0; i <= hashes.length - w; i++) {
      int minIdx = i;
      // In case of ties, select rightmost minimum (standard winnowing rule)
      for (int j = i + 1; j < i + w; j++) {
        if (hashes[j] <= hashes[minIdx]) {
          minIdx = j;
        }
      }

      if (minIdx != lastSelectedIdx) {
        fingerprints.add(
          WinnowingFingerprint(
            hash: hashes[minIdx],
            tokenIndex: minIdx,
            charStart: tokens[minIdx].start,
            charEnd: tokens[minIdx + k - 1].end,
          ),
        );
        lastSelectedIdx = minIdx;
      }
    }

    return fingerprints;
  }

  /// Calculates Jaccard similarity and containment between two fingerprint sets.
  WinnowingMatchResult compare({
    required String queryText,
    required SourceCorpusDocument source,
  }) {
    final queryTokens = MatchTokenizer.tokenize(queryText);
    final sourceTokens = source.matchTokens;

    final queryFps = fingerprintTokens(queryTokens);
    final sourceFps = fingerprintTokens(sourceTokens);

    if (queryFps.isEmpty || sourceFps.isEmpty) {
      return WinnowingMatchResult(
        source: source,
        jaccardSimilarity: 0.0,
        containmentQueryInSource: 0.0,
        sharedFingerprints: 0,
        totalQueryFingerprints: queryFps.length,
        totalSourceFingerprints: sourceFps.length,
        segments: const [],
      );
    }

    final sourceMap = <int, List<WinnowingFingerprint>>{};
    for (final sfp in sourceFps) {
      sourceMap.putIfAbsent(sfp.hash, () => []).add(sfp);
    }

    final shared = <int>{};
    final segments = <WinnowingMatchSegment>[];

    for (final qfp in queryFps) {
      final matches = sourceMap[qfp.hash];
      if (matches != null && matches.isNotEmpty) {
        shared.add(qfp.hash);
        final firstMatch = matches.first;
        segments.add(
          WinnowingMatchSegment(
            queryStartChar: qfp.charStart,
            queryEndChar: qfp.charEnd,
            sourceStartChar: firstMatch.charStart,
            sourceEndChar: firstMatch.charEnd,
            matchedText: queryText.substring(qfp.charStart, min(qfp.charEnd, queryText.length)),
            matchedTokenCount: k,
            sourceTitle: source.title,
            sourceUrl: source.url,
          ),
        );
      }
    }

    final setQ = queryFps.map((f) => f.hash).toSet();
    final setS = sourceFps.map((f) => f.hash).toSet();
    final intersectionCount = setQ.intersection(setS).length;
    final unionCount = setQ.union(setS).length;

    final jaccard = unionCount > 0 ? (intersectionCount / unionCount) : 0.0;
    final containment = setQ.isNotEmpty ? (intersectionCount / setQ.length) : 0.0;

    return WinnowingMatchResult(
      source: source,
      jaccardSimilarity: jaccard,
      containmentQueryInSource: containment,
      sharedFingerprints: intersectionCount,
      totalQueryFingerprints: setQ.length,
      totalSourceFingerprints: setS.length,
      segments: segments,
    );
  }
}
