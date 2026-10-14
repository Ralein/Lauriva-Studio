import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lauriva/services/forensic_database_service.dart';
import 'package:lauriva/models/forensic/forensic_report.dart';
import 'package:lauriva/models/forensic/ai_authorship_evidence.dart';
import 'package:lauriva/models/forensic/confidence_assessment.dart';
import 'package:lauriva/models/forensic/internal_repetition_evidence.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';

void main() {
  group('ForensicDatabaseService & Export Tests', () {
    late ForensicDatabaseService dbService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dbService = ForensicDatabaseService();
    });

    final testReport = ForensicReport(
      metadata: ForensicReportMetadata(
        analysisId: 'scan_001',
        textHash: 'hash_abc',
        analyzedAt: DateTime(2026, 9, 23, 10, 0),
        engineVersion: '3.5.0',
      ),
      rawText: 'In conclusion, artificial intelligence has fundamentally revolutionized modern research paradigms.',
      normalizedText: 'in conclusion artificial intelligence has fundamentally revolutionized modern research paradigms',
      wordCount: 10,
      charCount: 95,
      sentenceCount: 1,
      paragraphCount: 1,
      aiAuthorship: const AiAuthorshipEvidence(
        aiProbability: 88.0,
        humanProbability: 12.0,
        authorshipClass: AuthorshipClass.likelyAi,
        uncertainty: 0.08,
        detectedSignals: [
          AiSignalItem(
            family: 'Formulaic Scaffolding',
            name: 'Discourse Transition',
            score: 0.9,
            weight: 1.0,
            description: 'Starts with high-frequency connective "In conclusion".',
          ),
        ],
        defensibleSummary: 'Passage shows high synthetic probability.',
      ),
      sourceSimilarity: const SourceSimilarityEvidence.clean(),
      internalRepetition: const InternalRepetitionEvidence.clean(),
      confidence: const ConfidenceAssessment(
        level: ForensicConfidenceLevel.high,
        score: 0.92,
        uncertainty: 0.08,
        summary: 'High confidence verdict.',
      ),
      sentences: const [],
      summary: 'Passage flagged for synthetic predictability and formal scaffolding.',
    );

    test('Saves and retrieves forensic scan records', () async {
      final record = await dbService.saveScan(testReport);
      expect(record.id, equals('scan_001'));
      expect(record.aiProbability, equals(88.0));
      expect(record.overallScore, equals(88.0));

      final scans = await dbService.getScans();
      expect(scans.length, equals(1));
      expect(scans.first.id, equals('scan_001'));
      expect(scans.first.wordCount, equals(10));
    });

    test('Deletes individual scan record', () async {
      await dbService.saveScan(testReport);
      expect((await dbService.getScans()).length, equals(1));

      final deleted = await dbService.deleteScan('scan_001');
      expect(deleted, isTrue);
      expect((await dbService.getScans()).isEmpty, isTrue);
    });

    test('Saves and retrieves humanization before/after audit records', () async {
      final humRecord = HumanizationRecord(
        id: 'hum_001',
        scanId: 'scan_001',
        createdAt: DateTime(2026, 9, 23, 10, 5),
        originalText: testReport.rawText,
        humanizedText: 'AI has completely changed how researchers do their work today.',
        aiBefore: 88.0,
        aiAfter: 12.0,
        preservationScore: 97.5,
      );

      await dbService.saveHumanization(humRecord);
      final list = await dbService.getHumanizations();

      expect(list.length, equals(1));
      expect(list.first.id, equals('hum_001'));
      expect(list.first.aiBefore, equals(88.0));
      expect(list.first.aiAfter, equals(12.0));
      expect(list.first.preservationScore, equals(97.5));
    });

    test('Clears all stored audits and scans', () async {
      await dbService.saveScan(testReport);
      await dbService.saveHumanization(HumanizationRecord(
        id: 'hum_test',
        createdAt: DateTime.now(),
        originalText: 'A',
        humanizedText: 'B',
        aiBefore: 50.0,
        aiAfter: 10.0,
        preservationScore: 95.0,
      ));

      expect((await dbService.getScans()).isNotEmpty, isTrue);
      expect((await dbService.getHumanizations()).isNotEmpty, isTrue);

      await dbService.clearAll();

      expect((await dbService.getScans()).isEmpty, isTrue);
      expect((await dbService.getHumanizations()).isEmpty, isTrue);
    });

    test('Exports defensible Markdown audit certificate', () {
      final md = ForensicDatabaseService.exportAsMarkdown(testReport);

      expect(md, contains('# Lauriva Forensic Audit Report'));
      expect(md, contains('`scan_001`'));
      expect(md, contains('88.0%'));
      expect(md, contains('Discourse Transition'));
      expect(md, contains('Lauriva AI Writing Studio'));
    });

    test('Exports standardized JSON report', () {
      final jsonStr = ForensicDatabaseService.exportAsJson(testReport);

      expect(jsonStr, contains('"analysisId": "scan_001"'));
      expect(jsonStr, contains('"aiProbability": 88.0'));
      expect(jsonStr, contains('"likelyAi"'));
    });
  });
}
