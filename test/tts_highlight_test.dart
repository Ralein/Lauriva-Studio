import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/tts_highlight.dart';
import 'package:lauriva/providers/speech_provider.dart';
import 'package:lauriva/providers/toast_provider.dart';
import 'package:lauriva/services/storage_service.dart';
import 'package:lauriva/services/tts_service.dart';
import 'package:lauriva/widgets/tts_highlight_text_view.dart';
import 'package:provider/provider.dart';

import 'test_mocks.dart';

void main() {
  setUp(() {
    setupMockPlatformChannels();
  });

  group('TtsWordToken Tokenizer & Char Offset Accuracy', () {
    test('Tokenizes simple sentence with exact character positions', () {
      const text = 'Hello world from Lauriva.';
      final tokens = TtsWordToken.tokenize(text);

      expect(tokens.length, equals(4));

      expect(tokens[0].word, equals('Hello'));
      expect(tokens[0].charStart, equals(0));
      expect(tokens[0].charEnd, equals(5));
      expect(text.substring(tokens[0].charStart, tokens[0].charEnd), equals('Hello'));

      expect(tokens[1].word, equals('world'));
      expect(tokens[1].charStart, equals(6));
      expect(tokens[1].charEnd, equals(11));
      expect(text.substring(tokens[1].charStart, tokens[1].charEnd), equals('world'));

      expect(tokens[2].word, equals('from'));
      expect(tokens[2].charStart, equals(12));
      expect(tokens[2].charEnd, equals(16));
      expect(text.substring(tokens[2].charStart, tokens[2].charEnd), equals('from'));

      // Outer period stripped from token word, character bounds snap to word
      expect(tokens[3].word, equals('Lauriva'));
      expect(tokens[3].charStart, equals(17));
      expect(tokens[3].charEnd, equals(24));
      expect(text.substring(tokens[3].charStart, tokens[3].charEnd), equals('Lauriva'));
    });

    test('Trims outer punctuation, quotes, and brackets without breaking internal apostrophes', () {
      const text = '“Don\'t hesitate,” she whispered (softly)!';
      final tokens = TtsWordToken.tokenize(text);

      expect(tokens.length, equals(5));

      // "Don't" with typographical quote stripped from boundary, internal apostrophe preserved
      expect(tokens[0].word, equals("Don't"));
      expect(text.substring(tokens[0].charStart, tokens[0].charEnd), equals("Don't"));

      // "hesitate" with comma and typographical quote stripped
      expect(tokens[1].word, equals('hesitate'));
      expect(text.substring(tokens[1].charStart, tokens[1].charEnd), equals('hesitate'));

      expect(tokens[2].word, equals('she'));
      expect(tokens[3].word, equals('whispered'));

      // "(softly)!" with parens and exclamation stripped
      expect(tokens[4].word, equals('softly'));
      expect(text.substring(tokens[4].charStart, tokens[4].charEnd), equals('softly'));
    });

    test('Preserves hyphenated compound words', () {
      const text = 'This is a state-of-the-art solution.';
      final tokens = TtsWordToken.tokenize(text);

      final hyphenToken = tokens.firstWhere((t) => t.word == 'state-of-the-art');
      expect(hyphenToken.charStart, equals(10));
      expect(hyphenToken.charEnd, equals(26));
      expect(text.substring(hyphenToken.charStart, hyphenToken.charEnd), equals('state-of-the-art'));
    });

    test('Handles multiple newlines and irregular whitespace with zero index drift', () {
      const text = "Paragraph one.\n\n\n  Paragraph two   with   spaces.\n";
      final tokens = TtsWordToken.tokenize(text);

      for (final t in tokens) {
        expect(text.substring(t.charStart, t.charEnd), equals(t.word));
      }
    });
  });

  group('TtsChunkSpan Exact Substring Slicing', () {
    test('Short documents produce exactly 1 unmodified chunk', () {
      const text = 'A concise sentence under the maximum limit.';
      final chunks = TtsChunkSpan.createChunks(text, maxChunkLength: 1200);

      expect(chunks.length, equals(1));
      expect(chunks[0].text, equals(text));
      expect(chunks[0].charStart, equals(0));
      expect(chunks[0].charEnd, equals(text.length));
    });

    test('Long documents slice strictly on natural boundaries with 100% substring integrity', () {
      final buffer = StringBuffer();
      for (int i = 0; i < 50; i++) {
        buffer.write('Sentence number $i has several descriptive words and clear grammar. ');
      }
      final longText = buffer.toString();
      expect(longText.length, greaterThan(2500));

      final chunks = TtsChunkSpan.createChunks(longText, maxChunkLength: 800);
      expect(chunks.length, greaterThan(1));

      // Crucial invariant: every chunk must be an exact substring of longText at [charStart..charEnd]
      for (final chunk in chunks) {
        expect(longText.substring(chunk.charStart, chunk.charEnd), equals(chunk.text));
      }

      // First chunk starts at 0, last chunk ends at longText.length
      expect(chunks.first.charStart, equals(0));
      expect(chunks.last.charEnd, equals(longText.length));
    });
  });

  group('TtsService Word Highlighting & Lifecycle Integration', () {
    test('speak() initializes tokens and sets initial highlight', () async {
      final ttsService = TtsService();
      await ttsService.init();

      const text = 'Lauriva produces elegant text.';
      await ttsService.speak(text);

      expect(ttsService.state, equals(TtsState.playing));
      expect(ttsService.currentHighlight, isNotNull);
      expect(ttsService.currentHighlight!.word, equals('Lauriva'));
      expect(ttsService.currentHighlight!.wordIndex, equals(0));
      expect(ttsService.currentHighlight!.fullText, equals(text));

      await ttsService.stop();
      expect(ttsService.state, equals(TtsState.idle));
      expect(ttsService.currentHighlight, isNull);
    });

    test('Platform onProgress updates highlightNotifier with exact word match', () async {
      final ttsService = TtsService();
      await ttsService.init();

      const text = 'Neural systems analyze writing accurately.';
      await ttsService.speak(text);

      // Simulate native platform progress event for word "analyze" (offset 15..22)
      // Call flutter_tts channel method call directly to simulate native event
      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channel = const MethodChannel('flutter_tts');

      await binding.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('speak.onProgress', {
            'text': text,
            'start': 15,
            'end': 22,
            'word': 'analyze',
          }),
        ),
        (_) {},
      );

      final highlight = ttsService.currentHighlight;
      expect(highlight, isNotNull);
      expect(highlight!.word, equals('analyze'));
      expect(highlight.charStart, equals(15));
      expect(highlight.charEnd, equals(22));
      expect(text.substring(highlight.charStart, highlight.charEnd), equals('analyze'));

      await ttsService.stop();
    });

    test('Pause retains current highlight and resume preserves state', () async {
      final ttsService = TtsService();
      await ttsService.init();

      const text = 'First word second word.';
      await ttsService.speak(text);

      final beforePause = ttsService.currentHighlight;
      expect(beforePause, isNotNull);

      await ttsService.pause();
      expect(ttsService.state, equals(TtsState.paused));
      // Highlight remains active on paused word
      expect(ttsService.currentHighlight, equals(beforePause));

      await ttsService.resume();
      expect(ttsService.state, equals(TtsState.playing));

      await ttsService.stop();
      expect(ttsService.state, equals(TtsState.idle));
      expect(ttsService.currentHighlight, isNull);
    });

    test('Stop button resets reading to start; pause and play resumes from where it left', () async {
      final ttsService = TtsService();
      await ttsService.init();

      const text = 'Alpha beta gamma delta epsilon zeta.';
      await ttsService.speak(text);

      expect(ttsService.state, equals(TtsState.playing));
      expect(ttsService.currentHighlight!.word, equals('Alpha'));

      // 1. Advance to word "gamma" (char 11..16, token index 2)
      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channel = const MethodChannel('flutter_tts');

      await binding.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('speak.onProgress', {
            'text': text,
            'start': 11,
            'end': 16,
            'word': 'gamma',
          }),
        ),
        (_) {},
      );

      expect(ttsService.currentHighlight!.word, equals('gamma'));
      expect(ttsService.currentHighlight!.charStart, equals(11));

      // 2. Pause speech — position must freeze at "gamma"
      await ttsService.pause();
      expect(ttsService.state, equals(TtsState.paused));
      expect(ttsService.pausedCharOffset, equals(11));
      expect(ttsService.pausedTokenIndex, equals(2));
      expect(ttsService.currentHighlight!.word, equals('gamma'));

      // 3. Play (resume) — speech resumes reading from "gamma delta epsilon zeta."
      await ttsService.resume();
      expect(ttsService.state, equals(TtsState.playing));
      expect(ttsService.currentHighlight!.word, equals('gamma'));
      expect(ttsService.currentHighlight!.charStart, equals(11));

      // 4. Advance to "delta"
      await binding.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('speak.onProgress', {
            'text': 'gamma delta epsilon zeta.',
            'start': 6,
            'end': 11,
            'word': 'delta',
          }),
        ),
        (_) {},
      );

      expect(ttsService.currentHighlight!.word, equals('delta'));
      expect(ttsService.currentHighlight!.charStart, equals(17)); // 11 + 6 = 17 in global document!

      // 5. Stop speech — must reset all position state
      await ttsService.stop();
      expect(ttsService.state, equals(TtsState.idle));
      expect(ttsService.pausedCharOffset, equals(0));
      expect(ttsService.pausedTokenIndex, equals(0));
      expect(ttsService.currentHighlight, isNull);

      // 6. Next Play (speak) — starts reading cleanly from the start (word 0 "Alpha")
      await ttsService.speak(text);
      expect(ttsService.state, equals(TtsState.playing));
      expect(ttsService.currentHighlight!.word, equals('Alpha'));
      expect(ttsService.currentHighlight!.charStart, equals(0));

      await ttsService.stop();
    });
  });

  group('SpeechProvider Isolated ValueNotifier Performance', () {
    test('SpeechProvider exposes highlightNotifier without triggering notifyListeners() on word progress', () async {
      final storage = StorageService();
      final toast = ToastProvider();
      final ttsService = TtsService();
      await ttsService.init();

      final speechProvider = SpeechProvider(
        storage: storage,
        toast: toast,
        ttsService: ttsService,
      );

      await speechProvider.speak('Word one word two word three');

      int providerNotificationCount = 0;
      speechProvider.addListener(() {
        providerNotificationCount++;
      });

      int highlightNotificationCount = 0;
      speechProvider.highlightNotifier.addListener(() {
        highlightNotificationCount++;
      });

      // Simulate native progress event
      final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channel = const MethodChannel('flutter_tts');

      await binding.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('speak.onProgress', {
            'text': 'Word one word two word three',
            'start': 5,
            'end': 8,
            'word': 'one',
          }),
        ),
        (_) {},
      );

      // AGENTS.md rule verification:
      // High-frequency word progress updates MUST fire isolated highlightNotifier
      // without bombarding provider listeners!
      expect(highlightNotificationCount, greaterThan(0));
      expect(providerNotificationCount, equals(0));

      await speechProvider.stop();
      speechProvider.dispose();
    });
  });

  group('TtsHighlightTextView Widget Rendering', () {
    testWidgets('Renders static text when highlight is null', (tester) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final speechProvider = SpeechProvider(storage: storage, toast: toast);

      const displayText = 'Standard readable article.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<SpeechProvider>.value(
              value: speechProvider,
              child: const TtsHighlightTextView(text: displayText),
            ),
          ),
        ),
      );

      expect(find.text(displayText), findsOneWidget);
      speechProvider.dispose();
    });

    testWidgets('Renders highlighted spans when active highlight is present', (tester) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final speechProvider = SpeechProvider(storage: storage, toast: toast);

      const displayText = 'Alpha Beta Gamma';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<SpeechProvider>.value(
              value: speechProvider,
              child: const TtsHighlightTextView(text: displayText),
            ),
          ),
        ),
      );

      // Emit highlight on "Beta" (charStart 6, charEnd 10)
      speechProvider.highlightNotifier.value = const TtsHighlight(
        fullText: displayText,
        charStart: 6,
        charEnd: 10,
        word: 'Beta',
        wordIndex: 1,
        totalWords: 3,
        progress: 0.66,
      );

      await tester.pump();

      // Find SelectableText and inspect its rich TextSpan tree
      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);

      final SelectableText widget = tester.widget(selectableFinder);
      final textSpan = widget.textSpan as TextSpan;

      // Children should be [before: "Alpha ", active: "Beta", after: " Gamma"]
      expect(textSpan.children, isNotNull);
      expect(textSpan.children!.length, greaterThanOrEqualTo(3));

      final activeSpan = textSpan.children![1] as TextSpan;
      expect(activeSpan.text, equals('Beta'));
      expect(activeSpan.style!.fontWeight, equals(FontWeight.w700));
      expect(activeSpan.style!.decoration, equals(TextDecoration.underline));

      speechProvider.dispose();
    });

    testWidgets('Manual selection freezes span mutation and prevents assertion errors', (tester) async {
      final storage = StorageService();
      final toast = ToastProvider();
      final speechProvider = SpeechProvider(storage: storage, toast: toast);

      const displayText = 'The quick brown fox jumps over the lazy dog';
      TextSelection? reportedSelection;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<SpeechProvider>.value(
              value: speechProvider,
              child: TtsHighlightTextView(
                text: displayText,
                onSelectionChanged: (selection, cause) {
                  reportedSelection = selection;
                },
              ),
            ),
          ),
        ),
      );

      // 1. Highlight is active on "quick"
      speechProvider.highlightNotifier.value = const TtsHighlight(
        fullText: displayText,
        charStart: 4,
        charEnd: 9,
        word: 'quick',
        wordIndex: 1,
        totalWords: 9,
        progress: 0.22,
      );
      await tester.pump();

      // 2. User simulates selecting "fox jumps"
      final selectableFinder = find.byType(SelectableText);
      final SelectableText widgetBefore = tester.widget(selectableFinder);
      widgetBefore.onSelectionChanged?.call(
        const TextSelection(baseOffset: 16, extentOffset: 25),
        SelectionChangedCause.drag,
      );
      await tester.pump();

      expect(reportedSelection, isNotNull);
      expect(reportedSelection!.start, equals(16));
      expect(reportedSelection!.end, equals(25));

      // 3. TTS emits next word "brown" while user selection is active.
      // Must not crash and should render stable text without resetting user selection.
      speechProvider.highlightNotifier.value = const TtsHighlight(
        fullText: displayText,
        charStart: 10,
        charEnd: 15,
        word: 'brown',
        wordIndex: 2,
        totalWords: 9,
        progress: 0.33,
      );
      await tester.pump();

      // Still renders SelectableText without throwing
      expect(find.byType(SelectableText), findsOneWidget);

      speechProvider.dispose();
    });
  });
}
