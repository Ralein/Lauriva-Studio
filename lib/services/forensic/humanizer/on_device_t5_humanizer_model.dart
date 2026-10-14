import 'package:flutter/foundation.dart';

import 'humanizer_model.dart';
import 't5_backend.dart';
import 't5_chunker.dart';
import 't5_greedy_decoder.dart';
import 't5_guards.dart';
import 't5_tokenizer.dart';

/// Per-call accounting of what the on-device T5 did to a chunk.
class T5RewriteStats {
  int sentenceChunks = 0;
  int rewritten = 0;
  int unchanged = 0;
  int skippedProtected = 0;
  final Map<String, int> guardFailures = {};

  int get kept => sentenceChunks - rewritten;

  @override
  String toString() => 'chunks=$sentenceChunks rewritten=$rewritten unchanged=$unchanged '
      'protected=$skippedProtected guardFailures=$guardFailures';
}

/// On-device T5-small humanizer (ONNX, int8). Rewrites sentence-aligned chunks
/// (<= [chunkMaxWords] words) with greedy decoding, then applies per-chunk
/// guards (length 0.80-1.30x, negation-count parity, numbers, citations). A
/// chunk that fails any guard keeps its source text, so the model can only
/// change a passage when the result is verifiably safe (README: tool/humanizer_release).
///
/// Chunks containing `[PROTECTED_nnn]` placeholders are passed through
/// untouched: the model was never trained on them and would corrupt them.
///
/// Throws [T5UnavailableException] (from the backend) when the model cannot
/// run; the fallback chain catches it.
class OnDeviceT5HumanizerModel implements HumanizerModel {
  final T5Tokenizer tokenizer;
  final T5Backend backend;
  final int chunkMaxWords;
  final int noRepeatNgramSize;

  /// Last call's accounting (not thread-safe by design; one rewrite at a time).
  T5RewriteStats lastStats = T5RewriteStats();

  static final RegExp _placeholder = RegExp(r'\[\s*PROTECTED_\d+\s*\]');
  static final RegExp _paragraphBreak = RegExp(r'(\r?\n[ \t]*){2,}');

  OnDeviceT5HumanizerModel({
    required this.tokenizer,
    required this.backend,
    this.chunkMaxWords = 50,
    this.noRepeatNgramSize = 3,
  });

  @override
  String get name => 'On-device T5 (ONNX int8)';

  @override
  int get maxContextTokens => tokenizer.maxLength;

  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    final stats = T5RewriteStats();
    lastStats = stats;
    final decoder = T5GreedyDecoder(backend: backend, noRepeatNgramSize: noRepeatNgramSize);
    final paragraphs = context.targetChunk.split(_paragraphBreak);
    final rebuilt = <String>[];
    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) continue;
      final out = <String>[];
      for (final source in T5Chunker.chunk(paragraph, maxWords: chunkMaxWords)) {
        stats.sentenceChunks++;
        out.add(await _rewriteSentenceChunk(source, decoder, stats));
      }
      rebuilt.add(out.join(' '));
    }
    return rebuilt.join('\n\n');
  }

  Future<String> _rewriteSentenceChunk(String source, T5GreedyDecoder decoder, T5RewriteStats stats) async {
    if (_placeholder.hasMatch(source)) {
      stats.skippedProtected++;
      return source;
    }
    final inputIds = tokenizer.encode('humanize: $source');
    // Output length tracks input length; a tight cap bounds rambling and the
    // quadratic no-KV-cache cost on a phone.
    final cap = (inputIds.length * 1.5).ceil() + 8;
    final generated = await decoder.generate(inputIds, maxNewTokensOverride: cap.clamp(8, 256));
    final candidate = tokenizer.decode(generated).trim();
    if (candidate.isEmpty) {
      stats.guardFailures.update('empty', (v) => v + 1, ifAbsent: () => 1);
      return source;
    }
    final guards = T5Guards.check(source, candidate);
    if (!guards.passed) {
      final key = guards.failure!;
      stats.guardFailures.update(key, (v) => v + 1, ifAbsent: () => 1);
      return source;
    }
    if (candidate.trim() == source.trim()) {
      stats.unchanged++;
      return source;
    }
    stats.rewritten++;
    return candidate;
  }

  /// Releases the ONNX sessions.
  void dispose() => backend.dispose();
}

/// On-device fallback used when the cloud rewrite fails or its output fails
/// the guards: on-device T5 when its model files are present (and ONNX
/// Runtime loads), otherwise the rule-based [LocalAlgorithmicHumanizerModel].
/// The chunk engine's normal post-processing (rule engine + verifier) then runs
/// on the result, which is the "hybrid" policy from tool/humanizer_release.
class LocalHumanizerFallbackModel implements HumanizerModel {
  final Future<HumanizerModel?> Function() _t5Provider;
  final HumanizerModel _rules;

  /// Which stage produced the last result (`t5` or `rules`), for logging/tests.
  String lastStage = 'rules';

  LocalHumanizerFallbackModel({
    required Future<HumanizerModel?> Function() t5Provider,
    required HumanizerModel rules,
  })  : _t5Provider = t5Provider,
        _rules = rules;

  @override
  String get name => 'On-device fallback (T5 ONNX, then rules)';

  @override
  int get maxContextTokens => 2048;

  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    try {
      final t5 = await _t5Provider();
      if (t5 != null) {
        final out = await t5.rewriteChunk(context);
        if (out.trim().isNotEmpty) {
          lastStage = 't5';
          return out;
        }
      }
    } on T5UnavailableException catch (e) {
      debugPrint('[LocalHumanizerFallback] T5 unavailable: ${e.reason}');
    } catch (e) {
      debugPrint('[LocalHumanizerFallback] T5 failed, using rules: $e');
    }
    lastStage = 'rules';
    return _rules.rewriteChunk(context);
  }
}
