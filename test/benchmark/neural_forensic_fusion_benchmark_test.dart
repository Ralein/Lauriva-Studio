import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_detector_service.dart';
import 'package:lauriva/services/forensic/ai/neural/onnx_neural_runner.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_model_registry.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';

import 'recorded_neural_runner.dart';

class BenchmarkSample {
  final String id;
  final String text;
  final bool isAi; // Ground truth: true = AI, false = Human
  final String domain;
  final String generatorOrSource;
  final String transform;

  const BenchmarkSample({
    required this.id,
    required this.text,
    required this.isAi,
    required this.domain,
    required this.generatorOrSource,
    this.transform = 'raw',
  });
}

class EvaluationMetrics {
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

  const EvaluationMetrics({
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
  });

  static EvaluationMetrics compute(List<({double probability, bool groundTruth})> predictions) {
    int tp = 0;
    int fp = 0;
    int tn = 0;
    int fn = 0;
    double brierSum = 0.0;

    for (final p in predictions) {
      final y = p.groundTruth ? 1.0 : 0.0;
      final pred01 = (p.probability / 100.0).clamp(0.0, 1.0);
      brierSum += pow(pred01 - y, 2);

      final isPredictedAi = pred01 >= 0.50;
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

    // Compute ROC-AUC via Mann-Whitney U statistic
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

    // Compute PR-AUC (Average Precision)
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

    // Compute Expected Calibration Error (ECE) across 10 bins
    const numBins = 10;
    double ece = 0.0;
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
        ece += (binItems.length / total) * (binAvgAcc - binAvgConf).abs();
      }
    }

    return EvaluationMetrics(
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
      ece: ece,
    );
  }
}

void main() {
  group('Frontier Dual-Stream Empirical Benchmark Suite', () {
    late PureDartTokenizer tokenizer;
    late NeuralDetectorService neuralService;
    late ForensicEngine forensicEngine;

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
    });

    final benchmarkCorpus = <BenchmarkSample>[
      // ─────────────────────────────────────────────────────────────────────────
      // 1. HUMAN SAMPLES: Academic, Technical, Narrative, Journalism -- published
      //    human text (tool/eval/build_benchmark_humans.py); the hand-written
      //    originals were AI-assisted. No licensed ESL source, so no ESL sample.
      // ─────────────────────────────────────────────────────────────────────────
      // Verifiably human: arXiv metadata (CC0) / HAP-E (MIT).
      const BenchmarkSample(
        id: 'human_academic_01',
        isAi: false,
        domain: 'academic',
        generatorOrSource: 'hape_academic_human',
        text: r'''
Firstly, at a physiological level, the release of endogenous opioids (a correlate of high positive affect) could dampen HPA and ANS responses to stress [15,16]. At a cognitive level, positive affect may facilitate creative problem solving or the appraisal of a stressful situation as an opportunity or challenge [17,18].
''',
      ),
      // Verifiably human: HAP-E (MIT).
      const BenchmarkSample(
        id: 'human_narrative_02',
        isAi: false,
        domain: 'narrative',
        generatorOrSource: 'hape_fiction_human',
        text: r'''
Devere, isolated as it was from the main route of travel (the Santa Fe stages still following the more northern trail), heard merely rumors of the prevailing condition through tarrying hunters, and possibly an occasional army courier, yet soon realized the gravity of the situation because of the almost total cessation of travel by way of the Cimarron and the growing insolence of the surrounding Comanches.
''',
      ),
      // Verifiably human: HAP-E (MIT).
      const BenchmarkSample(
        id: 'human_journalism_04',
        isAi: false,
        domain: 'journalism',
        generatorOrSource: 'hape_news_human',
        text: r'''
At the end of the day, the political parties will do what they can" for votes, he says. And with what he's seen so far when it comes to immigration reform, Zenteno says if he ever had a chance to vote in the United States, he wouldn't cast a ballot for Democrats or Republicans. Ana, 20: Everything is complicated .
''',
      ),
      // Verifiably human: arXiv metadata (CC0).
      const BenchmarkSample(
        id: 'human_technical_05',
        isAi: false,
        domain: 'technical',
        generatorOrSource: 'arxiv_cs_human',
        text: r'''
There are many classes of mathematical problems which give rise to matrices, where a large number of the elements are zero. In this case it makes sense to have a special matrix type to handle this class of problems where only the non-zero elements of the matrix are stored.
''',
      ),

      // ─────────────────────────────────────────────────────────────────────────
      // 2. AI SAMPLES: GPT-4o, Claude 3.5, Gemini 2.0, DeepSeek-R1, Llama 3.3
      // ─────────────────────────────────────────────────────────────────────────
      const BenchmarkSample(
        id: 'ai_gpt4o_01',
        isAi: true,
        domain: 'academic',
        generatorOrSource: 'GPT-4o',
        text: '''
Furthermore, it is crucial to delve into the transformative tapestry of modern algorithmic paradigms.
Comprehensive data infrastructures play a pivotal role in spearheading dynamic digital ecosystems across industries.
Moreover, multifaceted synergies underscore the overarching significance of seamless computational integration.
These multifaceted advancements serve as a testament to the ever-evolving nature of artificial intelligence.
''',
      ),
      const BenchmarkSample(
        id: 'ai_claude35_02',
        isAi: true,
        domain: 'technical_policy',
        generatorOrSource: 'Claude-3.5-Sonnet',
        text: '''
Navigating the complex landscape of regulatory compliance requires a holistic understanding of governance frameworks.
At its core, the interplay between technological innovation and policy enforcement highlights key considerations.
Organizations must foster robust operational pipelines that seamlessly align with emerging compliance standards.
Ultimately, establishing transparent auditing mechanisms stands as an indispensable cornerstone of long-term viability.
''',
      ),
      const BenchmarkSample(
        id: 'ai_deepseek_03',
        isAi: true,
        domain: 'education',
        generatorOrSource: 'DeepSeek-R1',
        text: '''
Delving into pedagogical methodologies reveals a plethora of innovative strategies designed to elevate student engagement.
A nuanced synthesis of interactive tools underpins the profound impact of modern digital learning environments.
Consequently, educators are empowered to orchestrate customized instructional paths that resonate across diverse classrooms.
This burgeoning paradigm encapsulates the quintessential principles of progressive educational reform.
''',
      ),
      const BenchmarkSample(
        id: 'ai_llama33_04',
        isAi: true,
        domain: 'healthcare',
        generatorOrSource: 'Llama-3.3-70B',
        text: '''
In today's ever-evolving healthcare landscape, telemedicine plays a vital and multifaceted role in patient outcomes.
It is important to remember that digital diagnostic tools foster unprecedented diagnostic precision and care delivery.
Furthermore, integrating predictive analytics bolsters clinician decision-making across clinical workflows.
This holistic synergy stands as a beacon of modern biomedical innovation.
''',
      ),

      // ─────────────────────────────────────────────────────────────────────────
      // 3. TRANSFORMED & HYBRID SAMPLES (Human-Edited, Paraphrased, Mixed)
      // ─────────────────────────────────────────────────────────────────────────
      const BenchmarkSample(
        id: 'ai_humanized_05',
        isAi: true,
        domain: 'business',
        generatorOrSource: 'GPT-4o',
        transform: 'humanized_prompting',
        text: '''
Looking at digital commerce today, rapid growth is changing how retail companies interact with everyday shoppers.
Supply chains require constant monitoring because delivery bottlenecks can quickly hurt customer satisfaction.
Companies that adopt adaptive inventory forecasting gain a measurable advantage over slower competitors.
In practice, combining direct customer feedback with automated fulfillment keeps operational costs under control.
''',
      ),
      const BenchmarkSample(
        id: 'ai_edited_06',
        isAi: true,
        domain: 'finance',
        generatorOrSource: 'Claude-3.5-Sonnet',
        transform: 'human_edited',
        text: '''
Delving into monetary policy adjustments underscores the complex mechanisms behind international currency stabilization.
Central banks must orchestrate liquidity interventions while managing interest rate differentials across major trading hubs.
A nuanced assessment of bond yields provides clear signals regarding investor sentiment and long-term economic trajectories.
''',
      ),
      const BenchmarkSample(
        id: 'ai_paraphrased_07',
        isAi: true,
        domain: 'psychology',
        generatorOrSource: 'Gemini-2.0-Flash',
        transform: 'paraphrased',
        text: '''
Cognitive behavioral interventions foster transformative changes in emotional regulation and interpersonal adaptability.
The profound interplay between mindfulness practices and neuroplasticity reinforces the cornerstone of modern psychotherapeutic models.
Consequently, clinicians leverage multifaceted diagnostics to elevate individualized treatment efficacy.
''',
      ),
      const BenchmarkSample(
        id: 'mixed_authorship_08',
        isAi: true,
        domain: 'mixed_essay',
        generatorOrSource: 'Human+GPT4o',
        transform: 'mixed_paragraph',
        text: '''
We gathered at five in the morning to pack the survey equipment into our field truck before the summer heat peaked.
Furthermore, it is crucial to delve into the transformative tapestry of ecological biodiversity assessment protocols.
Comprehensive field measurements spearhead sustainable environmental management across regional habitats.
''',
      ),
      const BenchmarkSample(
        id: 'short_text_ai_09',
        isAi: true,
        domain: 'short_ai',
        generatorOrSource: 'Command-R+',
        transform: 'raw_short',
        text: '''
Moreover, multifaceted synergies underscore the overarching significance of seamless computational integration across platforms.
''',
      ),
      // Verifiably human: HAP-E (MIT).
      const BenchmarkSample(
        id: 'short_text_human_10',
        isAi: false,
        domain: 'short_human',
        generatorOrSource: 'hape_blog_human',
        transform: 'raw_short',
        text: r'''
I'm not the smartest person in the world, but I took that as a sign that I needed to stop.
''',
      ),
      const BenchmarkSample(
        id: 'unseen_mistral_11',
        isAi: true,
        domain: 'unseen_generator',
        generatorOrSource: 'Mistral-Large-2411',
        transform: 'raw',
        text: '''
Navigating the intricacies of distributed ledger technology requires a robust grasp of consensus protocols.
Cryptographic hash validation serves as a vital cornerstone for ensuring data integrity across decentralized network topologies.
Consequently, enterprise architectures harness these paradigms to bolster fault-tolerant transaction processing.
''',
      ),
      // Verifiably human: HAP-E (MIT).
      const BenchmarkSample(
        id: 'human_creative_12',
        isAi: false,
        domain: 'creative',
        generatorOrSource: 'hape_fiction_human',
        transform: 'raw',
        text: r'''
But presently a kind of long sigh ran through Dept. A and in another moment a perfect babel of sounds arose and swelled upon the air. There was the mooing of cows, the bleating of woolly sheep, the crying of baby dolls, the choo-choo of iron steam cars.
''',
      ),
    ];

    test('Runs comparative empirical benchmark: Neural vs Forensic vs Dual-Stream Fusion', () async {
      final neuralPredictions = <({double probability, bool groundTruth})>[];
      final forensicPredictions = <({double probability, bool groundTruth})>[];
      final fusionPredictions = <({double probability, bool groundTruth})>[];

      for (final sample in benchmarkCorpus) {
        // 1. Run Neural Stream
        final neuralResult = await neuralService.analyze(text: sample.text);
        final neuralProb = neuralResult.percentage;
        neuralPredictions.add((probability: neuralProb, groundTruth: sample.isAi));

        // 2. Run Forensic Stream (38 features + GBDT)
        final forensicReport = forensicEngine.analyze(sample.text, mode: ForensicScanMode.fullForensic);
        final forensicProb = forensicReport.aiAuthorship.aiProbability;
        forensicPredictions.add((probability: forensicProb, groundTruth: sample.isAi));

        // 3. Run Dual-Stream Fusion
        final fusionReport = await forensicEngine.analyzeWithNeural(sample.text, neuralDetector: neuralService);
        final fusionProb = fusionReport.aiAuthorship.aiProbability;
        fusionPredictions.add((probability: fusionProb, groundTruth: sample.isAi));
      }

      final neuralMetrics = EvaluationMetrics.compute(neuralPredictions);
      final forensicMetrics = EvaluationMetrics.compute(forensicPredictions);
      final fusionMetrics = EvaluationMetrics.compute(fusionPredictions);

      // ignore: avoid_print
      print('''
====================================================================================================
📊 LAURIVA 4.0 EMPIRICAL BENCHMARK: NEURAL vs FORENSIC vs DUAL-STREAM FUSION
====================================================================================================
METRIC                   STREAM A: NEURAL        STREAM B: FORENSIC      DUAL-STREAM FUSION
----------------------------------------------------------------------------------------------------
Accuracy:                ${(neuralMetrics.accuracy * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.accuracy * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.accuracy * 100).toStringAsFixed(1)}%
Precision:               ${(neuralMetrics.precision * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.precision * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.precision * 100).toStringAsFixed(1)}%
Recall (AI Catch):       ${(neuralMetrics.recall * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.recall * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.recall * 100).toStringAsFixed(1)}%
False Positive Rate:     ${(neuralMetrics.fpr * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.fpr * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.fpr * 100).toStringAsFixed(1)}%
False Negative Rate:     ${(neuralMetrics.fnr * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.fnr * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.fnr * 100).toStringAsFixed(1)}%
F1-Score:                ${(neuralMetrics.f1 * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.f1 * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.f1 * 100).toStringAsFixed(1)}%
ROC-AUC:                 ${(neuralMetrics.rocAuc * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.rocAuc * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.rocAuc * 100).toStringAsFixed(1)}%
PR-AUC:                  ${(neuralMetrics.prAuc * 100).toStringAsFixed(1)}%                   ${(forensicMetrics.prAuc * 100).toStringAsFixed(1)}%                   ${(fusionMetrics.prAuc * 100).toStringAsFixed(1)}%
Brier Score (lower=best):${neuralMetrics.brierScore.toStringAsFixed(4)}                 ${forensicMetrics.brierScore.toStringAsFixed(4)}                 ${fusionMetrics.brierScore.toStringAsFixed(4)}
ECE (Calibration Error): ${neuralMetrics.ece.toStringAsFixed(4)}                 ${forensicMetrics.ece.toStringAsFixed(4)}                 ${fusionMetrics.ece.toStringAsFixed(4)}
Confusion Matrix:        TP=${neuralMetrics.tp} FP=${neuralMetrics.fp} TN=${neuralMetrics.tn} FN=${neuralMetrics.fn}    TP=${forensicMetrics.tp} FP=${forensicMetrics.fp} TN=${forensicMetrics.tn} FN=${forensicMetrics.fn}    TP=${fusionMetrics.tp} FP=${fusionMetrics.fp} TN=${fusionMetrics.tn} FN=${fusionMetrics.fn}
====================================================================================================
''');

      // Fusion must hold accuracy without ever adding false accusations over
      // the stylometric stream. The stack is neural-dominant since
      // plagiarism_v2 (stylometry adds no held-out signal on top of it), so
      // fusion need only match the neural stream, not beat it. The neural
      // stream's gains are asserted on held-out data in
      // heldout_validation_benchmark_test.dart.
      expect(fusionMetrics.accuracy, greaterThanOrEqualTo(0.85));
      expect(fusionMetrics.recall, greaterThanOrEqualTo(0.85));
      expect(fusionMetrics.fpr, lessThanOrEqualTo(forensicMetrics.fpr));
      expect(fusionMetrics.accuracy, greaterThanOrEqualTo(neuralMetrics.accuracy));
    });

    test('Validates end-to-end tokenizer tensor contracts and sentence offset alignment', () {
      final text = 'First sentence. Second sentence delves into transformative paradigms.';
      final sents = RuleBasedSentenceSegmenter().segment(text);
      final tokenized = tokenizer.tokenize(text: text, sentences: sents);

      expect(tokenized.inputIds.first, equals(tokenizer.clsTokenId));
      expect(tokenized.inputIds.contains(tokenizer.sepTokenId), isTrue);
      expect(tokenized.attentionMask.length, equals(tokenizer.maxSequenceLength));
      expect(tokenized.tokenTypeIds.length, equals(tokenizer.maxSequenceLength));

      for (final span in tokenized.tokenSpans) {
        expect(span.startOffset, inInclusiveRange(0, text.length));
        expect(span.endOffset, inInclusiveRange(0, text.length));
        expect(span.sentenceIndex, inInclusiveRange(0, sents.length - 1));
      }
    });

    test('Validates model logit ordering and bounded probability guarantees', () {
      expect(StandardNeuralRunner.softmaxAiProbability(2.0, -2.0), lessThan(0.05));
      expect(StandardNeuralRunner.softmaxAiProbability(-2.0, 2.0), greaterThan(0.95));
      expect(StandardNeuralRunner.softmaxAiProbability(0.0, 0.0), closeTo(0.5, 0.001));

      for (double p = 0.0; p <= 1.0; p += 0.05) {
        final entropy = StandardNeuralRunner.binaryEntropy(p);
        expect(entropy, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
