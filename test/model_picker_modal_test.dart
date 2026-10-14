import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/models/llm_provider.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/widgets/model_picker_modal.dart';
import 'package:lauriva/screens/settings_screen.dart';
import 'test_mocks.dart';

/// Wires one instance of every app provider together exactly as main.dart's
/// bootstrap does, so SettingsScreen (and anything it opens, like the model
/// picker) has the full dependency graph it expects at runtime.
class _Providers {
  final LlmSettingsProvider llmSettings;
  final List<ChangeNotifierProvider> asList;

  _Providers(this.llmSettings, this.asList);

  factory _Providers.build(StorageService storage) {
    final toast = ToastProvider();
    final history = HistoryProvider(storage: storage, toast: toast);
    final plagiarism = PlagiarismProvider(storage: storage, toast: toast, history: history);
    final speech = SpeechProvider(storage: storage, toast: toast);
    final llmSettings = LlmSettingsProvider(storage: storage);
    final studio = StudioProvider(
      storage: storage,
      speech: speech,
      llmSettings: llmSettings,
      history: history,
      toast: toast,
      plagiarism: plagiarism,
    );
    return _Providers(llmSettings, [
      ChangeNotifierProvider<ToastProvider>.value(value: toast),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider(storage: storage)),
      ChangeNotifierProvider<HistoryProvider>.value(value: history),
      ChangeNotifierProvider<LlmSettingsProvider>.value(value: llmSettings),
      ChangeNotifierProvider<SpeechProvider>.value(value: speech),
      ChangeNotifierProvider<PlagiarismProvider>.value(value: plagiarism),
      ChangeNotifierProvider<StudioProvider>.value(value: studio),
    ]);
  }
}

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  testWidgets('ModelPickerModal does not overflow on a narrow mobile screen (360x640)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();

    String? selected;

    await tester.pumpWidget(
      MultiProvider(
        providers: _Providers.build(storage).asList,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  final prov = LlmProvider.getById('openrouter');
                  showModelPickerModal(
                    context: context,
                    provider: prov,
                    currentModel: prov.defaultModel,
                    onModelSelected: (m) => selected = m,
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    // Verify modal prompts for API key when none is configured
    expect(find.text('OpenRouter Models'), findsOneWidget);
    expect(find.text('API Key Required'), findsOneWidget);
    expect(find.text('Fetch Models'), findsOneWidget);
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ModelPickerModal displays catalog and custom model option when API key is set',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setApiKey('openrouter', 'sk-or-v1-mock-test-key');

    String? selected;

    await tester.pumpWidget(
      MultiProvider(
        providers: _Providers.build(storage).asList,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  final prov = LlmProvider.getById('openrouter');
                  showModelPickerModal(
                    context: context,
                    provider: prov,
                    currentModel: prov.defaultModel,
                    onModelSelected: (m) => selected = m,
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    expect(find.text('OpenRouter Models'), findsOneWidget);
    expect(find.text('Custom Model'), findsOneWidget);
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen does not overflow when a long model ID is selected',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    await storage.setSelectedModel('openrouter', 'meta-llama/llama-3.3-70b-instruct:free');
    final providers = _Providers.build(storage);
    await providers.llmSettings.setActiveProvider('openrouter');

    await tester.pumpWidget(
      MultiProvider(
        providers: providers.asList,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
