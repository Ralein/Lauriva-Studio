import '../../../../models/forensic/ai_authorship_evidence.dart';
import '../../../../models/forensic/forensic_scan_mode.dart';
import '../ai/neural/neural_detector_service.dart';
import '../forensic_engine.dart';
import 'evaluation_dataset.dart';
import 'evaluation_metrics_report.dart';

/// Master empirical evaluation harness for Lauriva 4.0 Dual-Stream Detection.
class DetectorEvaluationHarness {
  final ForensicEngine forensicEngine;
  final NeuralDetectorService neuralService;

  const DetectorEvaluationHarness({
    required this.forensicEngine,
    required this.neuralService,
  });

  /// Executes full evaluation across [dataset] comparing Neural, Forensic, and Dual-Stream Fusion.
  Future<EvaluationHarnessReport> evaluate(
    EvaluationDataset dataset, {
    bool runThroughputBenchmark = true,
    void Function(int current, int total)? onProgress,
  }) async {
    final neuralPredictions = <({double probability, bool groundTruth})>[];
    final forensicPredictions = <({double probability, bool groundTruth})>[];
    final fusionPredictions = <({double probability, bool groundTruth})>[];

    final sampleResults = <({
      String id,
      String domain,
      String generator,
      String transform,
      bool isAi,
      double neuralProb,
      double forensicProb,
      double fusionProb,
    })>[];

    int idx = 0;
    var inconclusive = 0;
    for (final sample in dataset.samples) {
      // 1. Run Neural Stream
      final neuralResult = await neuralService.analyze(text: sample.text);
      final neuralProb = neuralResult.percentage;

      // 2. Run Forensic Stream (38 features + GBDT)
      final forensicReport = forensicEngine.analyze(sample.text, mode: ForensicScanMode.fullForensic);
      final forensicProb = forensicReport.aiAuthorship.aiProbability;

      // 3. Run Dual-Stream Fusion
      final fusionReport = await forensicEngine.analyzeWithNeural(sample.text, neuralDetector: neuralService);
      final fusionProb = fusionReport.aiAuthorship.aiProbability;

      idx++;
      onProgress?.call(idx, dataset.length);

      // Texts too short for a verdict (< 40 words) are shown to users as
      // inconclusive, never as AI or human, so they are counted, not scored.
      if (fusionReport.aiAuthorship.authorshipClass == AuthorshipClass.inconclusive) {
        inconclusive++;
        continue;
      }
      neuralPredictions.add((probability: neuralProb, groundTruth: sample.isAi));
      forensicPredictions.add((probability: forensicProb, groundTruth: sample.isAi));
      fusionPredictions.add((probability: fusionProb, groundTruth: sample.isAi));

      sampleResults.add((
        id: sample.id,
        domain: sample.domain,
        generator: sample.generator,
        transform: sample.transformation,
        isAi: sample.isAi,
        neuralProb: neuralProb,
        forensicProb: forensicProb,
        fusionProb: fusionProb,
      ));
    }

    // 4. Compute Stream Metrics
    final neuralMetrics = StreamMetrics.compute(
      streamName: 'Neural Transformer Student',
      predictions: neuralPredictions,
    );
    final forensicMetrics = StreamMetrics.compute(
      streamName: '38-Feature Stylometric Engine',
      predictions: forensicPredictions,
    );
    final fusionMetrics = StreamMetrics.compute(
      streamName: 'Dual-Stream Evidence Fusion',
      predictions: fusionPredictions,
    );

    // 5. Compute Partitions Breakdown
    final domainBreakdown = _computeCategoryBreakdown(sampleResults, (r) => r.domain);
    final generatorBreakdown = _computeCategoryBreakdown(sampleResults, (r) => r.generator);
    final transformBreakdown = _computeCategoryBreakdown(sampleResults, (r) => r.transform);

    // 6. Run Scale Latency Benchmarks
    final throughputRecords = <ThroughputBenchmarkRecord>[];
    if (runThroughputBenchmark) {
      throughputRecords.addAll(await _benchmarkThroughput());
    }

    return EvaluationHarnessReport(
      timestamp: DateTime.now(),
      totalSamples: dataset.length,
      inconclusiveSamples: inconclusive,
      neuralMetrics: neuralMetrics,
      forensicMetrics: forensicMetrics,
      fusionMetrics: fusionMetrics,
      domainBreakdown: domainBreakdown,
      generatorBreakdown: generatorBreakdown,
      transformBreakdown: transformBreakdown,
      throughputBenchmarks: throughputRecords,
    );
  }

  List<CategoryBreakdown> _computeCategoryBreakdown(
    List<({
      String id,
      String domain,
      String generator,
      String transform,
      bool isAi,
      double neuralProb,
      double forensicProb,
      double fusionProb,
    })> results,
    String Function(dynamic) keySelector,
  ) {
    final groups = <String, List<dynamic>>{};
    for (final r in results) {
      final key = keySelector(r);
      groups.putIfAbsent(key, () => []).add(r);
    }

    final breakdowns = <CategoryBreakdown>[];
    for (final entry in groups.entries) {
      final items = entry.value;
      int neuralCorrect = 0;
      int forensicCorrect = 0;
      int fusionCorrect = 0;
      int fusionFp = 0;
      int fusionTn = 0;
      int fusionTp = 0;
      int fusionFn = 0;

      for (final item in items) {
        final isAi = item.isAi as bool;
        final neuralAi = (item.neuralProb as double) >= 50.0;
        final forensicAi = (item.forensicProb as double) >= 50.0;
        final fusionAi = (item.fusionProb as double) >= 50.0;

        if (neuralAi == isAi) neuralCorrect++;
        if (forensicAi == isAi) forensicCorrect++;
        if (fusionAi == isAi) fusionCorrect++;

        if (fusionAi && isAi) fusionTp++;
        if (fusionAi && !isAi) fusionFp++;
        if (!fusionAi && !isAi) fusionTn++;
        if (!fusionAi && isAi) fusionFn++;
      }

      final count = items.length;
      final fusionFpr = (fusionFp + fusionTn) > 0 ? fusionFp / (fusionFp + fusionTn) : 0.0;
      final fusionRecall = (fusionTp + fusionFn) > 0 ? fusionTp / (fusionTp + fusionFn) : 1.0;

      breakdowns.add(CategoryBreakdown(
        categoryName: entry.key,
        sampleCount: count,
        neuralAccuracy: count > 0 ? neuralCorrect / count : 0.0,
        forensicAccuracy: count > 0 ? forensicCorrect / count : 0.0,
        fusionAccuracy: count > 0 ? fusionCorrect / count : 0.0,
        fusionFpr: fusionFpr,
        fusionRecall: fusionRecall,
      ));
    }

    return breakdowns;
  }

  Future<List<ThroughputBenchmarkRecord>> _benchmarkThroughput() async {
    final records = <ThroughputBenchmarkRecord>[];
    final scales = [
      (label: 'Standard Short (500 words)', wordTarget: 500),
      (label: 'Article Scale (2,000 words)', wordTarget: 2000),
      (label: 'Document Scale (5,000 words)', wordTarget: 5000),
    ];

    const paragraphUnit = '''
Furthermore, it is crucial to delve into the transformative tapestry of modern algorithmic architectures.
Comprehensive data pipelines play a pivotal role in spearheading dynamic digital ecosystems across diverse applications.
Moreover, multifaceted synergies underscore the overarching significance of seamless computational integration.
These advancements serve as a testament to the ever-evolving nature of automated machine learning systems.
''';

    for (final s in scales) {
      final repeats = (s.wordTarget / 50).ceil();
      final text = List.generate(repeats, (_) => paragraphUnit).join('\n\n');
      final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      // 1. Measure Neural Latency
      final nWatch = Stopwatch()..start();
      await neuralService.analyze(text: text);
      nWatch.stop();

      // 2. Measure Forensic Latency
      final fWatch = Stopwatch()..start();
      forensicEngine.analyze(text, mode: ForensicScanMode.fullForensic);
      fWatch.stop();

      // 3. Measure Dual-Stream Fusion Latency
      final fusionWatch = Stopwatch()..start();
      await forensicEngine.analyzeWithNeural(text, neuralDetector: neuralService);
      fusionWatch.stop();

      final totalSeconds = fusionWatch.elapsedMilliseconds / 1000.0;
      final wps = totalSeconds > 0 ? wordCount / totalSeconds : 0.0;

      records.add(ThroughputBenchmarkRecord(
        label: s.label,
        wordCount: wordCount,
        neuralLatency: nWatch.elapsed,
        forensicLatency: fWatch.elapsed,
        fusionLatency: fusionWatch.elapsed,
        wordsPerSecond: wps,
      ));
    }

    return records;
  }
}
