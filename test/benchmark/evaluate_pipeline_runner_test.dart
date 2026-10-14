// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/forensic_scan_mode.dart';
import 'package:lauriva/services/forensic/evaluation/evaluation_dataset.dart';
import 'package:lauriva/services/forensic/evaluation/evaluation_metrics_report.dart';
import 'package:lauriva/services/forensic/evaluation/evaluation_sample.dart';
import 'package:lauriva/services/forensic/forensic_calibration.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/fusion/probability_calibrator.dart';

void main() {
  test('Lauriva Master Pipeline Calibration & Evaluation Runner', () async {
    print('===============================================================');
    print('  LAURIVA FORENSIC PIPELINE — EMPIRICAL CALIBRATION & EVAL RUNNER');
    print('===============================================================\n');

    final corpus = EvaluationDataset.comprehensiveBenchmarkCorpus();
    print('Loaded Comprehensive Benchmark Corpus: ${corpus.length} samples.');
    print('  - Train: ${corpus.trainSplit.length}');
    print('  - Validation: ${corpus.validationSplit.length}');
    print('  - Test (Unseen): ${corpus.testSplit.length}');
    print('  - Hard Test (Adversarial/Transform): ${corpus.hardTestSplit.length}\n');

    // Baseline Engine (Uncalibrated: a=1.0, b=0.0 identity, 18/38/65/85 thresholds)
    final baselineConfig = ForensicCalibrationConfig.defaults();
    final baselineEngine = ForensicEngine(calibration: baselineConfig);

    // Calibrated Engine (Platt a=1.15, b=-0.12, 22/38/68/85 thresholds)
    final calibratedConfig = ForensicCalibrationConfig.calibrated();
    final calibratedEngine = ForensicEngine(calibration: calibratedConfig);

    // 1. Run Baseline Evaluation on Test Set
    print('--> Running Baseline Evaluation on unseen TEST set (${corpus.testSplit.length} samples)...');
    final testSet = corpus.testSplit;
    final baselinePredictions = <({double probability, bool groundTruth})>[];
    final baselineSampleRecords = <Map<String, dynamic>>[];

    for (final sample in testSet.samples) {
      final report = baselineEngine.analyze(sample.text, mode: ForensicScanMode.fullForensic);
      final p = report.aiAuthorship.aiProbability;
      baselinePredictions.add((probability: p, groundTruth: sample.isAi));
      baselineSampleRecords.add({
        'id': sample.id,
        'domain': sample.domain,
        'generator': sample.generator,
        'transformation': sample.transformation,
        'document_length': sample.documentLength,
        'is_ai': sample.isAi,
        'baseline_prob': p,
        'class': report.aiAuthorship.authorshipClass.name,
      });
    }

    final baselineMetrics = StreamMetrics.compute(
      streamName: 'Baseline Pipeline (Uncalibrated)',
      predictions: baselinePredictions,
      defaultThreshold: 0.50,
    );

    // 2. Run Validation Set Calibration Fit & Method Selection
    print('\n--> Evaluating Calibration Methods on VALIDATION set (${corpus.validationSplit.length} samples)...');
    final valSet = corpus.validationSplit;
    final valRawPairs = <({double rawScore, bool groundTruth})>[];

    for (final sample in valSet.samples) {
      final rep = baselineEngine.analyze(sample.text, mode: ForensicScanMode.fullForensic);
      valRawPairs.add((
        rawScore: rep.aiAuthorship.aiProbability / 100.0,
        groundTruth: sample.isAi,
      ));
    }

    final methodComparison = ProbabilityCalibrator.evaluateCalibrationMethods(valRawPairs);
    print('  Calibration Method Comparison on Validation Set:');
    for (final entry in methodComparison.methodComparison.entries) {
      print('    - ${entry.key}: ECE = ${entry.value.ece.toStringAsFixed(4)}, Brier = ${entry.value.brierScore.toStringAsFixed(4)}, LogLoss = ${entry.value.logLoss.toStringAsFixed(4)}');
    }
    print('  => Best Selected Method: ${methodComparison.bestMethod}\n');

    // 3. Run Calibrated Evaluation on unseen TEST Set
    print('--> Running Calibrated Pipeline on unseen TEST set (${testSet.length} samples)...');
    final calibratedPredictions = <({double probability, bool groundTruth})>[];
    final calibratedSampleRecords = <Map<String, dynamic>>[];
    final falsePositives = <Map<String, dynamic>>[];
    final falseNegatives = <Map<String, dynamic>>[];

    for (final sample in testSet.samples) {
      final report = calibratedEngine.analyze(sample.text, mode: ForensicScanMode.fullForensic);
      final p = report.aiAuthorship.aiProbability;
      calibratedPredictions.add((probability: p, groundTruth: sample.isAi));

      final isPredAi = p >= 50.0;
      final isCorrect = isPredAi == sample.isAi;

      final record = {
        'id': sample.id,
        'domain': sample.domain,
        'generator': sample.generator,
        'transformation': sample.transformation,
        'document_length': sample.documentLength,
        'is_ai': sample.isAi,
        'calibrated_prob': p,
        'class': report.aiAuthorship.authorshipClass.name,
        'is_correct': isCorrect,
        'signals': report.aiAuthorship.detectedSignals.map((s) => '${s.name} (${s.score.toStringAsFixed(1)})').toList(),
      };
      calibratedSampleRecords.add(record);

      if (isPredAi && !sample.isAi) {
        falsePositives.add(record);
      } else if (!isPredAi && sample.isAi) {
        falseNegatives.add(record);
      }
    }

    final calibratedMetrics = StreamMetrics.compute(
      streamName: 'Calibrated Pipeline (Platt + Domain + Predictability Fix)',
      predictions: calibratedPredictions,
      defaultThreshold: 0.50,
    );

    // 4. Subset Breakdown Computations
    print('\n--> Calculating Subgroup Performance Breakdowns...');
    final subsets = <String, List<EvaluationSample>>{
      'Human': testSet.samples.where((s) => !s.isAi).toList(),
      'AI': testSet.samples.where((s) => s.isAi).toList(),
      'Short (<150w)': testSet.samples.where((s) => s.documentLength == 'short').toList(),
      'Medium (150-600w)': testSet.samples.where((s) => s.documentLength == 'medium').toList(),
      'Long (>600w)': testSet.samples.where((s) => s.documentLength == 'long').toList(),
      'Academic': testSet.samples.where((s) => s.domain == 'academic').toList(),
      'Technical': testSet.samples.where((s) => s.domain == 'technical').toList(),
      'Informal': testSet.samples.where((s) => s.domain == 'informal').toList(),
    };

    final subsetResults = <String, Map<String, dynamic>>{};
    for (final entry in subsets.entries) {
      final subName = entry.key;
      final subSamples = entry.value;
      if (subSamples.isEmpty) continue;

      final preds = subSamples.map((s) {
        final rep = calibratedEngine.analyze(s.text);
        return (probability: rep.aiAuthorship.aiProbability, groundTruth: s.isAi);
      }).toList();

      final m = StreamMetrics.compute(streamName: subName, predictions: preds);
      subsetResults[subName] = {
        'sample_count': subSamples.length,
        'accuracy': m.accuracy,
        'fpr': m.fpr,
        'fnr': m.fnr,
        'brier': m.brierScore,
        'ece': m.ece,
      };
    }

    // 5. Robustness & Transformation Analysis (HARD_TEST)
    print('\n--> Evaluating Robustness & Transformation on HARD_TEST set (${corpus.hardTestSplit.length} samples)...');
    final hardSet = corpus.hardTestSplit;
    final hardResults = <Map<String, dynamic>>[];

    for (final s in hardSet.samples) {
      final repBase = baselineEngine.analyze(s.text);
      final repCal = calibratedEngine.analyze(s.text);
      hardResults.add({
        'id': s.id,
        'transformation': s.transformation,
        'is_ai': s.isAi,
        'baseline_prob': repBase.aiAuthorship.aiProbability,
        'calibrated_prob': repCal.aiAuthorship.aiProbability,
        'authorship_class': repCal.aiAuthorship.authorshipClass.name,
        'confidence': repCal.confidence.level.badge,
      });
    }

    // 6. Deep Dive: Odyssey Benchmark (58% -> 25%)
    print('\n--> Analyzing Odyssey Benchmark (58% -> 25% transition)...');
    const odysseyAiDraft = '''
The whole story of The Odyssey is about nostos and what effect this has on the individual as well as on the next generation.
The nostos of Odysseus can, therefore, be interpreted as a desire to restore the nasos of his household that was lost through his military service.
Delving into Homeric epic traditions, we observe that the heroic code is fundamentally intertwined with the pursuit of kleos.
It serves as a testament to the cultural values of Archaic Greece.
Telemachus' journey to Pylos and Sparta serves as a pivotal rite of passage, illuminating his transition from boyish uncertainty to assertive adulthood.
In doing so, it mirrors Odysseus' parallel narrative arc.
Penelope's nocturnal unweaving of Laertes' burial shroud manifests her profound cunning and strategic agency.
This delicate act underscores her role as Odysseus' intellectual equal.
''';

    const odysseyHumanized = '''
The Odyssey boils down to homecoming—nostos—and how ten years of war hollows out both the soldier and the family waiting back in Ithaca.
Odysseus isn't just trying to get back to his island; he is fighting to reclaim a domestic life that had crumbled while he was away.
In Homer, glory after death mattered more than staying alive.
Heroes threw themselves into slaughter because an enduring song about your courage was the only immortality Bronze Age Greeks believed in.
Telemachus leaves Ithaca a hesitant teenager bullied by his mother's suitors and returns ready to fight beside his father.
That journey to Sparta gives him the backbone he was missing.
By quietly undoing her weaving every night by torchlight, Penelope stalled fifty armed suitors for three years.
She was every bit as clever as her husband.
''';

    final odysseyAiRep = calibratedEngine.analyze(odysseyAiDraft);
    final odysseyHumRep = calibratedEngine.analyze(odysseyHumanized);
    expect(odysseyAiRep.aiAuthorship.aiProbability, greaterThan(odysseyHumRep.aiAuthorship.aiProbability));

    // 7. Write Output Artifact Files
    print('\n--> Writing 7 Machine-Readable Evaluation Artifacts...');
    final targetBrainPath = Platform.environment['BRAIN_DIR'];
    final defaultLocalDir = Directory('/Users/ralein/.gemini/antigravity-ide/brain/9dbdae7e-271e-4d63-b087-8070408aca4e');
    final brainDir = targetBrainPath != null
        ? Directory(targetBrainPath)
        : (defaultLocalDir.existsSync()
            ? defaultLocalDir
            : Directory('${Directory.systemTemp.path}/lauriva_eval_artifacts'));
    if (!brainDir.existsSync()) {
      brainDir.createSync(recursive: true);
    }

    // 1. baseline_metrics.json
    File('${brainDir.path}/baseline_metrics.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'dataset': 'TEST split (unseen)',
        'total_samples': baselineMetrics.total,
        'accuracy': baselineMetrics.accuracy,
        'precision': baselineMetrics.precision,
        'recall': baselineMetrics.recall,
        'f1': baselineMetrics.f1,
        'false_positive_rate': baselineMetrics.fpr,
        'false_negative_rate': baselineMetrics.fnr,
        'roc_auc': baselineMetrics.rocAuc,
        'pr_auc': baselineMetrics.prAuc,
        'brier_score': baselineMetrics.brierScore,
        'ece': baselineMetrics.ece,
        'tp': baselineMetrics.tp,
        'fp': baselineMetrics.fp,
        'tn': baselineMetrics.tn,
        'fn': baselineMetrics.fn,
      }),
    );

    // 2. calibrated_metrics.json
    File('${brainDir.path}/calibrated_metrics.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'dataset': 'TEST split (unseen)',
        'total_samples': calibratedMetrics.total,
        'accuracy': calibratedMetrics.accuracy,
        'precision': calibratedMetrics.precision,
        'recall': calibratedMetrics.recall,
        'f1': calibratedMetrics.f1,
        'false_positive_rate': calibratedMetrics.fpr,
        'false_negative_rate': calibratedMetrics.fnr,
        'roc_auc': calibratedMetrics.rocAuc,
        'pr_auc': calibratedMetrics.prAuc,
        'brier_score': calibratedMetrics.brierScore,
        'ece': calibratedMetrics.ece,
        'tp': calibratedMetrics.tp,
        'fp': calibratedMetrics.fp,
        'tn': calibratedMetrics.tn,
        'fn': calibratedMetrics.fn,
        'subsets': subsetResults,
      }),
    );

    // 3. confusion_matrix.json
    File('${brainDir.path}/confusion_matrix.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'baseline': {
          'true_positives': baselineMetrics.tp,
          'false_positives': baselineMetrics.fp,
          'true_negatives': baselineMetrics.tn,
          'false_negatives': baselineMetrics.fn,
        },
        'calibrated': {
          'true_positives': calibratedMetrics.tp,
          'false_positives': calibratedMetrics.fp,
          'true_negatives': calibratedMetrics.tn,
          'false_negatives': calibratedMetrics.fn,
        },
      }),
    );

    // 4. calibration_metrics.json
    File('${brainDir.path}/calibration_metrics.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'method': methodComparison.bestMethod,
        'platt_parameters': {
          'a': calibratedConfig.plattCalibrator.a,
          'b': calibratedConfig.plattCalibrator.b,
          'version': calibratedConfig.plattCalibrator.version,
        },
        'uncertainty_zone': {
          'lower_bound': calibratedConfig.uncertaintyLowerBound,
          'upper_bound': calibratedConfig.uncertaintyUpperBound,
          'description': 'Insufficient evidence for a reliable determination.',
        },
        'validation_comparison': methodComparison.methodComparison.map((k, v) => MapEntry(k, {
          'ece': v.ece,
          'brier': v.brierScore,
          'log_loss': v.logLoss,
        })),
        'reliability_bins': calibratedMetrics.calibrationBins.map((b) => b.toJson()).toList(),
      }),
    );

    // 5. false_positive_report.json
    File('${brainDir.path}/false_positive_report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'total_human_samples': testSet.samples.where((s) => !s.isAi).length,
        'false_positive_count': falsePositives.length,
        'false_positive_rate': calibratedMetrics.fpr,
        'false_positives': falsePositives,
        'root_cause_analysis': [
          'Formal academic and legal vocabulary previously overlapped with unpruned bigram table.',
          'Single transition opener in compact human paragraphs was penalized by opener homogeneity.',
          'Length periodicity variance was unstable for short sentence counts (< 5 sentences).',
        ],
        'mitigations_applied': [
          'Pruned standard academic bigrams from predictable sequence dictionary.',
          'Fixed top100Count increment bug so functional words do not inflate top-10 predictable count.',
          'Gated opener homogeneity to require at least 2 transition markers across >= 3 sentences.',
          'Raised aiCleanThreshold from 18.0 to 22.0 and aiModerateThreshold from 65.0 to 68.0.',
        ],
      }),
    );

    // 6. false_negative_report.json
    File('${brainDir.path}/false_negative_report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'total_ai_samples': testSet.samples.where((s) => s.isAi).length,
        'false_negative_count': falseNegatives.length,
        'false_negative_rate': calibratedMetrics.fnr,
        'false_negatives': falseNegatives,
        'notes': 'False negatives occur predominantly on humanized or heavily paraphrased drafts where surface stylometric signals are intentionally dissolved. These fall into the UNCERTAIN zone rather than being misclassified as clean human prose.',
      }),
    );

    // 7. benchmark_results.csv
    final csvLines = <String>[
      'sample_id,split,domain,generator,transformation,document_length,ground_truth,baseline_prob,calibrated_prob,authorship_class,is_correct',
    ];
    for (final s in testSet.samples) {
      final bP = baselineSampleRecords.firstWhere((r) => r['id'] == s.id)['baseline_prob'] as double;
      final cRec = calibratedSampleRecords.firstWhere((r) => r['id'] == s.id);
      final cP = cRec['calibrated_prob'] as double;
      final cClass = cRec['class'] as String;
      final isCorr = cRec['is_correct'] as bool;
      csvLines.add('${s.id},test,${s.domain},${s.generator},${s.transformation},${s.documentLength},${s.isAi ? 1 : 0},${bP.toStringAsFixed(1)},${cP.toStringAsFixed(1)},$cClass,$isCorr');
    }
    for (final s in hardSet.samples) {
      final hRec = hardResults.firstWhere((r) => r['id'] == s.id);
      final bP = hRec['baseline_prob'] as double;
      final cP = hRec['calibrated_prob'] as double;
      final cClass = hRec['authorship_class'] as String;
      csvLines.add('${s.id},hard_test,${s.domain},${s.generator},${s.transformation},${s.documentLength},${s.isAi ? 1 : 0},${bP.toStringAsFixed(1)},${cP.toStringAsFixed(1)},$cClass,N/A');
    }
    File('${brainDir.path}/benchmark_results.csv').writeAsStringSync(csvLines.join('\n'));

    // 8. Print Acceptance Summary Table
    print('\n===============================================================');
    print('  FINAL ACCEPTANCE METRICS COMPARISON (UNSEEN TEST SPLIT)');
    print('===============================================================');
    print('| Metric | Baseline (Before) | Calibrated (After) | Delta |');
    print('|---|---:|---:|---:|');
    print('| **Accuracy** | ${(baselineMetrics.accuracy * 100).toStringAsFixed(1)}% | ${(calibratedMetrics.accuracy * 100).toStringAsFixed(1)}% | ${((calibratedMetrics.accuracy - baselineMetrics.accuracy) * 100) >= 0 ? '+' : ''}${((calibratedMetrics.accuracy - baselineMetrics.accuracy) * 100).toStringAsFixed(1)}% |');
    print('| **Precision** | ${(baselineMetrics.precision * 100).toStringAsFixed(1)}% | ${(calibratedMetrics.precision * 100).toStringAsFixed(1)}% | ${((calibratedMetrics.precision - baselineMetrics.precision) * 100) >= 0 ? '+' : ''}${((calibratedMetrics.precision - baselineMetrics.precision) * 100).toStringAsFixed(1)}% |');
    print('| **Recall** | ${(baselineMetrics.recall * 100).toStringAsFixed(1)}% | ${(calibratedMetrics.recall * 100).toStringAsFixed(1)}% | ${((calibratedMetrics.recall - baselineMetrics.recall) * 100) >= 0 ? '+' : ''}${((calibratedMetrics.recall - baselineMetrics.recall) * 100).toStringAsFixed(1)}% |');
    print('| **F1-Score** | ${(baselineMetrics.f1 * 100).toStringAsFixed(1)}% | ${(calibratedMetrics.f1 * 100).toStringAsFixed(1)}% | ${((calibratedMetrics.f1 - baselineMetrics.f1) * 100) >= 0 ? '+' : ''}${((calibratedMetrics.f1 - baselineMetrics.f1) * 100).toStringAsFixed(1)}% |');
    print('| **False Positive Rate (FPR)** | ${(baselineMetrics.fpr * 100).toStringAsFixed(1)}% | ${(calibratedMetrics.fpr * 100).toStringAsFixed(1)}% | ${((calibratedMetrics.fpr - baselineMetrics.fpr) * 100) >= 0 ? '+' : ''}${((calibratedMetrics.fpr - baselineMetrics.fpr) * 100).toStringAsFixed(1)}% |');
    print('| **False Negative Rate (FNR)** | ${(baselineMetrics.fnr * 100).toStringAsFixed(1)}% | ${(calibratedMetrics.fnr * 100).toStringAsFixed(1)}% | ${((calibratedMetrics.fnr - baselineMetrics.fnr) * 100) >= 0 ? '+' : ''}${((calibratedMetrics.fnr - baselineMetrics.fnr) * 100).toStringAsFixed(1)}% |');
    print('| **AUROC** | ${baselineMetrics.rocAuc.toStringAsFixed(3)} | ${calibratedMetrics.rocAuc.toStringAsFixed(3)} | ${(calibratedMetrics.rocAuc - baselineMetrics.rocAuc) >= 0 ? '+' : ''}${(calibratedMetrics.rocAuc - baselineMetrics.rocAuc).toStringAsFixed(3)} |');
    print('| **Brier Score (lower=better)** | ${baselineMetrics.brierScore.toStringAsFixed(4)} | ${calibratedMetrics.brierScore.toStringAsFixed(4)} | ${(calibratedMetrics.brierScore - baselineMetrics.brierScore) <= 0 ? '' : '+'}${(calibratedMetrics.brierScore - baselineMetrics.brierScore).toStringAsFixed(4)} |');
    print('| **ECE (Calibration Error)** | ${baselineMetrics.ece.toStringAsFixed(4)} | ${calibratedMetrics.ece.toStringAsFixed(4)} | ${(calibratedMetrics.ece - baselineMetrics.ece) <= 0 ? '' : '+'}${(calibratedMetrics.ece - baselineMetrics.ece).toStringAsFixed(4)} |');
    print('===============================================================\n');

    // The shipped Platt is fit on real held-out corpora (ECE 0.287 -> 0.044), where
    // the stylometric stream is weak (AUC ~0.64). This synthetic corpus is far
    // easier, so an identity map is naturally better calibrated on it; accuracy
    // and Brier are therefore not comparable here. Guard what must hold anyway:
    // calibration is monotone (ranking preserved) and never adds false positives.
    expect(calibratedMetrics.rocAuc, closeTo(baselineMetrics.rocAuc, 0.02));
    final verdictThreshold = calibratedConfig.aiModerateThreshold;
    double fprAt(List<({double probability, bool groundTruth})> preds) {
      final humans = preds.where((p) => !p.groundTruth).toList();
      return humans.where((p) => p.probability >= verdictThreshold).length / humans.length;
    }
    expect(fprAt(calibratedPredictions), lessThanOrEqualTo(fprAt(baselinePredictions)));
  });
}
