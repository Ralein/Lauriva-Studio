import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/humanizer_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/screens/humanizer_screen.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/widgets/humanizer/humanizer_report_card.dart';
import '../test_mocks.dart';

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  setUp(() {
    clearMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HumanizerScreen renders minimalist layout with Humanize CTA and Mini Settings bar', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final storage = StorageService();
    await storage.init();
    final toast = ToastProvider();
    final history = HistoryProvider(storage: storage, toast: toast);
    final plagiarism = PlagiarismProvider(storage: storage, toast: toast, history: history);
    final speech = SpeechProvider(storage: storage, toast: toast);
    final llmSettings = LlmSettingsProvider(storage: storage);
    final theme = ThemeProvider(storage: storage);
    final humanizer = HumanizerProvider(
      storage: storage,
      toast: toast,
      history: history,
      llmSettings: llmSettings,
      plagiarism: plagiarism,
      speech: speech,
    );
    final studio = StudioProvider(
      storage: storage,
      speech: speech,
      llmSettings: llmSettings,
      history: history,
      toast: toast,
      plagiarism: plagiarism,
    );

    humanizer.setInputText('This passage is formulated using synthetic patterns that warrant natural cadence.');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ToastProvider>.value(value: toast),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<HistoryProvider>.value(value: history),
          ChangeNotifierProvider<LlmSettingsProvider>.value(value: llmSettings),
          ChangeNotifierProvider<SpeechProvider>.value(value: speech),
          ChangeNotifierProvider<PlagiarismProvider>.value(value: plagiarism),
          ChangeNotifierProvider<StudioProvider>.value(value: studio),
          ChangeNotifierProvider<HumanizerProvider>.value(value: humanizer),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: HumanizerScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify "Humanize" button is present (replaces "Improve Naturally")
    expect(find.text('Humanize'), findsOneWidget);
    expect(find.byIcon(LucideIcons.fingerprint), findsOneWidget);
    expect(find.text('Improve Naturally'), findsNothing);

    // 2. Verify Zone 2 Writing Profile & Mini Settings bar
    expect(find.text('WRITING PROFILE'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(LucideIcons.settings2), findsOneWidget);
    expect(find.text('Meaning Guard'), findsNothing);

    // 3. Verify tone chips are no longer cluttering the main screen
    expect(find.text('Casual'), findsNothing);
    expect(find.text('Academic'), findsNothing);

    // 4. Tap "Settings" button to open the Mini Settings bottom sheet
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // 5. Verify modal content
    expect(find.text('Mini Settings'), findsOneWidget);
    expect(find.text('WRITING TONE'), findsOneWidget);
    expect(find.text('CONSTRAINTS & LENGTH'), findsOneWidget);
    expect(find.text('Meaning Guard Active'), findsNothing);
    expect(find.text('Apply Settings'), findsOneWidget);

    // All tones present in modal
    expect(find.text('Professional'), findsNWidgets(2)); // pill + modal
    expect(find.text('Academic'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    expect(find.text('Conversational'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('Natural'), findsOneWidget);

    // Style chips present in modal
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Concise'), findsOneWidget);
    expect(find.text('Detailed'), findsOneWidget);
    expect(find.text('Technical'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);

    // 6. Select "Casual" tone in modal and tap Apply Settings
    await tester.tap(find.text('Casual'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Apply Settings'));
    await tester.tap(find.text('Apply Settings'));
    await tester.pumpAndSettle();

    // Modal is dismissed, and profile shows Casual!
    expect(find.text('Mini Settings'), findsNothing);
    expect(find.text('Casual'), findsOneWidget);
  });

  testWidgets('HumanizerReportCard renders key metrics in a 2-column grid matching Plagiarism card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HumanizerReportCard(
              originalScore: 82.0,
              humanizedScore: 14.0,
              semanticFidelity: 98.0,
              contentPreserved: 100.0,
              wordCount: 125,
              charCount: 680,
              readTimeSec: 32,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify 4 metric labels in 2-column layout
    expect(find.text('Fidelity'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('High Precision'), findsOneWidget);

    expect(find.text('Preserved Words'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('125 Words Retained'), findsOneWidget);

    expect(find.text('Word Count'), findsOneWidget);
    expect(find.text('125'), findsOneWidget);
    expect(find.text('680 Characters'), findsOneWidget);

    expect(find.text('Read Time'), findsOneWidget);
    expect(find.text('32s'), findsOneWidget);
    expect(find.text('Estimated Pace'), findsOneWidget);
  });

  testWidgets('ToneStyleSelector settings no longer expose intensity and keep the default 85', (tester) async {
    final storage = StorageService();
    await storage.init();
    final toast = ToastProvider();
    final history = HistoryProvider(storage: storage, toast: toast);
    final plagiarism = PlagiarismProvider(storage: storage, toast: toast, history: history);
    final speech = SpeechProvider(storage: storage, toast: toast);
    final llmSettings = LlmSettingsProvider(storage: storage);
    final theme = ThemeProvider(storage: storage);
    final humanizer = HumanizerProvider(
      storage: storage,
      toast: toast,
      history: history,
      llmSettings: llmSettings,
      plagiarism: plagiarism,
      speech: speech,
    );
    final studio = StudioProvider(
      storage: storage,
      speech: speech,
      llmSettings: llmSettings,
      history: history,
      toast: toast,
      plagiarism: plagiarism,
    );

    expect(humanizer.humanizeIntensity, 85);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ToastProvider>.value(value: toast),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<HistoryProvider>.value(value: history),
          ChangeNotifierProvider<LlmSettingsProvider>.value(value: llmSettings),
          ChangeNotifierProvider<SpeechProvider>.value(value: speech),
          ChangeNotifierProvider<PlagiarismProvider>.value(value: plagiarism),
          ChangeNotifierProvider<StudioProvider>.value(value: studio),
          ChangeNotifierProvider<HumanizerProvider>.value(value: humanizer),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: HumanizerScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Settings modal
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // The intensity slider/presets were removed from the settings UI; the engine keeps its default.
    expect(find.text('HUMANIZATION INTENSITY'), findsNothing);

    await tester.ensureVisible(find.text('Apply Settings'));
    await tester.tap(find.text('Apply Settings'));
    await tester.pumpAndSettle();

    expect(humanizer.humanizeIntensity, 85);
  });
}
