import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/evaluation/detector_evaluation_harness.dart';
import 'package:lauriva/services/forensic/evaluation/evaluation_dataset.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/fusion/probability_calibrator.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';

import 'recorded_neural_runner.dart';

void main() {
  group('Lauriva 4.0 Detector Evaluation Harness Suite', () {
    late PureDartTokenizer tokenizer;
    late NeuralDetectorService neuralService;
    late ForensicEngine forensicEngine;
    late DetectorEvaluationHarness harness;

    setUp(() {
      const vocabStr = '''
[PAD]
[UNK]
[CLS]
[SEP]
the
of
and
in
to
a
is
that
for
it
as
was
with
be
by
on
not
he
i
this
are
furthermore
moreover
crucial
pivotal
delve
tapestry
transformative
paradigm
foster
comprehensive
ever-evolving
multifaceted
indispensable
interplay
underscores
significance
overarching
cornerstone
vital
nuanced
holistic
synergy
seamless
robust
groundbreaking
intricate
intricacies
spearhead
harness
elevate
catalyst
unprecedented
quintessential
paramount
culmination
testament
burgeoning
profound
unravel
illuminate
orchestrate
resonate
epitome
beacon
nexus
plethora
myriad
panacea
concomitant
ubiquitous
embarks
navigating
delving
transcends
showcased
manifests
exemplifies
amplifies
bolsters
underpins
encapsulates
epitomizes
crystallizes
synthesizes
delineates
juxtaposes
articulates
accentuates
elucidates
coalesces
##ing
##ed
##ly
##tion
##s
##es
##ment
##able
##ible
##al
##ic
##ive
##ous
''';
      tokenizer = PureDartTokenizer.fromVocabString(vocabStr);
      neuralService = NeuralDetectorService(
        runner: RecordedNeuralRunner(),
        tokenizer: tokenizer,
        config: NeuralModelRegistry.getConfig(ForensicCoordinatorService.bundledModelVersion)!,
      );
      forensicEngine = ForensicEngine(neuralDetector: neuralService);
      harness = DetectorEvaluationHarness(
        forensicEngine: forensicEngine,
        neuralService: neuralService,
      );
    });

    test('Runs master evaluation harness on multi-generator corpus', () async {
      final dataset = EvaluationDataset.curatedStandardCorpus();
      final report = await harness.evaluate(dataset);

      // Print full formatted report
      // ignore: avoid_print
      print(report.toMarkdown());

      // Assert overall stream performance
      expect(report.totalSamples, equals(23));
      // Sub-40-word samples get no verdict in the app, so they are not scored.
      expect(report.inconclusiveSamples, equals(6));
      expect(report.fusionMetrics.accuracy, greaterThanOrEqualTo(0.85));
      // Modern-LLM corpus the stylometric stream was tuned on: fusion must not
      // add false positives and must stay well-ranked. Held-out gains from the
      // trained transformer are asserted in heldout_validation_benchmark_test.dart.
      expect(report.fusionMetrics.fpr, lessThanOrEqualTo(0.10));
      expect(report.fusionMetrics.fpr, lessThanOrEqualTo(report.forensicMetrics.fpr));
      expect(report.fusionMetrics.recall, greaterThanOrEqualTo(0.85));
      expect(report.fusionMetrics.rocAuc, greaterThanOrEqualTo(0.85));
      expect(report.fusionMetrics.brierScore, lessThanOrEqualTo(0.10));

      // Assert breakdowns are populated
      expect(report.domainBreakdown.isNotEmpty, isTrue);
      expect(report.generatorBreakdown.isNotEmpty, isTrue);
      expect(report.transformBreakdown.isNotEmpty, isTrue);
      expect(report.throughputBenchmarks.length, equals(3));
    });

    test('Evaluates generator holdout partitioning for unseen generators', () async {
      final dataset = EvaluationDataset.curatedStandardCorpus();
      final holdoutSplit = dataset.splitHoldout('mistral_large');

      expect(holdoutSplit.holdout.samples.isNotEmpty, isTrue);
      expect(holdoutSplit.train.samples.length, equals(dataset.length - holdoutSplit.holdout.samples.length));

      final holdoutReport = await harness.evaluate(holdoutSplit.holdout, runThroughputBenchmark: false);
      // Unseen generator should still be caught reliably
      expect(holdoutReport.fusionMetrics.recall, greaterThanOrEqualTo(0.80));
    });

    test('Fits Platt probability calibrator to minimize empirical calibration error (ECE)', () {
      // Mock validation scores exhibiting raw miscalibration
      final validationPairs = <({double rawScore, bool groundTruth})>[
        (rawScore: 0.92, groundTruth: true),
        (rawScore: 0.88, groundTruth: true),
        (rawScore: 0.75, groundTruth: true),
        (rawScore: 0.65, groundTruth: true),
        (rawScore: 0.58, groundTruth: true),
        (rawScore: 0.42, groundTruth: false),
        (rawScore: 0.30, groundTruth: false),
        (rawScore: 0.22, groundTruth: false),
        (rawScore: 0.15, groundTruth: false),
        (rawScore: 0.08, groundTruth: false),
      ];

      final calibrator = ProbabilityCalibrator.fit(validationPairs);
      expect(calibrator.a, greaterThan(0.0));

      final calibrated09 = calibrator.calibrate(0.92);
      final calibrated01 = calibrator.calibrate(0.08);

      expect(calibrated09, greaterThan(0.80));
      expect(calibrated01, lessThan(0.20));
    });
  });
}
