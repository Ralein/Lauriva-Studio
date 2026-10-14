import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_calibration.dart';
import 'package:lauriva/services/forensic/fusion/probability_calibrator.dart';

void main() {
  group('ProbabilityCalibrator Tests', () {
    test('standard calibration preserves midpoint 0.5 when b=0', () {
      const calibrator = ProbabilityCalibrator(a: 1.0, b: 0.0);
      expect(calibrator.calibrate(0.5), closeTo(0.5, 0.001));
    });

    test('calibrator is strictly monotonic', () {
      const calibrator = ProbabilityCalibrator(a: 1.15, b: -0.05);
      final p1 = calibrator.calibrate(0.2);
      final p2 = calibrator.calibrate(0.4);
      final p3 = calibrator.calibrate(0.6);
      final p4 = calibrator.calibrate(0.8);

      expect(p1, lessThan(p2));
      expect(p2, lessThan(p3));
      expect(p3, lessThan(p4));
    });

    test('handles extreme probability bounds safely', () {
      const calibrator = ProbabilityCalibrator(a: 1.2, b: -0.1);
      expect(calibrator.calibrate(0.0), closeTo(0.0, 0.01));
      expect(calibrator.calibrate(1.0), closeTo(1.0, 0.01));
    });
  });

  group('Shipped calibration asset', () {
    test('assets/forensic_calibration.json matches the in-code defaults', () {
      final fromAsset = ForensicCalibrationConfig.fromString(
        File('assets/forensic_calibration.json').readAsStringSync(),
      );
      final inCode = ForensicCalibrationConfig.calibrated();
      expect(fromAsset.plattCalibrator.a, closeTo(inCode.plattCalibrator.a, 1e-9));
      expect(fromAsset.plattCalibrator.b, closeTo(inCode.plattCalibrator.b, 1e-9));
      expect(fromAsset.plattCalibrator.version, equals(inCode.plattCalibrator.version));
    });

    test('stylometric-only scores never become confident without corroboration', () {
      final c = ForensicCalibrationConfig.defaultPlatt;
      // A weak (AUC ~0.64) stream must stay in a bounded band at moderate raw scores.
      expect(c.calibrate(0.30), inInclusiveRange(0.45, 0.60));
      expect(c.calibrate(0.62), lessThan(0.65));
    });
  });
}
