/// Nature of a detected source match.
enum SourceMatchType {
  exact(label: 'Verbatim Match'),
  phraseMatch(label: 'Distinctive Phrase Match'),
  lexical(label: 'Lexical Match'),
  structural(label: 'Structural Parallelism'),
  shingleOverlap(label: 'High Shingle Overlap'),
  fuzzyParaphrase(label: 'Paraphrased Match'),
  semantic(label: 'Semantic Source Similarity');

  final String label;
  const SourceMatchType({required this.label});
}

/// Academic or literature citation context for a matched passage.
enum CitationStatus {
  uncited(label: 'Uncited'),
  quoted(label: 'Quoted Without Citation'),
  cited(label: 'Cited Without Quotation'),
  quotedAndCited(label: 'Properly Quoted & Cited');

  final String label;
  const CitationStatus({required this.label});
}

/// A specific matched span between the input document and an external source.
class SourceMatchSegment {
  final int documentStartOffset;
  final int documentEndOffset;
  final String matchedText;
  final String sourceTitle;
  final String? sourceUrl;
  final int tokenCount;
  final double similarityPercent;
  final SourceMatchType matchType;
  final CitationStatus citationStatus;

  /// Which text of an online source matched: `abstract` (search API
  /// abstract/snippet) or `full_text` (fetched open-access body). Null for
  /// sources without fetched full text (on-device corpus, abstract-only).
  final String? matchedIn;

  /// Character span of the aligned passage inside the source text.
  final int? sourceStartOffset;
  final int? sourceEndOffset;

  /// Short excerpt (≤ 280 chars) of the aligned source passage.
  final String? sourceExcerpt;

  /// Open-access URL where the matched full text can be read.
  final String? oaUrl;

  bool get matchedInFullText => matchedIn == 'full_text';

  const SourceMatchSegment({
    required this.documentStartOffset,
    required this.documentEndOffset,
    required this.matchedText,
    required this.sourceTitle,
    this.sourceUrl,
    required this.tokenCount,
    required this.similarityPercent,
    required this.matchType,
    this.citationStatus = CitationStatus.uncited,
    this.matchedIn,
    this.sourceStartOffset,
    this.sourceEndOffset,
    this.sourceExcerpt,
    this.oaUrl,
  });

  /// Copy with a different match type / citation status (provenance kept).
  SourceMatchSegment copyWith({SourceMatchType? matchType, CitationStatus? citationStatus}) => SourceMatchSegment(
        documentStartOffset: documentStartOffset,
        documentEndOffset: documentEndOffset,
        matchedText: matchedText,
        sourceTitle: sourceTitle,
        sourceUrl: sourceUrl,
        tokenCount: tokenCount,
        similarityPercent: similarityPercent,
        matchType: matchType ?? this.matchType,
        citationStatus: citationStatus ?? this.citationStatus,
        matchedIn: matchedIn,
        sourceStartOffset: sourceStartOffset,
        sourceEndOffset: sourceEndOffset,
        sourceExcerpt: sourceExcerpt,
        oaUrl: oaUrl,
      );

  factory SourceMatchSegment.fromJson(Map<String, dynamic> json) {
    final matchTypeName = json['matchType'] as String;
    final citationStatusName = json['citationStatus'] as String? ?? 'uncited';
    return SourceMatchSegment(
      documentStartOffset: (json['documentStartOffset'] as num).toInt(),
      documentEndOffset: (json['documentEndOffset'] as num).toInt(),
      matchedText: json['matchedText'] as String,
      sourceTitle: json['sourceTitle'] as String,
      sourceUrl: json['sourceUrl'] as String?,
      tokenCount: (json['tokenCount'] as num).toInt(),
      similarityPercent: (json['similarityPercent'] as num).toDouble(),
      matchType: SourceMatchType.values.firstWhere(
        (t) => t.name == matchTypeName,
        orElse: () => SourceMatchType.exact,
      ),
      citationStatus: CitationStatus.values.firstWhere(
        (c) => c.name == citationStatusName,
        orElse: () => CitationStatus.uncited,
      ),
      matchedIn: json['matchedIn'] as String?,
      sourceStartOffset: (json['sourceStartOffset'] as num?)?.toInt(),
      sourceEndOffset: (json['sourceEndOffset'] as num?)?.toInt(),
      sourceExcerpt: json['sourceExcerpt'] as String?,
      oaUrl: json['oaUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'documentStartOffset': documentStartOffset,
        'documentEndOffset': documentEndOffset,
        'matchedText': matchedText,
        'sourceTitle': sourceTitle,
        'sourceUrl': sourceUrl,
        'tokenCount': tokenCount,
        'similarityPercent': similarityPercent,
        'matchType': matchType.name,
        'citationStatus': citationStatus.name,
        if (matchedIn != null) 'matchedIn': matchedIn,
        if (sourceStartOffset != null) 'sourceStartOffset': sourceStartOffset,
        if (sourceEndOffset != null) 'sourceEndOffset': sourceEndOffset,
        if (sourceExcerpt != null) 'sourceExcerpt': sourceExcerpt,
        if (oaUrl != null) 'oaUrl': oaUrl,
      };
}

/// Independent forensic evidence measuring whether writing was copied or paraphrased from known sources.
class SourceSimilarityEvidence {
  final double overallSimilarityScore; // 0.0 to 100.0
  final double documentCoveragePercent; // 0.0 to 100.0
  final int matchedTokenCount;
  final int longestContiguousTokenMatch;
  final int uniqueSourceCount;
  final List<SourceMatchSegment> matches;
  final String defensibleSummary;

  // Hierarchical & multi-threshold indicators
  final int matchedSentenceCount;
  final int totalSentenceCount;
  final double matchedSentencePercent;
  final String longestMatchingPhrase;
  final double distinctivePhraseDensity;
  final double sourceConcentration;
  final String confidenceLevel;
  final int exactMatchCount;
  final int paraphraseMatchCount;

  const SourceSimilarityEvidence({
    required this.overallSimilarityScore,
    required this.documentCoveragePercent,
    required this.matchedTokenCount,
    required this.longestContiguousTokenMatch,
    required this.uniqueSourceCount,
    this.matches = const [],
    required this.defensibleSummary,
    this.matchedSentenceCount = 0,
    this.totalSentenceCount = 0,
    this.matchedSentencePercent = 0.0,
    this.longestMatchingPhrase = '',
    this.distinctivePhraseDensity = 0.0,
    this.sourceConcentration = 0.0,
    this.confidenceLevel = 'HIGH CONFIDENCE',
    this.exactMatchCount = 0,
    this.paraphraseMatchCount = 0,
  });

  const SourceSimilarityEvidence.clean()
      : overallSimilarityScore = 0.0,
        documentCoveragePercent = 0.0,
        matchedTokenCount = 0,
        longestContiguousTokenMatch = 0,
        uniqueSourceCount = 0,
        matches = const [],
        defensibleSummary = 'No meaningful external source similarity detected.',
        matchedSentenceCount = 0,
        totalSentenceCount = 0,
        matchedSentencePercent = 0.0,
        longestMatchingPhrase = '',
        distinctivePhraseDensity = 0.0,
        sourceConcentration = 0.0,
        confidenceLevel = 'HIGH CONFIDENCE',
        exactMatchCount = 0,
        paraphraseMatchCount = 0;

  factory SourceSimilarityEvidence.fromJson(Map<String, dynamic> json) {
    final matchesList = (json['matches'] as List<dynamic>? ?? [])
        .map((m) => SourceMatchSegment.fromJson(m as Map<String, dynamic>))
        .toList();
    return SourceSimilarityEvidence(
      overallSimilarityScore: (json['overallSimilarityScore'] as num).toDouble(),
      documentCoveragePercent: (json['documentCoveragePercent'] as num).toDouble(),
      matchedTokenCount: (json['matchedTokenCount'] as num).toInt(),
      longestContiguousTokenMatch: (json['longestContiguousTokenMatch'] as num).toInt(),
      uniqueSourceCount: (json['uniqueSourceCount'] as num).toInt(),
      matches: matchesList,
      defensibleSummary: json['defensibleSummary'] as String,
      matchedSentenceCount: (json['matchedSentenceCount'] as num?)?.toInt() ?? 0,
      totalSentenceCount: (json['totalSentenceCount'] as num?)?.toInt() ?? 0,
      matchedSentencePercent: (json['matchedSentencePercent'] as num?)?.toDouble() ?? 0.0,
      longestMatchingPhrase: json['longestMatchingPhrase'] as String? ?? '',
      distinctivePhraseDensity: (json['distinctivePhraseDensity'] as num?)?.toDouble() ?? 0.0,
      sourceConcentration: (json['sourceConcentration'] as num?)?.toDouble() ?? 0.0,
      confidenceLevel: json['confidenceLevel'] as String? ?? 'HIGH CONFIDENCE',
      exactMatchCount: (json['exactMatchCount'] as num?)?.toInt() ?? 0,
      paraphraseMatchCount: (json['paraphraseMatchCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'overallSimilarityScore': overallSimilarityScore,
        'documentCoveragePercent': documentCoveragePercent,
        'matchedTokenCount': matchedTokenCount,
        'longestContiguousTokenMatch': longestContiguousTokenMatch,
        'uniqueSourceCount': uniqueSourceCount,
        'matches': matches.map((m) => m.toJson()).toList(),
        'defensibleSummary': defensibleSummary,
        'matchedSentenceCount': matchedSentenceCount,
        'totalSentenceCount': totalSentenceCount,
        'matchedSentencePercent': matchedSentencePercent,
        'longestMatchingPhrase': longestMatchingPhrase,
        'distinctivePhraseDensity': distinctivePhraseDensity,
        'sourceConcentration': sourceConcentration,
        'confidenceLevel': confidenceLevel,
        'exactMatchCount': exactMatchCount,
        'paraphraseMatchCount': paraphraseMatchCount,
      };
}
