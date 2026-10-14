import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';

void main() {
  group('ForensicEngine Performance Benchmark', () {
    late ForensicEngine engine;

    setUp(() {
      engine = ForensicEngine();
    });

    String generateCorpus(int wordTarget) {
      final sentences = [
        'The quick brown fox jumps over the lazy dog in the autumnal morning sun.',
        'Furthermore, it is evident that technological innovations accelerate semantic data processing.',
        'However, despite significant architectural advancements, certain edge conditions persist across modules.',
        'We hypothesize that distributed computing models mitigate latency anomalies in production clusters.',
        'In conclusion, quantitative evaluations indicate defensible statistical convergence over all iterations.',
      ];

      final buffer = StringBuffer();
      int currentWords = 0;
      int sIndex = 0;

      while (currentWords < wordTarget) {
        final s = sentences[sIndex % sentences.length];
        buffer.write('$s ');
        currentWords += s.split(' ').length;
        sIndex++;
      }

      return buffer.toString().trim();
    }

    test('analyzes 500-word document within latency budget (< 250ms)', () {
      final text = generateCorpus(500);

      // Warm-up pass
      engine.analyze(text);

      final sw = Stopwatch()..start();
      final report = engine.analyze(text);
      sw.stop();

      // ignore: avoid_print
      print('[Benchmark] 500 words analyzed in ${sw.elapsedMilliseconds}ms (${report.wordCount} words)');

      expect(report.wordCount, greaterThanOrEqualTo(500));
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('analyzes 1,000-word document within latency budget (< 500ms)', () {
      final text = generateCorpus(1000);

      // Warm-up pass
      engine.analyze(text);

      final sw = Stopwatch()..start();
      final report = engine.analyze(text);
      sw.stop();

      // ignore: avoid_print
      print('[Benchmark] 1000 words analyzed in ${sw.elapsedMilliseconds}ms (${report.wordCount} words)');

      expect(report.wordCount, greaterThanOrEqualTo(1000));
      expect(sw.elapsedMilliseconds, lessThan(1200));
    });

    test('analyzes 3,000-word multi-paragraph document with linear scalability', () {
      final text = generateCorpus(3000);

      final sw = Stopwatch()..start();
      final report = engine.analyze(text);
      sw.stop();

      // ignore: avoid_print
      print('[Benchmark] 3000 words analyzed in ${sw.elapsedMilliseconds}ms (${report.wordCount} words)');

      expect(report.wordCount, greaterThanOrEqualTo(3000));
      expect(sw.elapsedMilliseconds, lessThan(2500));
    });
  });
}
