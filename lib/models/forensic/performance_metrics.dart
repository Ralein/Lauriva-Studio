/// Performance and latency diagnostics across dual-stream forensic pipelines (Plan 7 Section 57).
class PerformanceMetrics {
  final Duration modelLoad;
  final Duration tokenization;
  final Duration neuralInference;
  final Duration forensicAnalysis;
  final Duration fusion;
  final Duration total;
  final int peakMemoryMb;

  const PerformanceMetrics({
    this.modelLoad = Duration.zero,
    this.tokenization = Duration.zero,
    this.neuralInference = Duration.zero,
    this.forensicAnalysis = Duration.zero,
    this.fusion = Duration.zero,
    this.total = Duration.zero,
    this.peakMemoryMb = 0,
  });

  Map<String, dynamic> toJson() => {
        'modelLoadMs': modelLoad.inMilliseconds,
        'tokenizationMs': tokenization.inMilliseconds,
        'neuralInferenceMs': neuralInference.inMilliseconds,
        'forensicAnalysisMs': forensicAnalysis.inMilliseconds,
        'fusionMs': fusion.inMilliseconds,
        'totalMs': total.inMilliseconds,
        'peakMemoryMb': peakMemoryMb,
      };

  factory PerformanceMetrics.fromJson(Map<String, dynamic> json) =>
      PerformanceMetrics(
        modelLoad: Duration(
          milliseconds: (json['modelLoadMs'] as num?)?.toInt() ?? 0,
        ),
        tokenization: Duration(
          milliseconds: (json['tokenizationMs'] as num?)?.toInt() ?? 0,
        ),
        neuralInference: Duration(
          milliseconds: (json['neuralInferenceMs'] as num?)?.toInt() ?? 0,
        ),
        forensicAnalysis: Duration(
          milliseconds: (json['forensicAnalysisMs'] as num?)?.toInt() ?? 0,
        ),
        fusion: Duration(
          milliseconds: (json['fusionMs'] as num?)?.toInt() ?? 0,
        ),
        total: Duration(
          milliseconds: (json['totalMs'] as num?)?.toInt() ?? 0,
        ),
        peakMemoryMb: (json['peakMemoryMb'] as num?)?.toInt() ?? 0,
      );
}
