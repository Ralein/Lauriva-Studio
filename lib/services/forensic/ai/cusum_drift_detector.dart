import 'dart:math' as math;

/// CUSUM (Cumulative Sum Control Chart) change-point detector for stylometric drift.
///
/// Much more sensitive to sudden AI insertion than window variance analysis.
/// Operates on sentence-level feature streams (e.g., AI probability per sentence).
/// A changepoint signals a transition between human and AI authorship regions.
///
/// Phase 4: Detects the exact sentence boundary where authorship mode switches.
class CusumDriftDetector {
  /// Threshold h: CUSUM score above this triggers a changepoint.
  final double _threshold;

  /// Slack parameter k: sensitivity control (0.5 = detect 1 std deviation shift).
  final double _slack;

  const CusumDriftDetector({
    double threshold = 4.0,
    double slack = 0.5,
  })  : _threshold = threshold,
        _slack = slack;

  /// Detects change-points in [featureTimeSeries] (list of per-sentence values, 0.0–1.0).
  ///
  /// Returns list of sentence indices where a significant style drift is detected.
  /// An empty list means no drift detected (uniform authorship throughout).
  List<int> detectChangepoints(List<double> featureTimeSeries) {
    if (featureTimeSeries.length < 4) return [];

    final mean = _mean(featureTimeSeries);
    final changepoints = <int>[];

    double cusumPos = 0.0; // upward cusum (detecting AI insertion)
    double cusumNeg = 0.0; // downward cusum (detecting human insertion after AI)

    for (int i = 0; i < featureTimeSeries.length; i++) {
      final deviation = featureTimeSeries[i] - mean;

      cusumPos = math.max(0.0, cusumPos + deviation - _slack);
      cusumNeg = math.max(0.0, cusumNeg - deviation - _slack);

      if (cusumPos > _threshold || cusumNeg > _threshold) {
        changepoints.add(i);
        cusumPos = 0.0; // reset after detection
        cusumNeg = 0.0;
      }
    }

    return changepoints;
  }

  /// Computes CUSUM-based mixed authorship confidence.
  /// Returns 0.0 (uniform) to 1.0 (high confidence of mixed authorship).
  double mixedAuthorshipConfidence(List<double> featureTimeSeries) {
    if (featureTimeSeries.length < 4) return 0.0;

    final changepoints = detectChangepoints(featureTimeSeries);
    if (changepoints.isEmpty) return 0.0;

    // More changepoints + higher amplitude = stronger mixed signal
    final amplitude = _standardDeviation(featureTimeSeries);
    final changepointDensity = changepoints.length / featureTimeSeries.length;

    return (changepointDensity * amplitude * 2.0).clamp(0.0, 1.0);
  }

  /// Identifies the most likely AI-authored sentence spans.
  /// Returns list of (startIndex, endIndex) inclusive tuples.
  List<(int, int)> identifyAiSpans(List<double> aiProbabilities, {double threshold = 0.60}) {
    final spans = <(int, int)>[];
    int? spanStart;

    for (int i = 0; i < aiProbabilities.length; i++) {
      final isAi = aiProbabilities[i] >= threshold;
      if (isAi && spanStart == null) {
        spanStart = i;
      } else if (!isAi && spanStart != null) {
        spans.add((spanStart, i - 1));
        spanStart = null;
      }
    }

    if (spanStart != null) {
      spans.add((spanStart, aiProbabilities.length - 1));
    }

    return spans;
  }

  double _mean(List<double> xs) {
    if (xs.isEmpty) return 0.0;
    return xs.reduce((a, b) => a + b) / xs.length;
  }

  double _standardDeviation(List<double> xs) {
    if (xs.length < 2) return 0.0;
    final m = _mean(xs);
    final variance = xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / xs.length;
    return math.sqrt(variance);
  }
}
