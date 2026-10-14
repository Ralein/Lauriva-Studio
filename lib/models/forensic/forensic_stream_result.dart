import 'forensic_evidence.dart';

/// Encapsulates the independent 38-feature statistical & forensic pipeline output.
class ForensicStreamResult {
  final double aiProbability; // 0.0 -> 1.0
  final List<double> features; // 38-dimensional feature vector
  final List<ForensicEvidence> evidence;
  final double structuralScore;
  final double predictabilityScore;
  final String domain;
  final bool isMixedOrEdited;

  const ForensicStreamResult({
    required this.aiProbability,
    required this.features,
    required this.evidence,
    required this.structuralScore,
    required this.predictabilityScore,
    this.domain = 'generalProse',
    this.isMixedOrEdited = false,
  });

  double get percentage => (aiProbability * 100.0).clamp(0.0, 100.0);

  Map<String, dynamic> toJson() => {
        'aiProbability': aiProbability,
        'features': features,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'structuralScore': structuralScore,
        'predictabilityScore': predictabilityScore,
        'domain': domain,
        'isMixedOrEdited': isMixedOrEdited,
      };

  factory ForensicStreamResult.fromJson(Map<String, dynamic> json) =>
      ForensicStreamResult(
        aiProbability: (json['aiProbability'] as num).toDouble(),
        features: (json['features'] as List).map((f) => (f as num).toDouble()).toList(),
        evidence: (json['evidence'] as List)
            .map((e) => ForensicEvidence.fromJson(e as Map<String, dynamic>))
            .toList(),
        structuralScore: (json['structuralScore'] as num).toDouble(),
        predictabilityScore: (json['predictabilityScore'] as num).toDouble(),
        domain: json['domain'] as String? ?? 'generalProse',
        isMixedOrEdited: json['isMixedOrEdited'] as bool? ?? false,
      );
}
