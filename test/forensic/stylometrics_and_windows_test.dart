import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/style_fingerprint.dart';
import 'package:lauriva/services/forensic/ai/sliding_window_analyzer.dart';
import 'package:lauriva/services/forensic/ai/stylometric_feature_extractor.dart';
import 'package:lauriva/services/forensic/document/document_segmenter.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/normalization/text_normalizer.dart';

void main() {
  group('StylometricFeatureExtractor Tests', () {
    late TextNormalizer normalizer;
    late DocumentSegmenter segmenter;
    late StylometricFeatureExtractor extractor;

    setUp(() {
      normalizer = TextNormalizer();
      segmenter = DocumentSegmenter();
      extractor = StylometricFeatureExtractor();
    });

    test('Extracts complete hierarchical feature families (A, B, C, D)', () {
      const text = '''
Moreover, the architecture plays a crucial role in modern systems.
I walked into the laboratory early in the morning, noting that the experiments were not only successful, but also transformative.
Nevertheless, could we perhaps improve the overall throughput?
''';

      final norm = normalizer.normalize(text);
      final doc = segmenter.segment(norm);
      final res = extractor.extract(doc);

      // Family A: Surface
      expect(res.surfaceMetrics['sentenceCount'], 3.0);
      expect(res.surfaceMetrics['meanSentenceLength']!, greaterThan(5.0));
      expect(res.fingerprint.burstiness, greaterThanOrEqualTo(0.0));

      // Family B: Punctuation
      expect(res.punctuationMetrics['commaRate']!, greaterThan(0.0));
      expect(res.punctuationMetrics['questionRate']!, greaterThan(0.0));
      expect(res.punctuationMetrics['punctuationEntropy']!, greaterThan(0.0));

      // Family C: Lexical
      expect(res.lexicalMetrics['typeTokenRatio']!, greaterThan(0.0));
      expect(res.lexicalMetrics['guiraudR']!, greaterThan(0.0));
      expect(res.lexicalMetrics['firstPersonRatio']!, greaterThan(0.0)); // 'I'
      expect(res.lexicalMetrics['hedgingDensity']!, greaterThan(0.0)); // 'perhaps'
      expect(res.lexicalMetrics['modalDensity']!, greaterThan(0.0)); // 'could'

      // Family D: Structural & Templates
      expect(res.structuralMetrics['transitionOpenerRate']!, greaterThan(0.0)); // 'Moreover', 'Nevertheless'
      expect(res.sentenceTemplates.length, 3);
      expect(res.sentenceTemplates.first.contains('TRANS'), isTrue);
    });

    test('StyleFingerprint distance reflects stylistic divergence', () {
      final fp1 = StyleFingerprint.empty();
      final fp2 = const StyleFingerprint(
        meanSentenceLength: 30.0,
        sentenceLengthStdDev: 12.0,
        sentenceLengthSkew: 0.5,
        meanParagraphLength: 100.0,
        burstiness: 0.8,
        commaRate: 6.0,
        semicolonRate: 1.0,
        colonRate: 0.5,
        emDashRate: 2.0,
        questionRate: 1.0,
        punctuationEntropy: 1.8,
        typeTokenRatio: 0.65,
        guiraudR: 8.5,
        hapaxRatio: 0.5,
        functionWordRatio: 0.45,
        contractionDensity: 2.0,
        transitionOpenerRate: 10.0,
        conjunctionDensity: 8.0,
        structuralTemplateEntropy: 2.5,
      );

      final distance = fp1.distanceTo(fp2);
      expect(distance, greaterThan(0.40));
    });
  });

  group('SlidingWindowAnalyzer & Mixed-Origin Detection Tests', () {
    late TextNormalizer normalizer;
    late DocumentSegmenter segmenter;
    late SlidingWindowAnalyzer windowAnalyzer;
    late ForensicEngine engine;

    setUp(() {
      normalizer = TextNormalizer();
      segmenter = DocumentSegmenter();
      windowAnalyzer = SlidingWindowAnalyzer(windowSizeWords: 50, stepSizeWords: 25);
      engine = ForensicEngine();
    });

    test('Short documents are evaluated in single window without crashing', () {
      const shortText = 'This is a brief note. It has two sentences.';
      final norm = normalizer.normalize(shortText);
      final doc = segmenter.segment(norm);
      final res = windowAnalyzer.analyze(doc);

      expect(res.windows.length, 1);
      expect(res.isMixedOrEdited, isFalse);
    });

    test('Detects mixed/hybrid writing with human preamble followed by AI boilerplate', () {
      // Preamble: distinct personal human voice
      const humanPreamble = '''
I woke up at five in the morning to rain tapping against the tin roof of the shed.
My hands were freezing, and I couldn't find my flashlight anywhere in the dark.
I stumbled outside, cursing under my breath, and grabbed the rusty garden spade from the porch.
''';

      // Body: distinct AI formulaic boilerplate
      const aiBody = '''
It is not only about operational efficiency, but also about strategic transformation.
At its core, this stands as a testament to the evolving landscape of enterprise technology.
Let us dive in to explore the multifaceted intricacies and pivotal paradigms.
Furthermore, the platform fosters seamless synergy, showcasing innovative excellence across all verticals.
As an AI language model, I hope this helps!
''';

      final combinedText = '$humanPreamble\n$aiBody';
      final report = engine.analyze(combinedText);

      expect(report.aiAuthorship.windows.isNotEmpty, isTrue);
      // Window scores should reflect the contrast
      expect(report.spans.any((s) => s.id.startsWith('window_span_') || s.type.name == 'aiPattern'), isTrue);
      expect(report.aiAuthorship.detectedSignals.isNotEmpty, isTrue);
    });
  });
}
