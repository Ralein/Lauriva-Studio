import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/forensic_report.dart';
import 'package:lauriva/models/forensic/ai_authorship_evidence.dart';
import 'package:lauriva/models/forensic/confidence_assessment.dart';

void main() {
  group('ForensicReport safe deserialization & empty fallback', () {
    test('ForensicReport.empty() produces a fully-valid zero-score fallback report', () {
      final report = ForensicReport.empty();

      expect(report.rawText, isEmpty);
      expect(report.normalizedText, isEmpty);
      expect(report.wordCount, equals(0));
      expect(report.charCount, equals(0));
      expect(report.sentenceCount, equals(0));
      expect(report.paragraphCount, equals(0));
      expect(report.spans, isEmpty);
      expect(report.sentences, isEmpty);
      expect(report.summary, contains('Analysis unavailable'));

      // Backward compatibility getters
      expect(report.overallScore, equals(0.0));
      expect(report.humanScore, equals(100.0));
      expect(report.burstinessScore, equals(0.5));
      expect(report.predictabilityScore, equals(0.0));
      expect(report.lexicalRichness, equals(0.0));
      expect(report.flaggedPhrases, isEmpty);

      // Dimension checks
      expect(report.aiAuthorship.aiProbability, equals(0.0));
      expect(report.aiAuthorship.humanProbability, equals(100.0));
      expect(report.aiAuthorship.authorshipClass, equals(AuthorshipClass.inconclusive));
      expect(report.confidence.level, equals(ForensicConfidenceLevel.insufficient));
      expect(report.sourceSimilarity.overallSimilarityScore, equals(0.0));
      expect(report.internalRepetition.repetitionScore, equals(0.0));

      // Legacy report conversion works without throwing
      final legacy = report.toLegacyPlagiarismReport();
      expect(legacy.overallScore, equals(0.0));
      expect(legacy.humanScore, equals(100.0));
    });

    test('ForensicReport.fromJsonSafe returns ForensicReport.empty() on empty/malformed map', () {
      final safe1 = ForensicReport.fromJsonSafe({});
      expect(safe1.wordCount, equals(0));
      expect(safe1.overallScore, equals(0.0));

      final safe2 = ForensicReport.fromJsonSafe({'invalid': 12345});
      expect(safe2.wordCount, equals(0));
      expect(safe2.summary, contains('Analysis unavailable'));
    });

    test('ForensicReport.fromJsonSafe returns ForensicReport.empty() on type cast mismatch', () {
      final corruptedJson = {
        'metadata': 'not a map',
        'rawText': 12345, // should be string
        'wordCount': 'NaN',
      };
      final safe = ForensicReport.fromJsonSafe(corruptedJson);
      expect(safe.wordCount, equals(0));
      expect(safe.overallScore, equals(0.0));
    });

    test('ForensicReport round-trips correctly through toJson and fromJsonSafe', () {
      final original = ForensicReport.empty();
      final json = original.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['wordCount'], equals(0));

      final restored = ForensicReport.fromJsonSafe(json);
      expect(restored.wordCount, equals(original.wordCount));
      expect(restored.summary, equals(original.summary));
      expect(restored.aiAuthorship.aiProbability, equals(original.aiAuthorship.aiProbability));
    });
  });
}
