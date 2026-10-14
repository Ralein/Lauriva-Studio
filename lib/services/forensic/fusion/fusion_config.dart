/// Configuration parameters controlling dual-stream evidence weighting and calibration.
class FusionConfig {
  final double neuralBaseWeight;
  final double minimumNeuralWeight;
  final double maximumNeuralWeight;
  final int fullContextWordCount;
  final double humanThreshold; // Scores <= this are predominantly human
  final double aiThreshold; // Scores >= this are predominantly AI

  /// Verdict thresholds when the neural stream is available. The stacked
  /// neural probability is calibrated (ECE 0.018 on the benchmark), so these are
  /// operating points, not guesses: p >= 0.90 keeps human false positives near
  /// 2% (1.8% on the frozen benchmark, 87% of AI caught); p <= 0.20 labels only
  /// text with almost no AI mass as likely human (79% of humans, 2% of AI).
  final double neuralAiThreshold;
  final double neuralHumanThreshold;

  /// Logistic stacking over the two streams' clipped log-odds. Refit for the
  /// Phase 3 Omni detector (fp32, BPE tokenizer, 512-token window) on the
  /// calibration split and checked on the frozen benchmark: neural AUC 0.984,
  /// ECE 0.018. Stylometry (AUC 0.64) adds nothing for this model (stack AUC
  /// 0.983 with a spurious negative stylometric weight), so its coefficient is 0
  /// and the stack is neural-only. The previous coefficients (fitted for the old
  /// model) gave ECE 0.257 with the new one. Refit whenever the bundled model
  /// changes: tool/fit_fusion_stack.py.
  final double stackNeuralCoef;
  final double stackForensicCoef;
  final double stackBias;
  final double stackLogitClip;

  const FusionConfig({
    this.stackNeuralCoef = 1.5043,
    this.stackForensicCoef = 0.0,
    this.stackBias = 0.9102,
    this.stackLogitClip = 4.0,
    this.neuralBaseWeight = 0.75,
    this.minimumNeuralWeight = 0.40,
    this.maximumNeuralWeight = 0.90,
    this.fullContextWordCount = 50,
    this.humanThreshold = 0.35,
    this.aiThreshold = 0.65,
    this.neuralAiThreshold = 0.90,
    this.neuralHumanThreshold = 0.20,
  });

  factory FusionConfig.fromJson(Map<String, dynamic> json) => FusionConfig(
        neuralBaseWeight: (json['neuralBaseWeight'] as num?)?.toDouble() ?? 0.75,
        minimumNeuralWeight: (json['minimumNeuralWeight'] as num?)?.toDouble() ?? 0.40,
        maximumNeuralWeight: (json['maximumNeuralWeight'] as num?)?.toDouble() ?? 0.90,
        fullContextWordCount: json['fullContextWordCount'] as int? ?? 50,
        humanThreshold: (json['humanThreshold'] as num?)?.toDouble() ?? 0.35,
        aiThreshold: (json['aiThreshold'] as num?)?.toDouble() ?? 0.65,
        neuralAiThreshold: (json['neuralAiThreshold'] as num?)?.toDouble() ?? 0.90,
        neuralHumanThreshold: (json['neuralHumanThreshold'] as num?)?.toDouble() ?? 0.20,
        stackNeuralCoef: (json['stackNeuralCoef'] as num?)?.toDouble() ?? 1.5043,
        stackForensicCoef: (json['stackForensicCoef'] as num?)?.toDouble() ?? 0.0,
        stackBias: (json['stackBias'] as num?)?.toDouble() ?? 0.9102,
        stackLogitClip: (json['stackLogitClip'] as num?)?.toDouble() ?? 4.0,
      );

  Map<String, dynamic> toJson() => {
        'neuralBaseWeight': neuralBaseWeight,
        'minimumNeuralWeight': minimumNeuralWeight,
        'maximumNeuralWeight': maximumNeuralWeight,
        'fullContextWordCount': fullContextWordCount,
        'humanThreshold': humanThreshold,
        'aiThreshold': aiThreshold,
        'neuralAiThreshold': neuralAiThreshold,
        'neuralHumanThreshold': neuralHumanThreshold,
        'stackNeuralCoef': stackNeuralCoef,
        'stackForensicCoef': stackForensicCoef,
        'stackBias': stackBias,
        'stackLogitClip': stackLogitClip,
      };
}
