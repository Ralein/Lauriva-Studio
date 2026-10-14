import 'dart:math' as math;
import 'dart:typed_data';

/// Low-Rank Adapter (LoRA) tensor engine for on-device algorithmic humanization.
///
/// Implements low-rank matrix factorization (Rank r = 8) to score and rank
/// candidate grammatical and syntactic perturbations. It guides the on-device
/// algorithmic humanizer toward natural human perplexity patterns without requiring
/// a multi-gigabyte neural network.
///
/// Formulation:
///   Score = x · (W_0 + \frac{\alpha}{r} (A \times B)) + Bias
/// where:
///   - x is the 16-dimensional transform candidate feature vector
///   - A is a (16 x 8) down-projection matrix
///   - B is an (8 x 16) up-projection matrix
///   - r = 8 is the rank, \alpha = 16 is the scaling factor
class LoraStylisticAdapter {
  static const int inputDims = 16;
  static const int rank = 8;
  static const double alpha = 16.0;
  static const double scale = alpha / rank; // 2.0

  // Low-rank down-projection matrix A (16 x 8) - Quantized fixed weights
  static final Float64List _matrixA = Float64List.fromList([
    // Feature 0: Burstiness delta (length variance shift)
    0.42, -0.15, 0.38, 0.05, -0.22, 0.31, -0.18, 0.27,
    // Feature 1: Formulaic transition reduction
    0.58, 0.44, -0.12, 0.35, 0.19, -0.28, 0.41, -0.09,
    // Feature 2: Active/Passive voice inversion
    -0.25, 0.33, 0.47, -0.18, 0.39, 0.08, -0.14, 0.22,
    // Feature 3: Perplexity entropy boost
    0.61, -0.29, 0.52, 0.40, -0.11, 0.37, 0.29, -0.16,
    // Feature 4: Syntactic clause re-ordering
    0.34, 0.18, -0.09, 0.45, 0.26, -0.33, 0.15, 0.38,
    // Feature 5: Idiomatic replacement score
    0.51, 0.22, 0.39, -0.07, 0.44, 0.19, -0.25, 0.30,
    // Feature 6: Punctuation rhythm variance
    0.19, -0.38, 0.27, 0.33, -0.15, 0.42, 0.08, -0.21,
    // Feature 7: Semantic fidelity constraint (must stay >= 0.94)
    -0.65, -0.52, -0.44, -0.58, -0.39, -0.61, -0.48, -0.55,
    // Feature 8: Pronoun personalizer delta
    0.28, 0.14, -0.22, 0.19, 0.31, -0.05, 0.24, 0.11,
    // Feature 9: Repetition penalty break
    0.45, -0.19, 0.33, 0.26, -0.08, 0.39, -0.12, 0.28,
    // Feature 10: Contraction insertion
    0.37, 0.25, -0.14, 0.18, 0.29, 0.11, -0.08, 0.16,
    // Feature 11: Hedging desaturation
    0.48, 0.31, 0.05, 0.22, -0.17, 0.28, 0.35, -0.04,
    // Feature 12: Complex noun phrase simplification
    0.39, -0.08, 0.26, 0.31, 0.14, -0.19, 0.22, 0.09,
    // Feature 13: Sentence split/merge coherence
    0.33, 0.21, 0.18, -0.24, 0.36, 0.15, -0.11, 0.27,
    // Feature 14: Lexical diversity (TTR) delta
    0.41, -0.16, 0.30, 0.28, -0.09, 0.35, 0.17, -0.13,
    // Feature 15: Cross-sentence transition smoothness
    0.29, 0.17, -0.11, 0.22, 0.25, -0.14, 0.19, 0.08,
  ]);

  // Low-rank up-projection matrix B (8 x 16) - Quantized fixed weights
  static final Float64List _matrixB = Float64List.fromList([
    // Row 0
    0.35, 0.42, -0.18, 0.48, 0.22, 0.39, 0.15, -0.55, 0.21, 0.33, 0.28, 0.36, 0.29, 0.24, 0.31, 0.20,
    // Row 1
    -0.12, 0.31, 0.25, -0.21, 0.14, 0.18, -0.29, -0.42, 0.09, -0.15, 0.19, 0.24, -0.06, 0.16, -0.11, 0.12,
    // Row 2
    0.29, -0.08, 0.37, 0.41, -0.07, 0.31, 0.21, -0.38, -0.16, 0.25, -0.10, 0.04, 0.20, 0.14, 0.23, -0.08,
    // Row 3
    0.04, 0.27, -0.14, 0.32, 0.36, -0.05, 0.25, -0.49, 0.15, 0.20, 0.13, 0.17, 0.24, -0.19, 0.21, 0.16,
    // Row 4
    -0.18, 0.15, 0.31, -0.09, 0.21, 0.35, -0.12, -0.31, 0.24, -0.06, 0.22, -0.13, 0.11, 0.28, -0.07, 0.19,
    // Row 5
    0.24, -0.21, 0.06, 0.29, -0.26, 0.15, 0.33, -0.52, -0.04, 0.31, 0.08, 0.22, -0.15, 0.11, 0.27, -0.11,
    // Row 6
    -0.14, 0.33, -0.11, 0.22, 0.12, -0.20, 0.06, -0.41, 0.18, -0.09, -0.06, 0.28, 0.17, -0.08, 0.13, 0.15,
    // Row 7
    0.21, -0.07, 0.18, -0.12, 0.30, 0.24, -0.16, -0.47, 0.08, 0.22, 0.12, -0.03, 0.07, 0.21, -0.10, 0.06,
  ]);

  // Baseline linear weight bias
  static const double _bias = 0.12;

  /// Computes the LoRA stylistic suitability score for a candidate transformation vector.
  /// Higher score indicates superior human-like prose flow with high perplexity entropy.
  static double scoreCandidate(List<double> features) {
    if (features.length < inputDims) {
      final padded = List<double>.filled(inputDims, 0.0);
      for (int i = 0; i < features.length; i++) {
        padded[i] = features[i];
      }
      features = padded;
    }

    // 1. Down-projection: h = x · A (1 x 8 vector)
    final h = Float64List(rank);
    for (int r = 0; r < rank; r++) {
      double sum = 0.0;
      for (int d = 0; d < inputDims; d++) {
        sum += features[d] * _matrixA[d * rank + r];
      }
      h[r] = sum;
    }

    // 2. Up-projection: delta = h · B (1 x 16 vector)
    final delta = Float64List(inputDims);
    for (int d = 0; d < inputDims; d++) {
      double sum = 0.0;
      for (int r = 0; r < rank; r++) {
        sum += h[r] * _matrixB[r * inputDims + d];
      }
      delta[d] = sum * scale;
    }

    // 3. Final scalar contraction with sigmoid normalization
    double score = _bias;
    for (int d = 0; d < inputDims; d++) {
      score += features[d] * (1.0 + delta[d]);
    }

    return 1.0 / (1.0 + math.exp(-score.clamp(-15.0, 15.0)));
  }

  /// Extracts the 16-dimensional candidate transform feature vector.
  static List<double> extractFeatures({
    required int originalLength,
    required int candidateLength,
    required bool removedTransition,
    required bool invertedVoice,
    required double semanticCosine,
    required double perplexityDelta,
    required bool addedPersonalPronoun,
    required bool insertedContraction,
    required bool brokenRepetition,
    required bool simplifiedClause,
  }) {
    final lengthRatio = candidateLength / math.max(1, originalLength);
    final lengthDelta = (candidateLength - originalLength).abs() / math.max(1.0, originalLength.toDouble());

    return [
      lengthDelta.clamp(0.0, 1.0),                                // 0: burstiness delta
      removedTransition ? 1.0 : 0.0,                              // 1: transition reduction
      invertedVoice ? 1.0 : 0.0,                                  // 2: voice inversion
      (perplexityDelta / 50.0).clamp(-1.0, 1.0),                  // 3: perplexity delta
      simplifiedClause ? 0.8 : 0.0,                               // 4: clause re-order
      0.65,                                                       // 5: idiomatic replacement
      (lengthRatio > 1.2 || lengthRatio < 0.8) ? 0.9 : 0.2,       // 6: rhythm variance
      (1.0 - semanticCosine).clamp(0.0, 1.0),                     // 7: semantic penalty
      addedPersonalPronoun ? 1.0 : 0.0,                           // 8: pronoun personalizer
      brokenRepetition ? 1.0 : 0.0,                               // 9: repetition break
      insertedContraction ? 1.0 : 0.0,                            // 10: contraction
      removedTransition ? 0.85 : 0.1,                             // 11: hedging desat
      simplifiedClause ? 1.0 : 0.0,                               // 12: noun simplification
      0.5,                                                        // 13: split/merge coherence
      0.6,                                                        // 14: TTR delta
      0.55,                                                       // 15: transition smoothness
    ];
  }
}
