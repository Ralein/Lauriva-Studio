import 'dart:async';
import '../../../models/humanizer_tone.dart';
import 'algorithmic_humanizer_service.dart';
import 'semantic_preservation_verifier.dart';

/// Master orchestrator for the Lauvira Humanize pipeline:
///   User Prompt -> ANY LLM (Groq / Claude / OpenAI) -> lauvira_humanize -> Humanized Text
///
/// Ensures any LLM output is stripped of Wikipedia AI tells, given high-burstiness
/// cadence, and filtered through strict factual/citation preservation guards.
class LauviraHumanizeService {
  final AlgorithmicHumanizerService _algorithmicService;
  final SemanticPreservationVerifier _verifier;

  LauviraHumanizeService({
    AlgorithmicHumanizerService? algorithmicService,
    SemanticPreservationVerifier? verifier,
  })  : _algorithmicService =
            algorithmicService ?? const AlgorithmicHumanizerService(),
        _verifier = verifier ?? SemanticPreservationVerifier();

  /// Converts various tone types (HumanizerTone, WritingToneProfile, String) into [WritingToneProfile].
  WritingToneProfile _resolveTone(dynamic tone) {
    if (tone is WritingToneProfile) return tone;
    if (tone is HumanizerTone) {
      switch (tone) {
        case HumanizerTone.academic:
          return WritingToneProfile.academic;
        case HumanizerTone.casual:
          return WritingToneProfile.casual;
        case HumanizerTone.creative:
          return WritingToneProfile.natural;
        case HumanizerTone.journalistic:
          return WritingToneProfile.direct;
        case HumanizerTone.professional:
          return WritingToneProfile.professional;
      }
    }
    if (tone is String) {
      return WritingToneProfile.fromString(tone);
    }
    return WritingToneProfile.professional;
  }

  /// Master transformation method: Takes raw output from ANY LLM and applies
  /// the lauvira_humanize post-processing pipeline.
  ///
  /// Flow:
  ///   1. Raw LLM output -> Algorithmic AI tell dissolution & cadence burstiness
  ///   2. Fact & semantic preservation verification -> Ensures numbers, citations, polarities are untouched
  ///   3. Verification fallback -> If drift detected, falls back to safe clean formatting
  Future<String> humanizeLlmOutput(
    String rawLlmText, {
    dynamic tone = WritingToneProfile.professional,
    String style = 'balanced',
    String? originalText,
    bool preserveFormatting = true,
    int intensity = 85,
  }) async {
    final cleanInput = rawLlmText.trim();
    if (cleanInput.isEmpty) return cleanInput;

    final resolvedTone = _resolveTone(tone);

    // Stage 1: Dissolve Wikipedia AI tells, robotic transition openers, and stacked modifiers
    final algorithmicResult = _algorithmicService.postProcess(
      cleanInput,
      tone: resolvedTone,
      style: style,
      intensity: intensity,
    );

    var candidateText = algorithmicResult;

    // Stage 2: Fact & semantic preservation verification against original LLM draft or source
    final baselineSource = (originalText != null && originalText.trim().isNotEmpty)
        ? originalText.trim()
        : cleanInput;

    final verification = _verifier.verify(
      originalText: baselineSource,
      humanizedText: candidateText,
    );

    // Only fall back to baseline source if critical factual corruption occurs (lost numbers or citations)
    if (verification.verdict == SemanticPreservationVerdict.factualDriftAlert &&
        (verification.hasNumericalDrift || verification.hasCitationLoss)) {
      candidateText = _algorithmicService.cleanPunctuationAndSpacing(baselineSource);
    }

    return candidateText;
  }
}
