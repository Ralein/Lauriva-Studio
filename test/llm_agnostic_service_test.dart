import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/services/llm_service.dart';
import 'package:lauriva/services/forensic/humanizer/surgical_humanizer_bridge.dart';

void main() {
  group('LLM-Agnostic Engine: OpenAI Reasoning Architectures (o1, o3-mini)', () {
    test('isOpenAiReasoningModel correctly identifies reasoning model variations', () {
      expect(LlmService.isOpenAiReasoningModel('o1'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('o1-mini'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('o1-preview'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('o1-2024-12-17'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('o3'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('o3-mini'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('o3-mini-2025-01-31'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('o3-high'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('openai/o1'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('openai/o3-mini'), isTrue);
      expect(LlmService.isOpenAiReasoningModel('azure/o1:latest'), isTrue);

      expect(LlmService.isOpenAiReasoningModel('gpt-4o'), isFalse);
      expect(LlmService.isOpenAiReasoningModel('gpt-4o-mini'), isFalse);
      expect(LlmService.isOpenAiReasoningModel('claude-3-7-sonnet'), isFalse);
      expect(LlmService.isOpenAiReasoningModel('deepseek-chat'), isFalse);
      expect(LlmService.isOpenAiReasoningModel('llama-3.3-70b'), isFalse);
    });

    test('formats o1/o3 reasoning requests with developer role, max_completion_tokens, and no penalties', () async {
      late Map<String, dynamic> capturedPayload;

      final service = LlmService(
        client: MockClient((req) async {
          capturedPayload = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Refined humanized text without reasoning tokens.'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final openAiProvider = LlmProvider.getById('openai');
      final result = await service.transformText(
        provider: openAiProvider,
        apiKey: 'sk-test-openai',
        featureId: 'Humanize',
        text: 'The aforementioned methodology fosters robust outcomes.',
        model: 'o3-mini',
        params: const LlmGenerationParams(
          temperature: 0.88,
          maxTokens: 1024,
          frequencyPenalty: 0.35,
          presencePenalty: 0.20,
        ),
      );

      expect(result, 'Refined humanized text without reasoning tokens.');
      expect(capturedPayload['model'], 'o3-mini');
      expect(capturedPayload['max_completion_tokens'], 1024);
      expect(capturedPayload.containsKey('max_tokens'), isFalse, reason: 'o3-mini rejects max_tokens');
      expect(capturedPayload.containsKey('temperature'), isFalse, reason: 'o3-mini rejects temperature');
      expect(capturedPayload.containsKey('top_p'), isFalse, reason: 'o3-mini rejects top_p');
      expect(capturedPayload.containsKey('frequency_penalty'), isFalse, reason: 'o3-mini rejects frequency_penalty');
      expect(capturedPayload.containsKey('presence_penalty'), isFalse, reason: 'o3-mini rejects presence_penalty');

      final messages = capturedPayload['messages'] as List<dynamic>;
      expect(messages[0]['role'], 'developer', reason: 'OpenAI reasoning models require developer role for instructions');
      expect(messages[1]['role'], 'user');
    });

    test('testApiKey properly adapts probe payload for o1/o3-mini', () async {
      late Map<String, dynamic> capturedPayload;

      final service = LlmService(
        client: MockClient((req) async {
          // /models answers 404 (custom-proxy case), so the completion probe is what gets sent.
          if (req.method == 'GET') return http.Response('', 404);
          capturedPayload = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'pong'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final ok = await service.testApiKey(
        LlmProvider.getById('openai'),
        'sk-test-key-123',
        model: 'o1',
      );

      expect(ok, isTrue);
      expect(capturedPayload['model'], 'o1');
      expect(capturedPayload.containsKey('max_completion_tokens'), isTrue);
      expect(capturedPayload.containsKey('max_tokens'), isFalse);
      expect(capturedPayload.containsKey('temperature'), isFalse);
    });
  });

  group('LLM-Agnostic Engine: Anthropic Claude 3.5 & 3.7', () {
    test('routes to /messages with x-api-key, anthropic-version, and top-level system prompt', () async {
      late http.BaseRequest capturedRequest;
      late Map<String, dynamic> capturedPayload;

      final service = LlmService(
        client: MockClient((req) async {
          capturedRequest = req;
          capturedPayload = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Humanized prose from Claude 3.7.'},
              ],
            }),
            200,
          );
        }),
      );

      final anthropicProvider = LlmProvider.getById('anthropic');
      final result = await service.transformText(
        provider: anthropicProvider,
        apiKey: 'sk-ant-testkey',
        featureId: 'Humanize',
        text: 'In today\'s dynamic digital landscape, AI stands as a catalyst.',
        model: 'claude-3-7-sonnet-20250219',
      );

      expect(result, 'Humanized prose from Claude 3.7.');
      expect(capturedRequest.url.path, endsWith('/messages'));
      expect(capturedRequest.headers['x-api-key'], 'sk-ant-testkey');
      expect(capturedRequest.headers['anthropic-version'], '2023-06-01');
      expect(capturedPayload['system'], isA<String>());
      expect((capturedPayload['messages'] as List).length, 1);
      expect((capturedPayload['messages'] as List)[0]['role'], 'user');
      expect(capturedPayload['max_tokens'], 2048);
    });

    test('streams tokens cleanly from Anthropic content_block_delta format', () async {
      final service = LlmService(
        client: MockClient.streaming((req, bodyStream) async {
          final sseData = [
            'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Claude "}}\n\n',
            'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"stream "}}\n\n',
            'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"complete."}}\n\n',
            'data: [DONE]\n\n',
          ].join();
          return http.StreamedResponse(Stream.value(utf8.encode(sseData)), 200);
        }),
      );

      final tokens = await service
          .transformTextStream(
            provider: LlmProvider.getById('anthropic'),
            apiKey: 'sk-ant-key',
            featureId: 'Humanize',
            text: 'Test input',
            model: 'claude-3-5-sonnet-20241022',
          )
          .toList();

      expect(tokens.join(), 'Claude stream complete.');
    });
  });

  group('LLM-Agnostic Engine: DeepSeek-R1, Gemini, Cohere, and Multi-Format Extractors', () {
    test('extracts text from Google Gemini direct REST candidates format', () async {
      final service = LlmService(
        client: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Direct Gemini Flash rewritten prose.'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.transformText(
        provider: LlmProvider.getById('gemini'),
        apiKey: 'AIzaSyTestKey',
        featureId: 'Humanize',
        text: 'Test input',
        model: 'gemini-2.0-flash',
      );

      expect(result, 'Direct Gemini Flash rewritten prose.');
    });

    test('extracts text from Cohere v2 format', () async {
      final service = LlmService(
        client: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'message': {
                'content': [
                  {'type': 'text', 'text': 'Cohere Command R+ output.'},
                ],
              },
            }),
            200,
          );
        }),
      );

      final result = await service.transformText(
        provider: LlmProvider.getById('cohere'),
        apiKey: 'cohere-test-key',
        featureId: 'Humanize',
        text: 'Test input',
        model: 'command-r-plus',
      );

      expect(result, 'Cohere Command R+ output.');
    });

    test('handles DeepSeek-R1 reasoning_content and strips think tags', () async {
      final service = LlmService(
        client: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'reasoning_content': 'Thinking through humanization step by step...',
                    'content': '<think>Pondering clause geometry...</think>Final pristine human rewrite.',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.transformText(
        provider: LlmProvider.getById('deepseek'),
        apiKey: 'sk-deepseek',
        featureId: 'Humanize',
        text: 'Test input',
        model: 'deepseek-reasoner',
      );

      expect(result, 'Final pristine human rewrite.');
      expect(result, isNot(contains('Pondering')));
      expect(result, isNot(contains('Thinking')));
    });

    test('streams DeepSeek reasoning tokens cleanly while stripping think blocks', () async {
      final service = LlmService(
        client: MockClient.streaming((req, bodyStream) async {
          final sseData = [
            'data: {"choices":[{"delta":{"content":"<think>Internal logic"}}]}\n\n',
            'data: {"choices":[{"delta":{"content":" chain</think>Clean token 1 "}}]}\n\n',
            'data: {"choices":[{"delta":{"content":"Clean token 2."}}]}\n\n',
            'data: [DONE]\n\n',
          ].join();
          return http.StreamedResponse(Stream.value(utf8.encode(sseData)), 200);
        }),
      );

      final tokens = await service
          .transformTextStream(
            provider: LlmProvider.getById('groq'),
            apiKey: 'gsk_test',
            featureId: 'Humanize',
            text: 'Test text',
            model: 'deepseek-r1-distill-llama-70b',
          )
          .toList();

      expect(tokens.join(), 'Clean token 1 Clean token 2.');
    });
  });

  group('LLM-Agnostic Engine: Keyless & Local Providers (Ollama, Pollinations, Airforce, Custom)', () {
    test('Ollama works locally without API key validation errors', () async {
      final service = LlmService(
        client: MockClient((req) async {
          expect(req.url.toString(), contains('11434'));
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Local on-device Llama 3.2 response.'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.transformText(
        provider: LlmProvider.getById('ollama'),
        apiKey: '',
        featureId: 'Humanize',
        text: 'Test offline input',
        model: 'llama3.2:latest',
      );

      expect(result, 'Local on-device Llama 3.2 response.');
    });

    test('Pollinations.ai works keylessly for instant free processing', () async {
      final service = LlmService(
        client: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Pollinations free pool response.'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.transformText(
        provider: LlmProvider.getById('pollinations'),
        apiKey: '',
        featureId: 'Humanize',
        text: 'Test input',
      );

      expect(result, 'Pollinations free pool response.');
    });
  });

  group('LLM-Agnostic Engine: Surgical Humanizer Bridge Across All Formats', () {
    test('parses JSON array from standard response', () {
      final raw = '["Rewritten sentence one.", "Rewritten sentence two."]';
      final parsed = SurgicalHumanizerBridge.parseRewriteArray(raw);
      expect(parsed, ['Rewritten sentence one.', 'Rewritten sentence two.']);
    });

    test('parses JSON array when LLM wraps in markdown code fences', () {
      final raw = '```json\n["Rewritten sentence one.", "Rewritten sentence two."]\n```';
      final parsed = SurgicalHumanizerBridge.parseRewriteArray(raw);
      expect(parsed, ['Rewritten sentence one.', 'Rewritten sentence two.']);
    });

    test('parses JSON array when LLM returns list of objects with target keys', () {
      final raw = jsonEncode([
        {'rewritten': 'Sentence one rewritten.'},
        {'humanized': 'Sentence two humanized.'},
      ]);
      final parsed = SurgicalHumanizerBridge.parseRewriteArray(raw);
      expect(parsed, ['Sentence one rewritten.', 'Sentence two humanized.']);
    });

    test('parses numbered list when model fails to output JSON', () {
      final raw = '1. First rewritten sentence.\n2. Second rewritten sentence.';
      final parsed = SurgicalHumanizerBridge.parseRewriteArray(raw);
      expect(parsed, ['First rewritten sentence.', 'Second rewritten sentence.']);
    });
  });
}
