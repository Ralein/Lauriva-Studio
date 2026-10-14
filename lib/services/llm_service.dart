import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_prompts.dart';
import '../models/llm_provider.dart';
import '../utils/logger.dart';
import 'circuit_breaker.dart';

class LlmApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isAuthError;
  final bool isRateLimit;
  final bool isCreditExhausted;

  LlmApiException(
    this.message, {
    this.statusCode,
    this.isAuthError = false,
    this.isRateLimit = false,
    this.isCreditExhausted = false,
  });

  @override
  String toString() => message;
}

class LlmService {
  final http.Client _client;

  /// Circuit breaker per provider: opens after 3 consecutive failures for 2 minutes.
  final Map<String, CircuitBreaker> _circuitBreakers = {};

  CircuitBreaker _getBreaker(String providerId) => _circuitBreakers.putIfAbsent(
        providerId,
        () => CircuitBreaker(
          name: 'LlmService_$providerId',
          failureThreshold: 3,
          cooldownDuration: const Duration(minutes: 2),
        ),
      );

  LlmService({http.Client? client}) : _client = client ?? http.Client();

  String _cleanBaseUrl(String url) {
    var cleaned = url.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  String _getCompletionsEndpoint(LlmProvider provider, {String? customBaseUrl}) {
    final base = _cleanBaseUrl(customBaseUrl ?? provider.baseUrl);
    if (provider.id == 'anthropic' && !base.endsWith('/messages') && !base.endsWith('/chat/completions')) {
      return '$base/messages';
    }
    if (base.endsWith('/chat/completions')) {
      return base;
    }
    return '$base/chat/completions';
  }

  Map<String, String> _buildHeaders(LlmProvider provider, String apiKey) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    final trimmedKey = apiKey.trim();
    if (trimmedKey.isNotEmpty) {
      if (provider.id == 'anthropic') {
        headers['x-api-key'] = trimmedKey;
        headers['anthropic-version'] = '2023-06-01';
      } else {
        headers['Authorization'] = 'Bearer $trimmedKey';
      }
    }

    if (provider.extraHeaders != null) {
      headers.addAll(provider.extraHeaders!);
    }

    return headers;
  }

  /// Removes internal reasoning tags e.g. `<think>...</think>` from output
  static String stripThinkingTags(String text) {
    var cleaned = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '').trim();
    // Also clean dangling opening tag if incomplete
    if (cleaned.startsWith('<think>')) {
      final closeIdx = cleaned.indexOf('</think>');
      if (closeIdx != -1) {
        cleaned = cleaned.substring(closeIdx + 8).trim();
      }
    }
    return cleaned;
  }

  /// Sanitizes raw LLM generation output by eliminating thinking tags,
  /// markdown code fences, chatbot conversational preambles, and polite closers.
  static String sanitizeOutput(String text, {String? featureId}) {
    var cleaned = stripThinkingTags(text);

    // 1. Strip markdown code block wrapper if present e.g. ```markdown ... ```
    final codeBlockPattern = RegExp(r'^```(?:markdown|text)?\s*\n([\s\S]*?)\n```\s*$', caseSensitive: false);
    final match = codeBlockPattern.firstMatch(cleaned);
    if (match != null) {
      cleaned = match.group(1)!.trim();
    }

    // 2. Strip chatbot conversational preambles (e.g., "Here is the humanized version:")
    cleaned = cleaned.replaceAll(
      RegExp(r'^(?:(?:Sure|Certainly|Of course|Here you go)[!.,]?\s*)?(?:Here(?:’|\x27)?s|Here is) (?:the|a|your) (?:humanized|rewritten|rephrased|naturalized|updated|edited)?\s*(?:version|text|passage|prose|draft)?.*?:(?:\s*\n+|\s+)', caseSensitive: false),
      '',
    ).trim();

    // 3. Strip chatbot sign-offs / pleasantries at the end
    cleaned = cleaned.replaceAll(
      RegExp(r'(?:\n+|\s+)(?:I hope this helps|Let me know if you (?:need|would like|want)|Feel free to ask|Hope this (?:helps|works)).*?$', caseSensitive: false),
      '',
    ).trim();

    // 4. Strip outer enclosing quotes if whole text is wrapped in quotes
    if (cleaned.length >= 2 &&
        ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
         (cleaned.startsWith('\'') && cleaned.endsWith('\'')) ||
         (cleaned.startsWith('“') && cleaned.endsWith('”')))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    return cleaned;
  }

  /// Determines if [modelId] is an OpenAI-style reasoning model requiring developer roles and max_completion_tokens.
  static bool isOpenAiReasoningModel(String modelId) {
    final lower = modelId.toLowerCase().trim();
    final pureModelName = lower.contains('/') ? lower.split('/').last : lower;
    return pureModelName == 'o1' ||
        pureModelName == 'o3' ||
        pureModelName == 'o4' ||
        pureModelName.startsWith('o1-') ||
        pureModelName.startsWith('o3-') ||
        pureModelName.startsWith('o4-') ||
        pureModelName.startsWith('o1:') ||
        pureModelName.startsWith('o3:') ||
        pureModelName.startsWith('o4:') ||
        pureModelName.contains('r1') ||
        pureModelName.contains('qwq') ||
        pureModelName.contains('reasoning');
  }

  /// Builds standardized request payload adapted to the target provider and model architecture.
  Map<String, dynamic> _buildRequestPayload({
    required LlmProvider provider,
    required String selectedModel,
    required String systemPrompt,
    required String userPrompt,
    required double temp,
    required int maxTok,
    required double topP,
    required LlmGenerationParams? params,
    bool isStreaming = false,
  }) {
    final isReasoning = isOpenAiReasoningModel(selectedModel);

    final payload = <String, dynamic>{
      'model': selectedModel,
    };

    if (isStreaming) {
      payload['stream'] = true;
    }

    // 1. Anthropic API Structure
    if (provider.id == 'anthropic') {
      payload['system'] = systemPrompt;
      payload['messages'] = [
        {'role': 'user', 'content': userPrompt},
      ];
      payload['max_tokens'] = maxTok;
      payload['temperature'] = temp;
      payload['top_p'] = topP;
    }
    // 2. OpenAI Reasoning Models (o1, o3-mini)
    else if (isReasoning) {
      payload['messages'] = [
        {'role': 'developer', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ];
      payload['max_completion_tokens'] = maxTok;
      // Note: temperature, top_p, frequency/presence penalties are intentionally omitted
      // because OpenAI reasoning models reject them with HTTP 400 errors.
    }
    // 3. Standard OpenAI-Compatible Format (OpenRouter, Groq, Gemini, DeepSeek, Mistral, Ollama, etc.)
    else {
      payload['messages'] = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ];
      payload['temperature'] = temp;
      payload['max_tokens'] = maxTok;
      payload['top_p'] = topP;

      if (params != null && params.frequencyPenalty != 0.0) {
        payload['frequency_penalty'] = params.frequencyPenalty;
      }
      if (params != null && params.presencePenalty != 0.0) {
        payload['presence_penalty'] = params.presencePenalty;
      }
    }

    final lora = params?.loraAdapter;
    if (lora != null && lora.trim().isNotEmpty) {
      payload['lora_adapter'] = lora.trim();
      payload['adapters'] = [lora.trim()];
    }

    return payload;
  }

  /// Parses text from diverse multi-provider response formats.
  static String? _extractTextFromResponse(Map<String, dynamic> decoded) {
    // 1. Standard OpenAI format
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final firstChoice = choices[0] as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>?;
      var content = message?['content'] as String?;
      if (content == null || content.isEmpty) {
        content = message?['reasoning_content'] as String? ??
            firstChoice['text'] as String?;
      }
      if (content != null && content.isNotEmpty) {
        return content;
      }
    }

    // 2. Anthropic Messages API format
    if (decoded['content'] is List) {
      final contentList = decoded['content'] as List<dynamic>;
      if (contentList.isNotEmpty) {
        final buffer = StringBuffer();
        for (final item in contentList) {
          if (item is Map<String, dynamic> && item['type'] == 'text') {
            final t = item['text'] as String?;
            if (t != null) buffer.write(t);
          }
        }
        if (buffer.isNotEmpty) return buffer.toString();
      }
    }

    // 3. Google Gemini Direct Candidates format
    if (decoded['candidates'] is List) {
      final candidates = decoded['candidates'] as List<dynamic>;
      if (candidates.isNotEmpty) {
        final first = candidates[0] as Map<String, dynamic>;
        final contentObj = first['content'] as Map<String, dynamic>?;
        final parts = contentObj?['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          final buffer = StringBuffer();
          for (final part in parts) {
            if (part is Map<String, dynamic>) {
              final t = part['text'] as String?;
              if (t != null) buffer.write(t);
            }
          }
          if (buffer.isNotEmpty) return buffer.toString();
        }
      }
    }

    // 4. Cohere v2 format
    if (decoded['message'] is Map<String, dynamic>) {
      final msg = decoded['message'] as Map<String, dynamic>;
      if (msg['content'] is List) {
        final cList = msg['content'] as List<dynamic>;
        if (cList.isNotEmpty) {
          final t = (cList[0] as Map<String, dynamic>?)?['text'] as String?;
          if (t != null && t.isNotEmpty) return t;
        }
      }
    }

    // 5. Fallback root text field
    if (decoded['text'] is String && (decoded['text'] as String).isNotEmpty) {
      return decoded['text'] as String;
    }

    return null;
  }

  /// Transform text with an LLM provider, model, and sampling parameters
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
    final keyToUse = apiKey.trim();
    if (keyToUse.isEmpty && provider.requiresKey && !provider.isCustom && provider.id != 'ollama' && provider.id != 'pollinations' && provider.id != 'airforce') {
      throw LlmApiException(
        '${provider.name} API Key is not configured. Please add your key in Settings.',
        isAuthError: true,
      );
    }

    if (text.trim().isEmpty) {
      throw LlmApiException('Text cannot be empty.');
    }

    final selectedModel = (model != null && model.trim().isNotEmpty)
        ? model.trim()
        : provider.defaultModel;

    // For Humanize, ensure anti-detection sampling variance without injecting unsupported penalties
    var effectiveParams = (featureId == 'Humanize' && customSystemPrompt == null && (params == null || params.temperature < 0.85))
        ? (params ?? const LlmGenerationParams()).copyWith(
            temperature: 0.88,
            topP: 0.95,
            frequencyPenalty: 0.0,
            presencePenalty: 0.0,
          )
        : params;

    final String systemPrompt;
    final String userPrompt;

    if (customSystemPrompt != null && customSystemPrompt.isNotEmpty) {
      systemPrompt = customSystemPrompt;
      userPrompt = text;
    } else {
      var sp = AppPrompts.buildSystemPrompt(featureId, targetLanguage: targetLanguage, persona: effectiveParams?.persona);
      if (effectiveParams != null && effectiveParams.persona != 'standard') {
        sp = '$sp\n\nPersona: ${effectiveParams.personaInstruction}';
      }
      if (effectiveParams != null && effectiveParams.ragContext != null && effectiveParams.ragContext!.trim().isNotEmpty) {
        sp = '$sp\n\n[RAG GROUNDING & STYLE CONTEXT]:\n${effectiveParams.ragContext!.trim()}\nAdhere strictly to the terminology, stylistic tone, and factual grounding provided above.';
      }
      systemPrompt = sp;
      userPrompt = AppPrompts.buildUserPrompt(featureId, text, targetLanguage: targetLanguage);
    }

    final endpoint = _getCompletionsEndpoint(provider, customBaseUrl: customBaseUrl);
    final headers = _buildHeaders(provider, keyToUse);

    if (effectiveParams != null && effectiveParams.langsmithTracing) {
      headers['x-langsmith-trace'] = 'true';
      headers['x-langsmith-project'] = effectiveParams.langsmithProject ?? 'lauriva-app';
      if (effectiveParams.langsmithApiKey != null && effectiveParams.langsmithApiKey!.isNotEmpty) {
        headers['x-langsmith-api-key'] = effectiveParams.langsmithApiKey!;
      }
    }

    final breaker = _getBreaker(provider.id);
    const int maxRetries = 2;
    int attempt = 0;

    while (true) {
      if (breaker.isOpen) {
        throw LlmApiException(
          '${provider.name} is temporarily unavailable (circuit breaker open). Please try again in a moment.',
          statusCode: 503,
        );
      }

      attempt++;
      final temp = effectiveParams?.temperature ?? 0.3;
      final maxTok = effectiveParams?.maxTokens ?? 2048;
      final topP = effectiveParams?.topP ?? 0.9;

      try {
        AppLogger.info(
          'Sending LLM transform request (provider: ${provider.name}, model: $selectedModel, attempt $attempt, temp: $temp${effectiveParams?.loraAdapter != null ? ", lora: ${effectiveParams!.loraAdapter}" : ""}${effectiveParams?.ragContext != null ? ", RAG: active" : ""})',
          'LlmService',
        );

        final requestPayload = _buildRequestPayload(
          provider: provider,
          selectedModel: selectedModel,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          temp: temp,
          maxTok: maxTok,
          topP: topP,
          params: effectiveParams,
          isStreaming: false,
        );

        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: headers,
              body: jsonEncode(requestPayload),
            )
            .timeout(const Duration(seconds: 35));

        if (response.statusCode == 200) {
          breaker.recordSuccess();
          final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          var content = _extractTextFromResponse(decoded);

          if (content != null && content.isNotEmpty) {
            if (params?.stripThinking ?? true) {
              content = sanitizeOutput(content, featureId: featureId);
            }
            return content.trim();
          }

          throw LlmApiException('Received empty response from ${provider.name}.');
        } else if (response.statusCode == 402) {
          throw LlmApiException(
            'Account credits depleted for ${provider.name}. Automatic failover will switch to available free models or providers.',
            statusCode: 402,
            isCreditExhausted: true,
          );
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          final bodyLower = response.body.toLowerCase();
          final isCreditIssue = bodyLower.contains('credit') ||
              bodyLower.contains('balance') ||
              bodyLower.contains('quota') ||
              bodyLower.contains('payment') ||
              bodyLower.contains('insufficient');
          throw LlmApiException(
            isCreditIssue
                ? 'Account balance or credit limit reached for ${provider.name}.'
                : 'Invalid or unauthorized API key for ${provider.name}. Please verify your key in Settings.',
            statusCode: response.statusCode,
            isAuthError: !isCreditIssue,
            isCreditExhausted: isCreditIssue,
          );
        } else if (response.statusCode == 429) {
          final bodyLower = response.body.toLowerCase();
          final isQuota = bodyLower.contains('quota') ||
              bodyLower.contains('credit') ||
              bodyLower.contains('billing') ||
              bodyLower.contains('exceeded your current quota');
          throw LlmApiException(
            isQuota
                ? 'Usage quota exceeded for ${provider.name}.'
                : 'Rate limit exceeded for ${provider.name} ($selectedModel). Please wait a moment or switch models in Settings.',
            statusCode: 429,
            isRateLimit: !isQuota,
            isCreditExhausted: isQuota,
          );
        } else if (response.statusCode == 400 && attempt == 1) {
          // If the model rejects sampling penalties or hyperparams with 400, sanitize and retry
          final bodyLower = response.body.toLowerCase();
          final isParamError = bodyLower.contains('penalty') ||
              bodyLower.contains('parameter') ||
              bodyLower.contains('unsupported') ||
              bodyLower.contains('temperature') ||
              bodyLower.contains('top_p') ||
              bodyLower.contains('not supported');
          if (isParamError) {
            AppLogger.warn(
              'HTTP 400 parameter rejection from ${provider.name} ($selectedModel). Retrying with sanitized baseline parameters...',
              'LlmService',
            );
            effectiveParams = (effectiveParams ?? const LlmGenerationParams()).copyWith(
              frequencyPenalty: 0.0,
              presencePenalty: 0.0,
              temperature: (effectiveParams?.temperature ?? 0.7).clamp(0.1, 1.0),
            );
            continue;
          }
          try {
            final errorJson = jsonDecode(response.body);
            final errorMsg = errorJson['error']?['message'] ??
                errorJson['message'] ??
                '${provider.name} API error (${response.statusCode})';
            throw LlmApiException(errorMsg.toString(), statusCode: response.statusCode);
          } catch (e) {
            if (e is LlmApiException) rethrow;
            throw LlmApiException(
              'Failed to communicate with ${provider.name} (${response.statusCode}).',
              statusCode: response.statusCode,
            );
          }
        } else if (response.statusCode >= 500 && attempt <= maxRetries) {
          breaker.recordFailure();
          AppLogger.warn(
            'Transient server error ${response.statusCode} from ${provider.name}, retrying in ${attempt * 1.5}s...',
            'LlmService',
          );
          await Future.delayed(Duration(milliseconds: (attempt * 1500)));
          continue;
        } else {
          try {
            final errorJson = jsonDecode(response.body);
            final errorMsg = errorJson['error']?['message'] ??
                errorJson['message'] ??
                '${provider.name} API error (${response.statusCode})';
            throw LlmApiException(errorMsg.toString(), statusCode: response.statusCode);
          } catch (e) {
            if (e is LlmApiException) rethrow;
            throw LlmApiException(
              'Failed to communicate with ${provider.name} (${response.statusCode}).',
              statusCode: response.statusCode,
            );
          }
        }
      } on TimeoutException {
        breaker.recordFailure();
        if (attempt <= maxRetries) {
          AppLogger.warn('Request to ${provider.name} timed out, retrying attempt $attempt...', 'LlmService');
          await Future.delayed(Duration(milliseconds: attempt * 1000));
          continue;
        }
        throw LlmApiException('Request to ${provider.name} timed out. Please check your internet connection.');
      } on http.ClientException catch (e) {
        breaker.recordFailure();
        if (attempt <= maxRetries) {
          AppLogger.warn('Network exception: ${e.message}, retrying...', 'LlmService');
          await Future.delayed(Duration(milliseconds: attempt * 1000));
          continue;
        }
        throw LlmApiException('Network error connecting to ${provider.name}: ${e.message}');
      } catch (e) {
        if (e is LlmApiException) rethrow;
        throw LlmApiException('An unexpected error occurred: $e');
      }
    }
  }

  /// Transform with Smart Auto-Failover: If primary provider hits rate limit, server error,
  /// or unrecoverable parameter rejection, automatically fail over to an available configured provider.
  Future<String> transformTextWithFailover({
    required LlmProvider primaryProvider,
    required String primaryApiKey,
    required String featureId,
    required String text,
    required Map<String, String> allConfiguredKeys,
    String? customSystemPrompt,
    String? primaryModel,
    String? customBaseUrl,
    String? targetLanguage,
    LlmGenerationParams? params,
    Function(String fallbackProviderName)? onFailover,
    void Function(LlmProvider provider, String model, String reason)? onFailoverDetails,
  }) async {
    try {
      return await transformText(
        provider: primaryProvider,
        apiKey: primaryApiKey,
        featureId: featureId,
        text: text,
        customSystemPrompt: customSystemPrompt,
        model: primaryModel,
        customBaseUrl: customBaseUrl,
        targetLanguage: targetLanguage,
        params: params,
      );
    } on LlmApiException catch (e) {
      final shouldFailover = (params?.autoFailover ?? true) &&
          (e.isCreditExhausted ||
           e.isRateLimit ||
           (!e.isAuthError &&
            (e.statusCode != null &&
             (e.statusCode! >= 500 || e.statusCode == 400 || e.statusCode == 402 || e.statusCode == 404 || e.statusCode == 422))));

      if (shouldFailover) {
        final reason = e.isCreditExhausted
            ? 'Credits depleted'
            : (e.isRateLimit ? 'Rate limit reached' : 'Server error (${e.statusCode})');
        AppLogger.warn(
          'Primary provider ${primaryProvider.name} failed ($reason: ${e.message}). Initiating auto-failover...',
          'LlmService',
        );

        // Stage 1: Intra-Provider Free-Model Pool Rotation (OpenRouter / Groq)
        // If credits are depleted or model is rate-limited (402, 429), rotate models within provider
        final isModelSpecificFailure = e.isCreditExhausted || e.isRateLimit || e.statusCode == 429 || e.statusCode == 402;
        if (isModelSpecificFailure) {
          if (primaryProvider.id == 'openrouter') {
            const openRouterFreeFallbacks = [
              'meta-llama/llama-3.3-70b-instruct:free',
              'google/gemma-4-31b-it:free',
              'mistralai/mistral-small-24b-instruct-2501:free',
              'qwen/qwen-2.5-72b-instruct:free',
            ];

            for (final freeModel in openRouterFreeFallbacks) {
              if (freeModel == primaryModel) continue;
              try {
                AppLogger.info('Rotating OpenRouter to free model: $freeModel...', 'LlmService');
                onFailover?.call('OpenRouter ($freeModel)');

                final result = await transformText(
                  provider: primaryProvider,
                  apiKey: primaryApiKey,
                  featureId: featureId,
                  text: text,
                  customSystemPrompt: customSystemPrompt,
                  model: freeModel,
                  targetLanguage: targetLanguage,
                  params: params,
                );
                onFailoverDetails?.call(primaryProvider, freeModel, reason);
                return result;
              } catch (freeErr) {
                AppLogger.warn('OpenRouter free model $freeModel failed: $freeErr', 'LlmService');
                continue;
              }
            }
          }

          // Groq intra-provider fallback from 70B to 8B instant on rate limits
          if (primaryProvider.id == 'groq' && primaryModel != 'llama-3.1-8b-instant') {
            const groqFreeFallbacks = ['llama-3.1-8b-instant'];
            for (final freeModel in groqFreeFallbacks) {
              try {
                AppLogger.info('Rotating Groq to model: $freeModel...', 'LlmService');
                onFailover?.call('Groq ($freeModel)');

                final result = await transformText(
                  provider: primaryProvider,
                  apiKey: primaryApiKey,
                  featureId: featureId,
                  text: text,
                  customSystemPrompt: customSystemPrompt,
                  model: freeModel,
                  targetLanguage: targetLanguage,
                  params: params,
                );
                onFailoverDetails?.call(primaryProvider, freeModel, reason);
                return result;
              } catch (freeErr) {
                AppLogger.warn('Groq model $freeModel failed: $freeErr', 'LlmService');
                continue;
              }
            }
          }
        }

        // Stage 2: Cross-Provider Failover Cascade across configured keys
        final candidates = <String>[
          'groq',
          'openrouter',
          'gemini',
          'cerebras',
          'sambanova',
          'github',
          'siliconflow',
          'pollinations',
        ];
        candidates.remove(primaryProvider.id);

        for (final candidateId in candidates) {
          final candidateProvider = LlmProvider.getById(candidateId);
          final candidateKey = allConfiguredKeys[candidateId] ?? '';

          if (!candidateProvider.requiresKey || candidateKey.isNotEmpty) {
            try {
              AppLogger.info('Failing over to ${candidateProvider.name}...', 'LlmService');
              onFailover?.call(candidateProvider.name);

              final result = await transformText(
                provider: candidateProvider,
                apiKey: candidateKey,
                featureId: featureId,
                text: text,
                customSystemPrompt: customSystemPrompt,
                model: candidateProvider.defaultModel,
                targetLanguage: targetLanguage,
                params: params,
              );
              onFailoverDetails?.call(candidateProvider, candidateProvider.defaultModel, reason);
              return result;
            } catch (fallbackError) {
              AppLogger.warn('Fallback candidate ${candidateProvider.name} failed: $fallbackError', 'LlmService');
              continue;
            }
          }
        }
      }
      rethrow;
    }
  }

  /// Evaluates AI writing likelihood, plagiarism, and stylometric characteristics
  /// directly using the active frontier LLM API over the internet.
  Future<Map<String, dynamic>> auditPlagiarismWithLlm({
    required LlmProvider provider,
    required String apiKey,
    required String text,
    String? model,
    Map<String, String>? allConfiguredKeys,
    String? customBaseUrl,
    LlmGenerationParams? params,
    Function(String fallbackProviderName)? onFailover,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty && provider.requiresKey && !provider.isCustom && provider.id != 'ollama' && provider.id != 'pollinations' && provider.id != 'airforce') {
      throw LlmApiException('API key required for ${provider.name}. Offline engine is disabled.');
    }

    final effectiveParams = (params ?? const LlmGenerationParams()).copyWith(
      temperature: 0.1, // Deterministic forensic evaluation
      topP: 0.9,
    );

    final rawJson = await transformTextWithFailover(
      primaryProvider: provider,
      primaryApiKey: trimmedKey,
      featureId: 'PlagiarismCheck',
      text: text,
      allConfiguredKeys: allConfiguredKeys ?? {},
      primaryModel: model,
      customBaseUrl: customBaseUrl,
      params: effectiveParams,
      onFailover: onFailover,
    );

    return parseAuditJson(rawJson, originalText: text);
  }

  /// Parses raw LLM output into structured audit dictionary
  static Map<String, dynamic> parseAuditJson(String rawOutput, {String? originalText}) {
    var cleaned = stripThinkingTags(rawOutput).trim();

    // 1. Strip markdown code fence wrapper if present
    final codeBlockPattern = RegExp(r'^```(?:json)?\s*\n([\s\S]*?)\n```\s*$', caseSensitive: false);
    final match = codeBlockPattern.firstMatch(cleaned);
    if (match != null) {
      cleaned = match.group(1)!.trim();
    }

    // 2. Direct JSON decode
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        return _normalizeAuditMap(decoded, originalText: originalText);
      }
    } catch (_) {
      // 3. Fallback: extract outermost JSON block { ... }
      final jsonObjectPattern = RegExp(r'\{[\s\S]*\}');
      final objMatch = jsonObjectPattern.firstMatch(cleaned);
      if (objMatch != null) {
        try {
          final decoded = jsonDecode(objMatch.group(0)!);
          if (decoded is Map<String, dynamic>) {
            return _normalizeAuditMap(decoded, originalText: originalText);
          }
        } catch (_) {}
      }
    }

    // 4. Regex extraction if LLM emitted conversational text with score values
    final overallMatch = RegExp(r'"?overallScore"?\s*:\s*([0-9.]+)').firstMatch(cleaned);
    final score = overallMatch != null ? double.tryParse(overallMatch.group(1)!) ?? 50.0 : 50.0;

    return {
      'overallScore': score,
      'plagiarismRiskScore': 0.0,
      'burstinessScore': 0.5,
      'predictabilityScore': score,
      'lexicalRichness': 70.0,
      'ngramOverlapScore': 0.0,
      'detectedTells': <String>['Frontier LLM Evaluation'],
      'defensibleSummary': cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned,
      'flaggedBoilerplates': <String>[],
      'sentences': <Map<String, dynamic>>[],
    };
  }

  static Map<String, dynamic> _normalizeAuditMap(Map<String, dynamic> raw, {String? originalText}) {
    final overall = (raw['overallScore'] as num?)?.toDouble() ??
        (raw['aiScore'] as num?)?.toDouble() ??
        (raw['aiProbability'] as num?)?.toDouble() ??
        50.0;

    final plagiarismRisk = (raw['plagiarismRiskScore'] as num?)?.toDouble() ??
        (raw['plagiarismScore'] as num?)?.toDouble() ??
        0.0;

    final burstiness = (raw['burstinessScore'] as num?)?.toDouble() ??
        (raw['burstiness'] as num?)?.toDouble() ??
        0.5;

    final predictability = (raw['predictabilityScore'] as num?)?.toDouble() ??
        (raw['predictability'] as num?)?.toDouble() ??
        overall;

    final lexicalRichness = (raw['lexicalRichness'] as num?)?.toDouble() ?? 70.0;
    final ngramOverlap = (raw['ngramOverlapScore'] as num?)?.toDouble() ?? 0.0;

    final detectedTellsRaw = raw['detectedTells'];
    final detectedTells = <String>[];
    if (detectedTellsRaw is List) {
      for (final t in detectedTellsRaw) {
        if (t != null && t.toString().trim().isNotEmpty) {
          detectedTells.add(t.toString().trim());
        }
      }
    }

    final boilerplatesRaw = raw['flaggedBoilerplates'];
    final flaggedBoilerplates = <String>[];
    if (boilerplatesRaw is List) {
      for (final b in boilerplatesRaw) {
        if (b != null && b.toString().trim().isNotEmpty) {
          flaggedBoilerplates.add(b.toString().trim());
        }
      }
    }

    final summary = raw['defensibleSummary'] as String? ??
        raw['summary'] as String? ??
        'Evaluated by Frontier LLM engine.';

    final sentencesRaw = raw['sentences'];
    final sentences = <Map<String, dynamic>>[];
    if (sentencesRaw is List) {
      for (final s in sentencesRaw) {
        if (s is Map<String, dynamic>) {
          sentences.add(s);
        }
      }
    }

    return {
      'overallScore': overall.clamp(0.0, 100.0),
      'plagiarismRiskScore': plagiarismRisk.clamp(0.0, 100.0),
      'burstinessScore': burstiness.clamp(0.0, 2.0),
      'predictabilityScore': predictability.clamp(0.0, 100.0),
      'lexicalRichness': lexicalRichness.clamp(0.0, 100.0),
      'ngramOverlapScore': ngramOverlap.clamp(0.0, 100.0),
      'detectedTells': detectedTells,
      'defensibleSummary': summary,
      'flaggedBoilerplates': flaggedBoilerplates,
      'sentences': sentences,
    };
  }

  /// Stream text transformation token-by-token over Server-Sent Events (SSE)
  Stream<String> transformTextStream({
    required LlmProvider provider,
    required String apiKey,
    required String featureId,
    required String text,
    String? model,
    String? customBaseUrl,
    String? targetLanguage,
    LlmGenerationParams? params,
  }) async* {
    final keyToUse = apiKey.trim();
    if (keyToUse.isEmpty && provider.requiresKey && !provider.isCustom && provider.id != 'ollama' && provider.id != 'pollinations' && provider.id != 'airforce') {
      throw LlmApiException(
        '${provider.name} API Key is not configured. Please add your key in Settings.',
        isAuthError: true,
      );
    }

    if (text.trim().isEmpty) {
      throw LlmApiException('Text cannot be empty.');
    }

    final selectedModel = (model != null && model.trim().isNotEmpty)
        ? model.trim()
        : provider.defaultModel;

    // For Humanize, ensure anti-detection sampling variance if not explicitly set high
    final effectiveParams = (featureId == 'Humanize' && (params == null || params.temperature < 0.85))
        ? (params ?? const LlmGenerationParams()).copyWith(
            temperature: 0.88,
            topP: 0.95,
            frequencyPenalty: 0.35,
            presencePenalty: 0.20,
          )
        : params;

    var systemPrompt = AppPrompts.buildSystemPrompt(featureId, targetLanguage: targetLanguage, persona: effectiveParams?.persona);
    if (effectiveParams != null && effectiveParams.persona != 'standard') {
      systemPrompt = '$systemPrompt\n\nPersona: ${effectiveParams.personaInstruction}';
    }
    if (effectiveParams != null && effectiveParams.ragContext != null && effectiveParams.ragContext!.trim().isNotEmpty) {
      systemPrompt = '$systemPrompt\n\n[RAG GROUNDING & STYLE CONTEXT]:\n${effectiveParams.ragContext!.trim()}\nAdhere strictly to the terminology, stylistic tone, and factual grounding provided above.';
    }

    final userPrompt = AppPrompts.buildUserPrompt(featureId, text, targetLanguage: targetLanguage);
    final endpoint = _getCompletionsEndpoint(provider, customBaseUrl: customBaseUrl);
    final headers = _buildHeaders(provider, keyToUse);

    if (effectiveParams != null && effectiveParams.langsmithTracing) {
      headers['x-langsmith-trace'] = 'true';
      headers['x-langsmith-project'] = effectiveParams.langsmithProject ?? 'lauriva-app';
      if (effectiveParams.langsmithApiKey != null && effectiveParams.langsmithApiKey!.isNotEmpty) {
        headers['x-langsmith-api-key'] = effectiveParams.langsmithApiKey!;
      }
    }

    final temp = effectiveParams?.temperature ?? 0.3;
    final maxTok = effectiveParams?.maxTokens ?? 2048;
    final topP = effectiveParams?.topP ?? 0.9;

    final requestPayload = _buildRequestPayload(
      provider: provider,
      selectedModel: selectedModel,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temp: temp,
      maxTok: maxTok,
      topP: topP,
      params: effectiveParams,
      isStreaming: true,
    );

    AppLogger.info(
      'Starting LLM SSE stream (provider: ${provider.name}, model: $selectedModel)',
      'LlmService',
    );

    final request = http.Request('POST', Uri.parse(endpoint));
    request.headers.addAll(headers);
    request.body = jsonEncode(requestPayload);

    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 35));
    } on TimeoutException {
      throw LlmApiException('Connection to ${provider.name} timed out.');
    } on http.ClientException catch (e) {
      throw LlmApiException('Network error connecting to ${provider.name}: ${e.message}');
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw LlmApiException(
          'Invalid or unauthorized API key for ${provider.name}. Please verify your key in Settings.',
          statusCode: response.statusCode,
          isAuthError: true,
        );
      } else if (response.statusCode == 429) {
        throw LlmApiException(
          'Rate limit exceeded for ${provider.name} ($selectedModel). Please wait a moment or switch models.',
          statusCode: 429,
          isRateLimit: true,
        );
      } else {
        try {
          final errorJson = jsonDecode(body);
          final errorMsg = errorJson['error']?['message'] ??
              errorJson['message'] ??
              '${provider.name} API error (${response.statusCode})';
          throw LlmApiException(errorMsg.toString(), statusCode: response.statusCode);
        } catch (e) {
          if (e is LlmApiException) rethrow;
          throw LlmApiException(
            'Failed to communicate with ${provider.name} (${response.statusCode}): $body',
            statusCode: response.statusCode,
          );
        }
      }
    }

    bool insideThinking = false;
    final lines = response.stream
        .timeout(
          const Duration(seconds: 25),
          onTimeout: (sink) {
            sink.addError(TimeoutException('Connection to ${provider.name} timed out while generating tokens.'));
            sink.close();
          },
        )
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

        final dataStr = trimmed.substring(5).trim();
        if (dataStr == '[DONE]') break;

        try {
          final decoded = jsonDecode(dataStr) as Map<String, dynamic>;
          String? token;

          // 1. OpenAI / Groq / Cerebras / SambaNova / Ollama / DeepSeek / Mistral / OpenRouter
          final choices = decoded['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final first = choices[0] as Map<String, dynamic>;
            final delta = first['delta'] as Map<String, dynamic>?;
            token = delta?['content'] as String?;
            if (token == null && delta?['reasoning_content'] is String) {
              if (params?.stripThinking == false) {
                token = delta!['reasoning_content'] as String;
              }
            }
            token ??= first['text'] as String?;
          }
          // 2. Anthropic format
          else if (decoded['type'] == 'content_block_delta' && decoded['delta'] is Map) {
            final delta = decoded['delta'] as Map<String, dynamic>;
            token = delta['text'] as String?;
          } else if (decoded['delta'] is Map) {
            final delta = decoded['delta'] as Map<String, dynamic>;
            token = delta['text'] as String? ?? delta['content'] as String?;
          }
          // 3. Google Gemini streaming format
          else if (decoded['candidates'] is List) {
            final candidates = decoded['candidates'] as List<dynamic>;
            if (candidates.isNotEmpty) {
              final first = candidates[0] as Map<String, dynamic>;
              final contentObj = first['content'] as Map<String, dynamic>?;
              final parts = contentObj?['parts'] as List<dynamic>?;
              if (parts != null && parts.isNotEmpty) {
                final firstPart = parts[0] as Map<String, dynamic>?;
                token = firstPart?['text'] as String?;
              }
            }
          }
          // 4. Cohere v2 streaming format
          else if (decoded['delta'] is Map && (decoded['delta'] as Map)['message'] is Map) {
            final deltaMsg = (decoded['delta'] as Map)['message'] as Map<String, dynamic>;
            final content = deltaMsg['content'] as Map<String, dynamic>?;
            token = content?['text'] as String?;
          }
          // 5. Fallback root text field
          else if (decoded['text'] is String) {
            token = decoded['text'] as String;
          }

          if (token != null && token.isNotEmpty) {
            if (params?.stripThinking ?? true) {
              if (!insideThinking && token.contains('<think>')) {
                insideThinking = true;
                final parts = token.split('<think>');
                if (parts[0].isNotEmpty) yield parts[0];
                if (parts.length > 1 && parts[1].contains('</think>')) {
                  insideThinking = false;
                  final postParts = parts[1].split('</think>');
                  if (postParts.length > 1 && postParts[1].isNotEmpty) {
                    yield postParts[1];
                  }
                }
                continue;
              }
              if (insideThinking) {
                if (token.contains('</think>')) {
                  insideThinking = false;
                  final parts = token.split('</think>');
                  if (parts.length > 1 && parts[1].isNotEmpty) {
                    yield parts[1];
                  }
                }
                continue;
              }
            }
            yield token;
          }
        } catch (_) {
          // Skip malformed individual stream frames
        }
      }
    } on TimeoutException {
      throw LlmApiException(
        'Connection to ${provider.name} timed out while waiting for tokens.',
        statusCode: 504,
      );
    }
  }

  /// Stream text with auto-failover: switches candidate providers seamlessly
  Stream<String> transformTextStreamWithFailover({
    required LlmProvider primaryProvider,
    required String primaryApiKey,
    required String featureId,
    required String text,
    required Map<String, String> allConfiguredKeys,
    String? primaryModel,
    String? customBaseUrl,
    String? targetLanguage,
    LlmGenerationParams? params,
    Function(String fallbackProviderName)? onFailover,
    void Function(LlmProvider provider, String model, String reason)? onFailoverDetails,
  }) async* {
    bool yieldedAny = false;
    try {
      await for (final token in transformTextStream(
        provider: primaryProvider,
        apiKey: primaryApiKey,
        featureId: featureId,
        text: text,
        model: primaryModel,
        customBaseUrl: customBaseUrl,
        targetLanguage: targetLanguage,
        params: params,
      )) {
        yieldedAny = true;
        yield token;
      }
    } on LlmApiException catch (e) {
      final shouldFailover = !yieldedAny &&
          (params?.autoFailover ?? true) &&
          (e.isCreditExhausted ||
           e.isRateLimit ||
           (!e.isAuthError &&
            (e.statusCode != null &&
             (e.statusCode! >= 500 || e.statusCode == 400 || e.statusCode == 402 || e.statusCode == 404 || e.statusCode == 422))));

      if (shouldFailover) {
        final reason = e.isCreditExhausted
            ? 'Credits depleted'
            : (e.isRateLimit ? 'Rate limit reached' : 'Server error (${e.statusCode})');
        AppLogger.warn(
          'Primary provider ${primaryProvider.name} failed ($reason: ${e.message}). Initiating streaming auto-failover...',
          'LlmService',
        );

        // Stage 1: Intra-Provider Free-Model Rotation (OpenRouter)
        // Stage 1: Intra-Provider Free-Model Pool Rotation (OpenRouter / Groq)
        final isModelSpecificFailure = e.isCreditExhausted || e.isRateLimit || e.statusCode == 429 || e.statusCode == 402;
        if (isModelSpecificFailure) {
          if (primaryProvider.id == 'openrouter') {
            const openRouterFreeFallbacks = [
              'meta-llama/llama-3.3-70b-instruct:free',
              'google/gemma-4-31b-it:free',
              'mistralai/mistral-small-24b-instruct-2501:free',
              'qwen/qwen-2.5-72b-instruct:free',
            ];

            for (final freeModel in openRouterFreeFallbacks) {
              if (freeModel == primaryModel) continue;
              try {
                AppLogger.info('Streaming rotation on OpenRouter to free model: $freeModel...', 'LlmService');
                onFailover?.call('OpenRouter ($freeModel)');

                var notified = false;
                await for (final token in transformTextStream(
                  provider: primaryProvider,
                  apiKey: primaryApiKey,
                  featureId: featureId,
                  text: text,
                  model: freeModel,
                  targetLanguage: targetLanguage,
                  params: params,
                )) {
                  if (!notified) {
                    onFailoverDetails?.call(primaryProvider, freeModel, reason);
                    notified = true;
                  }
                  yield token;
                }
                return;
              } catch (freeErr) {
                AppLogger.warn('OpenRouter streaming free model $freeModel failed: $freeErr', 'LlmService');
                continue;
              }
            }
          }

          // Groq streaming intra-provider fallback from 70B to 8B instant
          if (primaryProvider.id == 'groq' && primaryModel != 'llama-3.1-8b-instant') {
            const groqFreeFallbacks = ['llama-3.1-8b-instant'];
            for (final freeModel in groqFreeFallbacks) {
              try {
                AppLogger.info('Streaming rotation on Groq to model: $freeModel...', 'LlmService');
                onFailover?.call('Groq ($freeModel)');

                var notified = false;
                await for (final token in transformTextStream(
                  provider: primaryProvider,
                  apiKey: primaryApiKey,
                  featureId: featureId,
                  text: text,
                  model: freeModel,
                  targetLanguage: targetLanguage,
                  params: params,
                )) {
                  if (!notified) {
                    onFailoverDetails?.call(primaryProvider, freeModel, reason);
                    notified = true;
                  }
                  yield token;
                }
                return;
              } catch (freeErr) {
                AppLogger.warn('Groq streaming model $freeModel failed: $freeErr', 'LlmService');
                continue;
              }
            }
          }
        }

        // Stage 2: Cross-Provider Failover Cascade
        final candidates = <String>[
          'groq',
          'openrouter',
          'gemini',
          'cerebras',
          'sambanova',
          'github',
          'siliconflow',
          'pollinations',
        ];
        candidates.remove(primaryProvider.id);

        for (final candidateId in candidates) {
          final candidateProvider = LlmProvider.getById(candidateId);
          final candidateKey = allConfiguredKeys[candidateId] ?? '';

          if (!candidateProvider.requiresKey || candidateKey.isNotEmpty) {
            try {
              AppLogger.info('Streaming failover to ${candidateProvider.name}...', 'LlmService');
              onFailover?.call(candidateProvider.name);

              var notified = false;
              await for (final token in transformTextStream(
                provider: candidateProvider,
                apiKey: candidateKey,
                featureId: featureId,
                text: text,
                model: candidateProvider.defaultModel,
                targetLanguage: targetLanguage,
                params: params,
              )) {
                if (!notified) {
                  onFailoverDetails?.call(candidateProvider, candidateProvider.defaultModel, reason);
                  notified = true;
                }
                yield token;
              }
              return;
            } catch (fallbackError) {
              AppLogger.warn(
                'Streaming fallback candidate ${candidateProvider.name} failed: $fallbackError',
                'LlmService',
              );
              continue;
            }
          }
        }
      }
      rethrow;
    }
  }

  /// Test connection and API key validity with a lightweight auth probe
  Future<bool> testApiKey(
    LlmProvider provider,
    String apiKey, {
    String? model,
    String? customBaseUrl,
  }) async {
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      return !provider.requiresKey;
    }

    // 1. URLs and malformed strings are NEVER valid API keys
    if (trimmedKey.startsWith('http://') ||
        trimmedKey.startsWith('https://') ||
        trimmedKey.startsWith('www.') ||
        trimmedKey.contains('://')) {
      return false;
    }
    if (trimmedKey.length < 8 && provider.requiresKey && !provider.isCustom) {
      return false;
    }

    // 2. Keyless providers require no verification
    if (!provider.requiresKey) {
      return true;
    }

    try {
      final base = _cleanBaseUrl(customBaseUrl ?? provider.baseUrl);
      final headers = _buildHeaders(provider, trimmedKey);

      // 3. OpenRouter dedicated auth verification endpoint
      if (provider.id == 'openrouter') {
        final res = await _client
            .get(Uri.parse('https://openrouter.ai/api/v1/auth/key'), headers: headers)
            .timeout(const Duration(seconds: 8));
        return res.statusCode == 200;
      }

      // 4. Anthropic Claude Messages auth check
      if (provider.id == 'anthropic') {
        final res = await _client
            .post(
              Uri.parse('$base/messages'),
              headers: headers,
              body: jsonEncode({
                'model': (model != null && model.isNotEmpty) ? model : provider.defaultModel,
                'max_tokens': 10,
                'messages': [
                  {'role': 'user', 'content': 'ping'}
                ],
              }),
            )
            .timeout(const Duration(seconds: 8));
        // 200 = Success, 429 = Valid key with rate limit. 401/403 = Invalid key.
        return res.statusCode == 200 || res.statusCode == 429;
      }

      // 5. Google Gemini OpenAI-compatible models verification
      if (provider.id == 'gemini') {
        final res = await _client
            .get(Uri.parse('$base/models'), headers: headers)
            .timeout(const Duration(seconds: 8));
        // Google returns 200 on valid key, 400 with 'INVALID_ARGUMENT' on invalid key
        return res.statusCode == 200;
      }

      // 6. Standard OpenAI-Compatible & dynamic discovery providers (Groq, OpenAI, Mistral, DeepSeek, Cerebras, etc.)
      final modelsRes = await _client
          .get(Uri.parse('$base/models'), headers: headers)
          .timeout(const Duration(seconds: 8));

      if (modelsRes.statusCode == 200) {
        return true;
      }
      if (modelsRes.statusCode == 401 || modelsRes.statusCode == 403) {
        return false;
      }

      // 7. Fallback for custom proxies where /models is 404 or 405: send test completion probe
      final endpoint = _getCompletionsEndpoint(provider, customBaseUrl: customBaseUrl);
      final testModel = (model != null && model.isNotEmpty) ? model : provider.defaultModel;
      final isReasoning = isOpenAiReasoningModel(testModel);
      final testPayload = _buildRequestPayload(
        provider: provider,
        selectedModel: testModel,
        systemPrompt: 'You are a test probe.',
        userPrompt: 'ping',
        temp: 0.1,
        maxTok: isReasoning ? 50 : 10,
        topP: 0.9,
        params: null,
        isStreaming: false,
      );

      final compRes = await _client
          .post(
            Uri.parse(endpoint),
            headers: headers,
            body: jsonEncode(testPayload),
          )
          .timeout(const Duration(seconds: 8));

      return compRes.statusCode == 200 || compRes.statusCode == 429;
    } catch (e) {
      AppLogger.warn('Auth probe failed for ${provider.name}: $e', 'LlmService');
      return false;
    }
  }

  /// Fetch live model catalog from /models endpoint
  Future<List<LlmModelInfo>> fetchLiveModels(
    LlmProvider provider,
    String apiKey, {
    String? customBaseUrl,
  }) async {
    final base = _cleanBaseUrl(customBaseUrl ?? provider.baseUrl);
    final endpoint = '$base/models';
    final headers = _buildHeaders(provider, apiKey);

    try {
      final response = await _client
          .get(Uri.parse(endpoint), headers: headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final data = decoded['data'] as List<dynamic>?;
        if (data != null && data.isNotEmpty) {
          final List<LlmModelInfo> models = [];
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final id = item['id'] as String? ?? '';
              if (id.isEmpty) continue;
              final name = item['name'] as String? ?? id;
              final desc = item['description'] as String? ?? '';
              final contextLen = item['context_length'] as int?;

              // Detect category & free tier
              bool isFree = false;
              if (id.endsWith(':free') || !provider.requiresKey) {
                isFree = true;
              } else if (item['pricing'] is Map<String, dynamic>) {
                final pricing = item['pricing'] as Map<String, dynamic>;
                final prompt = pricing['prompt']?.toString() ?? '';
                final completion = pricing['completion']?.toString() ?? '';
                if (prompt == '0' && completion == '0') {
                  isFree = true;
                }
              }

              String category = 'general';
              final lower = id.toLowerCase();
              if (lower.contains('r1') || lower.contains('o1') || lower.contains('reason') || lower.contains('qwq') || lower.contains('thinking')) {
                category = 'reasoning';
              } else if (lower.contains('flash') || lower.contains('instant') || lower.contains('8b') || lower.contains('mini')) {
                category = 'fast';
              } else if (lower.contains('qwen') || lower.contains('command') || lower.contains('mistral') || lower.contains('glm')) {
                category = 'multilingual';
              } else if (lower.contains('code')) {
                category = 'code';
              }

              models.add(
                LlmModelInfo(
                  id: id,
                  name: name,
                  description: desc,
                  isFree: isFree,
                  tag: isFree ? 'Free' : null,
                  contextWindow: contextLen,
                  category: category,
                ),
              );
            }
          }
          return models;
        }
      }
    } catch (e) {
      AppLogger.warn('Failed to fetch live models for ${provider.name}: $e', 'LlmService');
    }
    return provider.models;
  }
}
