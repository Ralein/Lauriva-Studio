import 'dart:math';

/// A single classification threshold operating point.
class OperatingPoint {
  final double threshold;
  final int tp;
  final int fp;
  final int tn;
  final int fn;
  final double accuracy;
  final double precision;
  final double recall;
  final double fpr;
  final double fnr;
  final double f1;

  const OperatingPoint({
    required this.threshold,
    required this.tp,
    required this.fp,
    required this.tn,
    required this.fn,
    required this.accuracy,
    required this.precision,
    required this.recall,
    required this.fpr,
    required this.fnr,
    required this.f1,
  });

  Map<String, dynamic> toJson() => {
        'threshold': threshold,
        'tp': tp,
        'fp': fp,
        'tn': tn,
        'fn': fn,
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'fpr': fpr,
        'fnr': fnr,
        'f1': f1,
      };
}

/// A reliability calibration bin for ECE / MCE diagrams.
class CalibrationBin {
  final int binIndex;
  final double minBound;
  final double maxBound;
  final int count;
  final double avgConfidence;
  final double avgAccuracy;
  final double calibrationGap;

  const CalibrationBin({
    required this.binIndex,
    required this.minBound,
    required this.maxBound,
    required this.count,
    required this.avgConfidence,
    required this.avgAccuracy,
    required this.calibrationGap,
  });

  Map<String, dynamic> toJson() => {
        'binIndex': binIndex,
        'minBound': minBound,
        'maxBound': maxBound,
        'count': count,
        'avgConfidence': avgConfidence,
        'avgAccuracy': avgAccuracy,
        'calibrationGap': calibrationGap,
      };
}

/// Comprehensive evaluation metrics for a single detector stream or fusion model.
class StreamMetrics {
  final String streamName;
  final int total;
  final int tp;
  final int fp;
  final int tn;
  final int fn;
  final double accuracy;
  final double precision;
  final double recall;
  final double fpr;
  final double fnr;
  final double f1;
  final double rocAuc;
  final double prAuc;
  final double brierScore;
  final double ece;
  final double mce;
  final List<OperatingPoint> operatingPoints;
  final List<CalibrationBin> calibrationBins;

  const StreamMetrics({
    required this.streamName,
    required this.total,
    required this.tp,
    required this.fp,
    required this.tn,
    required this.fn,
    required this.accuracy,
    required this.precision,
    required this.recall,
    required this.fpr,
    required this.fnr,
    required this.f1,
    required this.rocAuc,
    required this.prAuc,
    required this.brierScore,
    required this.ece,
    required this.mce,
    required this.operatingPoints,
    required this.calibrationBins,
  });

  static StreamMetrics compute({
    required String streamName,
    required List<({double probability, bool groundTruth})> predictions,
    double defaultThreshold = 0.50,
  }) {
    if (predictions.isEmpty) {
      return StreamMetrics(
        streamName: streamName,
        total: 0,
        tp: 0,
        fp: 0,
        tn: 0,
        fn: 0,
        accuracy: 0,
        precision: 0,
        recall: 0,
        fpr: 0,
        fnr: 0,
        f1: 0,
        rocAuc: 0.5,
        prAuc: 0,
        brierScore: 0,
        ece: 0,
        mce: 0,
        operatingPoints: const [],
        calibrationBins: const [],
      );
    }

    // 1. Compute Base Metrics at Default Threshold
    int tp = 0;
    int fp = 0;
    int tn = 0;
    int fn = 0;
    double brierSum = 0.0;

    for (final p in predictions) {
      final y = p.groundTruth ? 1.0 : 0.0;
      final pred01 = (p.probability / 100.0).clamp(0.0, 1.0);
      brierSum += pow(pred01 - y, 2);

      final isPredictedAi = pred01 >= defaultThreshold;
      if (isPredictedAi && p.groundTruth) {
        tp++;
      } else if (isPredictedAi && !p.groundTruth) {
        fp++;
      } else if (!isPredictedAi && !p.groundTruth) {
        tn++;
      } else {
        fn++;
      }
    }

    final total = predictions.length;
    final accuracy = total > 0 ? (tp + tn) / total : 0.0;
    final precision = (tp + fp) > 0 ? tp / (tp + fp) : 0.0;
    final recall = (tp + fn) > 0 ? tp / (tp + fn) : 0.0;
    final fpr = (fp + tn) > 0 ? fp / (fp + tn) : 0.0;
    final fnr = (tp + fn) > 0 ? fn / (tp + fn) : 0.0;
    final f1 = (precision + recall) > 0 ? 2 * (precision * recall) / (precision + recall) : 0.0;
    final brierScore = total > 0 ? brierSum / total : 0.0;

    // 2. Compute ROC-AUC (Wilcoxon-Mann-Whitney U statistic)
    final positives = predictions.where((p) => p.groundTruth).map((p) => p.probability).toList();
    final negatives = predictions.where((p) => !p.groundTruth).map((p) => p.probability).toList();
    double rocAuc = 0.5;
    if (positives.isNotEmpty && negatives.isNotEmpty) {
      double uSum = 0.0;
      for (final pos in positives) {
        for (final neg in negatives) {
          if (pos > neg) {
            uSum += 1.0;
          } else if (pos == neg) {
            uSum += 0.5;
          }
        }
      }
      rocAuc = uSum / (positives.length * negatives.length);
    }

    // 3. Compute PR-AUC (Average Precision)
    final sorted = List<({double probability, bool groundTruth})>.from(predictions)
      ..sort((a, b) => b.probability.compareTo(a.probability));
    double prAuc = 0.0;
    int cumTp = 0;
    int cumFp = 0;
    double prevRecall = 0.0;

    for (final item in sorted) {
      if (item.groundTruth) {
        cumTp++;
      } else {
        cumFp++;
      }
      final curPrecision = cumTp / (cumTp + cumFp);
      final curRecall = positives.isNotEmpty ? cumTp / positives.length : 0.0;
      prAuc += curPrecision * (curRecall - prevRecall);
      prevRecall = curRecall;
    }

    // 4. Threshold Sweep (Operating Points across 0.05 -> 0.95 in 0.05 steps)
    final operatingPoints = <OperatingPoint>[];
    for (double t = 0.05; t <= 0.95; t += 0.05) {
      int oTp = 0;
      int oFp = 0;
      int oTn = 0;
      int oFn = 0;

      for (final p in predictions) {
        final pred01 = (p.probability / 100.0).clamp(0.0, 1.0);
        final predAi = pred01 >= t;
        if (predAi && p.groundTruth) {
          oTp++;
        } else if (predAi && !p.groundTruth) {
          oFp++;
        } else if (!predAi && !p.groundTruth) {
          oTn++;
        } else {
          oFn++;
        }
      }

      final oAcc = total > 0 ? (oTp + oTn) / total : 0.0;
      final oPrec = (oTp + oFp) > 0 ? oTp / (oTp + oFp) : 0.0;
      final oRec = (oTp + oFn) > 0 ? oTp / (oTp + oFn) : 0.0;
      final oFpr = (oFp + oTn) > 0 ? oFp / (oFp + oTn) : 0.0;
      final oFnr = (oTp + oFn) > 0 ? oFn / (oTp + oFn) : 0.0;
      final oF1 = (oPrec + oRec) > 0 ? 2 * (oPrec * oRec) / (oPrec + oRec) : 0.0;

      operatingPoints.add(OperatingPoint(
        threshold: double.parse(t.toStringAsFixed(2)),
        tp: oTp,
        fp: oFp,
        tn: oTn,
        fn: oFn,
        accuracy: oAcc,
        precision: oPrec,
        recall: oRec,
        fpr: oFpr,
        fnr: oFnr,
        f1: oF1,
      ));
    }

    // 5. Reliability Calibration Bins & ECE / MCE (10 bins)
    const numBins = 10;
    final calibrationBins = <CalibrationBin>[];
    double eceSum = 0.0;
    double mce = 0.0;

    for (int b = 0; b < numBins; b++) {
      final binMin = b / numBins;
      final binMax = (b + 1) / numBins;
      final binItems = predictions.where((p) {
        final val = (p.probability / 100.0).clamp(0.0, 1.0);
        return b == numBins - 1
            ? (val >= binMin && val <= binMax)
            : (val >= binMin && val < binMax);
      }).toList();

      if (binItems.isNotEmpty) {
        final binAvgConf = binItems.map((i) => (i.probability / 100.0).clamp(0.0, 1.0)).reduce((a, b) => a + b) / binItems.length;
        final binAvgAcc = binItems.where((i) => i.groundTruth).length / binItems.length;
        final gap = (binAvgAcc - binAvgConf).abs();

        eceSum += (binItems.length / total) * gap;
        if (gap > mce) mce = gap;

        calibrationBins.add(CalibrationBin(
          binIndex: b,
          minBound: binMin,
          maxBound: binMax,
          count: binItems.length,
          avgConfidence: binAvgConf,
          avgAccuracy: binAvgAcc,
          calibrationGap: gap,
        ));
      } else {
        calibrationBins.add(CalibrationBin(
          binIndex: b,
          minBound: binMin,
          maxBound: binMax,
          count: 0,
          avgConfidence: (binMin + binMax) / 2,
          avgAccuracy: 0.0,
          calibrationGap: 0.0,
        ));
      }
    }

    return StreamMetrics(
      streamName: streamName,
      total: total,
      tp: tp,
      fp: fp,
      tn: tn,
      fn: fn,
      accuracy: accuracy,
      precision: precision,
      recall: recall,
      fpr: fpr,
      fnr: fnr,
      f1: f1,
      rocAuc: rocAuc,
      prAuc: prAuc,
      brierScore: brierScore,
      ece: eceSum,
      mce: mce,
      operatingPoints: operatingPoints,
      calibrationBins: calibrationBins,
    );
  }

  Map<String, dynamic> toJson() => {
        'streamName': streamName,
        'total': total,
        'confusionMatrix': {'tp': tp, 'fp': fp, 'tn': tn, 'fn': fn},
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'fpr': fpr,
        'fnr': fnr,
        'f1': f1,
        'rocAuc': rocAuc,
        'prAuc': prAuc,
        'brierScore': brierScore,
        'ece': ece,
        'mce': mce,
        'operatingPoints': operatingPoints.map((o) => o.toJson()).toList(),
        'calibrationBins': calibrationBins.map((c) => c.toJson()).toList(),
      };
}

/// Category partition breakdown (e.g. per generator, domain, or transform).
class CategoryBreakdown {
  final String categoryName;
  final int sampleCount;
  final double neuralAccuracy;
  final double forensicAccuracy;
  final double fusionAccuracy;
  final double fusionFpr;
  final double fusionRecall;

  const CategoryBreakdown({
    required this.categoryName,
    required this.sampleCount,
    required this.neuralAccuracy,
    required this.forensicAccuracy,
    required this.fusionAccuracy,
    required this.fusionFpr,
    required this.fusionRecall,
  });

  Map<String, dynamic> toJson() => {
        'categoryName': categoryName,
        'sampleCount': sampleCount,
        'neuralAccuracy': neuralAccuracy,
        'forensicAccuracy': forensicAccuracy,
        'fusionAccuracy': fusionAccuracy,
        'fusionFpr': fusionFpr,
        'fusionRecall': fusionRecall,
      };
}

/// Latency and memory benchmark record across text scale sizes.
class ThroughputBenchmarkRecord {
  final String label;
  final int wordCount;
  final Duration neuralLatency;
  final Duration forensicLatency;
  final Duration fusionLatency;
  final double wordsPerSecond;

  const ThroughputBenchmarkRecord({
    required this.label,
    required this.wordCount,
    required this.neuralLatency,
    required this.forensicLatency,
    required this.fusionLatency,
    required this.wordsPerSecond,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'wordCount': wordCount,
        'neuralLatencyMs': neuralLatency.inMilliseconds,
        'forensicLatencyMs': forensicLatency.inMilliseconds,
        'fusionLatencyMs': fusionLatency.inMilliseconds,
        'wordsPerSecond': wordsPerSecond,
      };
}

/// Master comprehensive report generated by the Lauriva Detector Evaluation Harness.
class EvaluationHarnessReport {
  final DateTime timestamp;
  final int totalSamples;

  /// Samples too short for a verdict; excluded from the stream metrics.
  final int inconclusiveSamples;
  final StreamMetrics neuralMetrics;
  final StreamMetrics forensicMetrics;
  final StreamMetrics fusionMetrics;
  final List<CategoryBreakdown> domainBreakdown;
  final List<CategoryBreakdown> generatorBreakdown;
  final List<CategoryBreakdown> transformBreakdown;
  final List<ThroughputBenchmarkRecord> throughputBenchmarks;

  const EvaluationHarnessReport({
    required this.timestamp,
    required this.totalSamples,
    this.inconclusiveSamples = 0,
    required this.neuralMetrics,
    required this.forensicMetrics,
    required this.fusionMetrics,
    required this.domainBreakdown,
    required this.generatorBreakdown,
    required this.transformBreakdown,
    required this.throughputBenchmarks,
  });

  /// Formats the complete empirical evaluation as a clean Markdown report table.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# Lauriva 4.0 Dual-Stream Empirical Evaluation Report');
    buffer.writeln('**Generated:** ${timestamp.toIso8601String()} | **Total Corpus Samples:** $totalSamples (inconclusive, unscored: $inconclusiveSamples)');
    buffer.writeln();

    buffer.writeln('## 1. Overall Stream Performance Comparison');
    buffer.writeln('| Metric | Stream A: Neural | Stream B: Forensic | Dual-Stream Fusion |');
    buffer.writeln('|---|---|---|---|');
    buffer.writeln('| **Accuracy** | ${(neuralMetrics.accuracy * 100).toStringAsFixed(1)}% | ${(forensicMetrics.accuracy * 100).toStringAsFixed(1)}% | **${(fusionMetrics.accuracy * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **Precision** | ${(neuralMetrics.precision * 100).toStringAsFixed(1)}% | ${(forensicMetrics.precision * 100).toStringAsFixed(1)}% | **${(fusionMetrics.precision * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **Recall (AI Catch)** | ${(neuralMetrics.recall * 100).toStringAsFixed(1)}% | ${(forensicMetrics.recall * 100).toStringAsFixed(1)}% | **${(fusionMetrics.recall * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **False Positive Rate (FPR)** | ${(neuralMetrics.fpr * 100).toStringAsFixed(1)}% | ${(forensicMetrics.fpr * 100).toStringAsFixed(1)}% | **${(fusionMetrics.fpr * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **False Negative Rate (FNR)** | ${(neuralMetrics.fnr * 100).toStringAsFixed(1)}% | ${(forensicMetrics.fnr * 100).toStringAsFixed(1)}% | **${(fusionMetrics.fnr * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **F1-Score** | ${(neuralMetrics.f1 * 100).toStringAsFixed(1)}% | ${(forensicMetrics.f1 * 100).toStringAsFixed(1)}% | **${(fusionMetrics.f1 * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **ROC-AUC** | ${(neuralMetrics.rocAuc * 100).toStringAsFixed(1)}% | ${(forensicMetrics.rocAuc * 100).toStringAsFixed(1)}% | **${(fusionMetrics.rocAuc * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **PR-AUC** | ${(neuralMetrics.prAuc * 100).toStringAsFixed(1)}% | ${(forensicMetrics.prAuc * 100).toStringAsFixed(1)}% | **${(fusionMetrics.prAuc * 100).toStringAsFixed(1)}%** |');
    buffer.writeln('| **Brier Score (lower=best)** | ${neuralMetrics.brierScore.toStringAsFixed(4)} | ${forensicMetrics.brierScore.toStringAsFixed(4)} | **${fusionMetrics.brierScore.toStringAsFixed(4)}** |');
    buffer.writeln('| **ECE (Calibration Error)** | ${neuralMetrics.ece.toStringAsFixed(4)} | ${forensicMetrics.ece.toStringAsFixed(4)} | **${fusionMetrics.ece.toStringAsFixed(4)}** |');
    buffer.writeln('| **Confusion Matrix** | TP=${neuralMetrics.tp} FP=${neuralMetrics.fp} TN=${neuralMetrics.tn} FN=${neuralMetrics.fn} | TP=${forensicMetrics.tp} FP=${forensicMetrics.fp} TN=${forensicMetrics.tn} FN=${forensicMetrics.fn} | TP=${fusionMetrics.tp} FP=${fusionMetrics.fp} TN=${fusionMetrics.tn} FN=${fusionMetrics.fn} |');
    buffer.writeln();

    buffer.writeln('## 2. Generator Breakdown & Holdouts');
    buffer.writeln('| Generator | Samples | Neural Acc | Forensic Acc | Fusion Acc | Fusion FPR | Fusion Recall |');
    buffer.writeln('|---|---|---|---|---|---|---|');
    for (final g in generatorBreakdown) {
      buffer.writeln('| **${g.categoryName}** | ${g.sampleCount} | ${(g.neuralAccuracy * 100).toStringAsFixed(1)}% | ${(g.forensicAccuracy * 100).toStringAsFixed(1)}% | **${(g.fusionAccuracy * 100).toStringAsFixed(1)}%** | ${(g.fusionFpr * 100).toStringAsFixed(1)}% | ${(g.fusionRecall * 100).toStringAsFixed(1)}% |');
    }
    buffer.writeln();

    buffer.writeln('## 3. Transformation & Attack Robustness');
    buffer.writeln('| Transformation / Attack | Samples | Neural Acc | Forensic Acc | Fusion Acc | Fusion FPR | Fusion Recall |');
    buffer.writeln('|---|---|---|---|---|---|---|');
    for (final t in transformBreakdown) {
      buffer.writeln('| **${t.categoryName}** | ${t.sampleCount} | ${(t.neuralAccuracy * 100).toStringAsFixed(1)}% | ${(t.forensicAccuracy * 100).toStringAsFixed(1)}% | **${(t.fusionAccuracy * 100).toStringAsFixed(1)}%** | ${(t.fusionFpr * 100).toStringAsFixed(1)}% | ${(t.fusionRecall * 100).toStringAsFixed(1)}% |');
    }
    buffer.writeln();

    buffer.writeln('## 4. Domain Breakdown (Human Diversity)');
    buffer.writeln('| Domain | Samples | Neural Acc | Forensic Acc | Fusion Acc | Fusion FPR | Fusion Recall |');
    buffer.writeln('|---|---|---|---|---|---|---|');
    for (final d in domainBreakdown) {
      buffer.writeln('| **${d.categoryName}** | ${d.sampleCount} | ${(d.neuralAccuracy * 100).toStringAsFixed(1)}% | ${(d.forensicAccuracy * 100).toStringAsFixed(1)}% | **${(d.fusionAccuracy * 100).toStringAsFixed(1)}%** | ${(d.fusionFpr * 100).toStringAsFixed(1)}% | ${(d.fusionRecall * 100).toStringAsFixed(1)}% |');
    }
    buffer.writeln();

    if (throughputBenchmarks.isNotEmpty) {
      buffer.writeln('## 5. Performance Latency & Scaling');
      buffer.writeln('| Scale | Words | Neural Latency | Forensic Latency | Total Fusion Latency | Throughput |');
      buffer.writeln('|---|---|---|---|---|---|');
      for (final b in throughputBenchmarks) {
        buffer.writeln('| **${b.label}** | ${b.wordCount} | ${b.neuralLatency.inMilliseconds}ms | ${b.forensicLatency.inMilliseconds}ms | **${b.fusionLatency.inMilliseconds}ms** | ${b.wordsPerSecond.toStringAsFixed(0)} w/s |');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'totalSamples': totalSamples,
        'inconclusiveSamples': inconclusiveSamples,
        'neuralMetrics': neuralMetrics.toJson(),
        'forensicMetrics': forensicMetrics.toJson(),
        'fusionMetrics': fusionMetrics.toJson(),
        'generatorBreakdown': generatorBreakdown.map((g) => g.toJson()).toList(),
        'transformBreakdown': transformBreakdown.map((t) => t.toJson()).toList(),
        'domainBreakdown': domainBreakdown.map((d) => d.toJson()).toList(),
        'throughputBenchmarks': throughputBenchmarks.map((b) => b.toJson()).toList(),
      };
}
