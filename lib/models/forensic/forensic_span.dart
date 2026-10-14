/// Type of forensic evidence attributed to a text span.
enum SpanForensicType {
  aiPattern(label: 'AI Pattern'),
  sourceExact(label: 'Verbatim Match'),
  sourceParaphrase(label: 'Paraphrase Match'),
  internalRepetition(label: 'Repeated Phrase'),
  styleAnomaly(label: 'Style Shift');

  final String label;
  const SpanForensicType({required this.label});
}

/// Visual and diagnostic severity level of a flagged span.
enum SpanSeverity {
  info,
  low,
  moderate,
  high,
  critical,
}

/// A precise segment within the document tagged with forensic evidence.
/// Offsets always map directly to the user's raw [originalText].
class ForensicSpan {
  final String id;
  final int startOffset;
  final int endOffset;
  final String text;
  final SpanForensicType type;
  final SpanSeverity severity;
  final double confidence; // 0.0 to 1.0
  final String label;
  final String explanation;
  final Map<String, dynamic> metadata;

  const ForensicSpan({
    required this.id,
    required this.startOffset,
    required this.endOffset,
    required this.text,
    required this.type,
    required this.severity,
    required this.confidence,
    required this.label,
    required this.explanation,
    this.metadata = const {},
  });

  factory ForensicSpan.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String;
    final severityName = json['severity'] as String;
    return ForensicSpan(
      id: json['id'] as String,
      startOffset: (json['startOffset'] as num).toInt(),
      endOffset: (json['endOffset'] as num).toInt(),
      text: json['text'] as String,
      type: SpanForensicType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => SpanForensicType.aiPattern,
      ),
      severity: SpanSeverity.values.firstWhere(
        (s) => s.name == severityName,
        orElse: () => SpanSeverity.moderate,
      ),
      confidence: (json['confidence'] as num).toDouble(),
      label: json['label'] as String,
      explanation: json['explanation'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'text': text,
        'type': type.name,
        'severity': severity.name,
        'confidence': confidence,
        'label': label,
        'explanation': explanation,
        'metadata': metadata,
      };
}
