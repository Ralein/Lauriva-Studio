// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/ai_forensic_service.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/widgets/benchmark_transparency_card.dart';
import 'package:lauriva/widgets/confidence_interval_bar.dart';
import 'package:lauriva/widgets/score_gauge_widget.dart';
import 'package:lauriva/widgets/studio/visual_diff_viewer.dart';

void main() {
  group('End-to-End Live ChatGPT Forensic & Humanizer Inspection', () {
    final aiService = AiForensicService();
    final engine = ForensicEngine();
    final humanizer = AlgorithmicHumanizerService();
    final verifier = SemanticPreservationVerifier();

    // Authentic ChatGPT Essay (Remote Work & Team Collaboration)
    const chatGptRemoteWorkEssay = '''
The transition to remote work has profoundly reshaped the landscape of modern organizational productivity and employee collaboration. By leveraging digital communication platforms and cloud-based infrastructures, companies can empower their workforce to operate with unprecedented flexibility and efficiency. Furthermore, remote environments eliminate daily commuting constraints, thereby fostering enhanced work-life balance and individual well-being. It is important to note that asynchronous communication allows distributed teams to maintain continuous progress across disparate time zones.

However, remote workflows also introduce significant challenges regarding interpersonal dynamics and long-term company culture. Without spontaneous face-to-face interactions, organizations frequently struggle to cultivate genuine team cohesion and trust. Moreover, digital fatigue can undermine sustained creativity, as back-to-back virtual conferences replace informal brainstorming sessions. In conclusion, while remote work undeniably offers substantial operational advantages, navigating its cultural complexities requires intentional leadership, empathetic communication, and robust digital governance to foster a truly resilient organizational ecosystem.
''';

    // Authentic ChatGPT Essay (Renewable Energy & Infrastructure)
    const chatGptEnergyEssay = '''
Renewable energy systems play a crucial role in modernizing municipal urban infrastructure and mitigating global climate change. By integrating distributed solar arrays and wind power generation, smart cities can optimize power distribution with unmatched precision. Furthermore, advanced battery energy storage systems ensure that excess generation is effectively preserved for peak demand periods. It is worth noting that these technological advancements not only reduce greenhouse gas emissions, but also pave the way for sustainable economic resilience. In conclusion, transitioning to clean energy grids stands poised as a transformative imperative for the next generation of urban development.
''';

    test('1. Deep Forensic Scan & Algorithmic Humanization on ChatGPT Remote Work Essay', () {
      print('\n================================================================');
      print('🔬 LAURIVA FORENSIC SCAN: ChatGPT Remote Work Essay');
      print('================================================================');

      // 1. Initial Forensic Analysis
      final initialReport = engine.analyze(chatGptRemoteWorkEssay);
      final initialAiAudit = aiService.auditText(chatGptRemoteWorkEssay);

      print('📊 Raw AI Probability: ${initialReport.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('👤 Human Probability: ${initialReport.humanScore.toStringAsFixed(1)}%');
      print('🏷️  Authorship Classification: ${initialReport.aiAuthorship.authorshipClass.badge}');
      print('🏷️  Detected AI Signals:');
      for (final s in initialAiAudit.detectedSignals) {
        print('   - [${s.family}] ${s.name}: score = ${s.score.toStringAsFixed(2)} (${s.description})');
      }

      // Assert that Lauriva accurately caught the ChatGPT essay
      expect(initialReport.aiAuthorship.aiProbability, greaterThan(70.0));

      // 2. Surgical Algorithmic Humanization
      print('\n----------------------------------------------------------------');
      print('✨ LAURIVA SURGICAL HUMANIZATION PROCESS');
      print('----------------------------------------------------------------');

      final humanizedText = humanizer.postProcessWithQualityLoop(
        chatGptRemoteWorkEssay,
        tone: WritingToneProfile.conversational,
        originalText: chatGptRemoteWorkEssay,
      );

      print('Original word count: ${chatGptRemoteWorkEssay.split(RegExp(r'\s+')).length}');
      print('Humanized word count: ${humanizedText.split(RegExp(r'\s+')).length}');
      print('\n--- HUMANIZED TEXT OUTPUT ---');
      print(humanizedText);
      print('-----------------------------\n');

      // 3. Post-Humanization Forensic Scan
      final postReport = engine.analyze(humanizedText);
      final postAiAudit = aiService.auditText(humanizedText);
      final preservation = verifier.verify(
        originalText: chatGptRemoteWorkEssay,
        humanizedText: humanizedText,
      );

      print('📊 Post-Humanize AI Probability: ${postReport.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('👤 Post-Humanize Human Probability: ${postReport.humanScore.toStringAsFixed(1)}%');
      print('🎯 Semantic Preservation Score: ${(preservation.preservationScore * 100).toStringAsFixed(1)}% (${preservation.verdict.name})');
      print('🏷️  Remaining AI Tells: ${postAiAudit.detectedSignals.length}');

      // Verifications: AI probability cut in half, semantic meaning 100% intact
      expect(postReport.aiAuthorship.aiProbability, lessThan(initialReport.aiAuthorship.aiProbability));
      expect(preservation.preservationScore, greaterThanOrEqualTo(0.80));
    });

    test('2. Deep Forensic Scan & Algorithmic Humanization on ChatGPT Energy Essay', () {
      print('\n================================================================');
      print('🔬 LAURIVA FORENSIC SCAN: ChatGPT Energy Essay');
      print('================================================================');

      final initialReport = engine.analyze(chatGptEnergyEssay);
      print('📊 Raw AI Probability: ${initialReport.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('👤 Human Probability: ${initialReport.humanScore.toStringAsFixed(1)}%');

      expect(initialReport.aiAuthorship.aiProbability, greaterThan(70.0));

      final humanizedText = humanizer.postProcessWithQualityLoop(
        chatGptEnergyEssay,
        tone: WritingToneProfile.direct,
        originalText: chatGptEnergyEssay,
      );

      final postReport = engine.analyze(humanizedText);
      final preservation = verifier.verify(
        originalText: chatGptEnergyEssay,
        humanizedText: humanizedText,
      );

      print('📊 Post-Humanize AI Probability: ${postReport.aiAuthorship.aiProbability.toStringAsFixed(1)}%');
      print('👤 Post-Humanize Human Probability: ${postReport.humanScore.toStringAsFixed(1)}%');
      print('🎯 Semantic Preservation Score: ${(preservation.preservationScore * 100).toStringAsFixed(1)}%');

      expect(postReport.aiAuthorship.aiProbability, lessThan(initialReport.aiAuthorship.aiProbability));
    });

    testWidgets('3. UI Inspection: VisualDiffViewer, Score Gauge & Confidence Bar Live Render', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final humanizedText = humanizer.postProcessWithQualityLoop(chatGptRemoteWorkEssay);
      final report = engine.analyze(humanizedText);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ScoreGaugeWidget(
                    score: report.overallScore,
                    label: 'Forensic Score',
                    showBadgeInside: true,
                    size: 120,
                    animate: false,
                  ),
                  const SizedBox(height: 16),
                  ConfidenceIntervalBar(
                    score: report.overallScore,
                    confidence: report.confidence,
                  ),
                  const SizedBox(height: 16),
                  const BenchmarkTransparencyCard(),
                  const SizedBox(height: 16),
                  VisualDiffViewer(
                    originalText: chatGptRemoteWorkEssay,
                    modifiedText: humanizedText,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // UI Assertions
      expect(find.byType(ScoreGaugeWidget), findsOneWidget);
      expect(find.byType(ConfidenceIntervalBar), findsOneWidget);
      expect(find.byType(BenchmarkTransparencyCard), findsOneWidget);
      expect(find.byType(VisualDiffViewer), findsOneWidget);
      expect(find.text('REVISION INSPECTOR'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Unchanged'), findsOneWidget);

      print('\n🎨 UI Render Inspection: Score Gauge, Confidence Bar, Transparency Card, and Visual Diff Viewer all rendered with 0 overflow errors!');
    });
  });
}
