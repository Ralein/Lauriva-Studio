import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lauriva/providers/history_provider.dart';
import 'package:lauriva/providers/llm_settings_provider.dart';
import 'package:lauriva/providers/plagiarism_provider.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/studio_provider.dart';
import 'package:lauriva/providers/theme_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/widgets/humanizer/comparison_view.dart';
import 'package:lauriva/widgets/rephrase_selection_sheet.dart';
import 'package:lauriva/widgets/zone3_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late ToastProvider toast;
  late HistoryProvider history;
  late PlagiarismProvider plagiarism;
  late SpeechProvider speech;
  late LlmSettingsProvider llmSettings;
  late ThemeProvider theme;
  late StudioProvider studio;

  setUp(() async {
    storage = StorageService();
    await storage.init();
    toast = ToastProvider();
    history = HistoryProvider(storage: storage, toast: toast);
    plagiarism = PlagiarismProvider(storage: storage, toast: toast, history: history);
    speech = SpeechProvider(storage: storage, toast: toast);
    llmSettings = LlmSettingsProvider(storage: storage);
    theme = ThemeProvider(storage: storage);
    studio = StudioProvider(
      storage: storage,
      speech: speech,
      llmSettings: llmSettings,
      history: history,
      toast: toast,
      plagiarism: plagiarism,
    );
  });

  Widget createTestWidget(Widget child) {
    return MultiProvider(
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
        home: Scaffold(body: child),
      ),
    );
  }

  group('RephraseSelectionSheet Widget Tests', () {
    testWidgets('Renders selected target text and suggested alternatives', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const fullText = 'The results demonstrate high accuracy and consistency.';
      const selected = 'demonstrate';

      await tester.pumpWidget(
        createTestWidget(
          const RephraseSelectionSheet(
            initialSelectedText: selected,
            fullText: fullText,
            initialStartIndex: 12,
            initialEndIndex: 23,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title and target
      expect(find.text('Rephrase Selection'), findsOneWidget);
      expect(find.text('demonstrate'), findsWidgets);
      expect(find.text('SUGGESTED REPHRASINGS'), findsOneWidget);

      // Verify lexical suggestions for "demonstrate"
      expect(find.text('show'), findsWidgets);

      // Verify replace action button
      expect(find.text('Replace in Output'), findsOneWidget);
    });

    testWidgets('Tapping Replace in Output triggers custom apply callback', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const fullText = 'This is crucial for the team.';
      String? appliedReplacement;
      int? appliedStart;
      int? appliedEnd;

      await tester.pumpWidget(
        createTestWidget(
          RephraseSelectionSheet(
            initialSelectedText: 'crucial',
            fullText: fullText,
            initialStartIndex: 8,
            initialEndIndex: 15,
            onCustomApply: (rep, s, e) {
              appliedReplacement = rep;
              appliedStart = s;
              appliedEnd = e;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on replacement option "essential"
      final essentialFinder = find.text('essential');
      expect(essentialFinder, findsWidgets);
      await tester.tap(essentialFinder.first);
      await tester.pumpAndSettle();

      // Tap Replace in Output
      await tester.tap(find.text('Replace in Output'));
      await tester.pumpAndSettle();

      expect(appliedReplacement, 'essential');
      expect(appliedStart, 8);
      expect(appliedEnd, 15);
    });
  });

  group('Studio & Humanizer Output Rephrase Integration Tests', () {
    testWidgets('Zone3Output provides Rephrase Selection action button when text exists', (tester) async {
      studio.setOutputText('This is generated text by Lauriva Studio.');

      await tester.pumpWidget(
        createTestWidget(
          const SingleChildScrollView(child: Zone3Output()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Rephrase Selection'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('ComparisonView provides Humanize Selection action button when output exists', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestWidget(
          SingleChildScrollView(
            child: ComparisonView(
              inputText: 'Original input text here',
              outputText: 'Humanized output text here',
              isLoading: false,
              outputReport: null,
              inputReport: null,
              semanticPreservationScore: 0.95,
              onReverify: () {},
              onUseAsInput: () {},
              onShowToast: (msg, type) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Humanize Selection'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });
  });
}
