/// Audit & reproducibility metadata for dual-stream forensic scans.
class ForensicScanMetadata {
  final String engineVersion;
  final String neuralModelVersion;
  final String calibrationVersion;
  final DateTime timestamp;
  final int wordCount;
  final int sentenceCount;
  final Duration processingTime;

  const ForensicScanMetadata({
    this.engineVersion = '4.0.0',
    this.neuralModelVersion = 'omni_p3_int8',
    this.calibrationVersion = 'calibration_v1',
    required this.timestamp,
    required this.wordCount,
    required this.sentenceCount,
    required this.processingTime,
  });

  Map<String, dynamic> toJson() => {
        'engineVersion': engineVersion,
        'neuralModelVersion': neuralModelVersion,
        'calibrationVersion': calibrationVersion,
        'timestamp': timestamp.toIso8601String(),
        'wordCount': wordCount,
        'sentenceCount': sentenceCount,
        'processingTimeMs': processingTime.inMilliseconds,
      };

  factory ForensicScanMetadata.fromJson(Map<String, dynamic> json) =>
      ForensicScanMetadata(
        engineVersion: json['engineVersion'] as String? ?? '4.0.0',
        neuralModelVersion: json['neuralModelVersion'] as String? ?? 'student_v1',
        calibrationVersion: json['calibrationVersion'] as String? ?? 'calibration_v1',
        timestamp: DateTime.parse(json['timestamp'] as String),
        wordCount: json['wordCount'] as int,
        sentenceCount: json['sentenceCount'] as int,
        processingTime: Duration(
          milliseconds: (json['processingTimeMs'] as num?)?.toInt() ?? 0,
        ),
      );
}
