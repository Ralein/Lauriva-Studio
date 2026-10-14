import '../plagiarism_report.dart';

/// Calibrated classification of authorship origin.
enum AuthorshipClass {
  likelyHuman(
    label: 'Likely Human Written',
    badge: 'HUMAN WRITTEN',
    description: 'High syntactic entropy, natural burstiness, and asymmetric pacing typical of authentic human prose.',
  ),
  mixedOrEdited(
    label: 'Mixed / Human-Edited AI',
    badge: 'MIXED / EDITED',
    description: 'Blended characteristics. Likely an AI draft substantially edited by a human or human prose containing formulaic AI fragments.',
  ),
  likelyAi(
    label: 'Likely AI-Generated',
    badge: 'LIKELY AI',
    description: 'Compressed syntactic variance, characteristic transition openers, and predictable rhetorical scaffolding.',
  ),
  inconclusive(
    label: 'Inconclusive / Short Text',
    badge: 'INSUFFICIENT DATA',
    description: 'Sample does not contain enough tokens to reliably infer stylometric distribution.',
  ),
  uncertain(
    label: 'Uncertain / Borderline Evidence',
    badge: 'UNCERTAIN',
    description: 'The available evidence is insufficient for a reliable determination.',
  );

  final String label;
  final String badge;
  final String description;

  const AuthorshipClass({
    required this.label,
    required this.badge,
    required this.description,
  });
}

/// Analysis for an individual sliding window over the document.
class AiWindowAssessment {
  final int windowIndex;
  final int startToken;
  final int endToken;
  final int startOffset;
  final int endOffset;
  final double aiProbability;
  final double uncertainty;
  final String summary;

  const AiWindowAssessment({
    required this.windowIndex,
    required this.startToken,
    required this.endToken,
    required this.startOffset,
    required this.endOffset,
    required this.aiProbability,
    required this.uncertainty,
    required this.summary,
  });

  factory AiWindowAssessment.fromJson(Map<String, dynamic> json) =>
      AiWindowAssessment(
        windowIndex: (json['windowIndex'] as num).toInt(),
        startToken: (json['startToken'] as num).toInt(),
        endToken: (json['endToken'] as num).toInt(),
        startOffset: (json['startOffset'] as num).toInt(),
        endOffset: (json['endOffset'] as num).toInt(),
        aiProbability: (json['aiProbability'] as num).toDouble(),
        uncertainty: (json['uncertainty'] as num).toDouble(),
        summary: json['summary'] as String,
      );

  Map<String, dynamic> toJson() => {
        'windowIndex': windowIndex,
        'startToken': startToken,
        'endToken': endToken,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'aiProbability': aiProbability,
        'uncertainty': uncertainty,
        'summary': summary,
      };
}

/// Diagnostic signal identified during forensic linguistic feature analysis.
class AiSignalItem {
  final String family; // 'Surface', 'Punctuation', 'Lexical', 'Syntax', 'Cohesion', 'Anomaly'
  final String name;
  final double score;
  final double weight;
  final String description;

  const AiSignalItem({
    required this.family,
    required this.name,
    required this.score,
    required this.weight,
    required this.description,
  });

  factory AiSignalItem.fromJson(Map<String, dynamic> json) => AiSignalItem(
        family: json['family'] as String,
        name: json['name'] as String,
        score: (json['score'] as num).toDouble(),
        weight: (json['weight'] as num).toDouble(),
        description: json['description'] as String,
      );

  Map<String, dynamic> toJson() => {
        'family': family,
        'name': name,
        'score': score,
        'weight': weight,
        'description': description,
      };
}

/// Independent forensic evidence measuring whether writing was generated or assisted by AI.
class AiAuthorshipEvidence {
  final double aiProbability; // 0.0 to 100.0
  final double humanProbability; // 0.0 to 100.0
  final AuthorshipClass authorshipClass;
  final double uncertainty; // 0.0 to 1.0
  final List<AiSignalItem> detectedSignals;
  final List<AiWindowAssessment> windows;
  final List<double> featureVector;
  final String defensibleSummary;

  const AiAuthorshipEvidence({
    required this.aiProbability,
    required this.humanProbability,
    required this.authorshipClass,
    required this.uncertainty,
    required this.detectedSignals,
    this.windows = const [],
    this.featureVector = const [],
    required this.defensibleSummary,
  });

  PlagiarismRiskLevel get toRiskLevel {
    if (aiProbability < 18.0) return PlagiarismRiskLevel.clean;
    if (aiProbability < 38.0) return PlagiarismRiskLevel.low;
    if (aiProbability < 65.0) return PlagiarismRiskLevel.moderate;
    if (aiProbability < 85.0) return PlagiarismRiskLevel.high;
    return PlagiarismRiskLevel.critical;
  }

  factory AiAuthorshipEvidence.fromJson(Map<String, dynamic> json) {
    final className = json['authorshipClass'] as String;
    final authorshipClass = AuthorshipClass.values.firstWhere(
      (c) => c.name == className,
      orElse: () => AuthorshipClass.inconclusive,
    );
    return AiAuthorshipEvidence(
      aiProbability: (json['aiProbability'] as num).toDouble(),
      humanProbability: (json['humanProbability'] as num).toDouble(),
      authorshipClass: authorshipClass,
      uncertainty: (json['uncertainty'] as num).toDouble(),
      detectedSignals: (json['detectedSignals'] as List<dynamic>? ?? [])
          .map((s) => AiSignalItem.fromJson(s as Map<String, dynamic>))
          .toList(),
      windows: (json['windows'] as List<dynamic>? ?? [])
          .map((w) => AiWindowAssessment.fromJson(w as Map<String, dynamic>))
          .toList(),
      featureVector: (json['featureVector'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      defensibleSummary: json['defensibleSummary'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'aiProbability': aiProbability,
        'humanProbability': humanProbability,
        'authorshipClass': authorshipClass.name,
        'uncertainty': uncertainty,
        'detectedSignals': detectedSignals.map((s) => s.toJson()).toList(),
        'windows': windows.map((w) => w.toJson()).toList(),
        'featureVector': featureVector,
        'defensibleSummary': defensibleSummary,
      };
}
