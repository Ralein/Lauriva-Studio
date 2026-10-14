// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/ai_forensic_service.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/humanizer/lauvira_humanize_service.dart';

void main() {
  group('Human Engine < 10% AI Score Threshold Tests', () {
    final forensic = AiForensicService();
    final coordinator = ForensicCoordinatorService();
    final lauviraService = LauviraHumanizeService();

    test('Passage with ~60-99% AI score is humanized below 10% threshold', () async {
      const syntheticInput =
          'Furthermore, the implementation of renewable energy plays a crucial role in combating climate change. '
          'By harnessing solar and wind power, communities can delve into sustainable practices that bolster economic resilience. '
          'In conclusion, it is important to note that these initiatives not only reduce emissions, but also pave the way for a brighter future.';

      // 1. Initial AI Score is high (> 60%)
      final beforeAudit = forensic.auditText(syntheticInput);
      final beforeCoord = await coordinator.coordinate(text: syntheticInput, enableOnlineSearch: false);
      expect(beforeAudit.aiProbability, greaterThanOrEqualTo(60.0), reason: 'Input should have >= 60% AI likelihood');
      expect(beforeCoord.overallScore, greaterThanOrEqualTo(50.0), reason: 'Coordinator initial score should be high');

      // 2. Run humanization pipeline
      final humanized = await lauviraService.humanizeLlmOutput(
        syntheticInput,
        originalText: syntheticInput,
      );

      // 3. Post-humanization score verification
      final afterAudit = forensic.auditText(humanized);
      final afterCoord = await coordinator.coordinate(text: humanized, enableOnlineSearch: false);

      print('Input AI probability: ${beforeAudit.aiProbability.toStringAsFixed(1)}%');
      print('Humanized AI probability (stylometric): ${afterAudit.aiProbability.toStringAsFixed(1)}%');
      print('Humanized AI probability (coordinator): ${afterCoord.overallScore.toStringAsFixed(1)}%');
      print('Humanized text: $humanized');

      // 4. Verify output strictly meets the < 10% threshold requirement
      expect(afterAudit.aiProbability, lessThan(10.0), reason: 'Stylometric AI score must be humanized below 10%');
      expect(afterCoord.overallScore, lessThan(10.0), reason: 'Overall Forensic Coordinator AI score must be humanized below 10%');
      expect(afterAudit.authorshipClass, equals(AiAuthorshipClass.likelyHuman));
    });

    test('Corporate AI announcement with multiple tells drops below 10% threshold', () async {
      const corporateAiText =
          'Artificial intelligence has revolutionized modern industries by streamlining complex operational workflows. '
          'Organizations leverage cutting-edge machine learning models to optimize data analysis and enhance decision-making capabilities. '
          'Moreover, adopting automated solutions fosters collaborative environments that elevate organizational productivity.';

      final beforeAudit = forensic.auditText(corporateAiText);
      expect(beforeAudit.aiProbability, greaterThanOrEqualTo(60.0));

      final humanized = await lauviraService.humanizeLlmOutput(
        corporateAiText,
        originalText: corporateAiText,
      );

      final afterAudit = forensic.auditText(humanized);
      final afterCoord = await coordinator.coordinate(text: humanized, enableOnlineSearch: false);

      print('Corporate Input AI score: ${beforeAudit.aiProbability.toStringAsFixed(1)}%');
      print('Corporate Humanized text: "$humanized"');
      print('Corporate Humanized score (stylometric): ${afterAudit.aiProbability.toStringAsFixed(1)}%');
      print('Corporate Humanized score (coordinator): ${afterCoord.overallScore.toStringAsFixed(1)}%');
      print('Corporate detected signals: ${afterAudit.detectedSignals.map((s) => s.name).toList()}');
      final f = forensic.extractFeatureVectorV2(humanized);
      print('Corporate features: words=${f[1]}, burstiness=${f[6]}, stock=${f[25]}, transitions=${f[26]}, triads=${f[28]}, contrast=${f[29]}');

      expect(afterAudit.aiProbability, lessThan(10.0), reason: 'Must drop below 10%');
      expect(afterCoord.overallScore, lessThan(10.0), reason: 'Must drop below 10%');
    });
  });
}
