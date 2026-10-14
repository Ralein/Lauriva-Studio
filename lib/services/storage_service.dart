import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_record.dart';
import '../models/llm_provider.dart';
import '../utils/logger.dart';

class StorageService {
  static const String _keyGroqApiKey = 'lauriva_groq_api_key';
  static const String _keyActiveProvider = 'lauriva_active_provider';
  static const String _keyProviderKeyPrefix = 'lauriva_api_key_';
  static const String _keyProviderModelPrefix = 'lauriva_active_model_';
  static const String _keyCustomBaseUrl = 'lauriva_custom_base_url';
  static const String _keySpeechSpeed = 'lauriva_speech_speed';
  static const String _keyThemeMode = 'lauriva_theme_mode';
  static const String _keyTargetLanguage = 'lauriva_target_lang';
  static const String _keyHistory = 'lauriva_history';
  static const String _keyTemperature = 'lauriva_llm_temperature';
  static const String _keyMaxTokens = 'lauriva_llm_max_tokens';
  static const String _keyPersona = 'lauriva_llm_persona';
  static const String _keyAutoFailover = 'lauriva_auto_failover';
  static const String _keyTtsVoiceName = 'lauriva_tts_voice_name';
  static const String _keyTtsVoiceLocale = 'lauriva_tts_voice_locale';
  static const String _keyHasSeenOnboarding = 'lauriva_has_seen_onboarding';
  static const String _keyHumanizeIntensity = 'lauriva_humanize_intensity';
  static const String _keySlopAutoPolish = 'lauriva_slop_auto_polish';

  SharedPreferences? _prefs;
  late final FlutterSecureStorage _secureStorage;

  // Safe accessor — returns null if prefs not yet initialized (race-condition guard).
  SharedPreferences? get _safePrefs => _prefs;

  String _activeProviderId = 'groq';
  final Map<String, String> _cachedApiKeys = {};
  final Map<String, String> _cachedModels = {};
  String? _cachedCustomBaseUrl;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } on Exception catch (e) {
      // Corrupted SharedPreferences store — clear and retry once.
      AppLogger.error(
        'SharedPreferences init failed: $e. Attempting factory reset.',
        tag: 'Storage',
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        _prefs = prefs;
      } catch (_) {
        // If retry also fails, continue with null prefs — all reads will return defaults.
        AppLogger.error(
          'SharedPreferences retry failed — running with in-memory defaults.',
          tag: 'Storage',
        );
      }
    }

    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
    );

    _activeProviderId =
        _safePrefs?.getString(_keyActiveProvider) ??
        _safePrefs?.getString('Lauriva_active_provider') ??
        'groq';
    _cachedCustomBaseUrl =
        _safePrefs?.getString(_keyCustomBaseUrl) ??
        _safePrefs?.getString('Lauriva_custom_base_url');

    // Read stored API keys for all providers with secure storage & migration
    for (final provider in LlmProvider.allProviders) {
      final keyName = '$_keyProviderKeyPrefix${provider.id}';
      final legacyKeyName = 'Lauriva_api_key_${provider.id}';
      try {
        var key = await _secureStorage.read(key: keyName);
        if (key == null || key.trim().isEmpty) {
          key = await _secureStorage.read(key: legacyKeyName);
          if (key != null && key.trim().isNotEmpty) {
            await _secureStorage.write(key: keyName, value: key.trim());
          }
        }
        if (key == null || key.trim().isEmpty) {
          final legacyKey =
              _prefs?.getString(keyName) ?? _prefs?.getString(legacyKeyName);
          if (legacyKey != null && legacyKey.trim().isNotEmpty) {
            key = legacyKey.trim();
            await _secureStorage.write(key: keyName, value: key);
            await _prefs?.remove(keyName);
            await _prefs?.remove(legacyKeyName);
          }
        }
        if (key != null && key.trim().isNotEmpty) {
          _cachedApiKeys[provider.id] = key.trim();
        }
      } catch (e) {
        if (e is! MissingPluginException) {
          AppLogger.warn(
            'Secure storage read error for ${provider.id}: $e',
            'Storage',
          );
        }
        final prefKey =
            _prefs?.getString(keyName) ?? _prefs?.getString(legacyKeyName);
        if (prefKey != null && prefKey.trim().isNotEmpty) {
          _cachedApiKeys[provider.id] = prefKey.trim();
        }
      }

      // Read selected models per provider
      final modelKey = '$_keyProviderModelPrefix${provider.id}';
      final legacyModelKey = 'Lauriva_active_model_${provider.id}';
      final savedModel =
          _prefs?.getString(modelKey) ?? _prefs?.getString(legacyModelKey);
      if (savedModel != null && savedModel.trim().isNotEmpty) {
        _cachedModels[provider.id] = savedModel.trim();
      }
    }

    // Migration check for legacy Groq key
    if (!_cachedApiKeys.containsKey('groq')) {
      try {
        final legacyGroq =
            await _secureStorage.read(key: _keyGroqApiKey) ??
            _prefs?.getString(_keyGroqApiKey) ??
            await _secureStorage.read(key: 'Lauriva_groq_api_key') ??
            _prefs?.getString('Lauriva_groq_api_key') ??
            await _secureStorage.read(key: 'Lauriva_api_key_groq') ??
            _prefs?.getString('Lauriva_api_key_groq');
        if (legacyGroq != null && legacyGroq.trim().isNotEmpty) {
          _cachedApiKeys['groq'] = legacyGroq.trim();
          await setApiKey('groq', legacyGroq.trim());
        }
      } catch (_) {}
    }
  }

  // --- Active Provider ---
  String getActiveProviderId() => _activeProviderId;
  Future<void> setActiveProviderId(String id) async {
    _activeProviderId = id;
    await _safePrefs?.setString(_keyActiveProvider, id);
  }

  // --- API Keys per Provider ---
  String? getApiKey(String providerId) {
    if (_cachedApiKeys.containsKey(providerId) &&
        _cachedApiKeys[providerId]!.trim().isNotEmpty) {
      return _cachedApiKeys[providerId]!.trim();
    }

    // Check environment variables as fallback
    if (providerId == 'groq') {
      const envKey = String.fromEnvironment('GROQ_API_KEY');
      if (envKey.isNotEmpty) return envKey;
    } else if (providerId == 'openrouter') {
      const envKey = String.fromEnvironment('OPENROUTER_API_KEY');
      if (envKey.isNotEmpty) return envKey;
    } else if (providerId == 'gemini') {
      const envKey = String.fromEnvironment('GEMINI_API_KEY');
      if (envKey.isNotEmpty) return envKey;
    }

    return null;
  }

  Future<void> setApiKey(String providerId, String key) async {
    final trimmed = key.trim();
    _cachedApiKeys[providerId] = trimmed;
    final keyName = '$_keyProviderKeyPrefix$providerId';

    try {
      await _secureStorage.write(key: keyName, value: trimmed);
    } catch (e) {
      if (e is! MissingPluginException) {
        AppLogger.warn(
          'Secure storage write failed for $providerId, using prefs: $e',
          'Storage',
        );
      }
      await _prefs?.setString(keyName, trimmed);
    }

    // Keep legacy key in sync for groq
    if (providerId == 'groq') {
      try {
        await _secureStorage.write(key: _keyGroqApiKey, value: trimmed);
      } catch (_) {
        await _prefs?.setString(_keyGroqApiKey, trimmed);
      }
    }
  }

  Future<void> clearApiKey(String providerId) async {
    _cachedApiKeys.remove(providerId);
    final keyName = '$_keyProviderKeyPrefix$providerId';
    try {
      await _secureStorage.delete(key: keyName);
    } catch (_) {}
    await _prefs?.remove(keyName);

    if (providerId == 'groq') {
      try {
        await _secureStorage.delete(key: _keyGroqApiKey);
      } catch (_) {}
      await _prefs?.remove(_keyGroqApiKey);
    }
  }

  // Backward compatibility
  String? getGroqApiKey() => getApiKey('groq');
  Future<void> setGroqApiKey(String key) => setApiKey('groq', key);
  Future<void> clearGroqApiKey() => clearApiKey('groq');

  // --- Active Model per Provider ---
  String? getSelectedModel(String providerId) {
    return _cachedModels[providerId];
  }

  bool hasUserSelectedModel(String providerId) {
    return _cachedModels.containsKey(providerId) &&
        _cachedModels[providerId]!.isNotEmpty;
  }

  Future<void> setSelectedModel(String providerId, String model) async {
    _cachedModels[providerId] = model.trim();
    await _prefs?.setString(
      '$_keyProviderModelPrefix$providerId',
      model.trim(),
    );
  }

  // --- Custom Base URL ---
  String? getCustomBaseUrl() => _cachedCustomBaseUrl;

  Future<void> setCustomBaseUrl(String url) async {
    _cachedCustomBaseUrl = url.trim();
    await _prefs?.setString(_keyCustomBaseUrl, _cachedCustomBaseUrl!);
  }

  // --- TTS & Language & History ---
  String getSpeechSpeed() {
    return _prefs?.getString(_keySpeechSpeed) ??
        _prefs?.getString('Lauriva_speech_speed') ??
        'normal';
  }

  Future<void> setSpeechSpeed(String speed) async {
    await _prefs?.setString(_keySpeechSpeed, speed);
  }

  String? getTtsVoiceName() => _prefs?.getString(_keyTtsVoiceName);
  String? getTtsVoiceLocale() => _prefs?.getString(_keyTtsVoiceLocale);

  Future<void> setTtsVoice({required String name, required String locale}) async {
    await _prefs?.setString(_keyTtsVoiceName, name);
    await _prefs?.setString(_keyTtsVoiceLocale, locale);
  }

  Future<void> clearTtsVoice() async {
    await _prefs?.remove(_keyTtsVoiceName);
    await _prefs?.remove(_keyTtsVoiceLocale);
  }

  /// Theme mode preference: 'system', 'light', or 'dark'. Defaults to
  /// 'system' so Lauriva follows the OS setting until the user overrides it.
  String getThemeMode() {
    return _prefs?.getString(_keyThemeMode) ??
        _prefs?.getString('Lauriva_theme_mode') ??
        'system';
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs?.setString(_keyThemeMode, mode);
  }

  String getTargetLanguage() {
    return _prefs?.getString(_keyTargetLanguage) ??
        _prefs?.getString('Lauriva_target_lang') ??
        'English';
  }

  Future<void> setTargetLanguage(String language) async {
    await _prefs?.setString(_keyTargetLanguage, language);
  }

  /// Returns raw string history or parsed outputText strings for backward compatibility
  List<String> getHistory() {
    final rawList =
        _prefs?.getStringList(_keyHistory) ??
        _prefs?.getStringList('Lauriva_history') ??
        [];
    return rawList.map((item) {
      if (item.trim().startsWith('{')) {
        try {
          final record = HistoryRecord.fromJson(
            jsonDecode(item) as Map<String, dynamic>,
          );
          return record.outputText;
        } catch (_) {}
      }
      return item;
    }).toList();
  }

  /// Returns structured transformation records with rich studio metadata
  List<HistoryRecord> getStructuredHistory() {
    final rawList =
        _prefs?.getStringList(_keyHistory) ??
        _prefs?.getStringList('Lauriva_history') ??
        [];
    return rawList.map((item) => HistoryRecord.fromLegacyString(item)).toList();
  }

  /// Adds a rich structured history record
  Future<void> addHistoryRecord(HistoryRecord record) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final rawList = List<String>.from(
        _prefs?.getStringList(_keyHistory) ??
            _prefs?.getStringList('Lauriva_history') ??
            [],
      );
      // Prevent exact duplicate saves
      if (rawList.isNotEmpty) {
        final first = HistoryRecord.fromLegacyString(rawList.first);
        if (first.id == record.id ||
            (first.outputText.trim() == record.outputText.trim() &&
                first.inputText.trim() == record.inputText.trim() &&
                first.featureId == record.featureId)) {
          return;
        }
      }
      rawList.insert(0, jsonEncode(record.toJson()));
      if (rawList.length > 50) {
        rawList.removeLast();
      }
      await _prefs?.setStringList(_keyHistory, rawList);
    } catch (e) {
      AppLogger.error('Failed to save history record: $e', tag: 'Storage');
    }
  }

  /// Adds a legacy string item (auto-converts to structured HistoryRecord)
  Future<void> addHistoryItem(String item) async {
    final record = HistoryRecord.fromLegacyString(item);
    await addHistoryRecord(record);
  }

  Future<void> removeHistoryItem(int index) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final rawList = List<String>.from(
        _prefs?.getStringList(_keyHistory) ??
            _prefs?.getStringList('Lauriva_history') ??
            [],
      );
      if (index >= 0 && index < rawList.length) {
        rawList.removeAt(index);
        await _prefs?.setStringList(_keyHistory, rawList);
      }
    } catch (e) {
      AppLogger.error('Failed to remove history item: $e', tag: 'Storage');
    }
  }

  Future<void> clearHistory() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.remove(_keyHistory);
      await _prefs?.remove('Lauriva_history');
    } catch (e) {
      AppLogger.error('Failed to clear history: $e', tag: 'Storage');
    }
  }

  // --- LLM Hyperparameters & Failover ---
  double getTemperature() {
    return _prefs?.getDouble(_keyTemperature) ??
        _prefs?.getDouble('Lauriva_llm_temperature') ??
        0.3;
  }

  Future<void> setTemperature(double temp) async {
    await _prefs?.setDouble(_keyTemperature, temp);
  }

  int getMaxTokens() {
    return _prefs?.getInt(_keyMaxTokens) ??
        _prefs?.getInt('Lauriva_llm_max_tokens') ??
        2048;
  }

  Future<void> setMaxTokens(int tokens) async {
    await _prefs?.setInt(_keyMaxTokens, tokens);
  }

  String getPersona() {
    return _prefs?.getString(_keyPersona) ??
        _prefs?.getString('Lauriva_llm_persona') ??
        'standard';
  }

  Future<void> setPersona(String persona) async {
    await _prefs?.setString(_keyPersona, persona);
  }

  bool getAutoFailover() {
    return _prefs?.getBool(_keyAutoFailover) ??
        _prefs?.getBool('Lauriva_auto_failover') ??
        true;
  }

  Future<void> setAutoFailover(bool enabled) async {
    await _prefs?.setBool(_keyAutoFailover, enabled);
  }

  // --- Superpowers: LoRA, RAG & LangSmith Tracing ---
  static const String _keyLoraAdapter = 'lauriva_llm_lora_adapter';
  static const String _keyRagContext = 'lauriva_llm_rag_context';
  static const String _keyLangsmithTracing = 'lauriva_langsmith_tracing';
  static const String _keyLangsmithProject = 'lauriva_langsmith_project';

  String? getLoraAdapter() =>
      _prefs?.getString(_keyLoraAdapter) ??
      _prefs?.getString('Lauriva_llm_lora_adapter');
  Future<void> setLoraAdapter(String? adapter) async {
    if (adapter == null || adapter.trim().isEmpty) {
      await _prefs?.remove(_keyLoraAdapter);
      await _prefs?.remove('Lauriva_llm_lora_adapter');
    } else {
      await _prefs?.setString(_keyLoraAdapter, adapter.trim());
    }
  }

  String? getRagContext() =>
      _prefs?.getString(_keyRagContext) ??
      _prefs?.getString('Lauriva_llm_rag_context');
  Future<void> setRagContext(String? context) async {
    if (context == null || context.trim().isEmpty) {
      await _prefs?.remove(_keyRagContext);
      await _prefs?.remove('Lauriva_llm_rag_context');
    } else {
      await _prefs?.setString(_keyRagContext, context.trim());
    }
  }

  bool getLangsmithTracing() =>
      _prefs?.getBool(_keyLangsmithTracing) ??
      _prefs?.getBool('Lauriva_langsmith_tracing') ??
      false;
  Future<void> setLangsmithTracing(bool enabled) async {
    await _prefs?.setBool(_keyLangsmithTracing, enabled);
  }

  String? getLangsmithProject() =>
      _prefs?.getString(_keyLangsmithProject) ??
      _prefs?.getString('Lauriva_langsmith_project');
  Future<void> setLangsmithProject(String? project) async {
    if (project == null || project.trim().isEmpty) {
      await _prefs?.remove(_keyLangsmithProject);
    } else {
      await _prefs?.setString(_keyLangsmithProject, project.trim());
    }
  }

  // --- Onboarding & Humanize Settings ---
  bool getHasSeenOnboarding() =>
      _safePrefs?.getBool(_keyHasSeenOnboarding) ??
      _safePrefs?.getBool('Lauriva_has_seen_onboarding') ??
      false;

  Future<void> setHasSeenOnboarding(bool seen) async {
    await _prefs?.setBool(_keyHasSeenOnboarding, seen);
  }

  int getHumanizeIntensity() =>
      _safePrefs?.getInt(_keyHumanizeIntensity) ?? 85;

  Future<void> setHumanizeIntensity(int percent) async {
    await _prefs?.setInt(_keyHumanizeIntensity, percent.clamp(0, 100));
  }

  bool getSlopAutoPolish() =>
      _safePrefs?.getBool(_keySlopAutoPolish) ??
      _safePrefs?.getBool('Lauriva_slop_auto_polish') ??
      true;

  Future<void> setSlopAutoPolish(bool enabled) async {
    await _prefs?.setBool(_keySlopAutoPolish, enabled);
  }
}
