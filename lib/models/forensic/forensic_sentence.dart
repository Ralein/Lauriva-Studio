import 'forensic_evidence.dart';

/// Single sentence forensic assessment combining neural and rule-based signals.
class ForensicSentence {
  final int index;
  final String text;
  final double aiProbability; // 0.0 -> 1.0
  final double confidence; // 0.0 -> 1.0
  final List<ForensicEvidence> evidence;
  final int startOffset;
  final int endOffset;

  const ForensicSentence({
    required this.index,
    required this.text,
    required this.aiProbability,
    required this.confidence,
    required this.evidence,
    this.startOffset = 0,
    this.endOffset = 0,
  });

  double get percentage => (aiProbability * 100.0).clamp(0.0, 100.0);

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        'aiProbability': aiProbability,
        'confidence': confidence,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'startOffset': startOffset,
        'endOffset': endOffset,
      };

  factory ForensicSentence.fromJson(Map<String, dynamic> json) =>
      ForensicSentence(
        index: json['index'] as int,
        text: json['text'] as String,
        aiProbability: (json['aiProbability'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
        evidence: (json['evidence'] as List? ?? const [])
            .map((e) => ForensicEvidence.fromJson(e as Map<String, dynamic>))
            .toList(),
        startOffset: json['startOffset'] as int? ?? 0,
        endOffset: json['endOffset'] as int? ?? 0,
      );
}
