import 'dart:math';

/// Platt-style logistic probability calibrator derived from empirical validation splits.
class ProbabilityCalibrator {
  final double a;
  final double b;
  final String version;

  const ProbabilityCalibrator({
    this.a = 1.0,
    this.b = 0.0,
    this.version = 'calibration_v1',
  });

  /// Calibrates unscaled probability (0.0 -> 1.0) through logit transform.
  double calibrate(double probability) {
    final p = probability.clamp(1e-6, 1.0 - 1e-6);
    final logit = log(p / (1.0 - p));
    final calibratedLogit = (a * logit) + b;
    return (1.0 / (1.0 + exp(-calibratedLogit))).clamp(0.0, 1.0);
  }

  /// Fits optimal Platt scaling parameters (a, b) on empirical validation pairs using L2-regularized logistic regression.
  static ProbabilityCalibrator fit(
    List<({double rawScore, bool groundTruth})> validationData, {
    String version = 'calibrated_empirical_v2',
    int iterations = 250,
    double learningRate = 0.05,
    double l2Reg = 0.01,
  }) {
    if (validationData.isEmpty) {
      return const ProbabilityCalibrator();
    }

    double curA = 1.0;
    double curB = 0.0;

    // Convert raw probabilities to log-odds logits
    final logitsAndLabels = validationData.map((d) {
      final p = d.rawScore.clamp(1e-5, 1.0 - 1e-5);
      final z = log(p / (1.0 - p));
      final y = d.groundTruth ? 1.0 : 0.0;
      return (z: z, y: y);
    }).toList();

    for (int iter = 0; iter < iterations; iter++) {
      double gradA = 0.0;
      double gradB = 0.0;

      for (final item in logitsAndLabels) {
        final logitOut = (curA * item.z) + curB;
        final pPred = 1.0 / (1.0 + exp(-logitOut.clamp(-20.0, 20.0)));
        final error = pPred - item.y;

        gradA += error * item.z;
        gradB += error;
      }

      final n = logitsAndLabels.length;
      gradA = (gradA / n) + l2Reg * (curA - 1.0);
      gradB = (gradB / n) + l2Reg * curB;

      curA -= learningRate * gradA;
      curB -= learningRate * gradB;

      // Bound parameters to avoid degenerate distortion
      curA = curA.clamp(0.3, 3.0);
      curB = curB.clamp(-2.0, 2.0);
    }

    return ProbabilityCalibrator(
      a: curA,
      b: curB,
      version: version,
    );
  }

  /// Factory producing a temperature-scaled calibrator (b = 0, a = 1 / T).
  factory ProbabilityCalibrator.temperature(double temperature) {
    final t = temperature.clamp(0.1, 10.0);
    return ProbabilityCalibrator(
      a: 1.0 / t,
      b: 0.0,
      version: 'temperature_T=${t.toStringAsFixed(2)}',
    );
  }

  /// Fits optimal Temperature Scaling parameter T on validation data by minimizing cross-entropy.
  static ProbabilityCalibrator fitTemperature(
    List<({double rawScore, bool groundTruth})> validationData, {
    String version = 'calibrated_temperature',
  }) {
    if (validationData.isEmpty) return const ProbabilityCalibrator();

    double bestT = 1.0;
    double minNll = double.infinity;

    for (double t = 0.5; t <= 3.0; t += 0.05) {
      double nll = 0.0;
      for (final item in validationData) {
        final p = item.rawScore.clamp(1e-5, 1.0 - 1e-5);
        final z = log(p / (1.0 - p));
        final pCal = 1.0 / (1.0 + exp(-z / t));
        final y = item.groundTruth ? 1.0 : 0.0;
        nll += -(y * log(pCal.clamp(1e-6, 1.0)) + (1.0 - y) * log((1.0 - pCal).clamp(1e-6, 1.0)));
      }
      if (nll < minNll) {
        minNll = nll;
        bestT = t;
      }
    }

    return ProbabilityCalibrator.temperature(bestT);
  }

  /// Evaluates and compares multiple calibration methods on validation data.
  static ({
    ProbabilityCalibrator bestCalibrator,
    String bestMethod,
    Map<String, ({double brierScore, double ece, double logLoss})> methodComparison,
  }) evaluateCalibrationMethods(
    List<({double rawScore, bool groundTruth})> validationData,
  ) {
    final uncalibrated = const ProbabilityCalibrator(a: 1.0, b: 0.0, version: 'identity');
    final platt = ProbabilityCalibrator.fit(validationData, version: 'platt_fitted');
    final temp = ProbabilityCalibrator.fitTemperature(validationData, version: 'temp_fitted');

    final candidates = {
      'Identity (Uncalibrated)': uncalibrated,
      'Platt Scaling (Logistic)': platt,
      'Temperature Scaling': temp,
    };

    final comparison = <String, ({double brierScore, double ece, double logLoss})>{};
    String bestMethod = 'Platt Scaling (Logistic)';
    double lowestEce = double.infinity;
    ProbabilityCalibrator bestCal = platt;

    for (final entry in candidates.entries) {
      final name = entry.key;
      final cal = entry.value;

      double brierSum = 0.0;
      double nllSum = 0.0;
      final predictions = <({double probability, bool groundTruth})>[];

      for (final item in validationData) {
        final calProb = cal.calibrate(item.rawScore);
        final y = item.groundTruth ? 1.0 : 0.0;
        brierSum += pow(calProb - y, 2);
        nllSum += -(y * log(calProb.clamp(1e-6, 1.0)) + (1.0 - y) * log((1.0 - calProb).clamp(1e-6, 1.0)));
        predictions.add((probability: calProb * 100.0, groundTruth: item.groundTruth));
      }

      final n = validationData.isEmpty ? 1 : validationData.length;
      final brier = brierSum / n;
      final nll = nllSum / n;

      // Compute 5-bin ECE
      double eceSum = 0.0;
      for (int b = 0; b < 5; b++) {
        final minB = b * 0.20;
        final maxB = (b + 1) * 0.20;
        final inBin = predictions.where((p) {
          final p01 = p.probability / 100.0;
          return b == 4 ? (p01 >= minB && p01 <= maxB) : (p01 >= minB && p01 < maxB);
        }).toList();

        if (inBin.isNotEmpty) {
          final avgConf = inBin.map((p) => p.probability / 100.0).reduce((a, b) => a + b) / inBin.length;
          final avgAcc = inBin.where((p) => p.groundTruth).length / inBin.length;
          eceSum += (inBin.length / n) * (avgConf - avgAcc).abs();
        }
      }

      comparison[name] = (brierScore: brier, ece: eceSum, logLoss: nll);
      if (eceSum < lowestEce) {
        lowestEce = eceSum;
        bestMethod = name;
        bestCal = cal;
      }
    }

    return (
      bestCalibrator: bestCal,
      bestMethod: bestMethod,
      methodComparison: comparison,
    );
  }

  factory ProbabilityCalibrator.fromJson(Map<String, dynamic> json) =>
      ProbabilityCalibrator(
        a: (json['a'] as num?)?.toDouble() ?? 1.0,
        b: (json['b'] as num?)?.toDouble() ?? 0.0,
        version: json['version'] as String? ?? 'calibration_v1',
      );

  Map<String, dynamic> toJson() => {
        'a': a,
        'b': b,
        'version': version,
      };
}
