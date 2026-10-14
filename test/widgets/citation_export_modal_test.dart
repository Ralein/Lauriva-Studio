import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/widgets/citation_export_modal.dart';

void main() {
  group('CitationExportModal Widget Tests', () {
    const mockMatches = [
      SourceMatchSegment(
        documentStartOffset: 0,
        documentEndOffset: 50,
        matchedText: 'Artificial intelligence enhances pedagogical methods in higher education.',
        sourceTitle: 'Smith, J. (2023). Advances in Machine Learning Pedagogy. Nature Education.',
        sourceUrl: 'https://nature.com/articles/edu123',
        tokenCount: 10,
        similarityPercent: 88.0,
        matchType: SourceMatchType.exact,
        citationStatus: CitationStatus.uncited,
      ),
      SourceMatchSegment(
        documentStartOffset: 60,
        documentEndOffset: 120,
        matchedText: 'Neural classifiers achieve robust accuracy on benchmark evaluations.',
        sourceTitle: 'Vaswani et al. (2017). Attention Is All You Need. NeurIPS.',
        sourceUrl: 'https://arxiv.org/abs/1706.03762',
        tokenCount: 9,
        similarityPercent: 92.0,
        matchType: SourceMatchType.fuzzyParaphrase,
        citationStatus: CitationStatus.cited,
      ),
    ];

    Widget buildTestModal({int initialIndex = 0}) {
      final toast = ToastProvider();
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ToastProvider>.value(value: toast),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CitationExportModal(
              matches: mockMatches,
              initialIndex: initialIndex,
            ),
          ),
        ),
      );
    }

    testWidgets('Renders citation generator with all style chips and action buttons', (tester) async {
      await tester.pumpWidget(buildTestModal());

      // Header checks
      expect(find.text('ACADEMIC CITATION GENERATOR'), findsOneWidget);
      expect(find.text('Source Citation'), findsOneWidget);

      // Style chips
      expect(find.text('APA 7th'), findsOneWidget);
      expect(find.text('MLA 9th'), findsOneWidget);
      expect(find.text('Chicago 17th'), findsOneWidget);
      expect(find.text('IEEE'), findsOneWidget);
      expect(find.text('Harvard'), findsOneWidget);

      // Action buttons
      expect(find.text('Copy Citation'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('Tapping style chips updates active citation formatting', (tester) async {
      await tester.pumpWidget(buildTestModal());

      // Tap MLA 9th
      await tester.tap(find.text('MLA 9th'));
      await tester.pumpAndSettle();

      // Tap IEEE
      await tester.tap(find.text('IEEE'));
      await tester.pumpAndSettle();

      expect(find.text('Copy Citation'), findsOneWidget);
    });

    testWidgets('Switching to All Bibliography mode formats full bibliography', (tester) async {
      await tester.pumpWidget(buildTestModal());

      expect(find.text('All Bibliography (2)'), findsOneWidget);
      await tester.tap(find.text('All Bibliography (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Full Bibliography'), findsOneWidget);
      expect(find.text('Copy Bibliography'), findsOneWidget);
    });

    testWidgets('Accommodates phone system UI navigation bar insets without clipping action buttons', (tester) async {
      final toast = ToastProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ToastProvider>.value(value: toast),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                viewPadding: EdgeInsets.only(bottom: 48.0),
                padding: EdgeInsets.only(bottom: 48.0),
              ),
              child: const Scaffold(
                body: CitationExportModal(
                  matches: mockMatches,
                  initialIndex: 0,
                ),
              ),
            ),
          ),
        ),
      );

      // Verify that the action buttons are present and interactive
      expect(find.text('Copy Citation'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);

      final containerFinder = find.byType(Container).first;
      final container = tester.widget<Container>(containerFinder);
      final padding = container.padding as EdgeInsets;
      // Bottom padding should include the 48.0 phone UI navigation bar + base margin (20.0)
      expect(padding.bottom, greaterThanOrEqualTo(68.0));
    });

    testWidgets('CitationExportModal.show displays bottom sheet and closes cleanly', (tester) async {
      final toast = ToastProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ToastProvider>.value(value: toast),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    CitationExportModal.show(context, matches: mockMatches);
                  },
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('ACADEMIC CITATION GENERATOR'), findsOneWidget);
      expect(find.text('Copy Citation'), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      expect(find.text('ACADEMIC CITATION GENERATOR'), findsNothing);
    });
  });
}
