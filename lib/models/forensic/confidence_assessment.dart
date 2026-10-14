/// Statistical confidence level based on multi-factor evidence stability.
enum ForensicConfidenceLevel {
  insufficient(
    label: 'Insufficient Evidence',
    badge: 'SHORT PASSAGE',
    description: 'Sample does not contain enough tokens to reliably infer statistical distributions.',
  ),
  low(
    label: 'Low Confidence',
    badge: 'PRELIMINARY',
    description: 'Preliminary indications with high statistical uncertainty.',
  ),
  moderate(
    label: 'Moderate Confidence',
    badge: 'EVALUATED',
    description: 'Signals are consistent across multiple linguistic families with moderate certainty.',
  ),
  high(
    label: 'High Confidence',
    badge: 'HIGH CERTAINTY',
    description: 'Stable linguistic signals, strong model agreement, and ample document length.',
  );

  final String label;
  final String badge;
  final String description;

  const ForensicConfidenceLevel({
    required this.label,
    required this.badge,
    required this.description,
  });

  static ForensicConfidenceLevel fromWordCount(int count) {
    if (count < 50) return ForensicConfidenceLevel.insufficient;
    if (count < 150) return ForensicConfidenceLevel.low;
    if (count < 500) return ForensicConfidenceLevel.moderate;
    return ForensicConfidenceLevel.high;
  }
}

/// A specific metric or condition contributing to overall confidence or uncertainty.
class ConfidenceFactor {
  final String name;
  final double score; // 0.0 to 1.0
  final bool isSupportive; // true = increases certainty, false = increases uncertainty
  final String description;

  const ConfidenceFactor({
    required this.name,
    required this.score,
    required this.isSupportive,
    required this.description,
  });

  factory ConfidenceFactor.fromJson(Map<String, dynamic> json) => ConfidenceFactor(
        name: json['name'] as String,
        score: (json['score'] as num).toDouble(),
        isSupportive: json['isSupportive'] as bool,
        description: json['description'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'score': score,
        'isSupportive': isSupportive,
        'description': description,
      };
}

/// Multi-factor quantification of uncertainty and evidence strength.
class ConfidenceAssessment {
  final ForensicConfidenceLevel level;
  final double score; // 0.0 to 1.0 (Higher = more reliable assessment)
  final double uncertainty; // 0.0 to 1.0 (Higher = wider error margin)
  final List<ConfidenceFactor> factors;
  final String summary;

  const ConfidenceAssessment({
    required this.level,
    required this.score,
    required this.uncertainty,
    this.factors = const [],
    required this.summary,
  });

  factory ConfidenceAssessment.fromJson(Map<String, dynamic> json) {
    final levelName = json['level'] as String;
    return ConfidenceAssessment(
      level: ForensicConfidenceLevel.values.firstWhere(
        (l) => l.name == levelName,
        orElse: () => ForensicConfidenceLevel.low,
      ),
      score: (json['score'] as num).toDouble(),
      uncertainty: (json['uncertainty'] as num).toDouble(),
      factors: (json['factors'] as List<dynamic>? ?? [])
          .map((f) => ConfidenceFactor.fromJson(f as Map<String, dynamic>))
          .toList(),
      summary: json['summary'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'score': score,
        'uncertainty': uncertainty,
        'factors': factors.map((f) => f.toJson()).toList(),
        'summary': summary,
      };
}
