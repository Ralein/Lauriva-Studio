import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/ai_authorship_evidence.dart';
import 'package:lauriva/models/forensic/confidence_assessment.dart';
import 'package:lauriva/models/forensic/forensic_report.dart';
import 'package:lauriva/models/forensic/internal_repetition_evidence.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/models/plagiarism_report.dart';

void main() {
  group('Forensic Domain Models & Legacy Bridge Tests', () {
    test('ForensicReport seamlessly maps to legacy PlagiarismReport', () {
      final report = ForensicReport(
        metadata: ForensicReportMetadata(
          analysisId: 'test_123',
          textHash: 'abc',
          analyzedAt: DateTime.now(),
        ),
        rawText: 'This is a test document.',
        normalizedText: 'This is a test document.',
        wordCount: 5,
        charCount: 24,
        sentenceCount: 1,
        paragraphCount: 1,
        aiAuthorship: const AiAuthorshipEvidence(
          aiProbability: 80.0,
          humanProbability: 20.0,
          authorshipClass: AuthorshipClass.likelyAi,
          uncertainty: 0.15,
          detectedSignals: [
            AiSignalItem(
              family: 'Syntax',
              name: 'Uniform Cadence',
              score: 0.85,
              weight: 1.0,
              description: 'Uniform sentence length distribution.',
            ),
          ],
          defensibleSummary: 'High AI probability detected.',
        ),
        sourceSimilarity: const SourceSimilarityEvidence.clean(),
        internalRepetition: const InternalRepetitionEvidence.clean(),
        confidence: const ConfidenceAssessment(
          level: ForensicConfidenceLevel.insufficient,
          score: 0.3,
          uncertainty: 0.7,
          summary: 'SHORT PASSAGE',
        ),
        sentences: const [
          SentenceAudit(
            index: 0,
            text: 'This is a test document.',
            aiProbability: 80.0,
            riskLevel: PlagiarismRiskLevel.high,
            detectedTells: ['Uniform Cadence'],
            wordCount: 5,
          ),
        ],
        summary: 'Executive forensic summary.',
      );

      // Verify master dimensions
      expect(report.aiAuthorship.aiProbability, 80.0);
      expect(report.aiAuthorship.authorshipClass, AuthorshipClass.likelyAi);
      expect(report.sourceSimilarity.overallSimilarityScore, 0.0);
      expect(report.confidence.level, ForensicConfidenceLevel.insufficient);

      // Verify backward-compatibility bridge
      final legacy = report.toLegacyPlagiarismReport();
      expect(legacy.overallScore, closeTo(80.0, 0.1));
      expect(legacy.humanScore, closeTo(20.0, 0.1));
      expect(legacy.confidenceLevel, 'insufficient');
      expect(legacy.sentences.length, 1);
      expect(legacy.sentences.first.detectedTells, contains('Uniform Cadence'));
    });

    test('ForensicReport serialization preserves all fields', () {
      final report = ForensicReport(
        metadata: ForensicReportMetadata(
          analysisId: 'test_id',
          textHash: 'hash_val',
          analyzedAt: DateTime(2026, 9, 22),
        ),
        rawText: 'Sample text.',
        normalizedText: 'Sample text.',
        wordCount: 2,
        charCount: 12,
        sentenceCount: 1,
        paragraphCount: 1,
        aiAuthorship: const AiAuthorshipEvidence(
          aiProbability: 10.0,
          humanProbability: 90.0,
          authorshipClass: AuthorshipClass.likelyHuman,
          uncertainty: 0.1,
          detectedSignals: [],
          defensibleSummary: 'Human written.',
        ),
        sourceSimilarity: const SourceSimilarityEvidence.clean(),
        internalRepetition: const InternalRepetitionEvidence.clean(),
        confidence: const ConfidenceAssessment(
          level: ForensicConfidenceLevel.high,
          score: 0.95,
          uncertainty: 0.05,
          summary: 'HIGH CERTAINTY',
        ),
        summary: 'Summary text.',
      );

      final json = report.toJson();
      expect(json['metadata']['analysisId'], 'test_id');
      expect(json['wordCount'], 2);
      expect(json['aiAuthorship']['authorshipClass'], 'likelyHuman');
      expect(json['confidence']['level'], 'high');
    });
  });
}
