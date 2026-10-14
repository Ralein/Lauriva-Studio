import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/services/llm_service.dart';
import 'package:lauriva/services/slop_linter.dart';
import 'package:lauriva/services/slop_repair_service.dart';

LlmProvider _provider() => const LlmProvider(
      id: 'test_provider',
      name: 'Test Provider',
      tag: 'test',
      baseUrl: 'https://example.test/v1',
      keyPortalUrl: 'https://example.test/keys',
      keyHint: 'test-...',
      description: 'Test provider',
      defaultModel: 'test-model',
      requiresKey: true,
      curatedModels: [],
    );

http.Response _reply(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
      200,
    );

const _source = 'The team looked at the numbers. Revenue grew 40% in 2023. See https://x.io for the details.';
const _candidate = 'The team will delve into the numbers. Revenue grew 40% in 2023. See https://x.io for the details.';
const _fixed = 'The team will look into the numbers. Revenue grew 40% in 2023. See https://x.io for the details.';

class _Harness {
  int calls = 0;
  String? lastBody;
  final SlopRepairService service;
  _Harness._(this.service);

  factory _Harness(Future<http.Response> Function(http.Request) handler) {
    late _Harness h;
    final client = MockClient((req) async {
      h.calls++;
      h.lastBody = req.body;
      return handler(req);
    });
    h = _Harness._(SlopRepairService(llmService: LlmService(client: client)));
    return h;
  }

  Future<SlopRepairResult> polish({
    String source = _source,
    String candidate = _candidate,
    String featureId = 'Rephrase',
  }) =>
      service.polish(
        source: source,
        candidate: candidate,
        featureId: featureId,
        provider: _provider(),
        apiKey: 'sk-test',
        allConfiguredKeys: const {},
        params: const LlmGenerationParams(autoFailover: false),
      );
}

void main() {
  test('fixture candidate has a repairable flag and fixed text has fewer', () {
    const linter = SlopLinter();
    expect(linter.check(_candidate).findings, isNotEmpty);
    expect(linter.check(_fixed).findings.length, lessThan(linter.check(_candidate).findings.length));
  });

  group('shouldCheck', () {
    test('rewrite features and styles are checked', () {
      for (final id in ['Humanize', 'Rephrase', 'Concise', 'Professional', 'Polite', 'Style: Witty']) {
        expect(SlopRepairService.shouldCheck(id), isTrue, reason: id);
      }
    });
    test('faithful features are skipped', () {
      for (final id in ['Grammar', 'Translate', 'PlagiarismCheck', 'SurgicalHumanize']) {
        expect(SlopRepairService.shouldCheck(id), isFalse, reason: id);
      }
    });
  });

  group('polish', () {
    test('skips Grammar/Translate without calling the LLM', () async {
      final h = _Harness((_) async => _reply(_fixed));
      for (final id in ['Grammar', 'Translate']) {
        final r = await h.polish(featureId: id);
        expect(r.repaired, isFalse);
        expect(r.text, _candidate);
      }
      expect(h.calls, 0);
    });

    test('clean text is unchanged and makes no LLM call', () async {
      final h = _Harness((_) async => _reply(_fixed));
      final r = await h.polish(candidate: _fixed);
      expect(r.repaired, isFalse);
      expect(r.text, _fixed);
      expect(h.calls, 0);
    });

    test('accepts a repair that passes every rule', () async {
      final h = _Harness((_) async => _reply(_fixed));
      final r = await h.polish();
      expect(h.calls, 1);
      expect(r.repaired, isTrue);
      expect(r.text, _fixed);
      expect(r.after.findings.length, lessThan(r.before.findings.length));
      expect(h.lastBody, contains('delve'));
      expect(h.lastBody, contains('SlopRepair'));
    });

    test('rejects a repair that drops a number', () async {
      final h = _Harness((_) async => _reply(
          'The team will look into the numbers. Revenue grew a lot in 2023. See https://x.io for the details.'));
      final r = await h.polish();
      expect(r.repaired, isFalse);
      expect(r.text, _candidate);
    });

    test('rejects a repair that changes length by more than 15 percent', () async {
      final h = _Harness((_) async => _reply('$_fixed Everyone on the team agreed this was a good result overall.'));
      final r = await h.polish();
      expect(r.repaired, isFalse);
      expect(r.reason, contains('length'));
    });

    test('rejects a repair that does not reduce flags', () async {
      final h = _Harness((_) async => _reply(_candidate.replaceFirst('will', 'would')));
      final r = await h.polish();
      expect(r.repaired, isFalse);
      expect(r.reason, contains('flags'));
    });

    test('rejects when the semantic verifier fails', () async {
      // Source states a figure the candidate (and so the repair) never carries.
      final h = _Harness((_) async => _reply(_fixed));
      final r = await h.polish(
        source: 'The team looked at the numbers. Revenue grew 40% in 2023 and costs fell 12%. See https://x.io for the details.',
      );
      expect(h.calls, 1);
      expect(r.repaired, isFalse);
      expect(r.reason, contains('meaning'));
    });

    test('returns the candidate when the LLM throws', () async {
      final h = _Harness((_) async => http.Response('boom', 400));
      final r = await h.polish();
      expect(r.repaired, isFalse);
      expect(r.text, _candidate);
      expect(r.reason, isNotNull);
    });

    test('proof-only findings are not sent to the LLM', () async {
      final h = _Harness((_) async => _reply(_fixed));
      const proofOnly = 'Our customers love us and everyone says it is the best tool they have used.';
      final report = const SlopLinter().check(proofOnly);
      // Guard the fixture: only proof findings, if any.
      expect(report.findings.every((f) => f.category == SlopCategory.unsupportedProof), isTrue);
      final r = await h.polish(source: proofOnly, candidate: proofOnly);
      expect(r.repaired, isFalse);
      expect(r.text, proofOnly);
      expect(h.calls, 0);
    });
  });
}
