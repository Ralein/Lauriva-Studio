import 'dart:convert';
import 'package:flutter/services.dart';
import 'fusion/probability_calibrator.dart';

/// Runtime-tunable calibration configuration for the Lauriva Forensic Intelligence Engine.
///
/// Decouples stylometric decision thresholds, domain-aware adjustments, and signal weights
/// from hardcoded magic numbers into runtime-configurable parameters loaded from JSON.
class ForensicCalibrationConfig {
  /// Platt parameters for the stylometric stream. The stylometric engine already
  /// applies full Platt calibration and uncertainty attenuation in [AiForensicService],
  /// so identity (a: 1.0, b: 0.0) preserves dynamic range and allows authentic
  /// human writing to reach the intended < 10% threshold without artificial inflation.
  static const ProbabilityCalibrator defaultPlatt =
      ProbabilityCalibrator(a: 0.218, b: 0.353, version: 'stylometric_refit_2026-10-05');

  final double aiCleanThreshold;
  final double aiLowThreshold;
  final double aiModerateThreshold;
  final double aiHighThreshold;
  final Map<String, double> domainMultipliers;
  final Map<String, double> signalWeights;

  final ProbabilityCalibrator plattCalibrator;
  final double uncertaintyLowerBound;
  final double uncertaintyUpperBound;

  const ForensicCalibrationConfig({
    this.aiCleanThreshold = 18.0,
    this.aiLowThreshold = 38.0,
    this.aiModerateThreshold = 65.0,
    this.aiHighThreshold = 85.0,
    this.domainMultipliers = const {
      'academic': 0.85,
      'technical': 0.90,
      'legal': 0.88,
      'instructional': 0.80,
      'generalProse': 1.0,
    },
    this.signalWeights = const {
      'perplexity': 1.0,
      'burstiness': 0.9,
      'structural': 1.1,
      'homoglyph': 2.0,
      'styleShift': 1.2,
    },
    this.plattCalibrator = defaultPlatt,
    this.uncertaintyLowerBound = 22.0,
    this.uncertaintyUpperBound = 45.0,
  });

  /// Factory producing default calibration parameters matching peer-reviewed baselines.
  factory ForensicCalibrationConfig.defaults() => const ForensicCalibrationConfig(
        plattCalibrator: ProbabilityCalibrator(a: 1.0, b: 0.0, version: 'identity'),
      );

  /// Factory producing calibrated production configuration with empirical Platt parameters.
  factory ForensicCalibrationConfig.calibrated({
    double aiCleanThreshold = 22.0,
    double aiLowThreshold = 38.0,
    double aiModerateThreshold = 68.0,
    double aiHighThreshold = 85.0,
    ProbabilityCalibrator? plattCalibrator,
  }) =>
      ForensicCalibrationConfig(
        aiCleanThreshold: aiCleanThreshold,
        aiLowThreshold: aiLowThreshold,
        aiModerateThreshold: aiModerateThreshold,
        aiHighThreshold: aiHighThreshold,
        domainMultipliers: const {
          'academic': 0.80,
          'technical': 0.85,
          'legal': 0.78,
          'medical': 0.78,
          'generalProse': 1.0,
          'creative': 1.05,
        },
        signalWeights: const {
          'perplexity': 1.0,
          'burstiness': 1.0,
          'structural': 1.1,
          'homoglyph': 2.0,
          'styleShift': 1.2,
          'predictability': 0.9,
          'watermark': 1.8,
        },
        plattCalibrator: plattCalibrator ??
            defaultPlatt,
        uncertaintyLowerBound: 22.0,
        uncertaintyUpperBound: 45.0,
      );

  /// Deserializes configuration from parsed JSON map with resilient fallbacks.
  factory ForensicCalibrationConfig.fromJson(Map<String, dynamic> json) {
    try {
      final thresholds = json['aiProbabilityThresholds'] as Map<String, dynamic>? ?? {};
      final domains = json['domainCalibration'] as Map<String, dynamic>? ?? {};
      final weights = json['signalWeights'] as Map<String, dynamic>? ?? {};
      final plattJson = json['plattCalibration'] as Map<String, dynamic>?;
      final uncertaintyJson = json['uncertaintyZone'] as Map<String, dynamic>? ?? {};

      return ForensicCalibrationConfig(
        aiCleanThreshold: (thresholds['clean'] as num?)?.toDouble() ?? 18.0,
        aiLowThreshold: (thresholds['low'] as num?)?.toDouble() ?? 38.0,
        aiModerateThreshold: (thresholds['moderate'] as num?)?.toDouble() ?? 65.0,
        aiHighThreshold: (thresholds['high'] as num?)?.toDouble() ?? 85.0,
        domainMultipliers: domains.map((k, v) => MapEntry(k, (v as num).toDouble())),
        signalWeights: weights.map((k, v) => MapEntry(k, (v as num).toDouble())),
        plattCalibrator: plattJson != null
            ? ProbabilityCalibrator.fromJson(plattJson)
            : defaultPlatt,
        uncertaintyLowerBound: (uncertaintyJson['lowerBound'] as num?)?.toDouble() ?? 22.0,
        uncertaintyUpperBound: (uncertaintyJson['upperBound'] as num?)?.toDouble() ?? 45.0,
      );
    } catch (_) {
      return ForensicCalibrationConfig.defaults();
    }
  }

  /// Parses JSON string directly.
  factory ForensicCalibrationConfig.fromString(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return ForensicCalibrationConfig.fromJson(map);
    } catch (_) {
      return ForensicCalibrationConfig.defaults();
    }
  }

  /// Loads calibration configuration from Flutter rootBundle asset, falling back
  /// cleanly to default parameters if the asset cannot be read.
  static Future<ForensicCalibrationConfig> loadFromAsset([
    String assetPath = 'assets/forensic_calibration.json',
  ]) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      return ForensicCalibrationConfig.fromString(jsonString);
    } catch (_) {
      return ForensicCalibrationConfig.defaults();
    }
  }

  /// Serializes calibration parameters to JSON map.
  Map<String, dynamic> toJson() => {
        'aiProbabilityThresholds': {
          'clean': aiCleanThreshold,
          'low': aiLowThreshold,
          'moderate': aiModerateThreshold,
          'high': aiHighThreshold,
        },
        'domainCalibration': domainMultipliers,
        'signalWeights': signalWeights,
        'plattCalibration': plattCalibrator.toJson(),
        'uncertaintyZone': {
          'lowerBound': uncertaintyLowerBound,
          'upperBound': uncertaintyUpperBound,
        },
      };
}
