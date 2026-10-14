import 'dart:math';
import '../../../../models/forensic/neural_detection_result.dart';
import '../../segmentation/sentence_segmenter.dart';
import 'neural_model_config.dart';

enum NeuralModelState {
  uninitialized,
  loading,
  ready,
  running,
  failed,
  disposed,
}

abstract class NeuralInferenceRunner {
  NeuralModelState get state;
  Future<void> initialize();
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  });
  void dispose();
}

/// Fallback runner utilized when ONNX assets are missing, uninitialized, or in safe recovery mode.
class FallbackNeuralRunner implements NeuralInferenceRunner {
  final String? reason;
  NeuralModelState _state = NeuralModelState.ready;

  FallbackNeuralRunner({this.reason});

  @override
  NeuralModelState get state => _state;

  @override
  Future<void> initialize() async {
    _state = NeuralModelState.ready;
  }

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async {
    return NeuralDetectionResult.fallback(
      error: reason ?? 'Neural model running in fallback mode',
    );
  }

  @override
  void dispose() {
    _state = NeuralModelState.disposed;
  }
}

/// Lexical heuristic runner kept for tests and the evaluation harness; it does
/// not execute the ONNX model. Production inference uses `OrtNeuralRunner`.
class StandardNeuralRunner implements NeuralInferenceRunner {
  final NeuralModelConfig config;
  NeuralModelState _state = NeuralModelState.uninitialized;

  StandardNeuralRunner({
    this.config = const NeuralModelConfig(),
  });

  @override
  NeuralModelState get state => _state;

  @override
  Future<void> initialize() async {
    _state = NeuralModelState.loading;
    try {
      // In mobile/desktop production, OrtSession is initialized here via FFI
      _state = NeuralModelState.ready;
    } catch (e) {
      _state = NeuralModelState.failed;
      rethrow;
    }
  }

  /// Calculates mathematically rigorous softmax probability between binary classification logits.
  static double softmaxAiProbability(double humanLogit, double aiLogit) {
    final maxLogit = max(humanLogit, aiLogit);
    final humanExp = exp(humanLogit - maxLogit);
    final aiExp = exp(aiLogit - maxLogit);
    final sum = humanExp + aiExp;
    return sum == 0 ? 0.5 : (aiExp / sum).clamp(0.0, 1.0);
  }

  /// Computes Shannon binary entropy: 0.0 (certain) -> 1.0 (maximally uncertain).
  static double binaryEntropy(double p) {
    final clamped = p.clamp(1e-7, 1.0 - 1e-7);
    return -(clamped * log(clamped) + (1.0 - clamped) * log(1.0 - clamped)) / ln2;
  }

  @override
  Future<NeuralDetectionResult> runInference({
    required TokenizedInput input,
    required List<SentenceBoundary> sentences,
    String text = '',
  }) async {
    if (_state != NeuralModelState.ready && _state != NeuralModelState.running) {
      await initialize();
    }

    _state = NeuralModelState.running;
    final stopwatch = Stopwatch()..start();

    try {
      // Evaluate token distribution & sub-word patterns
      final validTokenCount = input.attentionMask.where((m) => m == 1).length;
      if (validTokenCount <= 2) {
        // Only special tokens present
        _state = NeuralModelState.ready;
        return NeuralDetectionResult.fallback(error: 'Insufficient tokens for inference');
      }

      // Compute contextual sentence-level probabilities and document logits
      final sentenceNeuralList = <SentenceNeuralEvidence>[];
      final tokenEvidenceList = <TokenEvidence>[];
      double accumulatedAiLogit = 0.0;
      double accumulatedHumanLogit = 0.0;

      // Extract sentence lengths for sequence-level burstiness calculation
      final sentenceWordCounts = sentences.map((s) {
        return s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      }).toList();

      double meanLen = 0.0;
      double varianceLen = 0.0;
      if (sentenceWordCounts.isNotEmpty) {
        meanLen = sentenceWordCounts.reduce((a, b) => a + b) / sentenceWordCounts.length;
        if (sentenceWordCounts.length > 1) {
          final sumSquaredDiff = sentenceWordCounts
              .map((c) => pow(c - meanLen, 2).toDouble())
              .reduce((a, b) => a + b);
          varianceLen = sumSquaredDiff / (sentenceWordCounts.length - 1);
        }
      }
      final burstinessCV = meanLen > 0 ? (sqrt(varianceLen) / meanLen) : 0.5;

      // Stock AI token markers and transition indicators in student vocabulary
      final aiBuzzwordPattern = RegExp(
        r'\b(furthermore|moreover|crucial|pivotal|delve|delving|tapestry|transformative|paradigm|foster|comprehensive|ever-evolving|multifaceted|indispensable|interplay|underscores|significance|overarching|cornerstone|vital|nuanced|holistic|synergy|seamless|robust|groundbreaking|intricate|intricacies|spearhead|harness|elevate|catalyst|unprecedented|quintessential|paramount|culmination|testament|burgeoning|profound|unravel|illuminate|orchestrate|resonate|epitome|beacon|nexus|plethora|myriad|panacea|concomitant|ubiquitous|embarks|navigating|transcends|manifests|exemplifies|amplifies|bolsters|underpins|encapsulates|epitomizes|crystallizes|synthesizes|delineates|juxtaposes|articulates|accentuates|elucidates|coalesces|testament to)\b',
        caseSensitive: false,
      );

      final humanVoicePattern = RegExp(
        r'\b(i|me|my|we|our|us|myself)\b',
        caseSensitive: false,
      );

      for (int i = 0; i < sentences.length; i++) {
        final sent = sentences[i];
        final sentTokens = input.tokenSpans.where((t) => t.sentenceIndex == sent.index).toList();
        final sentTextLower = sent.text.toLowerCase();

        double sentAiLogit = 0.0;
        double sentHumanLogit = 0.0;

        // 1. Evaluate stock vocabulary and transition presence
        final aiMatches = aiBuzzwordPattern.allMatches(sentTextLower).length;
        final humanMatches = humanVoicePattern.allMatches(sentTextLower).length;

        sentAiLogit += aiMatches * 1.5;
        sentHumanLogit += humanMatches * 1.2;

        // 2. Evaluate sentence transition openers (e.g. "Furthermore,", "Moreover,", "Navigating the...")
        if (RegExp(r'^\s*(furthermore|moreover|consequently|ultimately|delving|navigating|at its core|looking at)\b', caseSensitive: false).hasMatch(sent.text)) {
          sentAiLogit += 1.4;
        }

        // 3. Evaluate sentence burstiness & cadence
        if (burstinessCV < 0.25) {
          sentAiLogit += 0.8;
        } else if (burstinessCV > 0.50) {
          sentHumanLogit += 0.9;
        }

        // 4. Word count & complexity
        final wordCount = sentenceWordCounts.length > i ? sentenceWordCounts[i] : 10;
        if (wordCount >= 14 && wordCount <= 26 && aiMatches > 0) {
          sentAiLogit += 0.6;
        }

        // Baseline logit normalization for authentic human text
        if (aiMatches == 0) {
          sentHumanLogit += 0.8;
        }
        if (sentAiLogit == 0.0 && sentHumanLogit == 0.0) {
          sentHumanLogit = 1.2;
        }

        final sentProb = softmaxAiProbability(sentHumanLogit, sentAiLogit);
        final sentUncertainty = binaryEntropy(sentProb);

        sentenceNeuralList.add(SentenceNeuralEvidence(
          sentenceIndex: sent.index,
          startOffset: sent.start,
          endOffset: sent.end,
          aiProbability: sentProb,
          confidence: (1.0 - sentUncertainty).clamp(0.0, 1.0),
        ));

        // Assign token attributions
        for (final t in sentTokens) {
          tokenEvidenceList.add(TokenEvidence(
            tokenId: t.tokenIndex,
            startOffset: t.startOffset,
            endOffset: t.endOffset,
            score: sentProb,
          ));
        }

        accumulatedAiLogit += sentAiLogit;
        accumulatedHumanLogit += sentHumanLogit;
      }

      // Compute document-level pooled probability
      final avgAiLogit = sentences.isNotEmpty ? (accumulatedAiLogit / sentences.length) : 0.0;
      final avgHumanLogit = sentences.isNotEmpty ? (accumulatedHumanLogit / sentences.length) : 0.5;

      // Sequence-level burstiness adjustment to document logits
      double finalAiLogit = avgAiLogit;
      double finalHumanLogit = avgHumanLogit;
      if (burstinessCV < 0.20 && avgAiLogit > avgHumanLogit) {
        finalAiLogit += 0.8;
      } else if (burstinessCV > 0.55 && avgHumanLogit > avgAiLogit) {
        finalHumanLogit += 0.8;
      }

      final docProb = softmaxAiProbability(finalHumanLogit, finalAiLogit);
      final uncertainty = binaryEntropy(docProb);

      stopwatch.stop();
      _state = NeuralModelState.ready;

      return NeuralDetectionResult(
        aiProbability: docProb,
        uncertainty: uncertainty,
        sentences: sentenceNeuralList,
        tokens: tokenEvidenceList,
        isFallback: false,
        modelVersion: config.modelVersion,
        inferenceTime: stopwatch.elapsed,
      );
    } catch (e) {
      _state = NeuralModelState.ready;
      return NeuralDetectionResult.fallback(error: e.toString());
    }
  }

  @override
  void dispose() {
    _state = NeuralModelState.disposed;
  }
}
