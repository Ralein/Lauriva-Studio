import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/segmentation/document_segmenter.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';

void main() {
  group('Segmentation Tests', () {
    late RuleBasedSentenceSegmenter sentenceSegmenter;
    late TokenAwareDocumentSegmenter docSegmenter;

    setUp(() {
      sentenceSegmenter = RuleBasedSentenceSegmenter();
      docSegmenter = TokenAwareDocumentSegmenter(
        targetTokenCount: 50,
        overlapTokenCount: 10,
      );
    });

    test('SentenceSegmenter extracts exact character boundaries and skips abbreviations', () {
      final text = 'Dr. Smith presented the thesis. Furthermore, it proved groundbreaking.';
      final boundaries = sentenceSegmenter.segment(text);

      expect(boundaries.length, equals(2));
      expect(boundaries[0].text, equals('Dr. Smith presented the thesis.'));
      expect(boundaries[1].text, equals('Furthermore, it proved groundbreaking.'));

      // Verify exact character slices match
      for (final b in boundaries) {
        expect(text.substring(b.start, b.end), equals(b.text));
      }
    });

    test('TokenAwareDocumentSegmenter partitions long texts into overlapping windows', () {
      final sentences = List.generate(
        15,
        (i) => 'Sentence number $i provides substantive linguistic material for analysis.',
      );
      final fullText = sentences.join(' ');

      final windows = docSegmenter.segment(fullText);
      expect(windows.length, greaterThan(1));

      // Each window has valid sentence indices and valid character offsets
      for (final w in windows) {
        expect(w.sentenceIndices.isNotEmpty, isTrue);
        expect(w.startOffset, greaterThanOrEqualTo(0));
        expect(w.endOffset, lessThanOrEqualTo(fullText.length));
        expect(w.text, equals(fullText.substring(w.startOffset, w.endOffset)));
      }
    });

    test('TokenAwareDocumentSegmenter returns single window for short text', () {
      final text = 'This is a brief five word sentence.';
      final windows = docSegmenter.segment(text);

      expect(windows.length, equals(1));
      expect(windows.first.text, equals(text));
    });
  });
}
