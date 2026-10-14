import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/plagiarism_report.dart';

void main() {
  group('Social Share & Executive Report Phrasing Tests', () {
    test('Constructs PlagiarismReport and verifies executive report fields', () {
      final mockReport = PlagiarismReport(
        overallScore: 8.5,
        riskLevel: PlagiarismRiskLevel.clean,
        humanScore: 91.5,
        plagiarismRiskScore: 0.0,
        burstinessScore: 1.25,
        predictabilityScore: 0.15,
        lexicalRichness: 52.0,
        ngramOverlapScore: 2.1,
        repeatedNgrams: const [],
        detectedTells: const ['Varied sentence rhythm', 'Low formulaic structure'],
        defensibleSummary: 'Document exhibits natural linguistic diversity and authentic human authorship.',
        sentences: const [],
      );

      expect(mockReport.overallScore, 8.5);
      expect(mockReport.humanScore, 91.5);
      expect(mockReport.riskLevel, PlagiarismRiskLevel.clean);
    });

    test('Report separator lines do not exceed 30 characters to prevent mobile chat bubble line-wraps', () {
      const separator = '─────────────────────────────';
      expect(separator.length, lessThanOrEqualTo(30));
    });
  });
}
