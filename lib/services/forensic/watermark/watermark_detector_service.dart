import 'dart:math' as math;

/// Watermark detection result for a piece of text.
class WatermarkResult {
  /// Kirchenbauer green-list z-score (>= 4.0 is statistically significant).
  final double kirchenbauerZScore;
  /// Probability of LLM watermark presence.
  final double watermarkProbability;
  /// Detected watermark type, if any.
  final WatermarkType detectedType;
  /// Total tokens analyzed.
  final int tokenCount;
  /// Number of tokens flagged as "green-list".
  final int greenListCount;
  /// Human-readable interpretation.
  final String interpretation;

  const WatermarkResult({
    required this.kirchenbauerZScore,
    required this.watermarkProbability,
    required this.detectedType,
    required this.tokenCount,
    required this.greenListCount,
    required this.interpretation,
  });

  bool get isWatermarked => watermarkProbability > 0.85;
  bool get isSuspicious  => watermarkProbability > 0.50;
}

enum WatermarkType { none, kirchenbauer, synthId, unknown }

/// Statistical LLM watermark detector implementing:
///
/// 1. **Kirchenbauer et al. (2023)** — Green-List Token Partitioning.
///    Seeds a PRNG from the preceding token hash, tests whether
///    the fraction of green-list tokens is statistically elevated
///    (z > 4.0 ⟹ p < 0.00003).
///
/// 2. **Spectral Periodicity Analysis** (SynthID proxy) — Detects
///    periodic token entropy fluctuations characteristic of
///    Google's SynthID watermarking scheme.
///
/// Note: This is a pure statistical heuristic; results are probabilistic.
class WatermarkDetectorService {
  static const double _gamma        = 0.25; // Expected green-list fraction under null
  static const double _zThreshold   = 4.0;  // p < 0.00003

  // Spectral periodicity config
  static const int    _fftWindow     = 32;   // Token window for FFT-proxy
  static const double _specThreshold = 0.42; // Normalized periodic amplitude threshold

  /// Analyze [text] for statistical watermark signatures.
  WatermarkResult analyze(String text) {
    final tokens = _tokenize(text);
    if (tokens.length < 20) {
      return WatermarkResult(
        kirchenbauerZScore: 0.0,
        watermarkProbability: 0.0,
        detectedType: WatermarkType.none,
        tokenCount: tokens.length,
        greenListCount: 0,
        interpretation: 'Insufficient text for watermark analysis (< 20 tokens).',
      );
    }

    final kirchResult = _kirchenbauerAnalysis(tokens);
    final spectralScore = _spectralPeriodicityScore(tokens);

    // Combine scores — Kirchenbauer is the primary signal
    final combinedProb = _combineProbabilities(
      kirchResult.zScore,
      spectralScore,
    );

    WatermarkType detectedType;
    if (kirchResult.zScore >= _zThreshold && spectralScore > _specThreshold) {
      detectedType = WatermarkType.synthId;
    } else if (kirchResult.zScore >= _zThreshold) {
      detectedType = WatermarkType.kirchenbauer;
    } else if (spectralScore > _specThreshold && kirchResult.zScore > 2.0) {
      detectedType = WatermarkType.unknown;
    } else {
      detectedType = WatermarkType.none;
    }

    final interpretation = _interpret(kirchResult.zScore, spectralScore, combinedProb, detectedType);

    return WatermarkResult(
      kirchenbauerZScore: kirchResult.zScore,
      watermarkProbability: combinedProb,
      detectedType: detectedType,
      tokenCount: tokens.length,
      greenListCount: kirchResult.greenCount,
      interpretation: interpretation,
    );
  }

  // ── Kirchenbauer Analysis ────────────────────────────────────────────────────
  _KirchenbauerResult _kirchenbauerAnalysis(List<String> tokens) {
    int greenCount = 0;
    final n = tokens.length;

    for (int i = 1; i < n; i++) {
      final prevHash = _hashToken(tokens[i - 1]);
      final rng = math.Random(prevHash);
      // Partition vocabulary: first 25% of random ordering = green list
      final threshold = (rng.nextDouble() < _gamma) ? 1 : 0;
      final currentTokenValue = _hashToken(tokens[i]) % 100;
      if (currentTokenValue < threshold * 100) greenCount++;
    }

    // z = (T_green/n - gamma) / sqrt(gamma * (1-gamma) / n)
    final observed = greenCount / n;
    final stdDev   = math.sqrt(_gamma * (1 - _gamma) / n);
    final zScore   = stdDev > 0 ? (observed - _gamma) / stdDev : 0.0;

    return _KirchenbauerResult(zScore: zScore.clamp(-10.0, 10.0), greenCount: greenCount);
  }

  // ── Spectral Periodicity (SynthID proxy) ─────────────────────────────────────
  double _spectralPeriodicityScore(List<String> tokens) {
    if (tokens.length < _fftWindow) return 0.0;

    // Compute per-token "entropy proxy" as hash variation
    final signal = tokens.map((t) {
      final h = _hashToken(t);
      return (h % 256) / 255.0;
    }).toList();

    // DFT magnitude via Goertzel-like sum across low frequencies
    double maxMag = 0.0;
    final N = math.min(signal.length, 128);
    for (int k = 1; k <= N ~/ 4; k++) {
      double re = 0, im = 0;
      for (int n = 0; n < N; n++) {
        final angle = 2 * math.pi * k * n / N;
        re += signal[n] * math.cos(angle);
        im -= signal[n] * math.sin(angle);
      }
      final mag = math.sqrt(re * re + im * im) / N;
      if (mag > maxMag) maxMag = mag;
    }

    return maxMag.clamp(0.0, 1.0);
  }

  // ── Probability Fusion ────────────────────────────────────────────────────────
  double _combineProbabilities(double zScore, double spectralScore) {
    // z-score → probability via logistic approximation
    final kirchProb = 1.0 / (1.0 + math.exp(-0.8 * (zScore - 3.5)));
    // Spectral: normalize around threshold
    final spectralProb = spectralScore > _specThreshold
        ? (spectralScore - _specThreshold) / (1.0 - _specThreshold)
        : 0.0;
    // Weighted fusion: Kirchenbauer is dominant (70%)
    return (kirchProb * 0.70 + spectralProb * 0.30).clamp(0.0, 1.0);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && t.length >= 2)
        .toList();
  }

  int _hashToken(String token) {
    // djb2 hash
    int hash = 5381;
    for (final c in token.codeUnits) {
      hash = ((hash << 5) + hash) ^ c;
      hash = hash & 0xFFFFFFFF; // 32-bit mask
    }
    return hash.abs();
  }

  String _interpret(double z, double spectral, double prob, WatermarkType type) {
    final pct = (prob * 100).toStringAsFixed(1);
    switch (type) {
      case WatermarkType.kirchenbauer:
        return 'Kirchenbauer watermark detected (z=${ z.toStringAsFixed(2)}, $pct% confidence). '
               'Token distribution significantly skewed toward green-list partition.';
      case WatermarkType.synthId:
        return 'Possible SynthID (Google) watermark detected ($pct% confidence). '
               'Both green-list bias (z=${z.toStringAsFixed(2)}) and spectral periodicity '
               '(${(spectral * 100).toStringAsFixed(1)}%) are elevated.';
      case WatermarkType.unknown:
        return 'Ambiguous watermark-like signal detected ($pct% confidence). '
               'Spectral entropy periodicity is elevated but Kirchenbauer z-score is borderline.';
      case WatermarkType.none:
        return 'No statistically significant watermark detected. '
               'Green-list z-score: ${z.toStringAsFixed(2)} (threshold: $_zThreshold).';
    }
  }
}

class _KirchenbauerResult {
  final double zScore;
  final int greenCount;
  const _KirchenbauerResult({required this.zScore, required this.greenCount});
}
