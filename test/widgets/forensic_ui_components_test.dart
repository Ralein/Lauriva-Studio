import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/confidence_assessment.dart';
import 'package:lauriva/widgets/score_gauge_widget.dart';
import 'package:lauriva/widgets/confidence_interval_bar.dart';
import 'package:lauriva/widgets/benchmark_transparency_card.dart';
import 'package:lauriva/widgets/fix_and_verify_card.dart';

void main() {
  group('Forensic UI SSS-Tier Components Tests', () {
    testWidgets('ScoreGaugeWidget displays score and risk badge without animation errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScoreGaugeWidget(
                score: 85.0,
                label: 'High Risk',
                showBadgeInside: true,
                size: 100,
                animate: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('85'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      expect(find.text('HIGH RISK'), findsOneWidget);
    });

    testWidgets('ScoreGaugeWidget displays score and % alone by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScoreGaugeWidget(
                score: 92.0,
                label: 'High Risk',
                size: 100,
                animate: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('92'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      expect(find.text('HIGH RISK'), findsNothing);
    });

    testWidgets('ConfidenceIntervalBar renders confidence limits and handles narrow screen', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConfidenceIntervalBar(
              score: 72.0,
              confidence: ConfidenceAssessment(
                level: ForensicConfidenceLevel.high,
                score: 0.88,
                uncertainty: 0.12,
                summary: 'High stability',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Statistical Confidence Band'), findsOneWidget);
      expect(find.textContaining('±12%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BenchmarkTransparencyCard renders peer-reviewed stats and expands on tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BenchmarkTransparencyCard(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Engine Accuracy & Validation'), findsOneWidget);
      expect(find.text('96.2%'), findsOneWidget);
      expect(find.text('97.1%'), findsOneWidget);
      expect(find.text('91.4%'), findsOneWidget);

      // Initially collapsed
      expect(find.text('Validation Methodology'), findsNothing);

      // Tap header to expand
      await tester.tap(find.text('Engine Accuracy & Validation'));
      await tester.pumpAndSettle();

      expect(find.text('Validation Methodology'), findsOneWidget);
      expect(find.textContaining('Platt scaling', findRichText: true), findsOneWidget);
    });

    testWidgets('FixAndVerifyCard displays score drop and triggers reverify callback', (tester) async {
      bool reverified = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FixAndVerifyCard(
                scoreBefore: 85.0,
                scoreAfter: 12.0,
                labelBefore: 'LIKELY AI',
                labelAfter: 'LIKELY HUMAN',
                preservationScore: 98.2,
                humanizedText: 'Authentic human revision text here.',
                onReverify: () {
                  reverified = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Humanizer Delta & Verification'), findsOneWidget);
      expect(find.text('-73 pts'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.textContaining('98% Semantic & Citation Fidelity Preserved'), findsOneWidget);
      expect(find.text('Copy Output'), findsOneWidget);
      expect(find.text('Re-Verify'), findsOneWidget);

      // Tap reverify button
      await tester.tap(find.text('Re-Verify'));
      await tester.pump();

      expect(reverified, isTrue);
    });
  });
}
