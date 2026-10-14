import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/explainer/score_explainer.dart';
import 'package:lauriva/models/forensic/forensic_report.dart';
import 'package:lauriva/models/forensic/ai_authorship_evidence.dart';
import 'package:lauriva/models/forensic/confidence_assessment.dart';
import 'package:lauriva/models/forensic/internal_repetition_evidence.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/models/plagiarism_report.dart';

void main() {
  const explainer = ScoreExplainer();

  group('ScoreExplainer Unit Tests', () {
    test('Identifies short passage as primary uncertainty reason', () {
      final report = ForensicReport(
        metadata: ForensicReportMetadata(
          analysisId: 'test_short',
          textHash: 'hash1',
          analyzedAt: DateTime.now(),
        ),
        rawText: 'Short sentence here.',
        normalizedText: 'short sentence here.',
        wordCount: 3,
        charCount: 20,
        sentenceCount: 1,
        paragraphCount: 1,
        aiAuthorship: const AiAuthorshipEvidence(
          aiProbability: 50.0,
          humanProbability: 50.0,
          authorshipClass: AuthorshipClass.inconclusive,
          uncertainty: 0.45,
          detectedSignals: [],
          defensibleSummary: 'Short text',
        ),
        sourceSimilarity: const SourceSimilarityEvidence.clean(),
        internalRepetition: const InternalRepetitionEvidence.clean(),
        confidence: const ConfidenceAssessment(
          level: ForensicConfidenceLevel.insufficient,
          score: 0.4,
          uncertainty: 0.45,
          summary: 'Sample is short',
        ),
        sentences: const [
          SentenceAudit(
            index: 0,
            text: 'Short sentence here.',
            aiProbability: 50.0,
            riskLevel: PlagiarismRiskLevel.moderate,
            detectedTells: [],
            wordCount: 3,
          ),
        ],
        summary: 'Short sample summary.',
      );

      final reason = explainer.primaryReason(report);
      expect(reason, contains('too short'));
      expect(reason, contains('3 words'));
    });

    test('Identifies external literature overlap as primary reason when similarity is high', () {
      final report = ForensicReport(
        metadata: ForensicReportMetadata(
          analysisId: 'test_match',
          textHash: 'hash2',
          analyzedAt: DateTime.now(),
        ),
        rawText: 'This is a text passage copied directly from Wikipedia machine learning entry.',
        normalizedText: 'this is a text passage copied directly from wikipedia machine learning entry.',
        wordCount: 45,
        charCount: 250,
        sentenceCount: 2,
        paragraphCount: 1,
        aiAuthorship: const AiAuthorshipEvidence(
          aiProbability: 80.0,
          humanProbability: 20.0,
          authorshipClass: AuthorshipClass.likelyAi,
          uncertainty: 0.1,
          detectedSignals: [],
          defensibleSummary: 'AI and external match',
        ),
        sourceSimilarity: const SourceSimilarityEvidence(
          overallSimilarityScore: 65.0,
          documentCoveragePercent: 65.0,
          matchedTokenCount: 30,
          longestContiguousTokenMatch: 20,
          uniqueSourceCount: 1,
          matches: [
            SourceMatchSegment(
              documentStartOffset: 0,
              documentEndOffset: 50,
              matchedText: 'text passage copied directly from Wikipedia machine learning entry',
              sourceTitle: 'Wikipedia: Machine Learning',
              sourceUrl: 'https://en.wikipedia.org/wiki/Machine_learning',
              tokenCount: 10,
              similarityPercent: 65.0,
              matchType: SourceMatchType.exact,
            ),
          ],
          defensibleSummary: 'Matched Wikipedia',
        ),
        internalRepetition: const InternalRepetitionEvidence.clean(),
        confidence: const ConfidenceAssessment(
          level: ForensicConfidenceLevel.high,
          score: 0.9,
          uncertainty: 0.1,
          summary: 'High confidence',
        ),
        sentences: const [],
        summary: 'External literature overlap summary.',
      );

      final reason = explainer.primaryReason(report);
      expect(reason, contains('Substantial text overlap'));
      expect(reason, contains('Wikipedia: Machine Learning'));
    });

    test('Generates sentence-level diagnostics for AI stock markers and discourse transitions', () {
      const audit = SentenceAudit(
        index: 0,
        text: 'Furthermore, it is worth noting that this study plays a crucial role in modern science.',
        wordCount: 15,
        aiProbability: 88.0,
        riskLevel: PlagiarismRiskLevel.high,
        detectedTells: [],
      );

      final explanation = explainer.explainSentence(audit, averageDocWords: 15);
      expect(explanation.any((s) => s.toLowerCase().contains('furthermore')), isTrue);
      expect(explanation.any((s) => s.contains('it is worth noting')), isTrue);
      expect(explanation.any((s) => s.contains('uniform pacing')), isTrue);
    });
  });
}
