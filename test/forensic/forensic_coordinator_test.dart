import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';

void main() {
  group('ForensicCoordinatorService', () {
    late ForensicCoordinatorService coordinator;

    setUp(() {
      coordinator = ForensicCoordinatorService();
    });

    test('empty string returns emptyReport immediately without error', () async {
      final report = await coordinator.coordinate(text: '');
      expect(report.wordCount, equals(0));
      expect(report.rawText, isEmpty);
      expect(report.overallScore, equals(0.0));
    });

    test('whitespace-only string returns emptyReport immediately without error', () async {
      final report = await coordinator.coordinate(text: '   \n\t   ');
      expect(report.wordCount, equals(0));
      expect(report.rawText, isEmpty);
      expect(report.overallScore, equals(0.0));
    });

    test('short text (<1200 characters) executes synchronous analysis path', () async {
      const sampleText = 'This is a normal short paragraph written by a human researcher for verification.';
      expect(sampleText.length, lessThan(1200));

      final report = await coordinator.coordinate(text: sampleText);
      expect(report.wordCount, greaterThan(0));
      expect(report.rawText, equals(sampleText));
    });

    test('ForensicScanMode enum defines all scan modes with badges and labels', () {
      expect(ForensicScanMode.values.length, equals(3));

      for (final mode in ForensicScanMode.values) {
        expect(mode.label.isNotEmpty, isTrue);
        expect(mode.badge.isNotEmpty, isTrue);
        expect(mode.description.isNotEmpty, isTrue);
      }
    });
  });
}
