import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lauriva/models/plagiarism_report.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/humanizer_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/widgets/plagiarism_audit_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_mocks.dart';

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  setUp(() {
    clearMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
  });

  group('Progressive Disclosure & Perspective Switcher Tests', () {
    testWidgets('Toggles smoothly between Executive View and Deep Forensic Audit', (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = StorageService();
      await storage.init();
      final toast = ToastProvider();
      final history = HistoryProvider(storage: storage, toast: toast);
      final llmSettings = LlmSettingsProvider(storage: storage);
      final plagiarism = PlagiarismProvider(
        storage: storage,
        toast: toast,
        history: history,
        llmSettings: llmSettings,
      );

      final mockReport = PlagiarismReport(
        overallScore: 78.0,
        riskLevel: PlagiarismRiskLevel.high,
        humanScore: 22.0,
        plagiarismRiskScore: 15.0,
        burstinessScore: 0.28,
        predictabilityScore: 0.85,
        lexicalRichness: 55.0,
        ngramOverlapScore: 22.0,
        repeatedNgrams: const [],
        detectedTells: const ['Formulaic transition triad'],
        defensibleSummary: 'High AI probability detected due to uniform sentence structures.',
        sentences: const [
          SentenceAudit(
            index: 0,
            text: 'Artificial intelligence is undeniably transforming the fabric of society.',
            aiProbability: 85.0,
            riskLevel: PlagiarismRiskLevel.high,
            detectedTells: ['Stock opening metaphor'],
            wordCount: 9,
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ToastProvider>.value(value: toast),
            ChangeNotifierProvider<PlagiarismProvider>.value(value: plagiarism),
            ChangeNotifierProvider<HumanizerProvider>(create: (_) => HumanizerProvider(storage: storage, toast: toast, history: history, llmSettings: llmSettings)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlagiarismAuditCard(report: mockReport),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Perspective Switcher presence
      expect(find.text('Executive'), findsOneWidget);
      expect(find.text('Deep Forensic'), findsOneWidget);

      // Default is Deep Forensic Audit
      expect(find.textContaining('Forensic Inspector'), findsOneWidget);

      // 2. Tap Executive View
      await tester.tap(find.text('Executive'));
      await tester.pumpAndSettle();

      // Verify Executive Metrics Grid is displayed
      expect(find.text('Originality'), findsOneWidget);
      expect(find.text('Cadence & Flow'), findsOneWidget);
      expect(find.text('Literature Match'), findsOneWidget);
      expect(find.text('Syntactic Tells'), findsOneWidget);
      expect(find.text('Humanize'), findsOneWidget);
      expect(find.text('Copy Report'), findsOneWidget);

      // 3. Tap Deep Forensic Audit to return
      await tester.tap(find.text('Deep Forensic'));
      await tester.pumpAndSettle();

      // Forensic Inspector accordion is back
      expect(find.textContaining('Forensic Inspector'), findsOneWidget);
    });
  });
}
