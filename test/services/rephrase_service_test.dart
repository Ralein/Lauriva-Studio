import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/rephrase_service.dart';

void main() {
  group('RephraseService Unit Tests', () {
    late RephraseService service;

    setUp(() {
      service = RephraseService();
    });

    test('isSingleWord accurately distinguishes single words from phrases', () {
      expect(service.isSingleWord('delve'), isTrue);
      expect(service.isSingleWord('  crucial  '), isTrue);
      expect(service.isSingleWord('delve deeper'), isFalse);
      expect(service.isSingleWord(''), isFalse);
    });

    test('extractSentenceSpans partitions prose into accurate sentence boundaries', () {
      const text = 'First sentence is here. Second sentence follows! Third one ends?';
      final spans = service.extractSentenceSpans(text);

      expect(spans.length, 3);
      expect(spans[0].text, 'First sentence is here.');
      expect(spans[1].text, 'Second sentence follows!');
      expect(spans[2].text, 'Third one ends?');
      expect(text.substring(spans[0].startIndex, spans[0].endIndex), 'First sentence is here.');
      expect(text.substring(spans[1].startIndex, spans[1].endIndex), 'Second sentence follows!');
    });

    test('findEnclosingSentence identifies the encompassing sentence for a word selection', () {
      const text = 'This is the opening. The crucial finding demonstrates success. Finally, concluding remarks.';
      // "crucial" is located at index 25..32
      final crucialStart = text.indexOf('crucial');
      final crucialEnd = crucialStart + 'crucial'.length;

      final enclosing = service.findEnclosingSentence(text, crucialStart, crucialEnd);
      expect(enclosing.text, 'The crucial finding demonstrates success.');
    });

    test('getRephraseOptions returns lexical synonyms with preserved capitalization', () async {
      final options = await service.getRephraseOptions(
        selectedText: 'Crucial',
        fullText: 'This is Crucial for our success.',
      );

      expect(options.isNotEmpty, isTrue);
      expect(options.any((o) => o.text == 'Essential' || o.text == 'Vital'), isTrue);
    });

    test('getRephraseOptions returns natural humanizing options for AI stock connectors', () async {
      const sentence = 'Furthermore, this study demonstrates strong evidence.';
      final options = await service.getRephraseOptions(
        selectedText: sentence,
        fullText: sentence,
      );

      expect(options.isNotEmpty, isTrue);
      expect(options.any((o) => o.text.startsWith('This study')), isTrue);
    });

    test('applyReplacement safely substitutes text within character range', () {
      const original = 'The results demonstrate high accuracy.';
      final target = 'demonstrate';
      final start = original.indexOf(target);
      final end = start + target.length;

      final updated = service.applyReplacement(
        originalText: original,
        startIndex: start,
        endIndex: end,
        replacement: 'show',
      );

      expect(updated, 'The results show high accuracy.');
    });
  });
}
