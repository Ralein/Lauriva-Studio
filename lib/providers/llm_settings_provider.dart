import 'package:flutter/foundation.dart';
import '../models/llm_provider.dart';
import '../services/llm_service.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';

/// Owns the active LLM provider/model/API-key configuration and generation
/// hyperparameters (temperature, persona, failover, LoRA, RAG, LangSmith).
class LlmSettingsProvider extends ChangeNotifier {
  final StorageService _storageService;
  final LlmService _llmService;

  late LlmProvider _activeProvider;
  late String _activeModel;
  late String _activeApiKey;
  String? _customBaseUrl;

  double _temperature = 0.3;
  int _maxTokens = 2048;
  String _persona = 'standard';
  bool _autoFailover = true;

  String? _loraAdapter;
  String? _ragContext;
  bool _langsmithTracing = false;
  String? _langsmithProject;

  LlmSettingsProvider({
    required StorageService storage,
    LlmService? llmService,
  })  : _storageService = storage,
        _llmService = llmService ?? LlmService() {
    _init();
  }

  /// Determines if [modelId] is an unusable preview, guardrail, non-instruct, or broken MoE model.
  static bool isUnusableModel(String? modelId) {
    if (modelId == null || modelId.trim().isEmpty) return true;
    final lower = modelId.toLowerCase().trim();
    if (lower.contains('note-preview') ||
        lower.contains('content-safety') ||
        lower.contains('guard') ||
        lower.contains('moderation') ||
        lower.contains('whisper') ||
        lower.contains('embed') ||
        lower.contains('dots-') ||
        lower.contains('inkling-small')) {
      return true;
    }
    return false;
  }

  /// Calculates capability/suitability score for an instruct model.
  static int rankModelQuality(String modelId) {
    final lower = modelId.toLowerCase();
    if (isUnusableModel(lower)) return -100;

    if (lower.contains('gemma-4-31b')) return 100;
    if (lower.contains('gemma-4-26b')) return 95;
    if (lower.contains('llama-3.3-70b')) return 92;
    if (lower.contains('nemotron-3.5-lightning')) return 90;
    if (lower.contains('nemotron-3-super')) return 88;
    if (lower.contains('llama-3.1-70b')) return 85;
    if (lower.contains('mistral-small')) return 82;
    if (lower.contains('qwen-2.5-72b')) return 80;
    if (lower.contains('deepseek-chat')) return 78;
    if (lower.contains('llama-3.1-8b') || lower.contains('llama-3-8b')) return 70;
    if (lower.contains('gemma-2-9b')) return 68;
    if (lower.contains('gemini-2.0-flash') || lower.contains('gemini-1.5-flash')) return 65;
    if (lower.contains('-it') || lower.contains('instruct') || lower.contains('chat')) return 50;
    return 10;
  }

  void _init() {
    final providerId = _storageService.getActiveProviderId();
    _activeProvider = LlmProvider.getById(providerId);

    // Sanitize any corrupt/unusable models across all providers
    for (final p in LlmProvider.allProviders) {
      final m = _storageService.getSelectedModel(p.id);
      if (m != null && (m.isEmpty || isUnusableModel(m))) {
        _storageService.setSelectedModel(p.id, p.defaultModel);
      }
    }

    final savedModel = _storageService.getSelectedModel(_activeProvider.id);
    _activeModel = (savedModel != null && savedModel.isNotEmpty && !isUnusableModel(savedModel))
        ? savedModel
        : _activeProvider.defaultModel;

    _activeApiKey = _storageService.getApiKey(_activeProvider.id) ?? '';
    _customBaseUrl = _storageService.getCustomBaseUrl();

    _temperature = _storageService.getTemperature();
    _maxTokens = _storageService.getMaxTokens();
    _persona = _storageService.getPersona();
    _autoFailover = _storageService.getAutoFailover();
    _loraAdapter = _storageService.getLoraAdapter();
    _ragContext = _storageService.getRagContext();
    _langsmithTracing = _storageService.getLangsmithTracing();
    _langsmithProject = _storageService.getLangsmithProject();
  }

  LlmProvider get activeProvider => _activeProvider;
  String get activeModel => _activeModel;
  String get activeApiKey => _activeApiKey;
  String? get customBaseUrl => _customBaseUrl;
  bool get hasActiveApiKey =>
      _activeApiKey.isNotEmpty || !_activeProvider.requiresKey || _activeProvider.isCustom;

  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  String get persona => _persona;
  bool get autoFailover => _autoFailover;
  String? get loraAdapter => _loraAdapter;
  String? get ragContext => _ragContext;
  bool get langsmithTracing => _langsmithTracing;
  String? get langsmithProject => _langsmithProject;

  LlmGenerationParams get generationParams => LlmGenerationParams(
        temperature: _temperature,
        maxTokens: _maxTokens,
        persona: _persona,
        autoFailover: _autoFailover,
        loraAdapter: _loraAdapter,
        ragContext: _ragContext,
        langsmithTracing: _langsmithTracing,
        langsmithProject: _langsmithProject,
      );

  Future<void> setLoraAdapter(String? adapter) async {
    _loraAdapter = adapter;
    await _storageService.setLoraAdapter(adapter);
    notifyListeners();
  }

  Future<void> setRagContext(String? context) async {
    _ragContext = context;
    await _storageService.setRagContext(context);
    notifyListeners();
  }

  Future<void> setLangsmithTracing(bool enabled) async {
    _langsmithTracing = enabled;
    await _storageService.setLangsmithTracing(enabled);
    notifyListeners();
  }

  Future<void> setLangsmithProject(String? project) async {
    _langsmithProject = project;
    await _storageService.setLangsmithProject(project);
    notifyListeners();
  }

  // Backward compatibility
  bool get hasApiKey => hasActiveApiKey;
  String get groqApiKey => _storageService.getApiKey('groq') ?? '';

  String getApiKeyForProvider(String providerId) {
    return _storageService.getApiKey(providerId) ?? '';
  }

  Future<void> setApiKeyForProvider(String providerId, String key) async {
    await _storageService.setApiKey(providerId, key);
    if (_activeProvider.id == providerId) {
      _activeApiKey = key.trim();
    }
    notifyListeners();
  }

  Future<void> setActiveProvider(String providerId) async {
    _activeProvider = LlmProvider.getById(providerId);
    await _storageService.setActiveProviderId(providerId);

    final savedModel = _storageService.getSelectedModel(providerId);
    _activeModel = (savedModel != null && savedModel.isNotEmpty)
        ? savedModel
        : _activeProvider.defaultModel;

    _activeApiKey = _storageService.getApiKey(providerId) ?? '';
    notifyListeners();
  }

  Future<void> setActiveModel(String modelId) async {
    _activeModel = modelId.trim();
    await _storageService.setSelectedModel(_activeProvider.id, _activeModel);
    notifyListeners();
  }

  /// Persists a model choice for an explicit provider, even when that
  /// provider isn't the currently-active one (e.g. the user is picking a
  /// model for a provider they're still configuring in Settings, before
  /// hitting "Save"). Without this, a model picked via the live catalog was
  /// only ever remembered if the user separately pressed "Save Settings" —
  /// forget that tap and it silently reverted to the provider's default on
  /// next launch.
  Future<void> setModelForProvider(String providerId, String model) async {
    final trimmed = model.trim();
    await _storageService.setSelectedModel(providerId, trimmed);
    if (_activeProvider.id == providerId) {
      _activeModel = trimmed;
      notifyListeners();
    }
  }

  LlmProvider? _pendingFailoverProvider;
  String? _pendingFailoverModel;

  bool get hasPendingFailover => _pendingFailoverProvider != null;
  LlmProvider? get pendingFailoverProvider => _pendingFailoverProvider;
  String? get pendingFailoverModel => _pendingFailoverModel;

  /// Seamlessly adopts a fallback provider/model after runtime failover.
  /// Updates in-memory active configuration so subsequent requests within
  /// the session use the functional model.
  /// If [persistPermanently] is false, saves it as pending confirmation.
  Future<void> adoptFailoverModel({
    required LlmProvider provider,
    required String model,
    bool persistPermanently = false,
  }) async {
    _activeProvider = provider;
    _activeModel = model.trim();
    _activeApiKey = _storageService.getApiKey(provider.id) ?? '';

    if (persistPermanently) {
      await _storageService.setActiveProviderId(provider.id);
      await _storageService.setSelectedModel(provider.id, _activeModel);
      _pendingFailoverProvider = null;
      _pendingFailoverModel = null;
    } else {
      _pendingFailoverProvider = provider;
      _pendingFailoverModel = _activeModel;
    }

    AppLogger.info(
      'LlmSettingsProvider: Adopted failover provider=${provider.name}, model=$_activeModel (session-active)',
      'LlmSettings',
    );
    notifyListeners();
  }

  /// Commits the active failover provider/model permanently to local storage.
  Future<void> savePendingFailoverAsDefault() async {
    if (_pendingFailoverProvider != null && _pendingFailoverModel != null) {
      await _storageService.setActiveProviderId(_pendingFailoverProvider!.id);
      await _storageService.setSelectedModel(_pendingFailoverProvider!.id, _pendingFailoverModel!);
      AppLogger.info(
        'LlmSettingsProvider: Persisted failover ${_pendingFailoverProvider!.name} as default',
        'LlmSettings',
      );
      _pendingFailoverProvider = null;
      _pendingFailoverModel = null;
      notifyListeners();
    }
  }

  /// Dismisses the pending failover notification without reverting current session.
  void dismissPendingFailover() {
    _pendingFailoverProvider = null;
    _pendingFailoverModel = null;
    notifyListeners();
  }


  Future<void> setCustomBaseUrl(String url) async {
    _customBaseUrl = url.trim();
    await _storageService.setCustomBaseUrl(_customBaseUrl!);
    notifyListeners();
  }

  Future<void> setTemperature(double temp) async {
    _temperature = temp;
    await _storageService.setTemperature(temp);
    notifyListeners();
  }

  Future<void> setMaxTokens(int tokens) async {
    _maxTokens = tokens;
    await _storageService.setMaxTokens(tokens);
    notifyListeners();
  }

  Future<void> setPersona(String persona) async {
    _persona = persona;
    await _storageService.setPersona(persona);
    notifyListeners();
  }

  Future<void> setAutoFailover(bool enabled) async {
    _autoFailover = enabled;
    await _storageService.setAutoFailover(enabled);
    notifyListeners();
  }

  Future<void> setGroqApiKey(String key) async {
    await setApiKeyForProvider('groq', key);
  }

  /// Live-fetches the model catalog for an explicit provider/key/base URL
  /// rather than whatever is currently saved as active. Settings screens use
  /// this so a freshly pasted (not-yet-saved) API key is what gets used to
  /// fetch models, instead of silently falling back to the old active key.
  Future<List<LlmModelInfo>> fetchLiveModelsFor({
    required LlmProvider provider,
    required String apiKey,
    String? customBaseUrl,
  }) async {
    return _llmService.fetchLiveModels(
      provider,
      apiKey,
      customBaseUrl: provider.isCustom ? customBaseUrl : null,
    );
  }

  /// Given an already-fetched live catalog, upgrades [currentModel] to the
  /// best entry it offers and persists that choice immediately — unless
  /// [currentModel] is already an explicit choice (something other than the
  /// provider's curated default) that's still present in the catalog, in
  /// which case the user's own pick is left alone. Returns the resulting
  /// model id (unchanged if nothing better applied).
  Future<String> selectBestModel({
    required LlmProvider provider,
    required List<LlmModelInfo> liveModels,
    required String currentModel,
  }) async {
    if (liveModels.isEmpty) return currentModel;

    final isUnmodifiedDefault = currentModel == provider.defaultModel;
    final currentStillValid = liveModels.any((m) => m.id == currentModel);
    if (!isUnmodifiedDefault && currentStillValid) {
      return currentModel;
    }

    final best = _pickBestModel(liveModels, provider);
    if (best == null || best.id == currentModel) return currentModel;

    await setModelForProvider(provider.id, best.id);
    return best.id;
  }

  /// Picks the most capable-looking model from a live catalog. There's no
  /// real quality signal in a bare `/models` listing, so this prefers the
  /// provider's own curated recommendation when the live catalog still
  /// serves it (that curation IS the "best model" judgment call, already
  /// made deliberately elsewhere in this codebase), then falls back to the
  /// largest-context-window model outside the pared-down "fast"/mini tier.
  LlmModelInfo? _pickBestModel(List<LlmModelInfo> models, LlmProvider provider) {
    if (models.isEmpty) return null;
    for (final model in models) {
      if (model.id == provider.defaultModel) return model;
    }
    final usable = models.where((m) => !isUnusableModel(m.id)).toList();
    final pool = usable.isNotEmpty ? usable : models;
    pool.sort((a, b) {
      final rankA = rankModelQuality(a.id);
      final rankB = rankModelQuality(b.id);
      if (rankA != rankB) return rankB.compareTo(rankA);
      return (b.contextWindow ?? 0).compareTo(a.contextWindow ?? 0);
    });
    return pool.first;
  }

  /// Whether the user has explicitly selected/saved a model for this provider
  bool hasUserSelectedModel(String providerId) => _storageService.hasUserSelectedModel(providerId);

  /// Returns the user-saved model for this provider if one was explicitly set
  String? getSavedModelForProvider(String providerId) => _storageService.getSelectedModel(providerId);

  /// Automatically fetches live models for [provider] and selects the best
  /// free model if the user has not explicitly configured a model for it yet.
  Future<String?> autoSelectFreeModelIfUnset({
    required LlmProvider provider,
    required String apiKey,
    String? customBaseUrl,
  }) async {
    // If the user already explicitly selected a model for this provider, do not override
    if (_storageService.hasUserSelectedModel(provider.id)) {
      final userChoice = _storageService.getSelectedModel(provider.id);
      if (userChoice != null && userChoice.isNotEmpty && !isUnusableModel(userChoice)) {
        return userChoice;
      }
    }

    try {
      final liveModels = await fetchLiveModelsFor(
        provider: provider,
        apiKey: apiKey,
        customBaseUrl: customBaseUrl,
      );

      if (liveModels.isEmpty) return null;

      // Filter for usable free models (flagged isFree or contains ':free' or tag == 'Free')
      final freeModels = liveModels.where((m) =>
          !isUnusableModel(m.id) &&
          (m.isFree ||
           m.id.toLowerCase().contains(':free') ||
           m.id.toLowerCase().endsWith('free') ||
           m.tag?.toLowerCase() == 'free')
      ).toList();

      LlmModelInfo? chosenModel;
      if (freeModels.isNotEmpty) {
        // Prefer default model if it's in free list
        for (final m in freeModels) {
          if (m.id == provider.defaultModel) {
            chosenModel = m;
            break;
          }
        }
        // Otherwise pick the model with highest ranked quality, then largest context window
        if (chosenModel == null) {
          final sorted = List<LlmModelInfo>.from(freeModels);
          sorted.sort((a, b) {
            final rankA = rankModelQuality(a.id);
            final rankB = rankModelQuality(b.id);
            if (rankA != rankB) return rankB.compareTo(rankA);
            return (b.contextWindow ?? 0).compareTo(a.contextWindow ?? 0);
          });
          chosenModel = sorted.first;
        }
      } else {
        // Fallback: if no model explicitly flagged free (e.g. Groq where whole tier is free),
        // pick default model or highest quality
        final usable = liveModels.where((m) => !isUnusableModel(m.id)).toList();
        final listToUse = usable.isNotEmpty ? usable : liveModels;
        chosenModel = listToUse.firstWhere(
          (m) => m.id == provider.defaultModel,
          orElse: () {
            final sorted = List<LlmModelInfo>.from(listToUse);
            sorted.sort((a, b) => rankModelQuality(b.id).compareTo(rankModelQuality(a.id)));
            return sorted.first;
          },
        );
      }

      await setModelForProvider(provider.id, chosenModel.id);
      return chosenModel.id;
    } catch (e) {
      AppLogger.warn('autoSelectFreeModelIfUnset failed for ${provider.name}: $e', 'LlmSettings');
    }
    return null;
  }

  Future<bool> testConnection({
    LlmProvider? provider,
    String? apiKey,
    String? model,
    String? customBaseUrl,
  }) async {
    final prov = provider ?? _activeProvider;
    final key = apiKey ?? _activeApiKey;
    final mod = model ?? _activeModel;
    final base = customBaseUrl ?? (prov.isCustom ? _customBaseUrl : null);

    return _llmService.testApiKey(
      prov,
      key,
      model: mod,
      customBaseUrl: base,
    );
  }

  /// All providers with a non-empty stored API key, keyed by provider id —
  /// used to build the smart auto-failover candidate list.
  Map<String, String> getAllConfiguredKeys() {
    final allKeys = <String, String>{};
    for (final p in LlmProvider.allProviders) {
      final k = _storageService.getApiKey(p.id);
      if (k != null && k.isNotEmpty) allKeys[p.id] = k;
    }
    return allKeys;
  }
}
