import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/ai_forensic_service.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';

void main() {
  group('Enhanced Humanizer Training & Meaning Guard Tests', () {
    const humanizer = AlgorithmicHumanizerService();
    final verifier = SemanticPreservationVerifier();
    final forensicService = AiForensicService();

    test('detoxifies expanded 2026 AI tropes (spearhead, myriad, bolster, pave the way)', () {
      const syntheticPassage =
          'The committee is spearheading an initiative with a myriad of stakeholders to bolster economic resilience, paving the way for a transformative catalyst in the healthcare realm.';
      final cleaned = humanizer.replaceAiStockPhrases(syntheticPassage);

      expect(cleaned.contains('spearheading'), isFalse);
      expect(cleaned.contains('myriad of'), isFalse);
      expect(cleaned.contains('bolster'), isFalse);
      expect(cleaned.contains('paving the way for'), isFalse);
      expect(cleaned.contains('transformative'), isFalse);
      expect(cleaned.contains('in the realm of'), isFalse);

      expect(cleaned.contains('leading'), isTrue);
      expect(cleaned.contains('many'), isTrue);
      expect(cleaned.contains('strengthen'), isTrue);
      expect(cleaned.contains('leading to'), isTrue);
    });

    test('applies casual tone profile contractions cleanly', () {
      const formalText = 'We do not believe that it is ready, and they will not agree because we cannot verify the data.';
      final casualResult = humanizer.postProcess(formalText, tone: WritingToneProfile.casual);

      expect(casualResult.contains("don't"), isTrue);
      expect(casualResult.contains("it's"), isTrue);
      expect(casualResult.contains("won't"), isTrue);
      expect(casualResult.contains("can't"), isTrue);
    });

    test('applies direct tone profile to prune padding adverbs', () {
      const wordyText = 'The team essentially completed the task in order to literally prevent any delay.';
      final directResult = humanizer.postProcess(wordyText, tone: WritingToneProfile.direct);

      expect(directResult.contains('essentially'), isFalse);
      expect(directResult.contains('literally'), isFalse);
      expect(directResult.contains('in order to'), isFalse);
      expect(directResult.contains('to prevent'), isTrue);
    });

    test('end-to-end humanizer drops synthetic draft to human range with 100% meaning preservation', () {
      const complexAiDraft =
          'Furthermore, in 2025 ACME Technologies achieved a 24% reduction in carbon emissions across 4 European production facilities (Vaswani et al., 2017). By spearheading renewable power adoption, the enterprise stands as a testament to environmental stewardship and bolsters sustainable operations.';

      final humanized = humanizer.postProcess(complexAiDraft, tone: WritingToneProfile.professional);

      // Verify AI stock vocabulary purged
      expect(humanized.contains('Furthermore,'), isFalse);
      expect(humanized.contains('spearheading'), isFalse);
      expect(humanized.contains('stands as a testament to'), isFalse);
      expect(humanized.contains('bolsters'), isFalse);

      // Verify forensic audit classification
      final beforeAudit = forensicService.auditText(complexAiDraft);
      final afterAudit = forensicService.auditText(humanized);
      expect(beforeAudit.aiProbability, greaterThan(50.0));
      expect(afterAudit.aiProbability, lessThan(beforeAudit.aiProbability));

      // Verify Meaning Guard: facts, numbers, and citations strictly intact
      final report = verifier.verify(
        originalText: complexAiDraft,
        humanizedText: humanized,
        aiProbabilityBefore: beforeAudit.aiProbability / 100.0,
        aiProbabilityAfter: afterAudit.aiProbability / 100.0,
      );

      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
      expect(report.preservedNumbers, containsAll(['2025', '24%', '4']));
      expect(report.missingNumbers, isEmpty);
      expect(report.hasNumericalDrift, isFalse);
      expect(report.preservedCitations, contains('(Vaswani et al., 2017)'));
      expect(report.hasCitationLoss, isFalse);
    });
  });
}
