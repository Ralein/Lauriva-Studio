/// Independent evidence classifications for Lauriva Dual-Stream Forensics.
enum EvidenceType {
  neural,
  stylometric,
  structural,
  lexical,
  predictability,
  authorshipDrift,
  sourceSimilarity,
  repetition,
  adversarial,
  watermark,
}

enum EvidenceSource {
  modelLogits,
  stylometricVector,
  structuralGrammar,
  lexicalPattern,
  autoregressiveLanguageModel,
  cusumDrift,
  corpusShingle,
  ngramOverlap,
  homoglyphScanner,
  statisticalWatermark,
}

class ForensicEvidence {
  final EvidenceType type;
  final String label;
  final String description;
  final double strength; // 0.0 -> 1.0 (magnitude)
  final double confidence; // 0.0 -> 1.0 (statistical certainty)
  final int? startOffset;
  final int? endOffset;
  final EvidenceSource? source;

  const ForensicEvidence({
    required this.type,
    required this.label,
    required this.description,
    required this.strength,
    required this.confidence,
    this.startOffset,
    this.endOffset,
    this.source,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'label': label,
        'description': description,
        'strength': strength,
        'confidence': confidence,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'source': source?.name,
      };

  factory ForensicEvidence.fromJson(Map<String, dynamic> json) =>
      ForensicEvidence(
        type: EvidenceType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => EvidenceType.stylometric,
        ),
        label: json['label'] as String,
        description: json['description'] as String,
        strength: (json['strength'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
        startOffset: json['startOffset'] as int?,
        endOffset: json['endOffset'] as int?,
        source: json['source'] != null
            ? EvidenceSource.values.firstWhere(
                (s) => s.name == json['source'],
                orElse: () => EvidenceSource.stylometricVector,
              )
            : null,
      );
}
