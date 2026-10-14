import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/screens/detector_screen.dart';
import 'package:lauriva/services/llm_service.dart';
import 'package:lauriva/services/storage_service.dart';
import 'test_mocks.dart';

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  setUp(() {
    clearMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('DetectorScreen has unified engine CTA, no fragmented scan mode chips, and zero overflow on AI scan',
      (WidgetTester tester) async {
    // Standard narrow mobile viewport
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final storage = StorageService();
    await storage.init();
    await storage.setApiKey('groq', 'gsk_mock_api_key_123');
    final toast = ToastProvider();
    final history = HistoryProvider(storage: storage, toast: toast);
    final mockAuditJson = jsonEncode({
      'overallScore': 90.0,
      'plagiarismRiskScore': 12.0,
      'burstinessScore': 0.2,
      'predictabilityScore': 0.9,
      'lexicalRichness': 60.0,
      'ngramOverlapScore': 15.0,
      'detectedTells': ['Artificial intelligence transition'],
      'defensibleSummary': 'High AI authorship detected.',
      'sentences': [
        {
          'text': 'Artificial intelligence is transforming education by enabling personalized learning experiences and automating administrative tasks.',
          'aiProbability': 92.0,
          'detectedTells': ['Predictable syntactic scaffolding']
        }
      ]
    });
    final mockLlmService = LlmService(
      client: MockClient((req) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': mockAuditJson}
            }
          ]
        }),
        200,
      )),
    );
    final llmSettings = LlmSettingsProvider(storage: storage);
    final plagiarism = PlagiarismProvider(
      storage: storage,
      toast: toast,
      history: history,
      llmSettings: llmSettings,
      llmService: mockLlmService,
    );
    final speech = SpeechProvider(storage: storage, toast: toast);
    final theme = ThemeProvider(storage: storage);
    final studio = StudioProvider(
      storage: storage,
      speech: speech,
      llmSettings: llmSettings,
      history: history,
      toast: toast,
      plagiarism: plagiarism,
    );

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
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DetectorScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    // 1. Verify old fragmented scan mode chip bar is removed in favor of unified Mini Settings
    expect(find.text('Quick Scan'), findsNothing);
    expect(find.text('Deep AI Scan'), findsNothing);
    expect(find.text('Source Scan'), findsNothing);
    expect(find.text('FORENSIC PROFILE'), findsOneWidget);

    // 2. Verify single unified forensic scan CTA is hidden until user types in
    expect(find.text('Run Full Audit'), findsNothing);

    // 3. Enter textbook AI test text
    const aiText =
        'Artificial intelligence is transforming education by enabling personalized learning '
        'experiences and automating administrative tasks. However, its implementation must be '
        'carefully balanced with ethical considerations and the essential role of human educators.';

    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    await tester.enterText(textField, aiText);
    await tester.pump();

    // Verify single unified forensic scan CTA appears after user types
    expect(find.text('Run Full Audit'), findsOneWidget);

    // 4. Tap the unified 'Run Full Audit' button
    await tester.tap(find.text('Run Full Audit'));
    // The scan mixes fake-clock timers (UI yields) with real async work (isolates, file I/O),
    // so each iteration advances the fake clock and then lets real time pass.
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (plagiarism.forensicReport == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump(const Duration(milliseconds: 100));

    final err = tester.takeException();
    expect(err, isNull);

    // 6. Verify accuracy: score is accurately flagged as high AI probability (> 65%, the likely-AI zone)
    expect(plagiarism.forensicReport, isNotNull);
    final overallScore = plagiarism.forensicReport!.overallScore;
    expect(overallScore, greaterThan(65.0));

    // 7. Verify the 2x2 grid forensic pillars render properly
    expect(find.text('AI Authorship'), findsOneWidget);
    expect(find.text('Source Match'), findsOneWidget);
    expect(find.text('Repetition'), findsOneWidget);
    expect(find.text('Confidence'), findsOneWidget);

    // 8. Verify the inspector accordion header has no overflow
    final inspectorHeader = find.textContaining('Forensic Inspector');
    expect(inspectorHeader, findsOneWidget);

    // 9. Scroll down to accordion, tap to expand and verify sentence breakdown
    await tester.ensureVisible(inspectorHeader);
    await tester.pumpAndSettle();
    await tester.tap(inspectorHeader, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    // Still no layout overflow exceptions after accordion is opened
    expect(tester.takeException(), isNull);

    // Flush toast notification timer (3.2s)
    await tester.pump(const Duration(seconds: 4));
  });
}
