import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/constants/app_colors.dart';
import 'package:lauriva/constants/app_prompts.dart';
import 'package:lauriva/main.dart';
import 'package:lauriva/models/feature_type.dart';
import 'package:lauriva/models/history_record.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/humanizer_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/providers/background_task_provider.dart';
import 'package:lauriva/services/llm_service.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/screens/settings_screen.dart';
import 'package:lauriva/widgets/history_drawer.dart';
import 'package:lauriva/widgets/tts_player_bar.dart';
import 'package:lauriva/widgets/voice_mini_settings.dart';
import 'package:lauriva/widgets/zone1_input.dart';
import 'package:lauriva/widgets/settings/about_section.dart';
import 'test_mocks.dart';

/// Bundles one instance of every app provider, wired together exactly as
/// main.dart's bootstrap does, so tests can exercise the real composition
/// (e.g. StudioProvider delegating to PlagiarismProvider/SpeechProvider)
/// instead of a stand-in.
class _Providers {
  final ToastProvider toast;
  final BackgroundTaskProvider backgroundTask;
  final ThemeProvider theme;
  final HistoryProvider history;
  final LlmSettingsProvider llmSettings;
  final SpeechProvider speech;
  final PlagiarismProvider plagiarism;
  final HumanizerProvider humanizer;
  final StudioProvider studio;

  _Providers({
    required this.toast,
    required this.backgroundTask,
    required this.theme,
    required this.history,
    required this.llmSettings,
    required this.speech,
    required this.plagiarism,
    required this.humanizer,
    required this.studio,
  });
}

_Providers _buildProviders(StorageService storage) {
  final toast = ToastProvider();
  final backgroundTask = BackgroundTaskProvider(toast: toast);
  final history = HistoryProvider(storage: storage, toast: toast);
  final llmSettings = LlmSettingsProvider(storage: storage);
  final speech = SpeechProvider(storage: storage, toast: toast);
  final plagiarism = PlagiarismProvider(
    storage: storage,
    toast: toast,
    history: history,
    llmSettings: llmSettings,
    backgroundTask: backgroundTask,
  );
  final humanizer = HumanizerProvider(
    storage: storage,
    toast: toast,
    history: history,
    llmSettings: llmSettings,
    plagiarism: plagiarism,
    speech: speech,
    backgroundTask: backgroundTask,
  );
  return _Providers(
    toast: toast,
    backgroundTask: backgroundTask,
    theme: ThemeProvider(storage: storage),
    history: history,
    llmSettings: llmSettings,
    speech: speech,
    plagiarism: plagiarism,
    humanizer: humanizer,
    studio: StudioProvider(
      storage: storage,
      speech: speech,
      llmSettings: llmSettings,
      history: history,
      toast: toast,
      plagiarism: plagiarism,
    ),
  );
}

Widget _wrapWithProviders(_Providers p, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ToastProvider>.value(value: p.toast),
      ChangeNotifierProvider<BackgroundTaskProvider>.value(value: p.backgroundTask),
      ChangeNotifierProvider<ThemeProvider>.value(value: p.theme),
      ChangeNotifierProvider<HistoryProvider>.value(value: p.history),
      ChangeNotifierProvider<LlmSettingsProvider>.value(value: p.llmSettings),
      ChangeNotifierProvider<SpeechProvider>.value(value: p.speech),
      ChangeNotifierProvider<PlagiarismProvider>.value(value: p.plagiarism),
      ChangeNotifierProvider<StudioProvider>.value(value: p.studio),
      ChangeNotifierProvider<HumanizerProvider>.value(value: p.humanizer),
    ],
    child: child,
  );
}

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  group('Lauriva Models and Features Tests', () {
    test('Verifies all 13 features are defined with labels and icons', () {
      expect(FeatureType.values.length, 13);

      final translate = FeatureType.fromId('Translate');
      expect(translate, isNotNull);
      expect(translate?.label, 'Translate');

      final plagiarism = FeatureType.fromId('PlagiarismCheck');
      expect(plagiarism, isNotNull);
      expect(plagiarism?.label, 'Check for AI');

      final humanize = FeatureType.fromId('Humanize');
      expect(humanize, isNotNull);
      expect(humanize?.label, 'Humanize');

      final grammar = FeatureType.fromId('Grammar');
      expect(grammar, isNotNull);
      expect(grammar?.label, 'Fix Grammar');

      final concise = FeatureType.fromId('Concise');
      expect(concise, isNotNull);
      expect(concise?.label, 'Make Shorter');

      final witty = FeatureType.fromId('Style: Witty');
      expect(witty, isNotNull);
      expect(witty?.label, 'Witty');
    });

    test('Verifies default models are configured across providers', () {
      final openai = LlmProvider.getById('openai');
      expect(openai.name, 'OpenAI');
      expect(openai.defaultModel, 'gpt-4o');
      expect(openai.models.any((m) => !m.isFree), isTrue);

      final anthropic = LlmProvider.getById('anthropic');
      expect(anthropic.name, contains('Anthropic'));
      expect(anthropic.defaultModel, contains('claude-3-7-sonnet'));

      final deepseek = LlmProvider.getById('deepseek');
      expect(deepseek.name, contains('DeepSeek'));
      expect(deepseek.defaultModel, 'deepseek-chat');
    });
  });

  group('Lauriva Multi-LLM Providers and Free Models Tests', () {
    test('Verifies all providers are configured with direct API key URLs', () {
      expect(LlmProvider.allProviders.length, 26);

      final ollama = LlmProvider.getById('ollama');
      expect(ollama.name, contains('Ollama'));
      expect(ollama.requiresKey, isFalse);
      expect(ollama.models.isNotEmpty, isTrue);

      final groq = LlmProvider.getById('groq');
      expect(groq.name, 'Groq');
      expect(groq.keyPortalUrl, 'https://console.groq.com/keys');
      expect(groq.models.isNotEmpty, isTrue);

      final openRouter = LlmProvider.getById('openrouter');
      expect(openRouter.name, 'OpenRouter');
      expect(openRouter.keyPortalUrl, 'https://openrouter.ai/settings/keys');
      expect(openRouter.models.any((m) => m.isFree), isTrue);

      final gemini = LlmProvider.getById('gemini');
      expect(gemini.name, 'Google Gemini');
      expect(gemini.keyPortalUrl, 'https://aistudio.google.com/app/apikey');

      final cerebras = LlmProvider.getById('cerebras');
      expect(cerebras.name, 'Cerebras');
      expect(cerebras.keyPortalUrl, 'https://cloud.cerebras.ai/platform/');

      final github = LlmProvider.getById('github');
      expect(github.name, 'GitHub Models');
      expect(github.keyPortalUrl, 'https://github.com/settings/tokens');

      final mistral = LlmProvider.getById('mistral');
      expect(mistral.name, 'Mistral AI');
      expect(mistral.keyPortalUrl, 'https://console.mistral.ai/api-keys/');

      final hf = LlmProvider.getById('huggingface');
      expect(hf.name, 'Hugging Face');
      expect(hf.keyPortalUrl, 'https://huggingface.co/settings/tokens');

      final custom = LlmProvider.getById('custom_freellmapi');
      expect(custom.name, contains('FreeLLMAPI'));
      expect(custom.keyPortalUrl, 'https://freellmapi.co');
      expect(custom.isCustom, isTrue);
    });

    test('All providers contain default models and valid portal URLs', () {
      for (final provider in LlmProvider.allProviders) {
        expect(provider.models.isNotEmpty, isTrue,
            reason: '${provider.name} should have model models');
        expect(provider.defaultModel.isNotEmpty, isTrue);
        expect(provider.keyPortalUrl.startsWith('http'), isTrue);
      }
    });
  });

  group('Lauriva Prompt Generation Tests', () {
    test('Builds system prompt containing global instructions and feature instructions', () {
      final prompt = AppPrompts.buildSystemPrompt('Grammar');
      expect(prompt, contains('You are an intelligent inline writing assistant'));
      expect(prompt, contains('Correct all spelling mistakes, grammatical errors'));
    });

    test('Builds user prompt for grammar correction', () {
      final prompt = AppPrompts.buildUserPrompt('Grammar', 'Hello world');
      expect(prompt, contains('FEATURE: Grammar'));
      expect(prompt, contains('TEXT: Hello world'));
    });

    test('Builds concise prompt', () {
      final prompt = AppPrompts.getFeatureInstruction('Concise');
      expect(prompt, contains('Compress the given text to its essential meaning'));
    });

    test('Builds Humanize prompt with anti-AI and plagiarism-free rules', () {
      final prompt = AppPrompts.getFeatureInstruction('Humanize');
      expect(prompt, contains('Wikipedia Signs of AI Writing'));
      expect(prompt, contains('Bursty Rhythm'));
      expect(prompt, isNot(contains('MUST score BELOW')));
      expect(prompt, isNot(contains('GPTZero')));
      expect(prompt, contains('Ban AI Vocabulary'));
      expect(prompt, contains('Plagiarism Elimination'));

      final systemPrompt = AppPrompts.buildSystemPrompt('Humanize');
      expect(systemPrompt, contains('Anti-AI Cadence & Voice'));
      expect(systemPrompt, contains('Plagiarism Elimination'));
    });
  });

  group('Shared editing principles block', () {
    const marker = 'Editing Principles:';
    test('present for rewrite-style features', () {
      for (final id in [
        'Humanize',
        'Rephrase',
        'Concise',
        'Professional',
        'Polite',
        'Style: Witty',
        'Style: Assertive',
        'Style: Empathetic',
        'Style: Direct',
        'Style: Storytelling',
      ]) {
        expect(AppPrompts.getFeatureInstruction(id), contains(marker), reason: id);
        expect(AppPrompts.buildSystemPrompt(id), contains(AppPrompts.editingPrinciples), reason: id);
      }
    });

    test('absent for Grammar, Translate and PlagiarismCheck', () {
      for (final id in ['Grammar', 'Translate', 'PlagiarismCheck']) {
        expect(AppPrompts.getFeatureInstruction(id), isNot(contains(marker)), reason: id);
      }
    });
  });

  group('Split Provider Unit Tests', () {
    test('Character and word counts calculate accurately', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final studio = _buildProviders(storage).studio;
      expect(studio.inputCharCount, 0);
      expect(studio.inputWordCount, 0);

      studio.setInputText('Lauriva AI writes elegantly.');
      expect(studio.inputCharCount, 28);
      expect(studio.inputWordCount, 4);

      studio.clearInput();
      expect(studio.inputCharCount, 0);
      expect(studio.inputWordCount, 0);
    });

    test('API Key storage and retrieval (Groq backward compatibility)', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final llmSettings = LlmSettingsProvider(storage: storage);
      expect(llmSettings.hasApiKey, isFalse);

      await llmSettings.setGroqApiKey('gsk_test123456');
      expect(llmSettings.hasApiKey, isTrue);
      expect(llmSettings.groqApiKey, 'gsk_test123456');
    });

    test('Multi-provider key management and switching', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final llmSettings = LlmSettingsProvider(storage: storage);
      expect(llmSettings.activeProvider.id, 'groq');

      // Set key for OpenRouter
      await llmSettings.setApiKeyForProvider('openrouter', 'sk-or-v1-testkey');
      expect(llmSettings.getApiKeyForProvider('openrouter'), 'sk-or-v1-testkey');

      // Switch to OpenRouter
      await llmSettings.setActiveProvider('openrouter');
      expect(llmSettings.activeProvider.id, 'openrouter');
      expect(llmSettings.activeApiKey, 'sk-or-v1-testkey');
      expect(llmSettings.hasActiveApiKey, isTrue);

      // Change model
      await llmSettings.setActiveModel('deepseek/deepseek-chat:free');
      expect(llmSettings.activeModel, 'deepseek/deepseek-chat:free');

      // Switch to Gemini
      await llmSettings.setActiveProvider('gemini');
      expect(llmSettings.activeProvider.id, 'gemini');
      expect(llmSettings.hasActiveApiKey, isFalse);
      await llmSettings.setApiKeyForProvider('gemini', 'AIzaSyTest');
      expect(llmSettings.activeApiKey, 'AIzaSyTest');
      expect(llmSettings.hasActiveApiKey, isTrue);
    });

    test('Use as Input swaps output to input', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final p = _buildProviders(storage);
      p.studio.setInputText('Initial input');

      await p.llmSettings.setGroqApiKey('gsk_test');
      p.studio.useOutputAsInput();
      expect(p.studio.inputText, 'Initial input');
    });

    test('History management adds, restores, and clears transformations', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final p = _buildProviders(storage);
      expect(p.history.history.isEmpty, isTrue);
      expect(p.history.structuredHistory.isEmpty, isTrue);

      final record1 = HistoryRecord(
        id: 'rec-1',
        timestamp: DateTime.now(),
        inputText: 'Raw draft input',
        outputText: 'Polished transformed output',
        featureId: 'Humanize',
        featureLabel: 'Humanize (Anti-AI)',
        providerName: 'Groq',
        modelUsed: 'llama-3.3-70b-versatile',
        inputWordCount: 3,
        outputWordCount: 3,
        humanScore: 92.0,
        aiRiskScore: 8.0,
      );

      await storage.addHistoryRecord(record1);
      expect(p.history.history.length, 1);
      expect(p.history.structuredHistory.length, 1);
      expect(p.history.structuredHistory.first.featureId, 'Humanize');
      expect(p.history.structuredHistory.first.humanScore, 92.0);
      expect(p.history.history.first, 'Polished transformed output');

      // Add legacy plain string item and test backward compatibility
      await storage.addHistoryItem('Legacy plain text item');
      expect(p.history.history.length, 2);
      expect(p.history.structuredHistory.length, 2);
      expect(p.history.structuredHistory.first.outputText, 'Legacy plain text item');
      expect(p.history.structuredHistory.first.outputWordCount, 4);

      // Restore to input
      p.studio.restoreFromHistory('Polished transformed output', toInput: true);
      expect(p.studio.inputText, 'Polished transformed output');

      // Restore to output
      p.studio.restoreFromHistory('Legacy plain text item', toInput: false);
      expect(p.studio.outputText, 'Legacy plain text item');

      // Remove single
      await p.history.removeHistoryItem(0);
      expect(p.history.history.length, 1);

      // Clear all
      await p.history.clearHistory();
      expect(p.history.history.isEmpty, isTrue);
      expect(p.history.structuredHistory.isEmpty, isTrue);
    });

    test('Voice recording duration formatting and isolated notifier', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final speech = _buildProviders(storage).speech;
      expect(speech.formattedRecordingTime, '00:00');
      expect(speech.recordingSeconds, 0);
      expect(speech.recordingSecondsNotifier.value, 0);

      // Mutate isolated notifier (emits no global rebuilds)
      speech.recordingSecondsNotifier.value = 65;
      expect(speech.recordingSeconds, 65);
      expect(speech.formattedRecordingTime, '01:05');
      expect(speech.soundLevel, 0.0);
    });

    test('Persona quick-switching updates provider state', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final llmSettings = LlmSettingsProvider(storage: storage);
      expect(llmSettings.persona, 'standard');

      await llmSettings.setPersona('executive');
      expect(llmSettings.persona, 'executive');

      await llmSettings.setPersona('academic');
      expect(llmSettings.persona, 'academic');
    });

    test('Markdown export utility triggers cleanly without crashes', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final p = _buildProviders(storage);
      p.studio.setInputText('This is sample draft text.');
      p.studio.restoreFromHistory('This is sample polished output text.', toInput: false);

      await p.studio.exportFormattedMarkdown();
      expect(p.toast.toasts.any((t) => t.message.contains('clipboard')), isTrue);
    });

    test('Microphone soundLevel updates through isolated ValueNotifier', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final speech = _buildProviders(storage).speech;
      expect(speech.soundLevel, 0.0);
      expect(speech.soundLevelNotifier.value, 0.0);

      // Mutate isolated notifier
      speech.soundLevelNotifier.value = 8.5;
      expect(speech.soundLevel, 8.5);
      expect(speech.soundLevelNotifier.value, 8.5);
    });

    test('stopGeneration cancels in-flight streaming cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();

      final studio = _buildProviders(storage).studio;
      expect(studio.isStreaming, isFalse);

      studio.stopGeneration();
      expect(studio.isStreaming, isFalse);
      expect(studio.isLoading, isFalse);
    });
  });

  group('Softened Botanical & Slate Color Palette Tokens Tests', () {
    setUp(() => AppColors.setBrightness(AppBrightness.dark));

    test('Verifies core botanical color palette tokens and hex values', () {
      expect(AppColors.paletteTeal, const Color(0xFF38B2AC));
      expect(AppColors.paletteTealLight, const Color(0xFF0D9488));
      expect(AppColors.paletteSage, const Color(0xFF7CA982));
      expect(AppColors.palettePistachio, const Color(0xFF93C572));
      expect(AppColors.paletteEmerald, const Color(0xFF2E8B84));
      expect(AppColors.paletteForest, const Color(0xFF235347));
      expect(AppColors.paletteCream, const Color(0xFFF1F5F9));
    });

    test('Verifies semantic mapping of core palette tokens to theme roles', () {
      expect(AppColors.primary, AppColors.paletteTeal);
      expect(AppColors.secondary, AppColors.paletteSage);
      expect(AppColors.accent, AppColors.palettePistachio);
      expect(AppColors.ice, AppColors.paletteTeal);
      expect(AppColors.textPrimary, const Color(0xFFF1F5F9));
    });

    test('Verifies textPrimary and primary flip to accessible brand teal under light brightness', () {
      AppColors.setBrightness(AppBrightness.light);
      expect(AppColors.primary, AppColors.paletteTealLight);
      expect(AppColors.accentText, AppColors.paletteTealLight);
      expect(AppColors.textPrimary, isNot(AppColors.paletteCream));
      expect(AppColors.textPrimary.computeLuminance(), lessThan(0.5),
          reason: 'light-mode primary text should be dark for legibility on a white surface');
      // Reset back to dark
      AppColors.setBrightness(AppBrightness.dark);
    });
  });

  group('LlmService Streaming & Reasoning Tests', () {
    test('stripThinkingTags cleanly extracts answer and removes think blocks', () {
      const reasoningOutput = '<think>\nAnalyze the text grammar.\nKey error found.\n</think>\nHere is the polished output.';
      final cleaned = LlmService.stripThinkingTags(reasoningOutput);
      expect(cleaned, 'Here is the polished output.');
    });

    test('stripThinkingTags handles dangling opening tag', () {
      const dangling = '<think>Partial reasoning</think>Polished text';
      final cleaned = LlmService.stripThinkingTags(dangling);
      expect(cleaned, 'Polished text');
    });

    test('HistoryRecord JSON serialization, deserialization, and delta calculation', () {
      final record = HistoryRecord(
        id: 'test-rec-1',
        timestamp: DateTime(2026, 9, 21, 12, 0, 0),
        inputText: 'This is short draft input',
        outputText: 'This is a significantly longer polished and comprehensive output text',
        featureId: 'Professional',
        featureLabel: 'Professional Tone',
        providerName: 'Groq',
        modelUsed: 'llama-3.3-70b-versatile',
        inputWordCount: 5,
        outputWordCount: 10,
        humanScore: 88.0,
        aiRiskScore: 12.0,
      );

      final json = record.toJson();
      final deserialized = HistoryRecord.fromJson(json);

      expect(deserialized.id, 'test-rec-1');
      expect(deserialized.featureId, 'Professional');
      expect(deserialized.modelUsed, 'llama-3.3-70b-versatile');
      expect(deserialized.inputWordCount, 5);
      expect(deserialized.outputWordCount, 10);
      expect(deserialized.humanScore, 88.0);
      expect(deserialized.wordDeltaPercent, 100);
      expect(deserialized.relativeTime.isNotEmpty, isTrue);
    });
  });

  group('Lauriva Widget Integration Tests (testWidgets)', () {
    testWidgets('LaurivaApp pumps and renders complete interface with Header, Input, Chips, and Output',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(_wrapWithProviders(p, const LaurivaApp()));
      await tester.pumpAndSettle();

      // Brand Header
      expect(find.text('Lauriva'), findsOneWidget);

      // Zone 1 Input
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('YOUR TEXT'), findsOneWidget);

      // Zone 2 Writing Profile (Mini Settings)
      expect(find.text('WRITING PROFILE'), findsOneWidget);
      expect(find.text('Rewrite'), findsOneWidget);
      expect(find.text('STUDIO'), findsOneWidget);

      // Zone 3 Output Area
      expect(find.text('OUTPUT'), findsOneWidget);
      expect(find.text('Your result will appear here.'), findsOneWidget);
    });

    testWidgets('Typing into TextField updates input text and character/word metrics live',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(_wrapWithProviders(p, const LaurivaApp()));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      await tester.enterText(textFieldFinder, 'Lauriva transforms every sentence cleanly.');
      await tester.pumpAndSettle();

      expect(p.studio.inputText, 'Lauriva transforms every sentence cleanly.');
      expect(p.studio.inputWordCount, 5);
      expect(find.text('5 words'), findsOneWidget);
    });

    testWidgets('Tapping Settings in Writing Profile opens Mini Settings and selects action',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(_wrapWithProviders(p, const LaurivaApp()));
      await tester.pumpAndSettle();

      final settingsBtn = find.text('Settings');
      expect(settingsBtn, findsWidgets);

      await tester.tap(settingsBtn.first);
      await tester.pumpAndSettle();

      expect(find.text('Mini Settings'), findsOneWidget);
      expect(find.text('WRITING ACTION'), findsOneWidget);
      expect(find.text('Fix Grammar'), findsOneWidget);

      await tester.tap(find.text('Fix Grammar'));
      await tester.pumpAndSettle();

      expect(p.studio.activeFeatureId, 'Grammar');
    });

    testWidgets('Tapping settings button in HeaderBar opens Settings screen',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(_wrapWithProviders(p, const LaurivaApp()));
      await tester.pumpAndSettle();

      final settingsButtonFinder = find.byIcon(LucideIcons.sliders);
      expect(settingsButtonFinder, findsOneWidget);

      await tester.tap(settingsButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
      expect(find.text('AI PROVIDER'), findsOneWidget);
    });

    testWidgets('Accessibility semantics tags are present on interactive action buttons',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(_wrapWithProviders(p, const LaurivaApp()));
      await tester.pumpAndSettle();

      // Verify Semantics nodes exist on controls
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Start microphone dictation',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Open Settings',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label?.contains('Rewrite') ?? false),
        ),
        findsOneWidget,
      );
    });
  });

  group('StudioProvider Stream Lifecycle and Error Resilience Tests', () {
    test('stopGeneration cancels active streaming flags and notifies listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      bool notified = false;
      p.studio.addListener(() {
        notified = true;
      });

      p.studio.stopGeneration();

      expect(p.studio.isStreaming, isFalse);
      expect(p.studio.isLoading, isFalse);
      expect(notified, isTrue);
    });

    test('handleFeatureClick with empty text displays error toast and returns early', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      p.studio.clearInput();
      await p.studio.handleFeatureClick('Grammar');

      expect(p.toast.toasts.isNotEmpty, isTrue);
      expect(p.toast.toasts.first.message, contains('Please type or record some text first'));
      expect(p.studio.isLoading, isFalse);
    });

    test('handleFeatureClick with unknown featureId displays error toast and returns early', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      p.studio.setInputText('Some valid text');
      await p.studio.handleFeatureClick('NonExistentFeatureId');

      expect(p.toast.toasts.isNotEmpty, isTrue);
      expect(p.toast.toasts.first.message, contains('Unknown action'));
      expect(p.studio.isLoading, isFalse);
    });

    testWidgets('History records persist correctly and render in HistoryModalContent', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      final record = HistoryRecord(
        id: 'test-rec-1',
        timestamp: DateTime(2026, 1, 1),
        inputText: 'Original input passage',
        outputText: 'Humanized output passage',
        featureId: 'Humanize',
        featureLabel: 'AI Humanizer',
        providerName: 'Groq',
        modelUsed: 'llama-3.3-70b-versatile',
        inputWordCount: 3,
        outputWordCount: 3,
        humanScore: 94.0,
        aiRiskScore: 6.0,
      );

      await p.history.addHistoryRecord(record);
      expect(p.history.structuredHistory.length, 1);
      expect(p.history.structuredHistory.first.inputText, 'Original input passage');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: p.llmSettings),
            ChangeNotifierProvider.value(value: p.theme),
            ChangeNotifierProvider.value(value: p.toast),
            ChangeNotifierProvider.value(value: p.history),
            ChangeNotifierProvider.value(value: p.studio),
          ],
          child: const MaterialApp(
            home: Scaffold(body: HistoryModalContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Humanized output passage'), findsOneWidget);
      expect(find.text('AI Humanizer'), findsOneWidget);
    });

    testWidgets('TtsPlayerBar renders Voice button when idle and hides it during active playback', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      // 1. When Idle: Voice button visible, stop button hidden
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: p.speech),
            ChangeNotifierProvider.value(value: p.studio),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TtsPlayerBar(textToSpeak: 'Hello world'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voice'), findsOneWidget);
      expect(find.byIcon(LucideIcons.square), findsNothing);

      // 2. When Playing: Speak begins, Voice button must be hidden and Stop button shown
      await p.speech.speak('Hello world');
      await tester.pump();

      expect(find.text('Voice'), findsNothing);
      expect(find.byIcon(LucideIcons.square), findsOneWidget);

      // 3. Stop speech returns to Idle: Voice button restored
      await p.speech.stop();
      await tester.pump();

      expect(find.text('Voice'), findsOneWidget);
      expect(find.byIcon(LucideIcons.square), findsNothing);
    });

    testWidgets('VoiceMiniSettingsModal renders consistent header, reading speed, and Apply Settings button', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: p.speech),
            ChangeNotifierProvider.value(value: p.toast),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: VoiceMiniSettingsModal(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mini Settings'), findsOneWidget);
      expect(find.text('VOICE'), findsOneWidget);
      expect(find.text('READING SPEED'), findsOneWidget);
      expect(find.text('TTS VOICE'), findsOneWidget);
      expect(find.text('Apply Settings'), findsOneWidget);
    });

    testWidgets('SettingsScreen has removed Voice and Speech section completely', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: p.llmSettings),
            ChangeNotifierProvider.value(value: p.theme),
            ChangeNotifierProvider.value(value: p.toast),
            ChangeNotifierProvider.value(value: p.history),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('VOICE & SPEECH'), findsNothing);
      expect(find.text('Voice & Speech'), findsNothing);
      expect(find.text('Reading Speed'), findsNothing);
    });

    test('Rephrase prompt instructs direct clean rewritten prose without numbered lists', () {
      final prompt = AppPrompts.getFeatureInstruction('Rephrase');
      expect(prompt, contains('CRITICAL OUTPUT CONSTRAINT: Output ONLY the direct rewritten prose'));
      expect(prompt, contains('Never output numbered alternatives'));
      expect(prompt, isNot(contains('output 2–3 variations numbered')));
    });

    testWidgets('Zone1Input syncs controller text to StudioProvider before transform', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      // Stale text in provider initially
      p.studio.setInputText('old test text');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: p.studio),
            ChangeNotifierProvider.value(value: p.speech),
            ChangeNotifierProvider.value(value: p.toast),
            ChangeNotifierProvider.value(value: p.theme),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Zone1Input(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter new text directly into the TextField
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'New user rewritten draft');
      await tester.pump();

      // Ensure button reflects new text and clicking updates provider
      final button = find.widgetWithText(ElevatedButton, 'Rewrite');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();

      expect(p.studio.inputText, 'New user rewritten draft');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('AboutSection displays Legal & AI Policies and opens LegalPolicySheet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final p = _buildProviders(storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: p.theme),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AboutSection(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Legal & AI Policies'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);

      await tester.tap(find.text('Legal & AI Policies'));
      await tester.pumpAndSettle();

      // Verify LegalPolicySheet content
      expect(find.text('Legal & Policies'), findsOneWidget);
      expect(find.text('AI Can Make Mistakes'), findsOneWidget);
      expect(find.text('AI Disclaimer'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms & Ethics'), findsOneWidget);

      // Tap Privacy Policy tab
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.text('Zero-Retention & Privacy by Design'), findsOneWidget);

      // Tap Terms & Ethics tab
      await tester.tap(find.text('Terms & Ethics'));
      await tester.pumpAndSettle();

      expect(find.text('Ethical Use & Academic Integrity'), findsOneWidget);
    });
  });
}


