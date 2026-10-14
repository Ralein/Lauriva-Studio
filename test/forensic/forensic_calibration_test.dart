import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_calibration.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';

void main() {
  group('ForensicCalibrationConfig', () {
    test('defaults() initializes standard peer-reviewed values', () {
      final config = ForensicCalibrationConfig.defaults();

      expect(config.aiCleanThreshold, equals(18.0));
      expect(config.aiLowThreshold, equals(38.0));
      expect(config.aiModerateThreshold, equals(65.0));
      expect(config.aiHighThreshold, equals(85.0));

      expect(config.domainMultipliers['academic'], equals(0.85));
      expect(config.domainMultipliers['technical'], equals(0.90));
      expect(config.domainMultipliers['legal'], equals(0.88));
      expect(config.domainMultipliers['instructional'], equals(0.80));

      expect(config.signalWeights['perplexity'], equals(1.0));
      expect(config.signalWeights['burstiness'], equals(0.9));
      expect(config.signalWeights['structural'], equals(1.1));
      expect(config.signalWeights['homoglyph'], equals(2.0));
    });

    test('fromJson accurately deserializes custom thresholds and signal weights', () {
      final json = {
        'aiProbabilityThresholds': {
          'clean': 15.0,
          'low': 35.0,
          'moderate': 60.0,
          'high': 80.0,
        },
        'domainCalibration': {
          'academic': 0.80,
          'technical': 0.85,
        },
        'signalWeights': {
          'perplexity': 1.5,
          'burstiness': 1.2,
        },
      };

      final config = ForensicCalibrationConfig.fromJson(json);

      expect(config.aiCleanThreshold, equals(15.0));
      expect(config.aiLowThreshold, equals(35.0));
      expect(config.aiModerateThreshold, equals(60.0));
      expect(config.aiHighThreshold, equals(80.0));
      expect(config.domainMultipliers['academic'], equals(0.80));
      expect(config.signalWeights['perplexity'], equals(1.5));
    });

    test('fromString safely parses JSON string and roundtrips through toJson', () {
      const jsonStr = '''
      {
        "aiProbabilityThresholds": {
          "clean": 20.0,
          "low": 40.0,
          "moderate": 70.0,
          "high": 90.0
        },
        "domainCalibration": {
          "academic": 0.82
        },
        "signalWeights": {
          "structural": 1.3
        }
      }
      ''';

      final config = ForensicCalibrationConfig.fromString(jsonStr);
      expect(config.aiCleanThreshold, equals(20.0));
      expect(config.aiHighThreshold, equals(90.0));

      final jsonMap = config.toJson();
      expect(jsonMap['aiProbabilityThresholds']['clean'], equals(20.0));
    });

    test('malformed JSON safely falls back to defaults without throwing', () {
      final config = ForensicCalibrationConfig.fromString('not a valid json string');
      expect(config.aiCleanThreshold, equals(18.0));
      expect(config.aiModerateThreshold, equals(65.0));

      final configFromBadMap = ForensicCalibrationConfig.fromJson({
        'aiProbabilityThresholds': 'corrupted value',
      });
      expect(configFromBadMap.aiCleanThreshold, equals(18.0));
    });

    test('ForensicEngine accepts custom calibration and exposes it via getter', () {
      const customConfig = ForensicCalibrationConfig(
        aiCleanThreshold: 22.0,
        aiLowThreshold: 44.0,
        aiModerateThreshold: 72.0,
        aiHighThreshold: 88.0,
      );

      final engine = ForensicEngine(calibration: customConfig);
      expect(engine.calibration.aiCleanThreshold, equals(22.0));
      expect(engine.calibration.aiModerateThreshold, equals(72.0));
    });
  });
}
