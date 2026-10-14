import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/watermark/watermark_detector_service.dart';

void main() {
  group('WatermarkDetectorService Tests', () {
    late WatermarkDetectorService detector;

    setUp(() {
      detector = WatermarkDetectorService();
    });

    test('Short text under 20 tokens returns clean result without throwing', () {
      final result = detector.analyze('Hello world this is too short.');

      expect(result.tokenCount, lessThan(20));
      expect(result.kirchenbauerZScore, equals(0.0));
      expect(result.watermarkProbability, equals(0.0));
      expect(result.detectedType, equals(WatermarkType.none));
      expect(result.isWatermarked, isFalse);
    });

    test('Natural human prose yields safe low watermark probability', () {
      const naturalProse = '''
        The morning sunlight streamed through the tall library windows, casting long rectangular 
        shadows across the weathered oak floorboards. A quiet hush settled over the room as readers 
        turned fragile paper pages with deliberate care. Outside, the autumn wind rustled red maples 
        along the quiet brick promenade, while bicycles rolled gently past the stone fountain.
        Each morning brought this same gentle cadence of tea, study, and quiet contemplation.
      ''';

      final result = detector.analyze(naturalProse);

      expect(result.tokenCount, greaterThan(20));
      expect(result.kirchenbauerZScore, lessThan(4.0));
      expect(result.isWatermarked, isFalse);
      expect(result.interpretation, isNotEmpty);
    });

    test('Result getters correctly evaluate threshold bounds', () {
      const suspiciousResult = WatermarkResult(
        kirchenbauerZScore: 4.8,
        watermarkProbability: 0.92,
        detectedType: WatermarkType.kirchenbauer,
        tokenCount: 65,
        greenListCount: 38,
        interpretation: 'Statistically elevated green-list token partition detected.',
      );

      expect(suspiciousResult.isSuspicious, isTrue);
      expect(suspiciousResult.isWatermarked, isTrue);
      expect(suspiciousResult.detectedType, equals(WatermarkType.kirchenbauer));
    });
  });
}
