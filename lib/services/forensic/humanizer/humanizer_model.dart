import '../../../models/llm_provider.dart';
import '../../llm_service.dart';
import 'algorithmic_humanizer_service.dart';
import 'document_style_profiler.dart';
import 'lauvira_humanize_service.dart';

/// Context parameters supplied to the model to perform a seamless,
/// boundary-aware rewrite without attention decay or coreference drift.
class ChunkRewriteContext {
  final String targetChunk;
  final String precedingContext;
  final String followingContext;
  final String paragraphTopic;
  final DocumentStyleProfile styleProfile;
  final WritingToneProfile tone;
  final String style;
  final List<String> protectedPlaceholders;
  final int intensity;

  /// Detector findings on a previous rewrite of this chunk that still read as
  /// AI-generated; empty on the first attempt.
  final String detectorFeedback;

  const ChunkRewriteContext({
    required this.targetChunk,
    this.precedingContext = '',
    this.followingContext = '',
    this.paragraphTopic = '',
    required this.styleProfile,
    this.tone = WritingToneProfile.professional,
    this.style = 'balanced',
    this.protectedPlaceholders = const [],
    this.detectorFeedback = '',
    this.intensity = 85,
  });

  ChunkRewriteContext withDetectorFeedback(String feedback) => ChunkRewriteContext(
        targetChunk: targetChunk,
        precedingContext: precedingContext,
        followingContext: followingContext,
        paragraphTopic: paragraphTopic,
        styleProfile: styleProfile,
        tone: tone,
        style: style,
        protectedPlaceholders: protectedPlaceholders,
        detectorFeedback: feedback,
        intensity: intensity,
      );
}

/// Model-agnostic abstraction for document chunk humanization.
/// Accommodates cloud LLMs, on-device small models, and future fine-tuned adapters.
abstract class HumanizerModel {
  String get name;
  int get maxContextTokens;

  /// Rewrites the target chunk within [context], returning rewritten text.
  Future<String> rewriteChunk(ChunkRewriteContext context);
}

/// Cloud LLM implementation of HumanizerModel using context-aware hierarchical prompting.
class CloudLlmHumanizerModel implements HumanizerModel {
  final LlmService _llmService;
  final LlmProvider _provider;
  final String _apiKey;
  final String _model;
  final Map<String, String> _allConfiguredKeys;
  final String? _customBaseUrl;
  final LlmGenerationParams? _generationParams;
  final void Function(LlmProvider provider, String model, String reason)? _onFailoverDetails;

  CloudLlmHumanizerModel({
    required LlmService llmService,
    required LlmProvider provider,
    required String apiKey,
    required String model,
    Map<String, String>? allConfiguredKeys,
    String? customBaseUrl,
    LlmGenerationParams? generationParams,
    void Function(LlmProvider provider, String model, String reason)? onFailoverDetails,
  })  : _llmService = llmService,
        _provider = provider,
        _apiKey = apiKey,
        _model = model,
        _allConfiguredKeys = allConfiguredKeys ?? {},
        _customBaseUrl = customBaseUrl,
        _generationParams = generationParams,
        _onFailoverDetails = onFailoverDetails;

  @override
  String get name => 'Cloud LLM (${_provider.name} - $_model)';

  @override
  int get maxContextTokens => 8192;

  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    final systemPrompt = _buildHierarchicalSystemPrompt(context);
    final userPrompt = _buildHierarchicalUserPrompt(context);

    final params = (_generationParams ?? const LlmGenerationParams()).copyWith(
      persona: context.tone.name,
      temperature: _generationParams?.temperature ?? 0.85,
      topP: _generationParams?.topP ?? 0.95,
      frequencyPenalty: _generationParams?.frequencyPenalty == 0.0 ? 0.32 : (_generationParams?.frequencyPenalty ?? 0.32),
      presencePenalty: _generationParams?.presencePenalty == 0.0 ? 0.25 : (_generationParams?.presencePenalty ?? 0.25),
    );

    final output = await _llmService.transformTextWithFailover(
      primaryProvider: _provider,
      primaryApiKey: _apiKey,
      featureId: 'Humanize',
      text: userPrompt,
      customSystemPrompt: systemPrompt,
      allConfiguredKeys: _allConfiguredKeys,
      primaryModel: _model,
      customBaseUrl: _customBaseUrl,
      params: params,
      onFailoverDetails: _onFailoverDetails,
    );

    return _cleanLlmChunkOutput(output);
  }

  String _buildHierarchicalSystemPrompt(ChunkRewriteContext context) {
    final buffer = StringBuffer();
    buffer.writeln(
      'You are an elite prose stylist, computational essayist, and forensic linguistic re-architect. Your mission is to radically rewrite ONLY the target passage provided '
      'so that it reads with authentic human voice, intellectual nuance, varied sentence architecture, and organic cadence. '
      'The rewrite must be indistinguishable from native human prose and completely dismantle uniform AI-generated syntactic patterns.',
    );
    buffer.writeln();
    buffer.writeln('### PRIMARY DETECTION TARGET:');
    buffer.writeln('The rewritten text MUST score BELOW 10% AI likelihood on rigorous forensic AI detectors (GPTZero, Turnitin, Copyleaks, Winston AI, and Lauriva Forensic ONNX Engine). 10% is the strict ceiling threshold.');
    buffer.writeln();
    buffer.writeln('### 4 MANDATORY SYNTACTIC TRANSFORMATION OPERATORS:');
    buffer.writeln('1. CLAUSE INVERSION & ASYMMETRIC SYNTAX:');
    buffer.writeln('   - NEVER start multiple sentences in a row with Subject-Verb-Object (e.g. "Odysseus is...", "He wants...").');
    buffer.writeln('   - Lead with dependent clauses ("While Nestor managed to...", "Because the journey stretched on..."), participial phrases ("Arriving amid tragedy..."), or prepositional modifiers.');
    buffer.writeln('   - Invert cause-and-effect clauses: put the consequence or context first to dismantle formulaic deductive structures.');
    buffer.writeln('2. EXTREME CADENCE BURSTINESS (TARGET CV > 0.55):');
    buffer.writeln('   - Human writers exhibit high variance in sentence length. Ban uniform 15-20 word sentences.');
    buffer.writeln('   - Deliberately alternate short, punchy 3-7 word assertions with multi-clause, 25-35 word analytical thoughts.');
    buffer.writeln('3. ACTIVE VERB DYNAMISM & COPULA ELIMINATION:');
    buffer.writeln('   - Eradicate passive copular formulas: "serves as a reminder that", "is an example of", "plays a crucial role in", "highlights the importance of", "can be seen as".');
    buffer.writeln('   - Replace with direct, muscular verbs: "illustrates", "anchors", "foreshadows", "erodes", "catalyzes", "reveals".');
    buffer.writeln('4. ANTI-VERBATIM REWRITE FLOOR (CRITICAL):');
    buffer.writeln('   - DO NOT merely swap isolated synonyms while keeping the original sentence skeleton intact.');
    buffer.writeln('   - Re-synthesize the sentence grammar and progression from the ground up. Output with > 75% verbatim word overlap with the input will be automatically rejected.');
    buffer.writeln('   - Keep 100% of underlying facts, proper nouns, figures, citations, and all [PROTECTED_xxx] tokens EXACTLY intact without hallucinating new claims.');
    buffer.writeln();
    buffer.writeln('### FEW-SHOT STRUCTURAL TRANSFORMATION DEMONSTRATION:');
    buffer.writeln('[ROBOTIC AI INPUT]:');
    buffer.writeln('"The Trojan War serves as the starting point for all the storylines in The Odyssey, and it seems that not one of the plot threads will be completed without a significant struggle. In Book 1, the gods are discussing the fate of Odysseus, who has been living on the island of Calypso for the past few years. Athena argues that it is time for Odysseus to return home to Ithaca."');
    buffer.writeln('[AUTHENTIC HUMAN REWRITE (< 10% AI)]:');
    buffer.writeln('"Every narrative arc in The Odyssey traces back to the Trojan War. None unfolds cleanly. Convening in Book 1 to weigh Odysseus’s fate, the gods debate his release after years of entrapment on Calypso’s shores. Athena demands an immediate homecoming, pressing for his return to Ithaca."');
    buffer.writeln();
    buffer.writeln('### STRICTLY FORBIDDEN AI HABITS & CLICHES:');
    buffer.writeln('- Starting with "In today\'s world" or "From X to Y". Start directly with the subject or an inverted clause.');
    buffer.writeln('- Overusing formulaic transitions: "Furthermore", "Moreover", "In conclusion", "On the other hand", "Specifically".');
    buffer.writeln('- Stock AI buzzwords: "testament", "tapestry", "beacon", "fosters", "interplay", "catalyst", "empower", "spearhead", "bolster", "harness", "leverage", "robust", "synergy", "landscape", "delve", "multifaceted", "sheds light on".');
    buffer.writeln();
    buffer.writeln('### MINI SETTINGS: WRITING TONE DIRECTIVE:');
    buffer.writeln(_buildToneInstruction(context.tone));
    buffer.writeln();
    buffer.writeln('### MINI SETTINGS: CONSTRAINT & LENGTH DIRECTIVE:');
    buffer.writeln(_buildStyleInstruction(context.style));
    buffer.writeln();
    buffer.writeln('### AUTHORIAL STYLE PROFILE:');
    buffer.writeln(context.styleProfile.toPromptInstructions());
    buffer.writeln();
    buffer.writeln('### INTENSITY CALIBRATION:');
    buffer.writeln('Intensity Level: ${context.intensity}% (Anti-detection bypass — dissolve formulaic scaffolding, apply high syntactic entropy, and guarantee < 10% AI likelihood).');
    buffer.writeln();
    buffer.writeln('### OUTPUT CONSTRAINT:');
    buffer.writeln('Return ONLY the rewritten target passage. Do NOT echo surrounding context, and do NOT include conversational preambles, markdown code fences, or explanatory notes.');
    return buffer.toString();
  }

  static String _buildToneInstruction(WritingToneProfile tone) {
    switch (tone) {
      case WritingToneProfile.academic:
        return 'Tone: ACADEMIC. Scholarly, analytically rigorous register. Use precise terminology, measured hedging ("suggests", "indicates"), and structured logic. Do NOT use colloquial contractions or chat residue. Retain technical discipline and citation framing.';
      case WritingToneProfile.professional:
        return 'Tone: PROFESSIONAL. Polished, authoritative executive diction. Clear, active voice, strategic clarity, and zero corporate buzzwords. Direct impact suitable for high-stakes business communication.';
      case WritingToneProfile.casual:
        return 'Tone: CASUAL. Natural, conversational everyday voice. Natural contractions ("don\'t", "can\'t", "it\'s") are encouraged. Friendly idioms, relaxed cadence, and relatable phrasing.';
      case WritingToneProfile.conversational:
        return 'Tone: CONVERSATIONAL. Warm spoken-word feel with human idiomatic flow. Natural rhetorical rhythm, comfortable pacing, and authentic voice that sounds natural when spoken aloud.';
      case WritingToneProfile.direct:
        return 'Tone: DIRECT / PUNCHY. Crisp, short, high-impact sentences. Cut every filler word. Deliver sharp assertions with zero preamble and maximum conciseness.';
      case WritingToneProfile.natural:
        return 'Tone: NATURAL / BALANCED. Authentic human cadence with maximum syntactic burstiness (CV > 0.55). Organic asymmetry across sentence length, openings, and cadence.';
    }
  }

  static String _buildStyleInstruction(String style) {
    switch (style.toLowerCase().trim()) {
      case 'concise':
        return 'Constraint: CONCISE. Target 70%–85% word count of the original passage. Aggressively prune redundant adjectives, filler prepositions, wordy clauses, and repetitive explanations. Maximum information density with zero fluff.';
      case 'detailed':
        return 'Constraint: DETAILED. Fully develop arguments over multiple well-crafted sentences. Thoroughly explain causal relationships, evidentiary context, and underlying nuances without superficial brevity.';
      case 'technical':
        return 'Constraint: TECHNICAL. Strictly preserve all domain-specific technical terminology, scientific nomenclature, formulas, and exact definitions. Prioritize mathematical and technical precision.';
      case 'simple':
        return 'Constraint: SIMPLE. Write in plain English (8th-grade reading level). Replace complicated Latinate vocabulary with familiar everyday words. Break long multi-clause sentences into straightforward, clear assertions.';
      case 'balanced':
      default:
        return 'Constraint: BALANCED. Standard natural narrative pacing. Maintain balanced sentence variety with a natural proportion of short and long clauses.';
    }
  }

  String _buildHierarchicalUserPrompt(ChunkRewriteContext context) {
    final buffer = StringBuffer();
    if (context.precedingContext.trim().isNotEmpty) {
      buffer.writeln('--- PRECEDING CONTEXT (READ-ONLY, DO NOT REWRITE OR OUTPUT) ---');
      buffer.writeln(context.precedingContext.trim());
      buffer.writeln('-------------------------------------------------------------');
      buffer.writeln();
    }

    buffer.writeln('>>> TARGET PASSAGE TO REWRITE (REWRITE ONLY THIS):');
    buffer.writeln(context.targetChunk.trim());
    buffer.writeln('<<< END TARGET PASSAGE');
    buffer.writeln();

    if (context.followingContext.trim().isNotEmpty) {
      buffer.writeln('--- FOLLOWING CONTEXT (READ-ONLY, DO NOT REWRITE OR OUTPUT) ---');
      buffer.writeln(context.followingContext.trim());
      buffer.writeln('------------------------------------------------------------');
      buffer.writeln();
    }

    if (context.detectorFeedback.trim().isNotEmpty) {
      buffer.writeln('### DETECTOR FEEDBACK & REJECTION DIRECTIVE:');
      buffer.writeln(context.detectorFeedback.trim());
      buffer.writeln('You MUST radically restructure these flagged parts with clause inversion, diverse sentence lengths (CV > 0.55), and fresh vocabulary while keeping facts identical.');
      buffer.writeln();
    }

    if (context.protectedPlaceholders.isNotEmpty) {
      buffer.writeln('Protected placeholders that must remain in your output:');
      buffer.writeln(context.protectedPlaceholders.join(', '));
      buffer.writeln();
    }

    buffer.writeln('REWRITE INSTRUCTIONS: Rewrite the target passage thoroughly applying clause inversion, high sentence length variance (CV > 0.55), and zero verbatim sentence mirroring. Preserve all facts and placeholders. Return solely the rewritten text.');
    return buffer.toString();
  }

  String _cleanLlmChunkOutput(String raw) {
    var cleaned = raw.trim();
    // Strip markdown code fences if wrapped
    if (cleaned.startsWith('```') && cleaned.endsWith('```')) {
      final lines = cleaned.split('\n');
      if (lines.length >= 2) {
        cleaned = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    // Strip common conversational preambles if present
    final preambleRegex = RegExp(
      r'^(?:Here(?:\x27s|\s+is)\s+(?:the\s+rewritten\s+(?:passage|text|chunk)|your\s+rewrite):?|Rewritten(?:\s+Target)?(?:\s+Passage)?:?)\s*',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceFirst(preambleRegex, '').trim();
    return cleaned;
  }
}

/// On-device algorithmic fallback model for offline tests or local transforms.
class LocalAlgorithmicHumanizerModel implements HumanizerModel {
  final LauviraHumanizeService _lauviraService;
  final AlgorithmicHumanizerService _algoService;

  LocalAlgorithmicHumanizerModel({
    LauviraHumanizeService? lauviraService,
    AlgorithmicHumanizerService? algoService,
  })  : _lauviraService = lauviraService ?? LauviraHumanizeService(),
        _algoService = algoService ?? const AlgorithmicHumanizerService();

  @override
  String get name => 'Local Algorithmic Model';

  @override
  int get maxContextTokens => 2048;

  @override
  Future<String> rewriteChunk(ChunkRewriteContext context) async {
    final neuralResult = await _lauviraService.humanizeLlmOutput(
      context.targetChunk,
      tone: context.tone,
      style: context.style,
      originalText: context.targetChunk,
      intensity: context.intensity,
    );

    return _algoService.postProcess(
      neuralResult,
      tone: context.tone,
      style: context.style,
      intensity: context.intensity,
    );
  }
}
