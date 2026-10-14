import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/confidence_assessment.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';

void main() {
  group('ForensicEngine End-to-End Tests', () {
    late ForensicEngine engine;

    setUp(() {
      engine = ForensicEngine();
    });

    test('Analyzes short text and correctly assigns insufficient confidence level', () {
      const shortText = 'The quick brown fox jumps over the lazy dog.';
      final report = engine.analyze(shortText);

      expect(report.wordCount, 9);
      expect(report.confidence.level, ForensicConfidenceLevel.insufficient);
      expect(report.aiAuthorship.aiProbability, greaterThanOrEqualTo(0.0));
      expect(report.sourceSimilarity.overallSimilarityScore, greaterThanOrEqualTo(0.0));
      expect(report.sentences.length, 1);
    });

    test('Analyzes multi-paragraph human-like text and produces comprehensive evidence', () {
      const humanText = '''
I woke up early yesterday and decided to take a long walk along the canal. The water was still,
reflecting the pale morning light, and a few ducks paddled quietly near the reeds. It wasn't
particularly warm, but the fresh air cleared my head after a hectic week at work.

Later in the afternoon, my sister stopped by with some homemade apple pie. We sat on the balcony,
sipping black coffee and talking about our plans for the upcoming summer holidays. It's funny how
simple moments like that can feel so restorative.
''';

      final report = engine.analyze(humanText);

      expect(report.wordCount, greaterThan(80));
      expect(report.sentenceCount, greaterThan(3));
      expect(report.paragraphCount, 2);
      expect(report.confidence.level, isNot(ForensicConfidenceLevel.insufficient));
      expect(report.aiAuthorship.humanProbability, greaterThan(40.0));
      expect(report.toLegacyPlagiarismReport().sentences.isNotEmpty, isTrue);
    });

    test('Detects repetitive n-grams and flags internal repetition independently of source plagiarism', () {
      const repetitiveText = '''
In today's digital era, the system plays a crucial role in operational efficiency across the organization.
Furthermore, the platform plays a crucial role in operational efficiency across the team.
Moreover, the software plays a crucial role in operational efficiency across the enterprise.
''';

      final report = engine.analyze(repetitiveText);

      expect(report.internalRepetition.repeatedNgrams.isNotEmpty, isTrue);
      expect(report.internalRepetition.flaggedBoilerplates.isNotEmpty, isTrue);
      expect(report.internalRepetition.repetitionScore, greaterThan(0.0));
    });
  });
}
