import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/document/document_segmenter.dart';
import 'package:lauriva/services/forensic/normalization/text_normalizer.dart';

void main() {
  group('TextNormalizer & PositionMapper Tests', () {
    late TextNormalizer normalizer;

    setUp(() {
      normalizer = TextNormalizer();
    });

    test('Strips invisible zero-width characters while maintaining position mapping', () {
      // String containing zero-width space (\u200B) and zero-width joiner (\u200D)
      const raw = 'Laur\u200Biva is an ad\u200Dvanced writing assistant.';
      final result = normalizer.normalize(raw);

      expect(result.normalizedText, 'Lauriva is an advanced writing assistant.');
      expect(result.metadata.invisibleCharactersRemoved, 2);

      // Verify that "advanced" maps back to correct raw offsets
      final normStart = result.normalizedText.indexOf('advanced');
      final normEnd = normStart + 'advanced'.length;

      final (rawStart, rawEnd) = result.mapper.mapSpan(normStart, normEnd);
      expect(raw.substring(rawStart, rawEnd), 'ad\u200Dvanced');
    });

    test('Standardizes smart quotes and whitespace correctly', () {
      const raw = '“Smart quotes” and ‘single quotes’ with   excessive   spaces.';
      final result = normalizer.normalize(raw);

      expect(result.normalizedText, '"Smart quotes" and \'single quotes\' with excessive spaces.');
      expect(result.metadata.smartQuotesStandardized, 4);
      expect(result.metadata.whitespaceSequencesCollapsed, greaterThan(0));

      // Test position mapping
      final normStart = result.normalizedText.indexOf('"Smart quotes"');
      final normEnd = normStart + '"Smart quotes"'.length;
      final (rawStart, rawEnd) = result.mapper.mapSpan(normStart, normEnd);
      expect(raw.substring(rawStart, rawEnd), '“Smart quotes”');
    });

    test('Normalizes CRLF and preserves paragraph structure', () {
      const raw = "Paragraph one.\r\n\r\nParagraph two with details.";
      final result = normalizer.normalize(raw);

      expect(result.normalizedText.contains('\r'), isFalse);
      expect(result.normalizedText, "Paragraph one.\n\nParagraph two with details.");
    });
  });

  group('DocumentSegmenter Tests', () {
    late TextNormalizer normalizer;
    late DocumentSegmenter segmenter;

    setUp(() {
      normalizer = TextNormalizer();
      segmenter = DocumentSegmenter();
    });

    test('Does not split on common abbreviations like Dr., e.g., and U.S.', () {
      const raw = 'Dr. Smith visited the U.S. embassy, e.g., in Washington. He held meetings.';
      final normDoc = normalizer.normalize(raw);
      final segDoc = segmenter.segment(normDoc);

      expect(segDoc.sentences.length, 2);
      expect(segDoc.sentences[0].text, 'Dr. Smith visited the U.S. embassy, e.g., in Washington.');
      expect(segDoc.sentences[1].text, 'He held meetings.');

      // Check raw offset mapping of second sentence
      final s2 = segDoc.sentences[1];
      expect(raw.substring(s2.rawStartOffset, s2.rawEndOffset), 'He held meetings.');
    });

    test('Correctly identifies multiple paragraphs and sentence boundaries', () {
      const raw = '''Artificial intelligence is progressing rapidly. Models generate human-like prose.

However, forensic verification requires careful statistical analysis. We must evaluate entropy.''';

      final normDoc = normalizer.normalize(raw);
      final segDoc = segmenter.segment(normDoc);

      expect(segDoc.paragraphs.length, 2);
      expect(segDoc.sentences.length, 4);
      expect(segDoc.paragraphs[0].sentenceCount, 2);
      expect(segDoc.paragraphs[1].sentenceCount, 2);
      expect(segDoc.totalWordCount, greaterThan(15));
    });

    test('Handles empty and whitespace-only text gracefully', () {
      final normDoc = normalizer.normalize('   ');
      final segDoc = segmenter.segment(normDoc);

      expect(segDoc.sentences.isEmpty, isTrue);
      expect(segDoc.paragraphs.isEmpty, isTrue);
      expect(segDoc.totalWordCount, 0);
    });
  });
}
