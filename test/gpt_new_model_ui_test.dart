// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/widgets/benchmark_transparency_card.dart';
import 'package:lauriva/widgets/confidence_interval_bar.dart';
import 'package:lauriva/widgets/plagiarism_audit_card.dart';
import 'package:lauriva/widgets/score_gauge_widget.dart';
import 'package:lauriva/widgets/studio/visual_diff_viewer.dart';
import 'test_mocks.dart';

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  setUp(() {
    clearMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
  });

  group('New GPT Models (GPT-4o / GPT-4o-mini / o1) Forensic & UI Inspection', () {
    final engine = ForensicEngine();
    final humanizer = AlgorithmicHumanizerService();
    final verifier = SemanticPreservationVerifier();

    // 1. GPT-4o Direct Academic Essay (Modern, subtle, high lexical richness)
    const gpt4oAcademicEssay = '''
Artificial intelligence is fundamentally reshaping higher education by personalizing curriculum delivery and optimizing instructional workflows. Adaptive learning algorithms analyze real-time student performance metrics to deliver targeted pedagogical interventions, enabling learners to master complex concepts at their own pace. Faculty members utilize automated grading and diagnostic analytics to identify knowledge deficits earlier in the academic semester, allowing them to redirect instructional time toward structured mentorship and collaborative problem-solving. While these technological integrations offer significant improvements in operational efficiency and learning accessibility, academic institutions must proactively establish ethical governance frameworks to safeguard student data privacy, maintain intellectual integrity, and ensure equitable digital access across diverse student demographics.
''';

    // 2. GPT-4o Technical Architecture Output
    const gpt4oTechEssay = '''
Cloud-native microservices architectures have become the standard paradigm for modern distributed enterprise systems. By decomposing monolithic codebases into modular, loosely-coupled services, engineering organizations can accelerate deployment velocity, isolate runtime faults, and scale computational resources independently based on real-time traffic demand. Service meshes and container orchestration engines manage inter-service communication, load balancing, and mutual TLS encryption across heterogeneous server clusters. However, transitioning to microservices introduces operational overhead regarding distributed tracing, network latency, and transactional consistency across disparate databases. Implementing robust observability pipelines, automated canary deployments, and resilient circuit-breaking patterns is essential to maintain high system availability and mitigate cascading failures in production environments.
''';

    // 3. o1-Style Step-by-Step Reasoning Analysis
    const o1ReasoningEssay = '''
To assess the economic feasibility of transitioning urban transit fleets to zero-emission battery electric buses, municipal planners must evaluate lifecycle capital expenditures, infrastructure readiness, and operational cost differentials. High upfront acquisition costs for electric vehicles and depot charging installations are progressively offset by reduced kilowatt-hour fuel costs and lower maintenance requirements over a twelve-year operational horizon. Grid capacity constraints necessitate the deployment of automated smart charging systems that shift electricity consumption to off-peak hours, thereby preventing substation overloads. Consequently, municipal transit authorities that combine targeted federal infrastructure grants with dynamic load management strategies achieve net cost parity with diesel fleets within five to seven operating years.
''';

    test('1. Forensic Engine Accuracy on New GPT Model Outputs', () {
      print('\n================================================================');
      print('🔬 FORENSIC ENGINE ANALYSIS ON NEW GPT MODELS (GPT-4o & o1)');
      print('================================================================');

      // Scan 1: GPT-4o Academic
      final report1 = engine.analyze(gpt4oAcademicEssay);
      print('\n[1] GPT-4o Academic Essay:');
      print('  AI Probability: ${report1.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('  Human Probability: ${report1.humanScore.toStringAsFixed(1)}%');
      print('  Classification: ${report1.aiAuthorship.authorshipClass.badge}');
      print('  Burstiness CV: ${report1.aiAuthorship.featureVector[6].toStringAsFixed(2)}');
      print('  Confidence Level: ${report1.confidence.level.badge}');
      for (final s in report1.aiAuthorship.detectedSignals) {
        print('    - [${s.family}] ${s.name}: ${s.score.toStringAsFixed(1)}');
      }
      expect(report1.aiAuthorship.aiProbability, greaterThanOrEqualTo(30.0));

      // Scan 2: GPT-4o Tech Essay
      final report2 = engine.analyze(gpt4oTechEssay);
      print('\n[2] GPT-4o Technical Architecture Essay:');
      print('  AI Probability: ${report2.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('  Human Probability: ${report2.humanScore.toStringAsFixed(1)}%');
      print('  Classification: ${report2.aiAuthorship.authorshipClass.badge}');
      expect(report2.aiAuthorship.aiProbability, greaterThanOrEqualTo(45.0));

      // Scan 3: o1 Reasoning Essay
      final report3 = engine.analyze(o1ReasoningEssay);
      print('\n[3] o1 Reasoning Essay:');
      print('  AI Probability: ${report3.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('  Human Probability: ${report3.humanScore.toStringAsFixed(1)}%');
      print('  Classification: ${report3.aiAuthorship.authorshipClass.badge}');
      expect(report3.aiAuthorship.aiProbability, greaterThanOrEqualTo(45.0));
    });

    test('2. Algorithmic Humanization & Preservation on GPT-4o Output', () {
      print('\n================================================================');
      print('✨ SURGICAL HUMANIZATION ON GPT-4o ESSAY');
      print('================================================================');

      final humanized = humanizer.postProcessWithQualityLoop(
        gpt4oAcademicEssay,
        tone: WritingToneProfile.conversational,
        originalText: gpt4oAcademicEssay,
      );

      final postReport = engine.analyze(humanized);
      final preservation = verifier.verify(
        originalText: gpt4oAcademicEssay,
        humanizedText: humanized,
      );

      print('Original AI Probability: ${(engine.analyze(gpt4oAcademicEssay).aiAuthorship.aiProbability).toStringAsFixed(1)}%');
      print('Humanized AI Probability: ${postReport.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('Humanized Human Score: ${postReport.humanScore.toStringAsFixed(1)}%');
      print('Semantic Preservation: ${(preservation.preservationScore * 100).toStringAsFixed(1)}% (${preservation.verdict.name})');
      final origReport = engine.analyze(gpt4oAcademicEssay);
      expect(postReport.aiAuthorship.aiProbability, lessThan(origReport.aiAuthorship.aiProbability));
      expect(preservation.preservationScore, greaterThanOrEqualTo(0.85));
    });

    testWidgets('3. Full UI Component & Responsive Screen Inspection', (WidgetTester tester) async {
      // Test across flagship mobile resolution (1080 x 2400, 400dpi)
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
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
      final studio = StudioProvider(
        storage: storage,
        speech: speech,
        llmSettings: llmSettings,
        history: history,
        toast: toast,
        plagiarism: plagiarism,
      );

      final humanized = humanizer.postProcessWithQualityLoop(gpt4oAcademicEssay);
      final report = engine.analyze(gpt4oAcademicEssay);

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
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ScoreGaugeWidget(
                      score: report.aiAuthorship.aiProbability,
                      label: 'AI AUTHORS',
                      showBadgeInside: true,
                      size: 130,
                      animate: false,
                    ),
                    const SizedBox(height: 12),
                    ConfidenceIntervalBar(
                      score: report.aiAuthorship.aiProbability,
                      confidence: report.confidence,
                    ),
                    const SizedBox(height: 12),
                    const BenchmarkTransparencyCard(),
                    const SizedBox(height: 12),
                    PlagiarismAuditCard(
                      report: report.toLegacyPlagiarismReport(),
                    ),
                    const SizedBox(height: 12),
                    VisualDiffViewer(
                      originalText: gpt4oAcademicEssay,
                      modifiedText: humanized,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // UI Element & Styling Assertions
      expect(find.byType(ScoreGaugeWidget), findsNWidgets(2)); // Primary hero gauge + embedded audit card gauge
      expect(find.byType(ConfidenceIntervalBar), findsOneWidget);
      expect(find.byType(BenchmarkTransparencyCard), findsOneWidget);
      expect(find.byType(PlagiarismAuditCard), findsOneWidget);
      expect(find.byType(VisualDiffViewer), findsOneWidget);

      // Verify specific UI badges and diff inspector
      expect(find.text('REVISION INSPECTOR'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Unchanged'), findsOneWidget);

      print('\n🎨 UI Screen & Widget Tree Inspection: 100% Passed with 0 Layout Overflows!');
    });
  });
}
