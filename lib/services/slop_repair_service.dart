import '../models/llm_provider.dart';
import '../utils/logger.dart';
import 'forensic/humanizer/semantic_preservation_verifier.dart';
import 'llm_service.dart';
import 'slop_linter.dart';

/// Outcome of a [SlopRepairService.polish] pass. [text] is always safe to use:
/// it is either the repaired text (when [repaired]) or the untouched candidate.
class SlopRepairResult {
  final String text;
  final SlopReport before;
  final SlopReport after;
  final bool repaired;

  /// Why the candidate was kept (or a note on the repair); null when repaired.
  final String? reason;

  const SlopRepairResult({
    required this.text,
    required this.before,
    required this.after,
    required this.repaired,
    this.reason,
  });
}

/// "Check -> targeted repair -> verify" pass over a finished Studio rewrite.
///
/// Lints the candidate, asks the LLM (one non-streaming call) to fix only the
/// flagged AI-pattern spots, and keeps the repair only if it provably did not
/// drift from the source. Never throws; on any doubt the candidate is returned.
class SlopRepairService {
  final LlmService _llm;
  final SlopLinter _linter;
  final SemanticPreservationVerifier _verifier;

  SlopRepairService({
    LlmService? llmService,
    SlopLinter? linter,
    SemanticPreservationVerifier? verifier,
  })  : _llm = llmService ?? LlmService(),
        _linter = linter ?? const SlopLinter(),
        _verifier = verifier ?? SemanticPreservationVerifier();

  static const String repairFeatureId = 'SlopRepair';
  static const double _lengthTolerance = 0.15;

  /// Rewrite-style features whose output is worth linting. Grammar and
  /// Translate must stay faithful to the input, so they are never touched.
  static bool shouldCheck(String featureId) {
    switch (featureId) {
      case 'Humanize':
      case 'Rephrase':
      case 'Concise':
      case 'Professional':
      case 'Polite':
        return true;
      default:
        return featureId.startsWith('Style:');
    }
  }

  static int repairableCount(SlopReport r) =>
      r.findings.where((f) => f.category != SlopCategory.unsupportedProof).length;

  Future<SlopRepairResult> polish({
    required String source,
    required String candidate,
    required String featureId,
    required LlmProvider provider,
    required String apiKey,
    required Map<String, String> allConfiguredKeys,
    String? model,
    String? customBaseUrl,
    LlmGenerationParams? params,
    bool Function()? isCancelled,
  }) async {
    final before = _linter.check(candidate);
    SlopRepairResult keep(String reason) => SlopRepairResult(
          text: candidate,
          before: before,
          after: before,
          repaired: false,
          reason: reason,
        );

    if (!shouldCheck(featureId)) return keep('feature not checked');
    final repairable = before.findings.where((f) => f.category != SlopCategory.unsupportedProof).toList();
    if (repairable.isEmpty) {
      return keep(before.findings.isEmpty ? 'clean' : 'only unsupported-claim findings');
    }

    try {
      final reply = await _llm.transformTextWithFailover(
        primaryProvider: provider,
        primaryApiKey: apiKey,
        featureId: repairFeatureId,
        text: _buildRequest(candidate, repairable),
        allConfiguredKeys: allConfiguredKeys,
        primaryModel: model,
        customBaseUrl: customBaseUrl,
        params: (params ?? const LlmGenerationParams()).copyWith(temperature: 0.2, persona: 'standard'),
      );
      if (isCancelled?.call() ?? false) return keep('cancelled');

      final repaired = reply.trim();
      if (repaired.isEmpty) return keep('empty repair');
      if (repaired == candidate.trim()) return keep('repair made no change');

      final after = _linter.check(repaired);
      final rejection = _validate(source, candidate, repaired, before, after);
      if (rejection != null) {
        AppLogger.info('Slop repair rejected: $rejection', 'SlopRepair');
        return keep(rejection);
      }
      return SlopRepairResult(text: repaired, before: before, after: after, repaired: true);
    } catch (e) {
      AppLogger.warn('Slop repair failed, keeping candidate: $e', 'SlopRepair');
      return keep('repair call failed');
    }
  }

  /// Returns a rejection reason, or null when every accept rule holds.
  String? _validate(String source, String candidate, String repaired, SlopReport before, SlopReport after) {
    if (repairableCount(after) >= repairableCount(before)) return 'flags did not drop';

    final ratio = _wordCount(repaired) / (_wordCount(candidate) == 0 ? 1 : _wordCount(candidate));
    if (ratio < 1 - _lengthTolerance || ratio > 1 + _lengthTolerance) return 'length changed too much';

    for (final token in _protectedTokens(candidate)) {
      if (!repaired.contains(token)) return 'dropped "$token"';
    }

    if (SemanticPreservationVerifier.countNegations(candidate) !=
        SemanticPreservationVerifier.countNegations(repaired)) {
      return 'negation count changed';
    }

    final check = _verifier.verify(originalText: source, humanizedText: repaired);
    if (check.verdict == SemanticPreservationVerdict.factualDriftAlert ||
        check.hasNumericalDrift ||
        check.hasCitationLoss) {
      return 'meaning check failed';
    }
    return null;
  }

  static final RegExp _tokenPattern = RegExp(
    r'https?://[^\s)\]>]+|www\.[^\s)\]>]+|@\w+|\{[^{}\s]+\}|\d+(?:[.,]\d+)*',
  );

  static Set<String> _protectedTokens(String text) {
    return _tokenPattern
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), ''))
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  static int _wordCount(String t) {
    final trimmed = t.trim();
    return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
  }

  static String _sentenceAround(String text, int start, int end) {
    var s = start.clamp(0, text.length);
    var e = end.clamp(0, text.length);
    while (s > 0 && !'.!?\n'.contains(text[s - 1])) {
      s--;
    }
    while (e < text.length && !'.!?\n'.contains(text[e])) {
      e++;
    }
    if (e < text.length && text[e] != '\n') e++;
    return text.substring(s, e).trim();
  }

  static String _buildRequest(String candidate, List<SlopFinding> findings) {
    final b = StringBuffer('FLAGGED SPOTS (fix only these):\n');
    var i = 1;
    for (final f in findings.take(40)) {
      final sentence = _sentenceAround(candidate, f.start, f.end);
      b.writeln('$i. [${f.label}] "${f.match.trim()}" in: "$sentence"');
      i++;
    }
    b.writeln();
    b.writeln('FULL TEXT:');
    b.write(candidate);
    return b.toString();
  }
}
