import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/widgets/studio/visual_diff_viewer.dart';

void main() {
  group('VisualDiffViewer Widget Tests', () {
    testWidgets('Renders revision inspector with stat badges and diff chunks', (tester) async {
      const originalText = 'Furthermore, it is crucial to analyze this.';
      const modifiedText = 'In practice, we examine this.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VisualDiffViewer(
              originalText: originalText,
              modifiedText: modifiedText,
            ),
          ),
        ),
      );

      // Verify header and badge presence
      expect(find.text('REVISION INSPECTOR'), findsOneWidget);
      expect(find.byType(VisualDiffViewer), findsOneWidget);

      // Verify legend presence
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Unchanged'), findsOneWidget);
    });

    testWidgets('Shows "No changes" when texts are identical', (tester) async {
      const identicalText = 'This is an identical piece of text.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VisualDiffViewer(
              originalText: identicalText,
              modifiedText: identicalText,
            ),
          ),
        ),
      );

      expect(find.text('REVISION INSPECTOR'), findsOneWidget);
      expect(find.text('No changes'), findsOneWidget);
    });
  });
}
