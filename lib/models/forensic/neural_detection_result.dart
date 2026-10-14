/// Data contracts for the neural detector stream (Plan v7 / Lauriva Forensic Intelligence 4.0).
class TokenSpan {
  final int tokenIndex;
  final int startOffset;
  final int endOffset;
  final int sentenceIndex;

  const TokenSpan({
    required this.tokenIndex,
    required this.startOffset,
    required this.endOffset,
    required this.sentenceIndex,
  });

  Map<String, dynamic> toJson() => {
        'tokenIndex': tokenIndex,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'sentenceIndex': sentenceIndex,
      };

  factory TokenSpan.fromJson(Map<String, dynamic> json) => TokenSpan(
        tokenIndex: json['tokenIndex'] as int,
        startOffset: json['startOffset'] as int,
        endOffset: json['endOffset'] as int,
        sentenceIndex: json['sentenceIndex'] as int,
      );
}

class TokenizedInput {
  final List<int> inputIds;
  final List<int> attentionMask;
  final List<int> tokenTypeIds;
  final List<TokenSpan> tokenSpans;

  const TokenizedInput({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.tokenSpans,
  });

  Map<String, dynamic> toJson() => {
        'inputIds': inputIds,
        'attentionMask': attentionMask,
        'tokenTypeIds': tokenTypeIds,
        'tokenSpans': tokenSpans.map((s) => s.toJson()).toList(),
      };

  factory TokenizedInput.fromJson(Map<String, dynamic> json) => TokenizedInput(
        inputIds: (json['inputIds'] as List).cast<int>(),
        attentionMask: (json['attentionMask'] as List).cast<int>(),
        tokenTypeIds: (json['tokenTypeIds'] as List).cast<int>(),
        tokenSpans: (json['tokenSpans'] as List)
            .map((s) => TokenSpan.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class TokenEvidence {
  final int tokenId;
  final int startOffset;
  final int endOffset;
  final double score;

  const TokenEvidence({
    required this.tokenId,
    required this.startOffset,
    required this.endOffset,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
        'tokenId': tokenId,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'score': score,
      };

  factory TokenEvidence.fromJson(Map<String, dynamic> json) => TokenEvidence(
        tokenId: json['tokenId'] as int,
        startOffset: json['startOffset'] as int,
        endOffset: json['endOffset'] as int,
        score: (json['score'] as num).toDouble(),
      );
}

class SentenceNeuralEvidence {
  final int sentenceIndex;
  final int startOffset;
  final int endOffset;
  final double aiProbability; // 0.0 -> 1.0
  final double confidence; // 0.0 -> 1.0

  const SentenceNeuralEvidence({
    required this.sentenceIndex,
    required this.startOffset,
    required this.endOffset,
    required this.aiProbability,
    required this.confidence,
  });

  double get percentage => (aiProbability * 100.0).clamp(0.0, 100.0);

  Map<String, dynamic> toJson() => {
        'sentenceIndex': sentenceIndex,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'aiProbability': aiProbability,
        'confidence': confidence,
      };

  factory SentenceNeuralEvidence.fromJson(Map<String, dynamic> json) =>
      SentenceNeuralEvidence(
        sentenceIndex: json['sentenceIndex'] as int,
        startOffset: json['startOffset'] as int,
        endOffset: json['endOffset'] as int,
        aiProbability: (json['aiProbability'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class NeuralDetectionResult {
  final double aiProbability; // 0.0 -> 1.0 internal standard
  final double uncertainty; // 0.0 (certain) -> 1.0 (uncertain)
  final List<SentenceNeuralEvidence> sentences;
  final List<TokenEvidence> tokens;
  final bool isFallback;
  final String modelVersion;
  final Duration inferenceTime;
  final String? error;

  const NeuralDetectionResult({
    required this.aiProbability,
    required this.uncertainty,
    required this.sentences,
    required this.tokens,
    required this.isFallback,
    required this.modelVersion,
    required this.inferenceTime,
    this.error,
  });

  double get percentage => (aiProbability * 100.0).clamp(0.0, 100.0);

  factory NeuralDetectionResult.fallback({
    String? error,
  }) {
    return NeuralDetectionResult(
      aiProbability: 0.5,
      uncertainty: 1.0,
      sentences: const [],
      tokens: const [],
      isFallback: true,
      modelVersion: 'fallback',
      inferenceTime: Duration.zero,
      error: error,
    );
  }

  Map<String, dynamic> toJson() => {
        'aiProbability': aiProbability,
        'uncertainty': uncertainty,
        'sentences': sentences.map((s) => s.toJson()).toList(),
        'tokens': tokens.map((t) => t.toJson()).toList(),
        'isFallback': isFallback,
        'modelVersion': modelVersion,
        'inferenceTimeMs': inferenceTime.inMilliseconds,
        'error': error,
      };

  factory NeuralDetectionResult.fromJson(Map<String, dynamic> json) =>
      NeuralDetectionResult(
        aiProbability: (json['aiProbability'] as num).toDouble(),
        uncertainty: (json['uncertainty'] as num).toDouble(),
        sentences: (json['sentences'] as List? ?? const [])
            .map((s) =>
                SentenceNeuralEvidence.fromJson(s as Map<String, dynamic>))
            .toList(),
        tokens: (json['tokens'] as List? ?? const [])
            .map((t) => TokenEvidence.fromJson(t as Map<String, dynamic>))
            .toList(),
        isFallback: json['isFallback'] as bool? ?? false,
        modelVersion: json['modelVersion'] as String? ?? 'student_v1',
        inferenceTime: Duration(
            milliseconds: (json['inferenceTimeMs'] as num?)?.toInt() ?? 0),
        error: json['error'] as String?,
      );
}
