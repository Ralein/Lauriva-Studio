/// Forensic tier defining the statistical predictability of a token under reference language models.
enum TokenTier {
  top10('Top 10', 'Extremely predictable (typical LLM selection)'),
  top100('Top 100', 'Expected natural prose'),
  top1000('Top 1000', 'Uncommon / expressive vocabulary'),
  rareTail('Rare / Tail', 'Idiosyncratic or highly creative human token');

  final String label;
  final String description;
  const TokenTier(this.label, this.description);
}

/// Token with calibrated log-probability and predictability tier.
class PredictableToken {
  final String token;
  final int rawStartOffset;
  final int rawEndOffset;
  final double logProbability;
  final int rankEstimate;
  final TokenTier tier;

  const PredictableToken({
    required this.token,
    required this.rawStartOffset,
    required this.rawEndOffset,
    required this.logProbability,
    required this.rankEstimate,
    required this.tier,
  });

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'rawStartOffset': rawStartOffset,
      'rawEndOffset': rawEndOffset,
      'logProbability': logProbability,
      'rankEstimate': rankEstimate,
      'tier': tier.name,
    };
  }
}

/// Document-level token predictability and perplexity distribution.
class TokenPredictabilityReport {
  final List<PredictableToken> tokens;
  final double top10Percentage;
  final double top100Percentage;
  final double top1000Percentage;
  final double rareTailPercentage;
  final double meanPerplexity;
  final double predictabilityScore; // 0 (creative human) - 100 (heavily machine-predicted)
  final String defensibleSummary;

  const TokenPredictabilityReport({
    required this.tokens,
    required this.top10Percentage,
    required this.top100Percentage,
    required this.top1000Percentage,
    required this.rareTailPercentage,
    required this.meanPerplexity,
    required this.predictabilityScore,
    required this.defensibleSummary,
  });

  const TokenPredictabilityReport.empty()
      : tokens = const [],
        top10Percentage = 0.0,
        top100Percentage = 0.0,
        top1000Percentage = 0.0,
        rareTailPercentage = 0.0,
        meanPerplexity = 0.0,
        predictabilityScore = 0.0,
        defensibleSummary = 'Insufficient text for token predictability mapping.';

  Map<String, dynamic> toJson() {
    return {
      'tokens': tokens.map((t) => t.toJson()).toList(),
      'top10Percentage': top10Percentage,
      'top100Percentage': top100Percentage,
      'top1000Percentage': top1000Percentage,
      'rareTailPercentage': rareTailPercentage,
      'meanPerplexity': meanPerplexity,
      'predictabilityScore': predictabilityScore,
      'defensibleSummary': defensibleSummary,
    };
  }
}
