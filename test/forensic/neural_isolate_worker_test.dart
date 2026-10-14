import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/forensic_scan_mode.dart';
import 'package:lauriva/services/forensic/ai/neural/neural_isolate_worker.dart';

void main() {
  group('NeuralIsolateWorker Tests', () {
    test('serializes and deserializes IsolateForensicJobRequest correctly', () {
      const request = IsolateForensicJobRequest(
        text: 'Sample text to analyze via background isolate worker.',
        scanMode: ForensicScanMode.fullForensic,
        sensitivity: ForensicSensitivity.strict,
        enableWatermark: true,
        enableHomoglyph: true,
        modelVersion: 'omni_p3_int8',
      );

      final jsonStr = jsonEncode(request.toJson());
      final decoded = IsolateForensicJobRequest.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      expect(decoded.text, equals(request.text));
      expect(decoded.scanMode, equals(ForensicScanMode.fullForensic));
      expect(decoded.sensitivity, equals(ForensicSensitivity.strict));
      expect(decoded.enableWatermark, isTrue);
      expect(decoded.modelVersion, equals('omni_p3_int8'));
    });
  });
}
