/// Calculates statistical confidence across multi-stream forensic dimensions.
class ConfidenceCalculator {
  const ConfidenceCalculator();

  /// Computes fused confidence (0.0 -> 1.0) evaluating model uncertainty and stream consensus.
  double calculateConfidence({
    required int wordCount,
    required double neuralProbability,
    required double neuralUncertainty,
    required double forensicProbability,
    required double forensicUncertainty,
    required bool isNeuralFallback,
  }) {
    // 1. Length-based sample size confidence factor
    final lengthFactor = (wordCount / 100.0).clamp(0.35, 1.0);

    // 2. Intrinsic certainty factor
    final neuralCertainty = isNeuralFallback ? 0.4 : (1.0 - neuralUncertainty).clamp(0.0, 1.0);
    final forensicCertainty = (1.0 - forensicUncertainty).clamp(0.0, 1.0);

    final meanCertainty = isNeuralFallback
        ? forensicCertainty
        : (neuralCertainty * 0.65 + forensicCertainty * 0.35);

    // 3. Agreement / Disagreement penalty
    double agreementPenalty = 0.0;
    if (!isNeuralFallback) {
      final delta = (neuralProbability - forensicProbability).abs();
      if (delta > 0.45) {
        // Severe divergence between deep transformer and surface stylometry
        agreementPenalty = (delta - 0.45) * 0.8;
      }
    }

    final rawConfidence = (meanCertainty * lengthFactor) - agreementPenalty;
    return rawConfidence.clamp(0.15, 0.99);
  }
}
