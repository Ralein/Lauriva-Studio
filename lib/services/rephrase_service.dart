import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/llm_provider.dart';
import 'llm_service.dart';

/// Represents an identified sentence boundary within a larger document.
class SentenceSpan {
  final String text;
  final int startIndex;
  final int endIndex;

  const SentenceSpan({
    required this.text,
    required this.startIndex,
    required this.endIndex,
  });

  @override
  String toString() => 'SentenceSpan($startIndex..$endIndex: "$text")';
}

/// A stylistic rephrase suggestion with category metadata.
class RephraseOption {
  final String text;
  final String styleLabel;
  final String description;

  const RephraseOption({
    required this.text,
    required this.styleLabel,
    required this.description,
  });
}

/// Decoupled editorial service that parses text selections into words/sentences
/// and generates contextual rephrase alternatives via LLM or on-device lexical rules.
class RephraseService {
  final LlmService _llmService;

  RephraseService({LlmService? llmService})
      : _llmService = llmService ?? LlmService();

  /// Curated on-device thesaurus for instant zero-latency word replacements,
  /// specializing in common AI tells, academic boilerplate, and power verbs.
  static final Map<String, List<String>> _thesaurus = {
    'delve': ['explore', 'examine', 'look into', 'investigate'],
    'delving': ['exploring', 'examining', 'looking into', 'investigating'],
    'crucial': ['essential', 'vital', 'key', 'important'],
    'pivotal': ['central', 'decisive', 'critical', 'key'],
    'demonstrate': ['show', 'reveal', 'illustrate', 'prove'],
    'demonstrates': ['shows', 'reveals', 'illustrates', 'proves'],
    'demonstrated': ['showed', 'revealed', 'illustrated', 'proved'],
    'utilize': ['use', 'apply', 'employ', 'adopt'],
    'utilizes': ['uses', 'applies', 'employs', 'adopts'],
    'utilized': ['used', 'applied', 'employed', 'adopted'],
    'utilizing': ['using', 'applying', 'employing', 'adopting'],
    'moreover': ['in addition', 'also', 'besides', 'further'],
    'furthermore': ['in addition', 'also', 'what is more', 'besides'],
    'additionally': ['also', 'in addition', 'plus', 'besides'],
    'nevertheless': ['however', 'even so', 'still', 'yet'],
    'nonetheless': ['however', 'even so', 'still', 'yet'],
    'consequently': ['as a result', 'therefore', 'so', 'thus'],
    'therefore': ['so', 'as a result', 'thus', 'for this reason'],
    'significant': ['notable', 'major', 'meaningful', 'substantial'],
    'foster': ['encourage', 'promote', 'support', 'nurture'],
    'fosters': ['encourages', 'promotes', 'supports', 'nurtures'],
    'fostering': ['encouraging', 'promoting', 'supporting', 'nurturing'],
    'robust': ['strong', 'solid', 'reliable', 'sturdy'],
    'leverage': ['use', 'harness', 'take advantage of', 'maximize'],
    'leveraging': ['using', 'harnessing', 'drawing on', 'maximizing'],
    'tapestry': ['blend', 'combination', 'network', 'mosaic'],
    'testament': ['proof', 'evidence', 'indication', 'reflection'],
    'intricate': ['complex', 'detailed', 'layered', 'nuanced'],
    'paramount': ['most important', 'top priority', 'vital', 'essential'],
    'seamlessly': ['smoothly', 'easily', 'flawlessly', 'naturally'],
    'streamline': ['simplify', 'optimize', 'speed up', 'clarify'],
    'streamlining': ['simplifying', 'optimizing', 'speeding up', 'clarifying'],
    'enhance': ['improve', 'boost', 'upgrade', 'strengthen'],
    'enhances': ['improves', 'boosts', 'upgrades', 'strengthens'],
    'enhancing': ['improving', 'boosting', 'upgrading', 'strengthening'],
    'underscore': ['highlight', 'emphasize', 'stress', 'reinforce'],
    'underscores': ['highlights', 'emphasizes', 'stresses', 'reinforces'],
    'underscoring': ['highlighting', 'emphasizing', 'stressing', 'reinforcing'],
    'navigate': ['handle', 'manage', 'work through', 'deal with'],
    'navigating': ['handling', 'managing', 'working through', 'dealing with'],
    'holistic': ['comprehensive', 'well-rounded', 'broad', 'complete'],
    'unravel': ['solve', 'uncover', 'explain', 'clarify'],
    'exemplify': ['illustrate', 'show', 'represent', 'typify'],
    'exemplifies': ['illustrates', 'shows', 'represents', 'typifies'],
    'groundbreaking': ['innovative', 'pioneering', 'novel', 'fresh'],
    'plethora': ['wide variety', 'abundance', 'wealth', 'host'],
    'vibrant': ['lively', 'dynamic', 'active', 'spirited'],
    'multifaceted': ['complex', 'diverse', 'broad', 'versatile'],
    'transformative': ['game-changing', 'profound', 'major', 'pivotal'],
    'subsequently': ['later', 'next', 'then', 'afterwards'],
    'predominantly': ['mainly', 'mostly', 'primarily', 'chiefly'],
    'comprehensive': ['thorough', 'complete', 'detailed', 'broad'],
    'facilitate': ['help', 'enable', 'ease', 'support'],
    'facilitates': ['helps', 'enables', 'eases', 'supports'],
    'implement': ['put into practice', 'apply', 'carry out', 'deploy'],
    'implementing': ['putting into practice', 'applying', 'carrying out', 'deploying'],
    'meticulous': ['careful', 'thorough', 'precise', 'detailed'],
    'meticulously': ['carefully', 'thoroughly', 'precisely', 'in detail'],
  };

  /// Check if the supplied string is a single word (no internal spaces).
  bool isSingleWord(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return !trimmed.contains(RegExp(r'\s+'));
  }

  /// Split full prose into constituent sentences with exact character offsets.
  List<SentenceSpan> extractSentenceSpans(String text) {
    final spans = <SentenceSpan>[];
    if (text.trim().isEmpty) return spans;

    // Boundary regex that avoids splitting on common honorifics/abbreviations
    final pattern = RegExp(
      r"""(?<=[.!?])\s+(?=[A-Z0-9"“'])|(?<=\n)\s*""",
      multiLine: true,
    );

    int currentStart = 0;
    final matches = pattern.allMatches(text);

    for (final match in matches) {
      final sentence = text.substring(currentStart, match.start).trim();
      if (sentence.isNotEmpty) {
        // Find exact start in text after trimming leading whitespace
        final exactStart = text.indexOf(sentence, currentStart);
        spans.add(SentenceSpan(
          text: sentence,
          startIndex: exactStart,
          endIndex: exactStart + sentence.length,
        ));
      }
      currentStart = match.end;
    }

    if (currentStart < text.length) {
      final remaining = text.substring(currentStart).trim();
      if (remaining.isNotEmpty) {
        final exactStart = text.indexOf(remaining, currentStart);
        spans.add(SentenceSpan(
          text: remaining,
          startIndex: exactStart,
          endIndex: exactStart + remaining.length,
        ));
      }
    }

    // Fallback if no punctuation boundaries were matched
    if (spans.isEmpty && text.trim().isNotEmpty) {
      spans.add(SentenceSpan(
        text: text.trim(),
        startIndex: 0,
        endIndex: text.trim().length,
      ));
    }

    return spans;
  }

  /// Locate the enclosing sentence span that wraps a given character range.
  SentenceSpan findEnclosingSentence(String fullText, int startIndex, int endIndex) {
    final sentences = extractSentenceSpans(fullText);
    if (sentences.isEmpty) {
      return SentenceSpan(text: fullText, startIndex: 0, endIndex: fullText.length);
    }

    final safeStart = startIndex.clamp(0, fullText.length);
    final safeEnd = endIndex.clamp(safeStart, fullText.length);

    for (final s in sentences) {
      if (s.startIndex <= safeStart && s.endIndex >= safeEnd) {
        return s;
      }
    }

    // If partial overlap or adjacent, find closest sentence
    for (final s in sentences) {
      if (s.startIndex <= safeEnd && s.endIndex >= safeStart) {
        return s;
      }
    }

    return sentences.first;
  }

  /// Generate contextual rephrase alternatives for a targeted word or sentence.
  Future<List<RephraseOption>> getRephraseOptions({
    required String selectedText,
    required String fullText,
    int? startIndex,
    int? endIndex,
    LlmProvider? provider,
    String? apiKey,
    String? model,
    String? customBaseUrl,
  }) async {
    final cleanTarget = selectedText.trim();
    if (cleanTarget.isEmpty) return const [];

    final isWord = isSingleWord(cleanTarget);
    final enclosing = (startIndex != null && endIndex != null)
        ? findEnclosingSentence(fullText, startIndex, endIndex)
        : null;
    final surroundingContext = enclosing?.text ?? cleanTarget;

    // 1. If an LLM provider and API key are available, query for high-fidelity alternatives
    if (provider != null && apiKey != null && apiKey.trim().isNotEmpty) {
      try {
        final llmOptions = await _fetchLlmRephrase(
          targetText: cleanTarget,
          surroundingContext: surroundingContext,
          isWord: isWord,
          provider: provider,
          apiKey: apiKey,
          model: model,
          customBaseUrl: customBaseUrl,
        );
        if (llmOptions.isNotEmpty) {
          return llmOptions;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RephraseService] LLM rephrase failed, falling back to local: $e');
        }
      }
    }

    // 2. Offline / Heuristic local fallback
    if (isWord) {
      return _generateLocalWordOptions(cleanTarget);
    } else {
      return _generateLocalSentenceOptions(cleanTarget);
    }
  }

  /// Calls the active LLM provider with a targeted prompt to return structured JSON alternatives.
  Future<List<RephraseOption>> _fetchLlmRephrase({
    required String targetText,
    required String surroundingContext,
    required bool isWord,
    required LlmProvider provider,
    required String apiKey,
    String? model,
    String? customBaseUrl,
  }) async {
    final prompt = isWord
        ? 'You are an expert editorial wordsmith. The user highlighted the word "$targetText" inside this sentence: "$surroundingContext". '
          'Provide 4 distinct, highly natural synonyms or short substitute phrases that fit into this exact context. '
          'Output ONLY a valid JSON array of 4 strings with no explanation, markdown formatting, or preamble. '
          'Example format: ["substitute1", "substitute2", "substitute3", "substitute4"]'
        : 'You are a master editorial prose rephraser. The user highlighted this target text: "$targetText" '
          'within this surrounding context: "$surroundingContext". '
          'Rewrite the highlighted text in 3 distinct stylistic variants that preserve the exact original meaning and fit seamlessly into context: '
          '1. Natural: Fluent, engaging, authentic human cadence. '
          '2. Concise: Crisp, punchy, active voice with zero filler words. '
          '3. Formal: Polished, professional, and authoritative. '
          'Output ONLY a valid JSON array of exactly 3 strings with no explanation, no markdown ticks, and no commentary. '
          'Example format: ["natural variation", "concise variation", "formal variation"]';

    final result = await _llmService.transformText(
      provider: provider,
      apiKey: apiKey,
      featureId: 'Rephrase',
      text: targetText,
      customSystemPrompt: prompt,
      model: model,
      customBaseUrl: customBaseUrl,
      params: const LlmGenerationParams(
        temperature: 0.75,
        maxTokens: 350,
      ),
    );

    return _parseLlmJsonArray(result, isWord, targetText);
  }

  /// Parses the raw JSON array output from an LLM call.
  List<RephraseOption> _parseLlmJsonArray(String raw, bool isWord, String original) {
    try {
      var cleaned = raw.trim();
      final startIdx = cleaned.indexOf('[');
      final endIdx = cleaned.lastIndexOf(']');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        cleaned = cleaned.substring(startIdx, endIdx + 1);
      }

      final dynamic decoded = jsonDecode(cleaned);
      if (decoded is List) {
        final strings = decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty && s.toLowerCase() != original.toLowerCase())
            .toList();

        if (isWord) {
          const labels = ['Natural Synonym', 'Simpler Term', 'Contextual Fit', 'Refined Choice'];
          return List.generate(strings.length, (i) {
            final label = i < labels.length ? labels[i] : 'Alternative';
            return RephraseOption(
              text: _preserveCase(strings[i], original),
              styleLabel: label,
              description: 'Contextual word alternative',
            );
          });
        } else {
          const styles = [
            ('Natural & Flowing', 'Authentic human cadence and smooth transitions'),
            ('Crisp & Direct', 'Active voice, concise, and straight to the point'),
            ('Polished & Formal', 'Structured, authoritative executive tone'),
          ];
          return List.generate(strings.length, (i) {
            final (label, desc) = i < styles.length ? styles[i] : ('Variation ${i + 1}', 'Alternative phrasing');
            return RephraseOption(
              text: strings[i],
              styleLabel: label,
              description: desc,
            );
          });
        }
      }
    } catch (_) {}

    return const [];
  }

  /// Local on-device thesaurus lookup for single words.
  List<RephraseOption> _generateLocalWordOptions(String word) {
    final lower = word.toLowerCase();
    final matches = _thesaurus[lower];

    if (matches != null && matches.isNotEmpty) {
      return matches.map((synonym) {
        return RephraseOption(
          text: _preserveCase(synonym, word),
          styleLabel: 'Synonym',
          description: 'Contextual replacement',
        );
      }).toList();
    }

    // Heuristic fallbacks for common suffixes
    final options = <RephraseOption>[];
    if (lower.endsWith('ly')) {
      final base = lower.substring(0, lower.length - 2);
      options.add(RephraseOption(
        text: _preserveCase('in a $base way', word),
        styleLabel: 'Descriptive',
        description: 'Expanded phrasing',
      ));
    }

    return options;
  }

  /// Rule-based local fallback for sentences when offline.
  List<RephraseOption> _generateLocalSentenceOptions(String sentence) {
    final options = <RephraseOption>[];

    // Variant 1: Natural (strip leading formal connectors)
    var natural = sentence;
    final connectorRegex = RegExp(
      r'^(?:Furthermore|Moreover|Additionally|In addition|Nevertheless|Consequently|Therefore|Notably|Importantly),\s*',
      caseSensitive: false,
    );
    if (connectorRegex.hasMatch(natural)) {
      natural = natural.replaceFirst(connectorRegex, '');
      if (natural.isNotEmpty) {
        natural = natural[0].toUpperCase() + natural.substring(1);
      }
      options.add(RephraseOption(
        text: natural,
        styleLabel: 'Natural & Flowing',
        description: 'Removed formulaic AI connector for human rhythm',
      ));
    }

    // Variant 2: Concise (trim passive/filler phrasing)
    var concise = sentence;
    final fillerReplacements = {
      RegExp(r'\bit is worth noting that\b', caseSensitive: false): '',
      RegExp(r'\bit is important to remember that\b', caseSensitive: false): '',
      RegExp(r'\bin order to\b', caseSensitive: false): 'to',
      RegExp(r'\bdue to the fact that\b', caseSensitive: false): 'because',
      RegExp(r'\butilize\b', caseSensitive: false): 'use',
      RegExp(r'\bdelve into\b', caseSensitive: false): 'explore',
      RegExp(r'\bplays a crucial role in\b', caseSensitive: false): 'shapes',
    };
    for (final entry in fillerReplacements.entries) {
      concise = concise.replaceAll(entry.key, entry.value);
    }
    concise = concise.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (concise != sentence && concise.isNotEmpty) {
      options.add(RephraseOption(
        text: concise,
        styleLabel: 'Crisp & Direct',
        description: 'Eliminated redundant fillers and streamlined verbs',
      ));
    }

    // Variant 3: Formal
    var formal = sentence;
    if (!formal.startsWith(RegExp(r'[A-Z]'))) {
      formal = formal.isEmpty ? formal : formal[0].toUpperCase() + formal.substring(1);
    }
    options.add(RephraseOption(
      text: formal,
      styleLabel: 'Polished',
      description: 'Cleaned sentence punctuation and structure',
    ));

    return options;
  }

  /// Preserves the capitalization of the original word on the replacement.
  static String _preserveCase(String replacement, String original) {
    if (original.isEmpty || replacement.isEmpty) return replacement;
    if (original == original.toUpperCase()) {
      return replacement.toUpperCase();
    }
    if (original[0] == original[0].toUpperCase()) {
      return replacement[0].toUpperCase() + replacement.substring(1);
    }
    return replacement.toLowerCase();
  }

  /// Safely replaces a target range in [originalText] with [replacement].
  String applyReplacement({
    required String originalText,
    required int startIndex,
    required int endIndex,
    required String replacement,
    String? fallbackTarget,
  }) {
    if (originalText.isEmpty) return replacement;

    if (startIndex >= 0 &&
        endIndex <= originalText.length &&
        startIndex <= endIndex) {
      return originalText.replaceRange(startIndex, endIndex, replacement);
    }

    // Boundary fallback: Find exact match of fallbackTarget if range shifted
    if (fallbackTarget != null && fallbackTarget.isNotEmpty) {
      final idx = originalText.indexOf(fallbackTarget);
      if (idx != -1) {
        return originalText.replaceRange(idx, idx + fallbackTarget.length, replacement);
      }
    }

    return originalText;
  }
}
