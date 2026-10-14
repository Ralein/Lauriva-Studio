import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/services/llm_service.dart';

LlmProvider _testProvider({bool requiresKey = true}) => LlmProvider(
      id: 'test_provider',
      name: 'Test Provider',
      tag: 'test',
      baseUrl: 'https://example.test/v1',
      keyPortalUrl: 'https://example.test/keys',
      keyHint: 'test-...',
      description: 'Test provider',
      defaultModel: 'test-model',
      requiresKey: requiresKey,
      curatedModels: const [],
    );

http.Response _chatCompletion(String content, {int statusCode = 200}) {
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    }),
    statusCode,
  );
}

void main() {
  group('LlmService.transformText', () {
    test('throws LlmApiException when a key is required but missing', () async {
      final service = LlmService(client: MockClient((req) async => _chatCompletion('unused')));

      expect(
        () => service.transformText(
          provider: _testProvider(),
          apiKey: '',
          featureId: 'Grammar',
          text: 'hello',
        ),
        throwsA(isA<LlmApiException>().having((e) => e.isAuthError, 'isAuthError', isTrue)),
      );
    });

    test('throws LlmApiException for empty input text', () async {
      final service = LlmService(client: MockClient((req) async => _chatCompletion('unused')));

      expect(
        () => service.transformText(
          provider: _testProvider(),
          apiKey: 'key',
          featureId: 'Grammar',
          text: '   ',
        ),
        throwsA(isA<LlmApiException>()),
      );
    });

    test('returns trimmed content on a successful 200 response', () async {
      final service = LlmService(
        client: MockClient((req) async {
          expect(req.url.toString(), 'https://example.test/v1/chat/completions');
          expect(req.headers['Authorization'], 'Bearer sk-test');
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['model'], 'test-model');
          expect((body['messages'] as List).length, 2);
          return _chatCompletion('  Polished output.  ');
        }),
      );

      final result = await service.transformText(
        provider: _testProvider(),
        apiKey: 'sk-test',
        featureId: 'Grammar',
        text: 'raw input',
      );

      expect(result, 'Polished output.');
    });

    test('strips <think> reasoning blocks from the response by default', () async {
      final service = LlmService(
        client: MockClient(
          (req) async => _chatCompletion('<think>internal reasoning</think>Final answer.'),
        ),
      );

      final result = await service.transformText(
        provider: _testProvider(),
        apiKey: 'sk-test',
        featureId: 'Grammar',
        text: 'raw input',
      );

      expect(result, 'Final answer.');
    });

    test('maps 401 to an auth LlmApiException', () async {
      final service = LlmService(
        client: MockClient((req) async => http.Response('{"error":"bad key"}', 401)),
      );

      await expectLater(
        service.transformText(
          provider: _testProvider(),
          apiKey: 'sk-bad',
          featureId: 'Grammar',
          text: 'raw input',
        ),
        throwsA(isA<LlmApiException>().having((e) => e.isAuthError, 'isAuthError', isTrue)),
      );
    });

    test('maps 429 to a rate-limit LlmApiException', () async {
      final service = LlmService(
        client: MockClient((req) async => http.Response('{"error":"rate limited"}', 429)),
      );

      await expectLater(
        service.transformText(
          provider: _testProvider(),
          apiKey: 'sk-test',
          featureId: 'Grammar',
          text: 'raw input',
        ),
        throwsA(isA<LlmApiException>().having((e) => e.isRateLimit, 'isRateLimit', isTrue)),
      );
    });

    test('retries transient 5xx errors and succeeds once the server recovers', () async {
      var attempt = 0;
      final service = LlmService(
        client: MockClient((req) async {
          attempt++;
          if (attempt < 2) {
            return http.Response('{"error":"server error"}', 503);
          }
          return _chatCompletion('Recovered output.');
        }),
      );

      final result = await service.transformText(
        provider: _testProvider(),
        apiKey: 'sk-test',
        featureId: 'Grammar',
        text: 'raw input',
      );

      expect(result, 'Recovered output.');
      expect(attempt, 2);
    });

    test('a keyless provider does not require an API key', () async {
      final service = LlmService(
        client: MockClient((req) async {
          expect(req.headers.containsKey('Authorization'), isFalse);
          return _chatCompletion('Free tier output.');
        }),
      );

      final result = await service.transformText(
        provider: _testProvider(requiresKey: false),
        apiKey: '',
        featureId: 'Grammar',
        text: 'raw input',
      );

      expect(result, 'Free tier output.');
    });
  });

  group('LlmService.transformTextWithFailover', () {
    test('fails over to the next configured provider on a 500 error', () async {
      final service = LlmService(
        client: MockClient((req) async {
          if (req.url.host == 'api.groq.com') {
            return http.Response('{"error":"down"}', 500);
          }
          // Any other configured candidate (e.g. openrouter) succeeds.
          return _chatCompletion('Fallback output.');
        }),
      );

      final onFailoverCalls = <String>[];
      final result = await service.transformTextWithFailover(
        primaryProvider: LlmProvider.getById('groq'),
        primaryApiKey: 'gsk_primary',
        featureId: 'Grammar',
        text: 'raw input',
        allConfiguredKeys: {'groq': 'gsk_primary', 'openrouter': 'sk-or-fallback'},
        onFailover: onFailoverCalls.add,
      );

      expect(result, 'Fallback output.');
      expect(onFailoverCalls, isNotEmpty);
    });

    test('does not fail over when autoFailover is disabled', () async {
      final service = LlmService(
        client: MockClient((req) async => http.Response('{"error":"down"}', 500)),
      );

      await expectLater(
        service.transformTextWithFailover(
          primaryProvider: LlmProvider.getById('groq'),
          primaryApiKey: 'gsk_primary',
          featureId: 'Grammar',
          text: 'raw input',
          allConfiguredKeys: {'groq': 'gsk_primary', 'openrouter': 'sk-or-fallback'},
          params: const LlmGenerationParams(autoFailover: false),
        ),
        throwsA(isA<LlmApiException>()),
      );
    });

    test('does not fail over on a plain auth error (only rate-limit/5xx trigger failover)',
        () async {
      var calls = 0;
      final service = LlmService(
        client: MockClient((req) async {
          calls++;
          return http.Response('{"error":"bad key"}', 401);
        }),
      );

      await expectLater(
        service.transformTextWithFailover(
          primaryProvider: LlmProvider.getById('groq'),
          primaryApiKey: 'gsk_bad',
          featureId: 'Grammar',
          text: 'raw input',
          allConfiguredKeys: {'groq': 'gsk_bad', 'openrouter': 'sk-or-fallback'},
        ),
        throwsA(isA<LlmApiException>().having((e) => e.isAuthError, 'isAuthError', isTrue)),
      );
      expect(calls, 1, reason: 'should not attempt fallback candidates for a plain auth error');
    });
  });

  group('LlmService.transformTextStream (SSE)', () {
    http.StreamedResponse sseResponse(List<String> dataLines, {int statusCode = 200}) {
      final body = dataLines.map((l) => 'data: $l\n\n').join();
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        statusCode,
      );
    }

    test('yields concatenated tokens from delta.content frames and stops at [DONE]', () async {
      final service = LlmService(
        client: MockClient.streaming((req, bodyStream) async {
          return sseResponse([
            jsonEncode({
              'choices': [
                {
                  'delta': {'content': 'Hello'},
                },
              ],
            }),
            jsonEncode({
              'choices': [
                {
                  'delta': {'content': ' world.'},
                },
              ],
            }),
            '[DONE]',
          ]);
        }),
      );

      final tokens = await service
          .transformTextStream(
            provider: _testProvider(),
            apiKey: 'sk-test',
            featureId: 'Grammar',
            text: 'raw input',
          )
          .toList();

      expect(tokens.join(), 'Hello world.');
    });

    test('strips <think>...</think> spanning multiple SSE frames', () async {
      final service = LlmService(
        client: MockClient.streaming((req, bodyStream) async {
          return sseResponse([
            jsonEncode({
              'choices': [
                {
                  'delta': {'content': 'Visible1 <think>hidden reasoning'},
                },
              ],
            }),
            jsonEncode({
              'choices': [
                {
                  'delta': {'content': ' still hidden</think>Visible2'},
                },
              ],
            }),
            '[DONE]',
          ]);
        }),
      );

      final tokens = await service
          .transformTextStream(
            provider: _testProvider(),
            apiKey: 'sk-test',
            featureId: 'Grammar',
            text: 'raw input',
          )
          .toList();

      final joined = tokens.join();
      expect(joined, contains('Visible1'));
      expect(joined, contains('Visible2'));
      expect(joined, isNot(contains('hidden reasoning')));
      expect(joined, isNot(contains('still hidden')));
    });

    test('throws LlmApiException when the stream opens with a non-200 status', () async {
      final service = LlmService(
        client: MockClient.streaming((req, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"nope"}}')),
            401,
          );
        }),
      );

      await expectLater(
        service
            .transformTextStream(
              provider: _testProvider(),
              apiKey: 'sk-bad',
              featureId: 'Grammar',
              text: 'raw input',
            )
            .toList(),
        throwsA(isA<LlmApiException>().having((e) => e.isAuthError, 'isAuthError', isTrue)),
      );
    });
  });

  group('LlmService.testApiKey', () {
    test('returns true for a 200 response and false otherwise', () async {
      final okService = LlmService(client: MockClient((req) async => _chatCompletion('pong')));
      expect(
        await okService.testApiKey(_testProvider(), 'sk-test-key-123'),
        isTrue,
      );

      final badService = LlmService(client: MockClient((req) async => http.Response('', 401)));
      expect(
        await badService.testApiKey(_testProvider(), 'sk-bad-key-123'),
        isFalse,
      );
    });

    test('never throws, even on a network exception', () async {
      final service = LlmService(
        client: MockClient((req) async => throw http.ClientException('offline')),
      );
      expect(await service.testApiKey(_testProvider(), 'sk-test-key-123'), isFalse);
    });
  });

  group('LlmService.fetchLiveModels', () {
    test('parses the /models catalog and falls back to curated models on failure', () async {
      final service = LlmService(
        client: MockClient((req) async {
          expect(req.url.toString(), 'https://example.test/v1/models');
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'model-a:free', 'pricing': null},
                {
                  'id': 'model-b',
                  'pricing': {'prompt': '0', 'completion': '0'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final models = await service.fetchLiveModels(_testProvider(), 'sk-test');
      expect(models.length, 2);
      expect(models.every((m) => m.isFree), isTrue);

      final failingService = LlmService(
        client: MockClient((req) async => http.Response('', 500)),
      );
      final fallback = await failingService.fetchLiveModels(_testProvider(), 'sk-test');
      expect(fallback.first.id, _testProvider().defaultModel);
    });
  });

  group('LlmService.sanitizeOutput', () {
    test('strips thinking tags', () {
      final input = '<think>Let us analyze this sentence.</think>This is natural writing.';
      expect(LlmService.sanitizeOutput(input), 'This is natural writing.');
    });

    test('strips markdown code blocks', () {
      final input = '```markdown\nThis is the revised prose without code blocks.\n```';
      expect(LlmService.sanitizeOutput(input), 'This is the revised prose without code blocks.');
    });

    test('strips conversational preambles and closers for Humanize', () {
      final input = 'Here is the humanized version of your text:\n\n'
          'Engineers fixed the database leak in twenty minutes.\n\n'
          'I hope this helps! Let me know if you need anything else.';
      final output = LlmService.sanitizeOutput(input, featureId: 'Humanize');
      expect(output, 'Engineers fixed the database leak in twenty minutes.');
    });

    test('strips wrapping quotes around prose', () {
      final input = '"Authentic human sentences that are not wrapped in quotation marks."';
      expect(
        LlmService.sanitizeOutput(input, featureId: 'Humanize'),
        'Authentic human sentences that are not wrapped in quotation marks.',
      );
    });

    test('leaves clean prose completely unchanged', () {
      final input = 'Authentic human sentences with varying lengths and natural cadence.';
      expect(LlmService.sanitizeOutput(input, featureId: 'Humanize'), input);
    });
  });
}
