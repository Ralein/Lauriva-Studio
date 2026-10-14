/// Represents a sliding window for neural model inference.
class TextWindow {
  final int index;
  final int startOffset;
  final int endOffset;
  final String text;
  final List<int> sentenceIndices;
  final double weight;

  const TextWindow({
    required this.index,
    required this.startOffset,
    required this.endOffset,
    required this.text,
    required this.sentenceIndices,
    this.weight = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'text': text,
        'sentenceIndices': sentenceIndices,
        'weight': weight,
      };

  factory TextWindow.fromJson(Map<String, dynamic> json) => TextWindow(
        index: json['index'] as int,
        startOffset: json['startOffset'] as int,
        endOffset: json['endOffset'] as int,
        text: json['text'] as String,
        sentenceIndices: (json['sentenceIndices'] as List).cast<int>(),
        weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      );
}

class WindowPrediction {
  final TextWindow window;
  final double aiProbability; // 0.0 -> 1.0
  final double uncertainty; // 0.0 -> 1.0
  final double weight;

  const WindowPrediction({
    required this.window,
    required this.aiProbability,
    required this.uncertainty,
    required this.weight,
  });
}
