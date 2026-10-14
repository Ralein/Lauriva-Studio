import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/neural/pure_dart_tokenizer.dart';
import 'package:lauriva/services/forensic/segmentation/sentence_segmenter.dart';

void main() {
  group('PureDartTokenizer Comprehensive Tests', () {
    late PureDartTokenizer tokenizer;
    final sentenceSegmenter = RuleBasedSentenceSegmenter();

    setUp(() {
      const vocabStr = '''
[PAD]
[UNK]
[CLS]
[SEP]
[MASK]
the
of
and
in
to
a
is
that
for
it
as
was
with
be
by
on
not
he
i
this
are
playing
play
##ing
quick
brown
fox
jumps
over
lazy
dog
delve
crucial
tapestry
transformative
hello
world
''';
      tokenizer = PureDartTokenizer.fromVocabString(vocabStr);
    });

    test('tokenizes empty string gracefully', () {
      final res = tokenizer.tokenize(text: '');
      expect(res.inputIds.first, equals(tokenizer.clsTokenId));
      expect(res.inputIds[1], equals(tokenizer.sepTokenId));
      expect(res.inputIds.length, equals(tokenizer.maxSequenceLength));
      expect(res.attentionMask[0], equals(1));
      expect(res.attentionMask[1], equals(1));
      expect(res.attentionMask[2], equals(0));
    });

    test('tokenizes single word and decomposes subwords', () {
      final res = tokenizer.tokenize(text: 'playing');
      expect(res.inputIds.contains(tokenizer.vocab['playing'] ?? tokenizer.vocab['play']), isTrue);
    });

    test('maps unknown tokens to [UNK]', () {
      final res = tokenizer.tokenize(text: 'xylophone');
      expect(res.inputIds.contains(tokenizer.unkTokenId), isTrue);
    });

    test('handles contractions and punctuation splitting', () {
      final text = "Don't delve into the tapestry!";
      final sents = sentenceSegmenter.segment(text);
      final res = tokenizer.tokenize(text: text, sentences: sents);

      expect(res.inputIds.length, equals(512));
      expect(res.tokenSpans.isNotEmpty, isTrue);
      // All spans should have valid offsets within text range
      for (final span in res.tokenSpans) {
        expect(span.startOffset, greaterThanOrEqualTo(0));
        expect(span.endOffset, lessThanOrEqualTo(text.length));
      }
    });

    test('handles Unicode, Tamil, and Emoji without crashing', () {
      final text = 'வணக்கம்! Modern AI detector is running 🚀 with high accuracy.';
      final sents = sentenceSegmenter.segment(text);
      final res = tokenizer.tokenize(text: text, sentences: sents);

      expect(res.inputIds.first, equals(tokenizer.clsTokenId));
      expect(res.inputIds.length, equals(512));
    });

    test('boundary handling: exactly truncates to maxSequenceLength', () {
      // Generate very long repetitive string exceeding 512 tokens
      final longText = List.generate(300, (i) => 'the quick brown fox jumps over').join(' ');
      final sents = sentenceSegmenter.segment(longText);
      final res = tokenizer.tokenize(text: longText, sentences: sents);

      expect(res.inputIds.length, equals(512));
      expect(res.inputIds.first, equals(tokenizer.clsTokenId));
      expect(res.attentionMask.every((m) => m == 1), isTrue);
    });

    test('preserves sentence indices in TokenSpan', () {
      final text = 'The brown fox jumps. This is crucial for forensic analysis.';
      final sents = sentenceSegmenter.segment(text);
      expect(sents.length, equals(2));

      final res = tokenizer.tokenize(text: text, sentences: sents);
      final sent0Tokens = res.tokenSpans.where((t) => t.sentenceIndex == 0).toList();
      final sent1Tokens = res.tokenSpans.where((t) => t.sentenceIndex == 1).toList();

      expect(sent0Tokens.isNotEmpty, isTrue);
      expect(sent1Tokens.isNotEmpty, isTrue);
    });
  });
}
