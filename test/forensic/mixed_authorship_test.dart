import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';

void main() {
  group('Mixed Authorship & Style Drift Tests', () {
    late ForensicEngine engine;

    setUp(() {
      engine = ForensicEngine();
    });

    test('detects style transitions between human personal prose and formulaic AI paragraphs', () {
      final text = '''
I woke up early this morning and took my dog for a walk around the neighborhood park.
The cool breeze and quiet streets gave me time to think about my upcoming family trip.

Furthermore, it is crucial to delve into the transformative tapestry of modern algorithmic paradigms.
Moreover, comprehensive data infrastructures play a pivotal role in spearheading dynamic digital ecosystems.
Additionally, multifaceted synergies underscore the overarching significance of seamless integration.

After returning home, I made some scrambled eggs and coffee while reading the morning newspaper.
My sister called to ask if we could meet for lunch later this afternoon.
''';

      final report = engine.analyze(text);

      expect(report.wordCount, greaterThan(60));
      // Sentences across the document have differentiated probabilities
      final sentenceProbs = report.sentences.map((s) => s.aiProbability).toList();
      expect(sentenceProbs.isNotEmpty, isTrue);

      final maxProb = sentenceProbs.reduce((a, b) => a > b ? a : b);
      final minProb = sentenceProbs.reduce((a, b) => a < b ? a : b);

      // Variance should capture the stylistic disparity between human and formulaic sections
      expect(maxProb - minProb, greaterThan(15.0));
    });
  });
}
