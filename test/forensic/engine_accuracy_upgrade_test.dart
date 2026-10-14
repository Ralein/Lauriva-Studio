import 'dart:convert';
import 'dart:math';

import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/models/plagiarism_report.dart';
import 'package:lauriva/services/forensic/ai/sentence_attribution_model.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/humanizer/surgical_humanizer_bridge.dart';
import 'package:lauriva/services/forensic/sources/fuzzy_similarity_matcher.dart';
import 'package:lauriva/services/forensic/sources/shingle_matching_engine.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';
import 'package:lauriva/services/llm_service.dart';
import 'package:lauriva/services/plagiarism_detector_service.dart';
import 'package:lauriva/services/text_forensics_lexicons.dart';
import 'package:flutter_test/flutter_test.dart';

SourceCorpusDocument _doc(String id, String content) => SourceCorpusDocument(
      id: id,
      title: 'Doc $id',
      category: SourceCategory.academic,
      content: content,
    );

double _cv(String text) {
  final lengths = TextForensicsLexicons.splitSentences(text)
      .map((s) => TextForensicsLexicons.extractWords(s).length.toDouble())
      .toList();
  final mean = lengths.reduce((a, b) => a + b) / lengths.length;
  final variance = lengths.map((l) => pow(l - mean, 2)).reduce((a, b) => a + b) / lengths.length;
  return sqrt(variance) / mean;
}

/// LlmService double that returns a scripted response per call.
class _ScriptedLlm extends LlmService {
  final List<String Function(List<String> sentences)> script;
  final calls = <String>[];
  _ScriptedLlm(this.script);

  @override
  Future<String> transformText({
    required LlmProvider provider,
    required String apiKey,
    required String featureId,
    required String text,
    String? customSystemPrompt,
    String? model,
    String? customBaseUrl,
    String? targetLanguage,
    LlmGenerationParams? params,
  }) async {
    calls.add(featureId);
    final sentences = (jsonDecode(text.substring(text.indexOf('['))) as List).cast<String>();
    final step = script[min(calls.length - 1, script.length - 1)];
    return step(sentences);
  }
}

void main() {
  group('Seed-and-extend source alignment', () {
    const engine = ShingleMatchingEngine();
    final attention = _doc(
      'attn',
      'We propose a new simple network architecture, the Transformer, based solely on attention '
          'mechanisms, dispensing with recurrence and convolutions entirely.',
    );

    test('aligns light-edit plagiarism (word swaps + inflection) as one segment instead of fragments', () {
      // new→novel, solely→only, convolutions→convolution
      const query = 'We propose a novel simple network architecture, the Transformer, based only on '
          'attention mechanisms, dispensing with recurrence and convolution entirely.';
      final detail = engine.matchDocument(queryText: query, queryTokens: const [], source: attention);
      expect(detail.segments, hasLength(1));
      final seg = detail.segments.single;
      expect(seg.matchType, SourceMatchType.shingleOverlap);
      expect(seg.tokenCount, greaterThanOrEqualTo(18));
      expect(seg.similarityPercent, greaterThan(85.0));
    });

    test('offsets point at the matched occurrence, not the first repeated word', () {
      const query = 'We propose many ideas in this essay. Later on, we propose a new simple network '
          'architecture, the Transformer, based solely on attention mechanisms.';
      final seg = engine.matchDocument(queryText: query, queryTokens: const [], source: attention).segments.single;
      expect(seg.documentStartOffset, query.indexOf('we propose a new'));
      expect(query.substring(seg.documentStartOffset, seg.documentEndOffset), seg.matchedText);
      expect(seg.matchedText, startsWith('we propose a new simple'));
    });

    test('stock function-word phrasing is not reported as copying', () {
      final source = _doc('common', 'It is one of the most important things in the world to all of us.');
      const query = 'Honestly, one of the most important things in my life is my family.';
      final detail = engine.matchDocument(queryText: query, queryTokens: const [], source: source);
      expect(detail.segments, isEmpty);
    });

    test('coverage is a union across sources, never double-counted', () {
      const text = 'All human beings are born free and equal in dignity and rights. I wrote the rest myself '
          'after a long walk along the river with my brother on Sunday.';
      const passage = 'All human beings are born free and equal in dignity and rights.';
      final one = SourceRepository(loadDefaultCorpus: false)..addDocument(_doc('a', passage));
      final two = SourceRepository(loadDefaultCorpus: false)
        ..addDocument(_doc('a', passage))
        ..addDocument(_doc('b', passage));
      final e1 = SourceSimilarityService(repository: one).analyzeDocument(text);
      final e2 = SourceSimilarityService(repository: two).analyzeDocument(text);
      expect(e2.uniqueSourceCount, 2);
      expect(e2.documentCoveragePercent, closeTo(e1.documentCoveragePercent, 1e-9));
      expect(e2.overallSimilarityScore, closeTo(e1.overallSimilarityScore, 1e-9));
    });

    test('sentence-level paraphrase tier catches reordered rewording', () {
      final repo = SourceRepository(loadDefaultCorpus: false)
        ..addDocument(_doc(
          'photo',
          'Photosynthesis is a biological process used by plants, algae, and certain bacteria to convert '
              'light energy into chemical energy.',
        ));
      const text = 'Plants, algae and some bacteria rely on photosynthesis, a biological process, to turn light '
          'energy into chemical energy.';
      final evidence = SourceSimilarityService(repository: repo).analyzeDocument(text);
      expect(evidence.matches.any((m) => m.matchType == SourceMatchType.fuzzyParaphrase), isTrue);
      expect(evidence.overallSimilarityScore, greaterThan(20.0));
    });

    test('original writing on the same topic is not flagged', () {
      final repo = SourceRepository(loadDefaultCorpus: false)
        ..addDocument(_doc(
          'photo',
          'Photosynthesis is a biological process used by plants, algae, and certain bacteria to convert '
              'light energy into chemical energy.',
        ));
      const text = 'My tomato plants turned yellow last week because I forgot to water them during the '
          'heatwave, and the basil next to them wilted too.';
      final evidence = SourceSimilarityService(repository: repo).analyzeDocument(text);
      expect(evidence.matches, isEmpty);
      expect(evidence.overallSimilarityScore, 0.0);
    });

    test('documents registered on the shared repository reach the engine', () {
      SourceRepository.baselineLiterature.addDocument(_doc(
        'late_loaded_corpus_doc',
        'The quiet harbour town of Vellmoor exported salted herring and hand-carved oak barrels to '
            'merchants across the northern sea for three centuries.',
      ));
      final report = ForensicEngine().analyze(
        'For three centuries the quiet harbour town of Vellmoor exported salted herring and hand-carved '
        'oak barrels to merchants across the northern sea.',
      );
      expect(report.sourceSimilarity.matches.any((m) => m.sourceTitle == 'Doc late_loaded_corpus_doc'), isTrue);
    });
  });

  group('Citation context', () {
    test('a match deep inside a long quotation counts as quoted', () {
      const text = 'The declaration opens: "Everyone agreed at the time that All human beings are born free '
          'and equal in dignity and rights, and nobody objected." (UN, 1948)';
      final start = text.indexOf('All human');
      final end = text.indexOf('rights') + 'rights'.length;
      final ctx = FuzzySimilarityMatcher().analyzeCitationContext(
        fullDocumentText: text,
        matchStartOffset: start,
        matchEndOffset: end,
      );
      expect(ctx.isQuoted, isTrue);
      expect(ctx.status, CitationStatus.quotedAndCited);
    });

    test('apostrophes in contractions are not quotation marks', () {
      const text = "I don't think All human beings are born free and equal in dignity and rights isn't new.";
      final start = text.indexOf('All human');
      final end = text.indexOf('rights') + 'rights'.length;
      expect(FuzzySimilarityMatcher.isEnclosedInQuotes(text, start, end), isFalse);
    });
  });

  group('Sentence attribution & calibration', () {
    test('domain calibration is monotone and continuous for every domain', () {
      for (final t in [55.0, 65.0, 72.0, 75.0, 80.0, 82.0]) {
        double prev = -1;
        for (double x = 0; x <= 100; x += 0.5) {
          final y = ForensicEngine.domainCalibrate(x, t);
          expect(y, greaterThanOrEqualTo(prev), reason: 'threshold $t at $x');
          expect((y - prev).abs(), lessThan(1.5), reason: 'jump at threshold $t, $x');
          prev = y;
        }
        expect(ForensicEngine.domainCalibrate(t, t), closeTo(65.0, 1e-9));
      }
      expect(ForensicEngine.domainCalibrate(42.0, 65.0), closeTo(42.0, 1e-9));
    });

    test('a stock-phrase sentence in a human document is surfaced; clean ones stay low', () {
      const model = SentenceAttributionModel();
      final r = model.score(
        [
          'I fixed the bike chain on Saturday.',
          'It took me way longer than it should have.',
          'Moreover, this pivotal journey underscores the transformative tapestry of cycling.',
          'Anyway, the chain works now.',
        ],
        documentAiProbability: 20.0,
      );
      expect(r[2].aiProbability, greaterThan(r[0].aiProbability + 25));
      expect(r[2].tells, contains('Formal transition opener'));
      expect(r[0].aiProbability, lessThan(30.0));
      expect(r[3].aiProbability, lessThan(30.0));
    });

    test('sentences in an AI document are separated by their own evidence', () {
      const model = SentenceAttributionModel();
      final r = model.score(
        [
          'Furthermore, it is important to note that this pivotal framework plays a crucial role in innovation.',
          'The study ran for 14 weeks in 3 clinics.',
        ],
        documentAiProbability: 80.0,
      );
      expect(r[0].aiProbability, greaterThan(r[1].aiProbability + 10));
    });

    test('isolate and in-thread paths produce identical sentence scores', () async {
      final text = List.filled(
        8,
        'Moreover, the pivotal framework fosters a robust landscape of innovation for every stakeholder. '
        'I spent last weekend repainting the shed, which was honestly more tiring than expected. ',
      ).join('\n\n');
      expect(text.length, greaterThan(1200));
      final engine = ForensicEngine();
      final sync = engine.analyze(text);
      final viaIsolate = await ForensicCoordinatorService(engine: engine).coordinate(text: text);
      expect(viaIsolate.sentences.length, sync.sentences.length);
      for (int i = 0; i < sync.sentences.length; i++) {
        expect(viaIsolate.sentences[i].aiProbability, closeTo(sync.sentences[i].aiProbability, 1e-6));
      }
      expect(viaIsolate.adversarialEvidence, isNotNull);
      expect(viaIsolate.tokenPredictability, isNotNull);
    });

    test('v1 classifier now spans a usable range instead of hovering at 50%', () {
      final detector = PlagiarismDetectorService();
      final ai = detector.mlClassifierScore(
        'Furthermore, in today\'s fast-paced world, it is important to note that leveraging robust, '
        'holistic frameworks plays a pivotal role. Moreover, this underscores the transformative '
        'tapestry of innovation. Additionally, stakeholders must navigate the evolving landscape.',
      );
      final human = detector.mlClassifierScore(
        'Car died on the highway again. Called my brother, he showed up an hour later with jumper '
        'cables and a bag of gas station donuts. We sat on the hood eating them while it charged.',
      );
      expect(ai, greaterThan(75.0));
      expect(human, lessThan(25.0));
    });
  });

  group('Humanizer structure & meaning safety', () {
    const h = AlgorithmicHumanizerService();

    test('paragraph structure survives postProcess', () {
      const input = 'Moreover, the first paragraph has a point.\n\nFurthermore, the second one does too.\n\nThird.';
      final out = h.postProcess(input);
      expect('\n\n'.allMatches(out).length, 2);
      expect(out, startsWith('The first paragraph'));
    });

    test('logical connectors are softened, not deleted', () {
      final pro = h.stripAiTransitions('Costs rose. Therefore, prices went up. Nevertheless, demand held.');
      expect(pro, 'Costs rose. For this reason, prices went up. Even so, demand held.');
      final casual = h.stripAiTransitions('Costs rose. Therefore, prices went up.', tone: WritingToneProfile.casual);
      expect(casual, 'Costs rose. So, prices went up.');
    });

    test('"not only" with an auxiliary collapses to grammatical coordination', () {
      expect(h.dissolveContrastAndStaging('It is not only fast but also cheap.'), 'It is fast and cheap.');
      expect(h.dissolveContrastAndStaging('We can not only save time but also cut costs.'), 'We can save time and cut costs.');
    });

    test('sentence case is restored after deleting a leading filler phrase', () {
      final out = h.postProcess('Costs fell. It is important to note that the budget grew.');
      expect(out, 'Costs fell. The budget grew.');
    });

    test('abbreviations and camel-cased names are not re-capitalised', () {
      final out = h.postProcess('The results (see e.g. the appendix) matter. It is worth noting that iPhone sales rose.');
      expect(out, contains('e.g. the appendix'));
      expect(out, contains('iPhone sales rose'));
    });

    test('lists and mid-sentence relative clauses are never split into fragments', () {
      const listy = 'The team reviewed the budget, the roadmap, and the hiring plan for the upcoming quarter today.';
      expect(h.optimizeBurstiness(listy), listy);
      const midWhich = 'The new API, which runs on the edge network, is much faster than the old service was.';
      expect(h.optimizeBurstiness(midWhich), midWhich);
    });

    test('burstiness optimizer makes multiple splits on long uniform text', () {
      const uniform = 'The team reviewed every service log carefully, and they found two memory leaks overnight. '
          'The database cluster handled the load well; the cache layer did not keep up. '
          'Engineers patched the ingestion worker quickly, and it recovered before the morning peak. '
          'The dashboard now shows stable latency, but the alerting rules still need tuning. '
          'Product managers approved the fix in the afternoon, and we shipped it before dinner. '
          'Support tickets dropped sharply after release, so the team closed the incident report.';
      final before = _cv(uniform);
      final out = h.optimizeBurstiness(uniform);
      expect(TextForensicsLexicons.splitSentences(out).length, greaterThanOrEqualTo(8));
      expect(_cv(out), greaterThan(before + 0.15));
    });
  });

  group('Meaning Guard', () {
    final v = SemanticPreservationVerifier();

    test('equivalent number spellings are preserved, not drift', () {
      final r = v.verify(
        originalText: 'We surveyed 1,000 people across 5 cities; 20% said yes.',
        humanizedText: 'We asked 1000 people in five cities, and 20 percent said yes.',
      );
      expect(r.missingNumbers, isEmpty);
      expect(r.hasNumericalDrift, isFalse);
    });

    test('a dropped negation is caught as polarity drift', () {
      final r = v.verify(
        originalText: 'The drug does not reduce mortality in adults.',
        humanizedText: 'The drug reduces mortality in adults.',
      );
      expect(r.hasPolarityDrift, isTrue);
      expect(r.verdict, isNot(SemanticPreservationVerdict.excellent));
    });

    test('dissolving "not only ... but also" is not treated as a negation change', () {
      final r = v.verify(
        originalText: 'The update not only fixes bugs but also speeds up startup.',
        humanizedText: 'The update fixes bugs. It also speeds up startup.',
      );
      expect(r.hasPolarityDrift, isFalse);
    });

    test('an entity moved to the start of a sentence is still preserved', () {
      final r = v.verify(
        originalText: 'The contract was signed by Northwind Traders in March.',
        humanizedText: 'Northwind Traders signed the contract in March.',
      );
      expect(r.missingEntities, isEmpty);
    });

    test('AI reduction on a 0-100 scale is reported in points', () {
      final r = v.verify(
        originalText: 'Plain text here.',
        humanizedText: 'Plain text here.',
        aiProbabilityBefore: 82.0,
        aiProbabilityAfter: 30.0,
      );
      expect(r.summary, contains('decreased by 52 points'));
    });
  });

  group('Surgical bridge closed loop', () {
    final provider = LlmProvider.getById('groq');
    const flaggedA = 'Moreover, this pivotal framework fosters a robust landscape of innovation.';
    const flaggedB = 'Furthermore, it underscores the transformative tapestry of modern teamwork.';
    const human = 'I wrote this part myself on the train home.';
    const text = '$flaggedA $human $flaggedB';

    SentenceAudit audit(int i, String t, double p) => SentenceAudit(
          index: i,
          text: t,
          aiProbability: p,
          riskLevel: PlagiarismRiskLevel.fromScore(p),
          detectedTells: const [],
          wordCount: t.split(' ').length,
          burstinessDelta: 0,
        );

    PlagiarismReport reportFor(String t, {required double a, required double b}) {
      final sentences = TextForensicsLexicons.splitSentences(t);
      return PlagiarismReport(
        overallScore: max(a, b),
        riskLevel: PlagiarismRiskLevel.fromScore(max(a, b)),
        humanScore: 100 - max(a, b),
        burstinessScore: 0.3,
        predictabilityScore: 50,
        lexicalRichness: 70,
        ngramOverlapScore: 0,
        repeatedNgrams: const [],
        detectedTells: const [],
        sentences: [
          audit(0, sentences[0], a),
          audit(1, sentences[1], 10),
          audit(2, sentences[2], b),
        ],
      );
    }

    test('re-targets only still-flagged sentences and keeps human text byte-identical', () async {
      final llm = _ScriptedLlm([
        // Pass 1: fixes A properly; B's rewrite still reads synthetic.
        (s) => jsonEncode(['This framework helps teams try new ideas.', 'Additionally, it showcases teamwork.']),
        // Pass 2: only B should be sent.
        (s) => jsonEncode(s.map((_) => 'It also changes how teams work together.').toList()),
      ]);
      int scoreCalls = 0;
      final bridge = SurgicalHumanizerBridge(
        llmService: llm,
        scorer: (t) async {
          scoreCalls++;
          final sentences = TextForensicsLexicons.splitSentences(t);
          final bScore = sentences.last.contains('showcases') ? 70.0 : 12.0;
          return reportFor(t, a: 12, b: bScore);
        },
      );

      final result = await bridge.surgicallyHumanize(
        originalText: text,
        report: reportFor(text, a: 80, b: 85),
        provider: provider,
        apiKey: 'k',
      );

      expect(llm.calls, ['SurgicalHumanize', 'SurgicalHumanize']);
      expect(scoreCalls, 2);
      expect(result.passesRequired, 2);
      expect(result.replacedSentenceCount, 2);
      expect(result.humanizedText, contains(human));
      expect(result.humanizedText, isNot(contains('pivotal')));
      expect(result.humanizedText, isNot(contains('showcases')));
    });

    test('rejects rewrites that drop a negation or a number', () async {
      const risky = 'Moreover, the pivotal trial did not improve outcomes in 42 patients.';
      const doc = '$risky $human $flaggedB';
      final llm = _ScriptedLlm([
        (s) => jsonEncode(['The trial improved outcomes in patients.', 'It changes how teams work together.']),
      ]);
      final bridge = SurgicalHumanizerBridge(
        llmService: llm,
        scorer: (t) async => reportFor(t, a: 80, b: 10),
      );
      final result = await bridge.surgicallyHumanize(
        originalText: doc,
        report: reportFor(doc, a: 80, b: 85),
        provider: provider,
        apiKey: 'k',
      );
      expect(result.humanizedText, contains(risky));
      expect(result.isFactualIntegrityPreserved, isTrue);
    });

    test('a length-mismatched LLM array is rejected instead of misaligned', () async {
      final llm = _ScriptedLlm([(s) => jsonEncode(['Only one rewrite came back.'])]);
      final bridge = SurgicalHumanizerBridge(llmService: llm, scorer: (t) async => reportFor(t, a: 80, b: 85));
      final result = await bridge.surgicallyHumanize(
        originalText: text,
        report: reportFor(text, a: 80, b: 85),
        provider: provider,
        apiKey: 'k',
      );
      expect(result.humanizedText, text);
      expect(result.replacedSentenceCount, 0);
    });

    test('parses arrays wrapped in prose or code fences', () {
      expect(SurgicalHumanizerBridge.parseRewriteArray('Sure! ```json\n["a", "b"]\n```'), ['a', 'b']);
    });
  });
}
