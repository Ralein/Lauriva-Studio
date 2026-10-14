/// Forensic scan execution stages (Plan 7 Section 36).
enum ForensicStage {
  preparing,
  tokenizing,
  neuralAnalysis,
  forensicAnalysis,
  fusing,
  generatingReport,
  complete,
  failed,
}

/// Real-time chunk progress and load time tracking for the Forensic Intelligence Engine.
class ForensicProgress {
  final int currentChunk;
  final int totalChunks;
  final double progressRatio; // 0.0 to 1.0
  final Duration elapsed;
  final Duration estimatedRemaining;
  final Duration estimatedTotal;
  final String stage;
  final int wordsProcessed;
  final int totalWords;
  final ForensicStage stageType;

  const ForensicProgress({
    required this.currentChunk,
    required this.totalChunks,
    required this.progressRatio,
    required this.elapsed,
    required this.estimatedRemaining,
    required this.estimatedTotal,
    required this.stage,
    required this.wordsProcessed,
    required this.totalWords,
    this.stageType = ForensicStage.forensicAnalysis,
  });

  /// Formatted remaining load time for user-facing indicators (e.g. "~0.3s remaining").
  String get loadTimeRemainingText {
    final ms = estimatedRemaining.inMilliseconds;
    if (ms <= 0) return 'Finalizing audit...';
    if (ms < 1000) return '~${(ms / 100).round() * 100}ms left';
    final sec = (ms / 1000.0).toStringAsFixed(1);
    return '~$sec s left';
  }

  /// Formatted progress percentage string (e.g. "65%").
  String get percentText => '${(progressRatio * 100).clamp(0, 100).toStringAsFixed(0)}%';

  /// Formatted chunk counter string (e.g. "Chunk 3 of 8").
  String get chunkCounterText => totalChunks > 1
      ? 'Chunk $currentChunk of $totalChunks'
      : 'Analyzing document';

  /// Defensive copy with updated fields.
  ForensicProgress copyWith({
    int? currentChunk,
    int? totalChunks,
    double? progressRatio,
    Duration? elapsed,
    Duration? estimatedRemaining,
    Duration? estimatedTotal,
    String? stage,
    int? wordsProcessed,
    int? totalWords,
    ForensicStage? stageType,
  }) {
    return ForensicProgress(
      currentChunk: currentChunk ?? this.currentChunk,
      totalChunks: totalChunks ?? this.totalChunks,
      progressRatio: progressRatio ?? this.progressRatio,
      elapsed: elapsed ?? this.elapsed,
      estimatedRemaining: estimatedRemaining ?? this.estimatedRemaining,
      estimatedTotal: estimatedTotal ?? this.estimatedTotal,
      stage: stage ?? this.stage,
      wordsProcessed: wordsProcessed ?? this.wordsProcessed,
      totalWords: totalWords ?? this.totalWords,
      stageType: stageType ?? this.stageType,
    );
  }

  /// Initial placeholder before processing starts.
  static ForensicProgress initial({required int totalWords}) {
    final estimatedChunks = (totalWords / 300).ceil().clamp(1, 999);
    final estChunkTimeMs = 25;
    final estTotal = Duration(milliseconds: estimatedChunks * estChunkTimeMs + 50);
    return ForensicProgress(
      currentChunk: 0,
      totalChunks: estimatedChunks,
      progressRatio: 0.05,
      elapsed: Duration.zero,
      estimatedRemaining: estTotal,
      estimatedTotal: estTotal,
      stage: 'Initializing forensic partitioner...',
      wordsProcessed: 0,
      totalWords: totalWords,
      stageType: ForensicStage.preparing,
    );
  }

  @override
  String toString() =>
      'ForensicProgress(chunk: $currentChunk/$totalChunks, ${(progressRatio * 100).toStringAsFixed(0)}%, stage: $stage, remaining: $loadTimeRemainingText)';
}
