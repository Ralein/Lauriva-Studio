class LlmModelInfo {
  final String id;
  final String name;
  final String description;
  final bool isFree;
  final String? tag;
  final int? contextWindow;
  final String category; // 'general', 'reasoning', 'fast', 'multilingual', 'creative', 'code'

  const LlmModelInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.isFree = true,
    this.tag,
    this.contextWindow,
    this.category = 'general',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'isFree': isFree,
        'tag': tag,
        'contextWindow': contextWindow,
        'category': category,
      };

  factory LlmModelInfo.fromJson(Map<String, dynamic> json) => LlmModelInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? (json['id'] as String? ?? ''),
        description: json['description'] as String? ?? '',
        isFree: json['isFree'] as bool? ?? false,
        tag: json['tag'] as String?,
        contextWindow: json['contextWindow'] as int?,
        category: json['category'] as String? ?? 'general',
      );
}

class LlmGenerationParams {
  final double temperature;
  final int maxTokens;
  final double topP;
  final String persona; // 'standard', 'executive', 'casual', 'academic'
  final bool stripThinking;
  final bool autoFailover;
  final String? loraAdapter; // LoRA adapter checkpoint e.g. huggingface repo or peft id
  final String? ragContext; // Lightweight RAG reference snippets & style grounding
  final bool langsmithTracing; // Observability & run tracing
  final String? langsmithProject;
  final String? langsmithApiKey;
  final double frequencyPenalty; // Discourages repeated tokens/phrases (formulaic AI loops)
  final double presencePenalty; // Discourages sticking to a narrow topic vocabulary

  const LlmGenerationParams({
    this.temperature = 0.3,
    this.maxTokens = 2048,
    this.topP = 0.9,
    this.persona = 'standard',
    this.stripThinking = true,
    this.autoFailover = true,
    this.loraAdapter,
    this.ragContext,
    this.langsmithTracing = false,
    this.langsmithProject,
    this.langsmithApiKey,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
  });

  LlmGenerationParams copyWith({
    double? temperature,
    int? maxTokens,
    double? topP,
    String? persona,
    bool? stripThinking,
    bool? autoFailover,
    String? loraAdapter,
    String? ragContext,
    bool? langsmithTracing,
    String? langsmithProject,
    String? langsmithApiKey,
    double? frequencyPenalty,
    double? presencePenalty,
  }) {
    return LlmGenerationParams(
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      persona: persona ?? this.persona,
      stripThinking: stripThinking ?? this.stripThinking,
      autoFailover: autoFailover ?? this.autoFailover,
      loraAdapter: loraAdapter ?? this.loraAdapter,
      ragContext: ragContext ?? this.ragContext,
      langsmithTracing: langsmithTracing ?? this.langsmithTracing,
      langsmithProject: langsmithProject ?? this.langsmithProject,
      langsmithApiKey: langsmithApiKey ?? this.langsmithApiKey,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
    );
  }

  String get personaInstruction {
    switch (persona) {
      case 'executive':
        return 'Adopt an executive, authoritative, and strategic tone suitable for high-stakes business communication.';
      case 'casual':
        return 'Adopt a friendly, punchy, conversational tone with vibrant phrasing and zero corporate jargon.';
      case 'academic':
        return 'Adopt a scholarly, analytically rigorous tone with precise terminology and structured logic.';
      case 'creative':
        return 'Adopt a vivid, imaginative tone with expressive language, evocative imagery, and original phrasing while preserving the original meaning.';
      case 'punchy':
        return 'Use short, punchy sentences. Alternate crisp fragments with longer sentences for maximum impact. Cut every filler word.';
      case 'standard':
      default:
        return 'Deliver clean, polished, direct output matching the user\'s intent.';
    }
  }
}

class LlmProvider {
  final String id;
  final String name;
  final String tag;
  final String baseUrl;
  final String keyPortalUrl;
  final String keyHint;
  final String description;
  final String defaultModel;
  final List<LlmModelInfo> curatedModels;
  final bool supportsModelDiscovery;
  final bool requiresKey;
  final Map<String, String>? extraHeaders;

  const LlmProvider({
    required this.id,
    required this.name,
    required this.tag,
    required this.baseUrl,
    required this.keyPortalUrl,
    required this.keyHint,
    required this.description,
    required this.defaultModel,
    this.curatedModels = const [],
    this.supportsModelDiscovery = true,
    this.requiresKey = true,
    this.extraHeaders,
  });

  bool get isCustom => id == 'custom_freellmapi';

  List<LlmModelInfo> get models => curatedModels.isNotEmpty
      ? curatedModels
      : [
          LlmModelInfo(
            id: defaultModel,
            name: defaultModel,
            isFree: !requiresKey || defaultModel.endsWith(':free'),
          )
        ];

  String get catalogUrl {
    switch (id) {
      case 'openrouter':
        return 'https://openrouter.ai/models';
      case 'groq':
        return 'https://console.groq.com/docs/models';
      case 'gemini':
        return 'https://ai.google.dev/gemini-api/docs/models/gemini';
      case 'cerebras':
        return 'https://inference-docs.cerebras.net/';
      case 'pollinations':
        return 'https://pollinations.ai';
      case 'nvidia':
        return 'https://build.nvidia.com/explore/discover';
      case 'siliconflow':
        return 'https://docs.siliconflow.cn/models';
      case 'cloudflare':
        return 'https://developers.cloudflare.com/workers-ai/models/';
      case 'zhipu':
        return 'https://open.bigmodel.cn/dev/api';
      case 'github':
        return 'https://github.com/marketplace/models';
      case 'deepseek':
        return 'https://platform.deepseek.com/';
      case 'mistral':
        return 'https://docs.mistral.ai/getting-started/models/';
      case 'together':
        return 'https://docs.together.ai/docs/inference-models';
      case 'fireworks':
        return 'https://fireworks.ai/models';
      case 'cohere':
        return 'https://docs.cohere.com/docs/models';
      case 'anthropic':
        return 'https://docs.anthropic.com/en/docs/about-claude/models';
      case 'openai':
        return 'https://platform.openai.com/docs/models';
      case 'perplexity':
        return 'https://docs.perplexity.ai/guides/model-cards';
      case 'ollama':
        return 'https://ollama.com/library';
      default:
        return keyPortalUrl;
    }
  }

  String getModelDocumentationUrl(String modelId) {
    if (id == 'openrouter') {
      final cleanId = modelId.replaceAll(':free', '');
      return 'https://openrouter.ai/models/$cleanId';
    }
    return catalogUrl;
  }

  static const List<LlmProvider> allProviders = [
    // 1. OpenRouter (Aggregation of 400+ models)
    LlmProvider(
      id: 'openrouter',
      name: 'OpenRouter',
      tag: '50+ Free Models (400+ Total)',
      baseUrl: 'https://openrouter.ai/api/v1',
      keyPortalUrl: 'https://openrouter.ai/settings/keys',
      keyHint: 'sk-or-v1-...',
      description: 'Single API aggregating 400+ models. All live models fetched directly via dynamic discovery.',
      defaultModel: 'google/gemma-4-31b-it:free',
      extraHeaders: {
        'HTTP-Referer': 'https://lauriva.app',
        'X-Title': 'Lauriva AI Writing Assistant',
      },
    ),

    // 2. Groq (Ultra-Fast LPU)
    LlmProvider(
      id: 'groq',
      name: 'Groq',
      tag: '100% Free LPU (500-1000 tps)',
      baseUrl: 'https://api.groq.com/openai/v1',
      keyPortalUrl: 'https://console.groq.com/keys',
      keyHint: 'gsk_...',
      description: 'Ultra-fast LPU inference (500–1000 tokens/sec). Generous 30 RPM free tier.',
      defaultModel: 'llama-3.3-70b-versatile',
    ),

    // 3. Google Gemini
    LlmProvider(
      id: 'gemini',
      name: 'Google Gemini',
      tag: '15 RPM Free Tier',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      keyPortalUrl: 'https://aistudio.google.com/app/apikey',
      keyHint: 'AIzaSy...',
      description: 'Google AI Studio free tier: 15 RPM, 1M Tokens Per Minute, 1,500 requests per day at zero cost.',
      defaultModel: 'gemini-2.0-flash',
    ),

    // 4. Cerebras
    LlmProvider(
      id: 'cerebras',
      name: 'Cerebras',
      tag: '1800+ TPS Wafer Engine',
      baseUrl: 'https://api.cerebras.ai/v1',
      keyPortalUrl: 'https://cloud.cerebras.ai/platform/',
      keyHint: 'csk-...',
      description: 'World record inference speed on wafer-scale hardware. Free tier: 30 RPM, 1M TPM.',
      defaultModel: 'llama-3.3-70b',
    ),

    // 5. SambaNova
    LlmProvider(
      id: 'sambanova',
      name: 'SambaNova',
      tag: 'Free Cloud Tier (SN40L)',
      baseUrl: 'https://api.sambanova.ai/v1',
      keyPortalUrl: 'https://cloud.sambanova.ai/apis',
      keyHint: '...',
      description: 'Ultra-fast inference on SN40L chips. Generous free tier with support for Llama 3.3 70B and 405B.',
      defaultModel: 'Meta-Llama-3.3-70B-Instruct',
    ),

    // 6. Cloudflare Workers AI
    LlmProvider(
      id: 'cloudflare',
      name: 'Cloudflare AI',
      tag: '10,000 Free Neurons/Day',
      baseUrl: 'https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1',
      keyPortalUrl: 'https://dash.cloudflare.com/',
      keyHint: 'API Token with Workers AI read...',
      description: '10,000 free neurons every single day on Cloudflare worldwide edge network.',
      defaultModel: '@cf/meta/llama-3.3-70b-instruct',
    ),

    // 7. GitHub Models
    LlmProvider(
      id: 'github',
      name: 'GitHub Models',
      tag: 'Free for Developers',
      baseUrl: 'https://models.inference.ai.azure.com',
      keyPortalUrl: 'https://github.com/settings/tokens',
      keyHint: 'ghp_...',
      description: 'Free playground and inference for all GitHub accounts with Personal Access Tokens.',
      defaultModel: 'gpt-4o-mini',
    ),

    // 8. SiliconFlow
    LlmProvider(
      id: 'siliconflow',
      name: 'SiliconFlow',
      tag: '20M Free Tokens',
      baseUrl: 'https://api.siliconflow.cn/v1',
      keyPortalUrl: 'https://cloud.siliconflow.cn/',
      keyHint: 'sk-...',
      description: 'Generous 20 million free tokens upon registration. Ultra-fast DeepSeek V3 and R1 cluster.',
      defaultModel: 'deepseek-ai/DeepSeek-V3',
    ),

    // 9. NVIDIA NIM
    LlmProvider(
      id: 'nvidia',
      name: 'NVIDIA NIM',
      tag: '1,000 Free Credits',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      keyPortalUrl: 'https://build.nvidia.com/',
      keyHint: 'nvapi-...',
      description: 'NVIDIA API Catalog gives 1,000 free API credits to test fully optimized NIM microservices.',
      defaultModel: 'meta/llama-3.3-70b-instruct',
    ),

    // 10. Mistral AI
    LlmProvider(
      id: 'mistral',
      name: 'Mistral AI',
      tag: 'Free Experimentation Tier',
      baseUrl: 'https://api.mistral.ai/v1',
      keyPortalUrl: 'https://console.mistral.ai/api-keys/',
      keyHint: '...',
      description: 'La Plateforme free tier for developers with access to Mistral Small, Nemo, and Codestral.',
      defaultModel: 'mistral-small-latest',
    ),

    // 11. Hugging Face
    LlmProvider(
      id: 'huggingface',
      name: 'Hugging Face',
      tag: 'Serverless Free API',
      baseUrl: 'https://api-inference.huggingface.co/v1',
      keyPortalUrl: 'https://huggingface.co/settings/tokens',
      keyHint: 'hf_...',
      description: 'Free Serverless Inference API for thousands of open-source models with User Access Tokens.',
      defaultModel: 'meta-llama/Llama-3.3-70B-Instruct',
    ),

    // 12. Api.Airforce
    LlmProvider(
      id: 'airforce',
      name: 'Api.Airforce',
      tag: 'Free Community Gateway',
      baseUrl: 'https://api.airforce/v1',
      keyPortalUrl: 'https://api.airforce/',
      keyHint: 'Optional or free key...',
      description: 'Community-driven open inference gateway providing daily free allowances across open models.',
      defaultModel: 'llama-3.3-70b',
      requiresKey: false,
    ),

    // 13. ModelScope
    LlmProvider(
      id: 'modelscope',
      name: 'ModelScope',
      tag: 'Free Community Inference',
      baseUrl: 'https://api-inference.modelscope.cn/v1',
      keyPortalUrl: 'https://modelscope.cn/',
      keyHint: '...',
      description: 'Alibaba Aliyun open AI community with free tier inference for open weights.',
      defaultModel: 'Qwen/Qwen2.5-72B-Instruct',
    ),

    // 14. OpenAI
    LlmProvider(
      id: 'openai',
      name: 'OpenAI',
      tag: 'Flagship Paid Tier',
      baseUrl: 'https://api.openai.com/v1',
      keyPortalUrl: 'https://platform.openai.com/api-keys',
      keyHint: 'sk-proj-... or sk-...',
      description: 'Official OpenAI API. Industry-standard GPT-4o, o1, and o3 reasoning models with state-of-the-art accuracy.',
      defaultModel: 'gpt-4o',
    ),

    // 15. Anthropic Claude
    LlmProvider(
      id: 'anthropic',
      name: 'Anthropic Claude',
      tag: 'Claude 3.7 & 3.5 Flagship',
      baseUrl: 'https://api.anthropic.com/v1',
      keyPortalUrl: 'https://console.anthropic.com/settings/keys',
      keyHint: 'sk-ant-...',
      description: 'Official Anthropic API. World-leading Claude 3.7 Sonnet hybrid reasoning and Claude 3.5 Sonnet prose.',
      defaultModel: 'claude-3-7-sonnet-20250219',
      extraHeaders: {
        'anthropic-version': '2023-06-01',
      },
    ),

    // 16. DeepSeek Official
    LlmProvider(
      id: 'deepseek',
      name: 'DeepSeek Official',
      tag: 'Direct V3 & R1 API',
      baseUrl: 'https://api.deepseek.com/v1',
      keyPortalUrl: 'https://platform.deepseek.com/api_keys',
      keyHint: 'sk-...',
      description: 'Official direct DeepSeek platform with ultra-low cost per token for V3 and R1.',
      defaultModel: 'deepseek-chat',
    ),

    // 17. Perplexity AI
    LlmProvider(
      id: 'perplexity',
      name: 'Perplexity AI',
      tag: 'Search & Grounding',
      baseUrl: 'https://api.perplexity.ai',
      keyPortalUrl: 'https://www.perplexity.ai/settings/api',
      keyHint: 'pplx-...',
      description: 'Live internet citation and factual grounding search models.',
      defaultModel: 'sonar-pro',
    ),

    // 18. Together AI
    LlmProvider(
      id: 'together',
      name: 'Together AI',
      tag: r'$5 Free Credits',
      baseUrl: 'https://api.together.xyz/v1',
      keyPortalUrl: 'https://api.together.xyz/settings/api-keys',
      keyHint: '...',
      description: r'$5 starter credit upon registration. Over 100 open source models hosted with fast inference.',
      defaultModel: 'meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo',
    ),

    // 19. Cohere
    LlmProvider(
      id: 'cohere',
      name: 'Cohere',
      tag: 'Free Trial Key',
      baseUrl: 'https://api.cohere.com/v2',
      keyPortalUrl: 'https://dashboard.cohere.com/api-keys',
      keyHint: '...',
      description: 'Free trial API key for experimentation with enterprise Command R+ models.',
      defaultModel: 'command-r-plus',
    ),

    // 20. Hyperbolic
    LlmProvider(
      id: 'hyperbolic',
      name: 'Hyperbolic',
      tag: 'High-Speed Open Cloud',
      baseUrl: 'https://api.hyperbolic.xyz/v1',
      keyPortalUrl: 'https://app.hyperbolic.xyz/',
      keyHint: '...',
      description: 'Fast open-source inference with generous developer starter credits.',
      defaultModel: 'deepseek-ai/DeepSeek-R1',
    ),

    // 21. DeepInfra
    LlmProvider(
      id: 'deepinfra',
      name: 'DeepInfra',
      tag: 'Free Credits & Low Cost',
      baseUrl: 'https://api.deepinfra.com/v1/openai',
      keyPortalUrl: 'https://deepinfra.com/dash/api_keys',
      keyHint: '...',
      description: 'Free starter credits for developers with ultra-cheap serverless open model endpoints.',
      defaultModel: 'meta-llama/Meta-Llama-3.3-70B-Instruct',
    ),

    // 22. Novita AI
    LlmProvider(
      id: 'novita',
      name: 'Novita AI',
      tag: 'Developer Free Credits',
      baseUrl: 'https://api.novita.ai/v3/openai',
      keyPortalUrl: 'https://novita.ai/',
      keyHint: '...',
      description: 'Developer cloud providing trial credits for open weights inference.',
      defaultModel: 'deepseek/deepseek-r1',
    ),

    // 23. Zhipu AI
    LlmProvider(
      id: 'zhipu',
      name: 'Zhipu AI (GLM)',
      tag: 'Unlimited Free GLM-4-Flash',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      keyPortalUrl: 'https://bigmodel.cn/',
      keyHint: '...',
      description: 'GLM-4-Flash is permanently 100% free with unlimited API calls and 128k context.',
      defaultModel: 'glm-4-flash',
    ),

    // 24. Pollinations.ai (Keyless community pool)
    LlmProvider(
      id: 'pollinations',
      name: 'Pollinations.ai',
      tag: 'No Key Needed (Instant)',
      baseUrl: 'https://text.pollinations.ai/openai',
      keyPortalUrl: 'https://pollinations.ai',
      keyHint: 'No API key needed (Public Free)',
      description: '100% free open inference platform. No account, no credit card, no API key required! Works immediately.',
      defaultModel: 'openai',
      requiresKey: false,
    ),

    // 25. Ollama (Zero-Config Local Offline)
    LlmProvider(
      id: 'ollama',
      name: 'Ollama (Local Offline)',
      tag: 'Zero-Cloud Private',
      baseUrl: 'http://localhost:11434/v1',
      keyPortalUrl: 'https://ollama.com',
      keyHint: 'No API key needed (localhost:11434)',
      description: 'Run 100% private, on-device models locally. No internet connection or API keys required.',
      defaultModel: 'llama3.2:latest',
      requiresKey: false,
    ),

    // 26. FreeLLMAPI & Custom Endpoint
    LlmProvider(
      id: 'custom_freellmapi',
      name: 'FreeLLMAPI & Custom Endpoint',
      tag: 'Any OpenAI-Compatible URL',
      baseUrl: 'http://localhost:11434/v1',
      keyPortalUrl: 'https://freellmapi.co',
      keyHint: 'Optional API key or Bearer token...',
      description: 'Connect to any OpenAI-compatible API, local Ollama (http://localhost:11434/v1), LM Studio, vLLM, or self-hosted gateway.',
      defaultModel: 'llama3.3:latest',
      requiresKey: false,
    ),
  ];

  static LlmProvider getById(String id) {
    return allProviders.firstWhere(
      (p) => p.id == id,
      orElse: () => allProviders.first,
    );
  }

  /// Smartly detect provider from an API key's prefix/format
  static String? detectProviderFromKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('www.')) {
      return null;
    }

    if (trimmed.startsWith('sk-proj-') || trimmed.startsWith('sk-admin-')) return 'openai';
    if (trimmed.startsWith('sk-ant-')) return 'anthropic';
    if (trimmed.startsWith('pplx-')) return 'perplexity';
    if (trimmed.startsWith('gsk_')) return 'groq';
    if (trimmed.startsWith('sk-or-v1-')) return 'openrouter';
    if (trimmed.startsWith('AIzaSy')) return 'gemini';
    if (trimmed.startsWith('csk-')) return 'cerebras';
    if (trimmed.startsWith('nvapi-')) return 'nvidia';
    if (trimmed.startsWith('ghp_') || trimmed.startsWith('github_pat_')) return 'github';
    if (trimmed.startsWith('hf_')) return 'huggingface';
    if (trimmed.startsWith('sk-')) return 'openai';

    return null;
  }
}
