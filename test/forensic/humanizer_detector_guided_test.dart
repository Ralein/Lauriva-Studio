import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/models/plagiarism_report.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_chunk_engine.dart';
import 'package:lauriva/services/forensic/humanizer/humanizer_model.dart';
import 'package:lauriva/services/llm_service.dart';

/// Returns [first] on the initial attempt and [retry] once detector feedback is supplied.
class _ScriptedModel implements HumanizerModel {
  final String first;
  final String retry;
  final List<ChunkRewriteContext> contexts = [];

  _ScriptedModel({required this.first, required this.retry});

  @override
  String get name => 'scripted';

  @override
  int get maxContextTokens => 4096;

  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    contexts.add(context);
    return context.detectorFeedback.isEmpty ? first : retry;
  }
}

PlagiarismReport _report(double score, {String flagged = ''}) => PlagiarismReport(
      overallScore: score,
      riskLevel: PlagiarismRiskLevel.fromScore(score),
      humanScore: 100 - score,
      burstinessScore: 0.5,
      predictabilityScore: 0,
      lexicalRichness: 0,
      ngramOverlapScore: 0,
      repeatedNgrams: const [],
      detectedTells: const ['Formulaic transition'],
      sentences: [
        if (flagged.isNotEmpty)
          SentenceAudit(
            index: 0,
            text: flagged,
            aiProbability: score,
            riskLevel: PlagiarismRiskLevel.fromScore(score),
            detectedTells: const ['Formulaic transition'],
            wordCount: 8,
          ),
      ],
    );

final _provider = LlmProvider(
  id: 'test',
  name: 'Test',
  tag: 'test',
  baseUrl: 'https://test',
  keyPortalUrl: 'https://test',
  keyHint: '',
  description: '',
  defaultModel: 'test',
  requiresKey: false,
  curatedModels: const [],
);

const _input = 'Remote work changed how the team met deadlines during the first quarter. '
    'Managers tracked output weekly and adjusted staffing when projects slipped.';
// "Q1" stands in for whatever the detector flags; the post-processor leaves it alone.
const _aiLike = 'Remote work transformed how the team met deadlines during Q1. '
    'Managers tracked output weekly and adjusted staffing when projects slipped.';
const _humanLike = 'Remote work shifted how the team hit its deadlines in the first quarter. '
    'Managers checked output every week and moved people around whenever a project slipped.';

Future<HumanizerResult> _run(_ScriptedModel model, Future<PlagiarismReport> Function(String) scorer) {
  return HumanizerChunkEngine().processDocument(
    rawText: _input,
    tone: WritingToneProfile.professional,
    llmService: LlmService(),
    activeProvider: _provider,
    activeApiKey: '',
    activeModel: 'test',
    customModel: model,
    documentScorer: scorer,
  );
}

void main() {
  group('Detector-guided humanization', () {
    test('retries a flagged chunk with feedback and keeps the lower-scoring rewrite', () async {
      final model = _ScriptedModel(first: _aiLike, retry: _humanLike);
      final result = await _run(model, (t) async => t.contains('Q1') ? _report(85, flagged: 'Remote work transformed how the team met deadlines during Q1.') : _report(12));

      expect(model.contexts.length, 2);
      expect(model.contexts.last.detectorFeedback, contains('during Q1'));
      expect(result.humanizedText, isNot(contains('Q1')));
    });

    test('does not retry chunks the detector already clears', () async {
      final model = _ScriptedModel(first: _humanLike, retry: _aiLike);
      await _run(model, (t) async => _report(10));
      expect(model.contexts.length, 1);
    });

    test('keeps the first rewrite when the retry scores no better', () async {
      final model = _ScriptedModel(first: _aiLike, retry: _humanLike);
      await _run(model, (t) async => _report(80, flagged: 'Remote work transformed how the team met deadlines during Q1.'));
      expect(model.contexts.length, 2);
    });

    test('before/after metrics come from the supplied detector', () async {
      final model = _ScriptedModel(first: _humanLike, retry: _humanLike);
      final result = await _run(model, (t) async => t == _input ? _report(64) : _report(9));
      expect(result.beforeReport.overallScore, 64);
      expect(result.afterReport.overallScore, 9);
      expect(result.preservationReport.aiProbabilityBefore, 64);
    });

    test('feedback lists the most AI-like sentences with their tells', () {
      final feedback = HumanizerChunkEngine.detectorFeedback(_report(90, flagged: 'Moreover, this is crucial.'));
      expect(feedback, contains('"Moreover, this is crucial."'));
      expect(feedback, contains('Formulaic transition'));
    });
  });
}
