import 'dart:convert';
import 'dart:math';
import '../../../models/humanizer_tone.dart';
import '../../../models/llm_provider.dart';
import '../../../models/plagiarism_report.dart';
import '../../llm_service.dart';
import '../forensic_coordinator_service.dart';
import 'algorithmic_humanizer_service.dart';
import 'semantic_preservation_verifier.dart';

/// Result of a surgical humanization operation targeting only flagged sentences.
class SurgicalHumanizeResult {
  final String originalText;
  final String humanizedText;
  final int flaggedSentenceCount;
  final int replacedSentenceCount;
  final double preservationScore;
  final bool isFactualIntegrityPreserved;
  final String summary;
  final int passesRequired;

  const SurgicalHumanizeResult({
    required this.originalText,
    required this.humanizedText,
    required this.flaggedSentenceCount,
    required this.replacedSentenceCount,
    required this.preservationScore,
    required this.isFactualIntegrityPreserved,
    required this.summary,
    this.passesRequired = 1,
  });
}

/// Re-scores a full document; used between passes to decide which
/// sentences still need work.
typedef ForensicScorer = Future<PlagiarismReport> Function(String text);

/// Bridges the Forensic Intelligence Engine with surgical, span-targeted humanization.
///
/// Closed-loop, multi-pass repair (max [_maxPasses]):
/// 1. Flag sentences above the risk threshold in the incoming report.
/// 2. Ask the LLM to rewrite only those, as a strict same-length JSON array.
/// 3. Lexically post-process each rewrite, then gate it through the Meaning
///    Guard against the sentence's *original* text (numbers, citations,
///    negation polarity) so drift cannot accumulate across passes.
/// 4. Splice accepted rewrites back in document order, re-score the whole
///    document, and re-target only sentences that are still flagged.
/// 5. Stop when flagged sentences fall below the target, nothing is left to
///    fix, the LLM stops producing usable output, or a pass makes the
///    document score worse — in which case the best version so far is kept.
class SurgicalHumanizerBridge {
  final LlmService _llmService;
  final SemanticPreservationVerifier _verifier;
  final ForensicScorer _scorer;

  static const int _maxPasses = 3;
  static const double _targetAiThreshold = 10.0;
  static const double _flagThreshold = 15.0;

  SurgicalHumanizerBridge({
    LlmService? llmService,
    SemanticPreservationVerifier? verifier,
    ForensicScorer? scorer,
  })  : _llmService = llmService ?? LlmService(),
        _verifier = verifier ?? SemanticPreservationVerifier(),
        _scorer = scorer ?? _defaultScorer;

  static Future<PlagiarismReport> _defaultScorer(String text) async {
    final report = await ForensicCoordinatorService().coordinate(text: text);
    return report.toLegacyPlagiarismReport();
  }

  static bool _isFlagged(SentenceAudit s) =>
      s.riskLevel == PlagiarismRiskLevel.moderate ||
      s.riskLevel == PlagiarismRiskLevel.high ||
      s.riskLevel == PlagiarismRiskLevel.critical ||
      s.aiProbability >= _flagThreshold;

  /// Surgically repairs only sentences in [originalText] that exceed AI risk
  /// thresholds in [report]. Supports [tone] for writing register selection.
  Future<SurgicalHumanizeResult> surgicallyHumanize({
    required String originalText,
    required PlagiarismReport report,
    required LlmProvider provider,
    required String apiKey,
    String? model,
    String? customBaseUrl,
    String? preferredTone,
    HumanizerTone tone = HumanizerTone.professional,
    String style = 'balanced',
  }) async {
    // One slot per flagged sentence, in document order. A slot keeps its
    // original text (for meaning checks), surrounding context, and its current text
    // (for splicing and re-scoring) across passes.
    final slots = <_Slot>[];
    int searchFrom = 0;
    for (int i = 0; i < report.sentences.length; i++) {
      final s = report.sentences[i];
      final at = originalText.indexOf(s.text.trim(), searchFrom);
      if (at == -1) continue;
      searchFrom = at + s.text.trim().length;
      if (_isFlagged(s)) {
        final before = i > 0 ? report.sentences[i - 1].text.trim() : null;
        final after = i + 1 < report.sentences.length ? report.sentences[i + 1].text.trim() : null;
        slots.add(_Slot(
          original: s.text.trim(),
          score: s.aiProbability,
          contextBefore: before,
          contextAfter: after,
          detectedTells: s.detectedTells,
          burstinessDelta: s.burstinessDelta,
        ));
      }
    }

    if (slots.isEmpty) {
      return SurgicalHumanizeResult(
        originalText: originalText,
        humanizedText: originalText,
        flaggedSentenceCount: 0,
        replacedSentenceCount: 0,
        preservationScore: 100.0,
        isFactualIntegrityPreserved: true,
        summary: 'Document contains no flagged synthetic sentences. Original voice preserved.',
        passesRequired: 0,
      );
    }

    final toneProfile = preferredTone != null
        ? WritingToneProfile.fromString(preferredTone)
        : WritingToneProfile.fromString(tone.name);
    final toneInstruction = preferredTone != null ? 'Use a $preferredTone tone.' : tone.promptHint;

    String currentText = originalText;
    String bestText = originalText;
    double bestDocScore = report.overallScore;
    List<String> bestSlotTexts = slots.map((s) => s.current).toList();
    int passesRequired = 0;

    for (int pass = 1; pass <= _maxPasses; pass++) {
      final targets = [for (int i = 0; i < slots.length; i++) if (slots[i].score >= _flagThreshold) i];
      if (targets.isEmpty) break;
      passesRequired = pass;

      final rewrites = await _requestRewrites(
        sentences: targets.map((i) => slots[i].current).toList(),
        contextBeforeList: targets.map((i) => slots[i].contextBefore).toList(),
        contextAfterList: targets.map((i) => slots[i].contextAfter).toList(),
        detectedTellsList: targets.map((i) => slots[i].detectedTells).toList(),
        burstinessDeltasList: targets.map((i) => slots[i].burstinessDelta).toList(),
        pass: pass,
        toneInstruction: toneInstruction,
        styleConstraint: style,
        provider: provider,
        apiKey: apiKey,
        model: model,
        customBaseUrl: customBaseUrl,
      );
      if (rewrites == null) break; // unusable LLM output; retrying won't help

      // Accept rewrites that pass the Meaning Guard against the ORIGINAL.
      final accepted = <int, String>{};
      for (int k = 0; k < targets.length; k++) {
        final slot = slots[targets[k]];
        final raw = rewrites[k].trim();
        final repl = const AlgorithmicHumanizerService().postProcess(raw, tone: toneProfile, style: style);

        // Evaluate candidate quality with Semantic Guard and LoRA Stylistic Adapter
        final replGuard = _verifier.verify(originalText: slot.original, humanizedText: repl);
        final replValid = repl.isNotEmpty &&
            repl != slot.current &&
            !replGuard.hasNumericalDrift &&
            !replGuard.hasCitationLoss &&
            !replGuard.hasPolarityDrift;

        final rawGuard = _verifier.verify(originalText: slot.original, humanizedText: raw);
        final rawValid = raw.isNotEmpty &&
            raw != slot.current &&
            !rawGuard.hasNumericalDrift &&
            !rawGuard.hasCitationLoss &&
            !rawGuard.hasPolarityDrift;

        String? bestCandidate;
        if (replValid && rawValid) {
          if (repl == raw) {
            bestCandidate = repl;
          } else {
            const humanizer = AlgorithmicHumanizerService();
            final replScore = humanizer.scoreTransformWithLora(
              original: slot.original,
              candidate: repl,
            );
            final rawScore = humanizer.scoreTransformWithLora(
              original: slot.original,
              candidate: raw,
            );
            bestCandidate = replScore >= rawScore ? repl : raw;
          }
        } else if (replValid) {
          bestCandidate = repl;
        } else if (rawValid) {
          bestCandidate = raw;
        }

        if (bestCandidate == null) continue;
        accepted[targets[k]] = bestCandidate;
      }
      if (accepted.isEmpty) break;

      // Splice in document order so identical sentences elsewhere are safe.
      final buffer = StringBuffer();
      int cursor = 0;
      for (int i = 0; i < slots.length; i++) {
        final at = currentText.indexOf(slots[i].current, cursor);
        if (at == -1) continue;
        buffer.write(currentText.substring(cursor, at));
        final next = accepted[i] ?? slots[i].current;
        buffer.write(next);
        cursor = at + slots[i].current.length;
        if (accepted.containsKey(i)) slots[i].current = next;
      }
      buffer.write(currentText.substring(cursor));
      currentText = buffer.toString();

      // Close the loop: re-score and update each slot's risk.
      final rescored = await _scorer(currentText);
      for (final slot in slots) {
        final covering = rescored.sentences.where((s) => slot.current.contains(s.text.trim())).toList();
        if (covering.isNotEmpty) {
          slot.score = covering.map((s) => s.aiProbability).reduce(max);
        } else if (accepted.values.contains(slot.current)) {
          slot.score = 0.0; // re-segmented beyond recognition; don't loop on it
        }
      }

      if (rescored.overallScore <= bestDocScore) {
        bestDocScore = rescored.overallScore;
        bestText = currentText;
        bestSlotTexts = slots.map((s) => s.current).toList();
      } else {
        // This pass made the document read as more synthetic: keep the best.
        currentText = bestText;
        for (int i = 0; i < slots.length; i++) {
          slots[i].current = bestSlotTexts[i];
        }
        break;
      }

      final remaining = slots.where((s) => s.score >= _flagThreshold).toList();
      if (remaining.isEmpty) break;
      final meanRemaining = remaining.map((s) => s.score).reduce((a, b) => a + b) / remaining.length;
      if (meanRemaining < _targetAiThreshold) break;
    }

    currentText = bestText;
    final replacedCount = [
      for (int i = 0; i < slots.length; i++)
        if (bestSlotTexts[i] != slots[i].original) i,
    ].length;

    final preservation = _verifier.verify(
      originalText: originalText,
      humanizedText: currentText,
    );
    final fidelity = (preservation.preservationScore * 100.0).clamp(0.0, 100.0);
    final factualIntegrity = !preservation.hasNumericalDrift && !preservation.hasCitationLoss && !preservation.hasPolarityDrift;

    return SurgicalHumanizeResult(
      originalText: originalText,
      humanizedText: currentText,
      flaggedSentenceCount: slots.length,
      replacedSentenceCount: replacedCount,
      preservationScore: fidelity,
      isFactualIntegrityPreserved: factualIntegrity,
      summary:
          'Surgically humanized $replacedCount of ${slots.length} sentence(s) in $passesRequired pass(es). Fidelity: ${fidelity.toStringAsFixed(1)}%.',
      passesRequired: passesRequired,
    );
  }

  /// Returns exactly one rewrite per input sentence, or null when the model
  /// output can't be aligned 1:1 (positional mapping of a short or long array
  /// would splice rewrites into the wrong sentences).
  Future<List<String>?> _requestRewrites({
    required List<String> sentences,
    List<String?>? contextBeforeList,
    List<String?>? contextAfterList,
    List<List<String>>? detectedTellsList,
    List<double>? burstinessDeltasList,
    required int pass,
    required String toneInstruction,
    String styleConstraint = 'balanced',
    required LlmProvider provider,
    required String apiKey,
    String? model,
    String? customBaseUrl,
  }) async {
    final aggressivenessNote = switch (pass) {
      1 => 'Vary sentence lengths naturally, break formulaic academic and corporate transitions, and strictly preserve all figures, dates, and names.',
      2 => 'These sentences still read as machine-written. Invert clause order, break canonical Subject-Verb-Object structures, eliminate abstract Latinate nouns, and use high-entropy natural phrasing.',
      _ => 'Extreme anti-detection mode: completely dissolve robotic formulas. Vary sentence lengths radically (alternate 4 words with 25 words). Never start consecutive sentences with the same word. Keep all facts, names, and numbers 100% intact.',
    };

    final payload = StringBuffer()
      ..writeln(toneInstruction)
      ..writeln('Constraint: $styleConstraint style.')
      ..writeln('Follow 165 Natural Essay Rules across 5 quality pillars: eradicate "In today\'s world", "delve into", "multifaceted", "plays a crucial role", "sheds light on", "it is evident that", "not only X but also Y", "serves as a reminder".');
    if (aggressivenessNote.isNotEmpty) payload.writeln(aggressivenessNote);
    if (detectedTellsList != null && detectedTellsList.any((tells) => tells.isNotEmpty)) {
      payload.writeln('Detector Forensic Diagnostics per Target Sentence:');
      for (int i = 0; i < sentences.length; i++) {
        final tells = (detectedTellsList.length > i) ? detectedTellsList[i] : <String>[];
        final bDelta = (burstinessDeltasList != null && burstinessDeltasList.length > i) ? burstinessDeltasList[i] : 0.0;
        final details = <String>[];
        if (tells.isNotEmpty) details.add('Flags: ${tells.join(", ")}');
        if (bDelta.abs() > 0.15) details.add(bDelta < 0 ? 'Too monotonous/short' : 'Too convoluted/long');
        if (details.isNotEmpty) {
          payload.writeln('Sentence ${i + 1}: [${details.join(" | ")}]. Specifically eradicate these signals.');
        }
      }
    }
    if (contextBeforeList != null && contextBeforeList.any((c) => c != null && c.isNotEmpty)) {
      payload.writeln('Contextual Flow Guidance for Target Sentences:');
      for (int i = 0; i < sentences.length; i++) {
        final b = (contextBeforeList.length > i) ? contextBeforeList[i] : null;
        final a = (contextAfterList != null && contextAfterList.length > i) ? contextAfterList[i] : null;
        if (b != null || a != null) {
          payload.writeln('Sentence ${i + 1}: ${b != null ? "Preceded by: \"$b\". " : ""}${a != null ? "Followed by: \"$a\"." : ""}');
        }
      }
    }
    payload.writeln(
      'Rewrite each sentence into natural, high-entropy human prose while preserving its surrounding continuity. '
      'Preserve all facts, numbers, dates, units, citations, and names 100% intact. '
      'CRITICAL: Return ONLY a valid JSON array of exactly ${sentences.length} string(s) containing the rewritten sentences in order. No preamble, no postscript.',
    );
    payload.writeln();
    payload.write(jsonEncode(sentences));

    final response = await _llmService.transformText(
      provider: provider,
      apiKey: apiKey,
      featureId: 'SurgicalHumanize',
      text: payload.toString(),
      model: model,
      customBaseUrl: customBaseUrl,
      params: LlmGenerationParams(temperature: (0.72 + (pass - 1) * 0.12).clamp(0.0, 1.0)),
    );

    final parsed = parseRewriteArray(response);
    if (parsed == null || parsed.length != sentences.length) return null;
    return parsed;
  }

  /// Extracts a JSON string array from [response], tolerating code fences,
  /// surrounding prose, map objects, unescaped internal quotes, or numbered list format.
  static List<String>? parseRewriteArray(String response) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) return null;

    final start = trimmed.indexOf('[');
    final end = trimmed.lastIndexOf(']');
    if (start != -1 && end > start) {
      final candidate = trimmed.substring(start, end + 1);
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is List) {
          final results = <String>[];
          for (final item in decoded) {
            if (item is String) {
              results.add(item.trim());
            } else if (item is Map) {
              final val = item['rewritten'] ??
                  item['target_sentence'] ??
                  item['target'] ??
                  item['humanized'] ??
                  item['sentence'] ??
                  item['text'] ??
                  item.values.firstOrNull;
              if (val != null) results.add(val.toString().trim());
            } else {
              results.add(item.toString().trim());
            }
          }
          if (results.isNotEmpty) return results;
        }
      } catch (_) {
        // Fallback for unescaped internal double quotes inside JSON string values
        final regexItems = _extractJsonArrayItems(candidate);
        if (regexItems.isNotEmpty) return regexItems;
      }
    }

    // Line-by-line fallback (handles numbered lists, bullet points, clean lines)
    final lines = trimmed
        .replaceAll(RegExp(r'^```\w*\s*|```\s*$', multiLine: true), '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l != '[' && l != ']')
        .map((l) => l.replaceFirst(RegExp(r'^\s*(?:\d+[.)]|[-*•])\s+'), '').trim())
        .map((l) => l.replaceAll(RegExp(r'^"|",?$'), '').trim())
        .where((l) => l.isNotEmpty && l != '[' && l != ']')
        .toList();
    return lines.isEmpty ? null : lines;
  }

  static List<String> _extractJsonArrayItems(String bracketed) {
    var inner = bracketed.trim();
    if (inner.startsWith('[')) inner = inner.substring(1);
    if (inner.endsWith(']')) inner = inner.substring(0, inner.length - 1);
    inner = inner.trim();
    if (inner.isEmpty) return const [];
    if (inner.startsWith('"')) inner = inner.substring(1);
    if (inner.endsWith('"')) inner = inner.substring(0, inner.length - 1);
    final parts = inner.split(RegExp(r'"\s*,\s*(?:\r?\n\s*)?"'));
    return parts
        .map((p) => p.replaceAll(r'\"', '"').trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }
}

class _Slot {
  final String original;
  String current;
  double score;
  final String? contextBefore;
  final String? contextAfter;
  final List<String> detectedTells;
  final double burstinessDelta;

  _Slot({
    required this.original,
    required this.score,
    this.contextBefore,
    this.contextAfter,
    this.detectedTells = const [],
    this.burstinessDelta = 0.0,
  }) : current = original;
}
