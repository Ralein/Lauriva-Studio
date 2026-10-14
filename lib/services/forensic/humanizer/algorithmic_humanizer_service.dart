import 'dart:math';
import '../../ai_forensic_service.dart';
import '../../text_forensics_lexicons.dart';
import 'lora_stylistic_adapter.dart';
import 'semantic_preservation_verifier.dart';

/// Writing tone profiles for user-controlled stylistic modulation.
enum WritingToneProfile {
  professional,
  academic,
  casual,
  conversational,
  direct,
  natural;

  static WritingToneProfile fromString(String? val) {
    if (val == null) return WritingToneProfile.professional;
    final lower = val.toLowerCase().trim();
    for (final tone in WritingToneProfile.values) {
      if (tone.name.toLowerCase() == lower) return tone;
    }
    return WritingToneProfile.professional;
  }
}

/// Algorithmic Humanizer Service
///
/// Implements deterministic code transformations to eliminate synthetic AI signals:
/// 1. Transition Purging: Strips formal transition sentence openers (Moreover, Furthermore, etc.).
/// 2. Lexical Detoxification: Substitutes high-frequency AI stock words, academic boilerplate, and sales puffery.
/// 3. Structural De-Staging: Dissolves formulaic "not only... but also..." and faux-dramatic constructs.
/// 4. Punctuation Realignment: Tames em-dash overuse and artificial triad structures.
/// 5. Burstiness Optimization: Dynamically modulates sentence lengths to ensure high variance (CV >= 0.40).
/// 6. Tone Modulation: Applies register-specific refinements (contractions for conversational, precision for academic).
class AlgorithmicHumanizerService {
  const AlgorithmicHumanizerService();

  static final RegExp _protectedBlockPattern = RegExp(
    r'(```[\s\S]*?```|`[^`\n]+`|\$\$[\s\S]*?\$\$|\$(?!\$)[^\n\$]+\$|https?:\/\/[^\s\)\],]+|\[\^[^\]\n]+\]|\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b|\((?:[A-Z][a-zA-Z\s\.\-]+(?:et\s+al\.?)?,?\s*(?:19|20)\d{2}[a-z]?|[A-Z][a-zA-Z\s\.\-]+\s+\d{1,4})\)|\[\^?[A-Za-z0-9]+(?:[\s,\-–][A-Za-z0-9]+)*\])',
  );

  /// Executes [transformer] on [text] while masking code blocks, inline code,
  /// LaTeX math, and URLs so they are never altered by lexical or structural passes.
  String _executeWithProtectedSpans(String text, String Function(String prose) transformer) {
    if (text.trim().isEmpty) return text;
    final protectedSpans = <String>[];
    final masked = text.replaceAllMapped(_protectedBlockPattern, (m) {
      final span = m.group(0)!;
      final placeholder = '⟦LAURIVA_PROTECTED_${protectedSpans.length}⟧';
      protectedSpans.add(span);
      return placeholder;
    });

    var transformed = transformer(masked);

    for (int i = 0; i < protectedSpans.length; i++) {
      transformed = transformed.replaceAll('⟦LAURIVA_PROTECTED_$i⟧', protectedSpans[i]);
    }
    return transformed;
  }

  /// Executes the humanization pipeline with closed-loop audit and iterative healing.
  ///
  /// Evaluates on-device AI authorship indicators, applies deep burstiness
  /// modulation if risk remains elevated, and gates all changes through the
  /// Semantic Meaning Guard to guarantee factual, numerical, and polarity invariance.
  String postProcessWithQualityLoop(
    String text, {
    WritingToneProfile tone = WritingToneProfile.professional,
    String style = 'balanced',
    String? originalText,
    AiForensicService? forensicService,
    SemanticPreservationVerifier? verifier,
  }) {
    final cleaned = postProcess(text, tone: tone, style: style);
    if (cleaned.trim().isEmpty) return cleaned;

    final forensic = forensicService ?? AiForensicService();
    final v = verifier ?? SemanticPreservationVerifier();

    try {
      final audit = forensic.auditText(cleaned);
      if (audit.aiProbability > 10.0) {
        // High-entropy healing pass to drive score below 10%
        final healed = _executeWithProtectedSpans(cleaned, (maskedCleaned) {
          final healedBurstiness = optimizeBurstiness(maskedCleaned, minCv: 0.55);
          return cleanPunctuationAndSpacing(
            applyStyleConstraintModulation(
              diversifyConsecutiveSentenceStarters(
                stripAiTransitions(
                  replaceAiStockPhrases(
                    dissolvePassiveCopulas(
                      dissolveFauxCandorOpeners(
                        dissolveContrastAndStaging(healedBurstiness),
                      ),
                    ),
                    tone: tone,
                  ),
                  tone: tone,
                ),
              ),
              style,
            ),
          );
        });
        final recap = _recapitalizeSentenceStarts(healed);

        if (originalText != null && originalText.trim().isNotEmpty) {
          final guard = v.verify(originalText: originalText, humanizedText: recap);
          if (!guard.hasNumericalDrift && !guard.hasCitationLoss && !guard.hasPolarityDrift) {
            return recap;
          }
        } else {
          return recap;
        }
      }
    } catch (_) {
      // Best effort quality healing
    }

    return cleaned;
  }

  /// Executes the complete deterministic humanization pipeline on [text] with optional [tone] and [style].
  ///
  /// Runs block-by-block (paragraphs and line-separated items) and re-joins
  /// with the original separators, so paragraph structure survives. The
  /// sentence-level passes re-join sentences with spaces, which previously
  /// flattened a multi-paragraph document into a single block.
  String postProcess(
    String text, {
    WritingToneProfile tone = WritingToneProfile.professional,
    String style = 'balanced',
    int intensity = 85,
  }) {
    if (text.trim().isEmpty) return text;

    return _executeWithProtectedSpans(text, (maskedText) {
      final out = StringBuffer();
      int cursor = 0;
      for (final sep in RegExp(r'\s*\n\s*').allMatches(maskedText)) {
        out.write(_postProcessBlock(maskedText.substring(cursor, sep.start), tone, style: style, intensity: intensity));
        out.write(RegExp(r'\n\s*\n').hasMatch(sep.group(0)!) ? '\n\n' : '\n');
        cursor = sep.end;
      }
      out.write(_postProcessBlock(maskedText.substring(cursor), tone, style: style, intensity: intensity));
      return out.toString().trim();
    });
  }

  String _postProcessBlock(
    String block,
    WritingToneProfile tone, {
    String style = 'balanced',
    int intensity = 85,
  }) {
    if (block.trim().isEmpty) return block.trim();
    // Markdown list items / headings are structure, not prose: only apply
    // the lexical passes so bullets are never merged or split.
    final isStructural = RegExp(r'^\s*(?:[-*•]\s+|\d+[.)]\s+|#{1,6}\s+)').hasMatch(block);

    // Phase 0: Strip any chatbot residue first
    String result = dissolveChatbotResidue(block);

    // Phase 1: Detoxify stock vocabulary and cliches first
    result = replaceAiStockPhrases(result, tone: tone);
    result = _recapitalizeSentenceStarts(result);

    // Phase 2: Dissolve contrast formulas and staging
    result = dissolveContrastAndStaging(result);

    // Phase 2.1: Dissolve staged domain sweep openers (From X to Y, In today's fast-paced world, etc.)
    result = dissolveStagedOpeners(result);

    // Phase 2.2: Dissolve phantom arguments (with polarity preservation)
    result = dissolvePhantomArguments(result);

    // Phase 2.3: Dissolve faux-candor conversational openers
    result = dissolveFauxCandorOpeners(result);

    // Phase 2.4: Dissolve inflated passive copulas
    result = dissolvePassiveCopulas(result);

    // Phase 2.5: Dissolve faux-profound aphorisms
    result = dissolveAphorismsAndDeepSayings(result);

    // Phase 2.55: Dissolve stacked qualifiers and hyphenated predicate pairs
    result = dissolveStackedQualifiers(result);
    result = dissolveHyphenatedPredicatePairs(result);

    if (!isStructural) {
      // Phase 2.6: Dissolve shallow trailing -ing participle tails
      result = dissolveParticipialTails(result);

      // Phase 2.7: Dissolve predictable 3-beat parallel gerund triads
      result = dissolveParallelTriads(result);

      // Phase 3: Strip or soften robotic AI transitions at sentence openers
      result = stripAiTransitions(result, tone: tone);
    }

    // Phase 4: Tone-specific syntactic modulation (e.g. contractions for casual/conversational)
    result = applyToneModulation(result, tone);

    // Phase 4.5: Mini Settings constraint & length modulation (concise, simple, technical, detailed, balanced)
    result = applyStyleConstraintModulation(result, style);

    // Phase 5: Regulate em-dash proliferation
    result = regulatePunctuation(result);

    // Recapitalize before sentence splitting so splitSentences detects all periods
    result = _recapitalizeSentenceStarts(result);

    if (!isStructural) {
      // Phase 6: Optimize burstiness (sentence length variance scaled by intensity calibrated with Kaggle empirical distributions)
      final baseCv = tone == WritingToneProfile.natural ? 0.50 : 0.48;
      final targetCv = (baseCv + ((intensity - 50) / 100.0) * 0.16).clamp(0.46, 0.62);
      result = optimizeBurstiness(result, minCv: targetCv);

      // Phase 7: Final pass to purge any transition openers exposed by splitting
      result = stripAiTransitions(result, tone: tone);

      // Phase 7.5: Diversify repetitive consecutive sentence starters
      result = diversifyConsecutiveSentenceStarters(result);

      // Phase 7.6: Dissolve one-line closers and platitudes
      result = dissolveOneLineClosers(result);
    }

    // Phase 8: Final whitespace, punctuation, and sentence-case polish
    result = cleanPunctuationAndSpacing(result);
    return _recapitalizeSentenceStarts(result);
  }

  /// Scores a candidate sentence transformation using the on-device LoRA Rank-8 tensor.
  /// Used to rank multiple candidate paraphrases or structural edits.
  double scoreTransformWithLora({
    required String original,
    required String candidate,
    bool removedTransition = false,
    bool invertedVoice = false,
    double semanticCosine = 0.96,
    double perplexityDelta = 25.0,
    bool addedPersonalPronoun = false,
    bool insertedContraction = false,
    bool brokenRepetition = false,
    bool simplifiedClause = false,
  }) {
    final features = LoraStylisticAdapter.extractFeatures(
      originalLength: original.split(RegExp(r'\s+')).length,
      candidateLength: candidate.split(RegExp(r'\s+')).length,
      removedTransition: removedTransition,
      invertedVoice: invertedVoice,
      semanticCosine: semanticCosine,
      perplexityDelta: perplexityDelta,
      addedPersonalPronoun: addedPersonalPronoun,
      insertedContraction: insertedContraction,
      brokenRepetition: brokenRepetition,
      simplifiedClause: simplifiedClause,
    );
    return LoraStylisticAdapter.scoreCandidate(features);
  }

  /// Diversifies consecutive sentence starters (e.g. "This... This..." or "The... The...")
  /// to break predictable auto-regressive Markov chain patterns.
  String diversifyConsecutiveSentenceStarters(String text) {
    final sentences = TextForensicsLexicons.splitSentences(text);
    if (sentences.length < 2) return text;

    final result = <String>[];
    String prevFirstWord = '';

    for (int i = 0; i < sentences.length; i++) {
      var s = sentences[i].trim();
      final match = RegExp(r'^([A-Za-z]+)\b').firstMatch(s);
      if (match != null) {
        final firstWord = match.group(1)!;
        final lower = firstWord.toLowerCase();
        if (i > 0 && lower == prevFirstWord.toLowerCase()) {
          if (lower == 'this' && s.length > 5) {
            final secondWordMatch = RegExp(r'^this\s+([a-zA-Z]+)', caseSensitive: false).firstMatch(s);
            final nextWord = secondWordMatch?.group(1)?.toLowerCase() ?? '';
            const verbs = {'lets', 'makes', 'allows', 'helps', 'means', 'creates', 'shows', 'proves', 'gives', 'leads', 'results', 'ensures', 'is', 'was', 'can', 'will', 'could', 'would'};
            if (verbs.contains(nextWord)) {
              s = 'It ${s.substring(5).trim()}';
            } else {
              s = 'The ${s.substring(5).trim()}';
            }
          } else if (lower == 'these' && s.length > 6) {
            s = 'Such ${s.substring(6).trim()}';
          } else if (lower == 'first' && s.length > 6) {
            s = 'Initially, ${s.substring(6).trim()}';
          } else if (lower == 'then' && s.length > 5) {
            s = 'Next, ${s.substring(5).trim()}';
          } else if (lower == 'such' && s.length > 5) {
            s = 'These ${s.substring(5).trim()}';
          } else if (lower == 'during' && s.length > 7) {
            s = 'In ${s.substring(7).trim()}';
          } else if (lower == 'he' && s.length > 3) {
            s = 'Later, he ${s.substring(3).trim()}';
          } else if (lower == 'she' && s.length > 4) {
            s = 'Later, she ${s.substring(4).trim()}';
          }
        }
        final newMatch = RegExp(r'^([A-Za-z]+)\b').firstMatch(s);
        prevFirstWord = newMatch?.group(1) ?? firstWord;
      }
      result.add(s);
    }
    return result.join(' ');
  }

  /// Converts shallow trailing participle riders (e.g. ", highlighting the importance of X")
  /// into independent active declarative sentences with authentic human verbs (e.g. ". This shows the importance of X.").
  String dissolveParticipialTails(String text) {
    final tailPattern = RegExp(
      r',\s+(highlighting|underscoring|emphasizing|ensuring|reflecting|symbolizing|fostering|showcasing|demonstrating|illustrating|signaling|exemplifying|reinforcing|solidifying|cementing|accentuating)\s+([^.!?]+)',
      caseSensitive: false,
    );

    return text.replaceAllMapped(tailPattern, (match) {
      final verbIng = match.group(1)!.toLowerCase();
      final rest = match.group(2)!.trim();
      final activeVerb = switch (verbIng) {
        'highlighting' => 'highlights',
        'underscoring' => 'shows',
        'emphasizing' => 'highlights',
        'ensuring' => 'helps ensure',
        'reflecting' => 'reflects',
        'symbolizing' => 'represents',
        'fostering' => 'encourages',
        'showcasing' => 'shows',
        'demonstrating' => 'demonstrates',
        'illustrating' => 'illustrates',
        'signaling' => 'signals',
        'exemplifying' => 'shows',
        'reinforcing' => 'strengthens',
        'solidifying' => 'secures',
        'cementing' => 'confirms',
        'accentuating' => 'draws attention to',
        _ => 'shows',
      };
      return '. This $activeVerb $rest';
    });
  }

  /// Pure filler openers: deleting them never changes the claim.
  static final RegExp _fillerOpener = RegExp(
    r"^(Furthermore|Moreover|Additionally|In addition|What is more|Notably|Crucially|Importantly|Evidently|Significantly|In particular|It is important to note that|It is worth noting that|It is crucial to recognize that|It is crucial to remember that|It is worth emphasizing that|It is worth mentioning that|It is essential to recognize that|It should be noted that|Needless to say|Without a doubt|At its core|In today's landscape|In today's fast-paced world|In today's digital world|In the grand scheme of things|Looking ahead|To conclude|In conclusion|To summarize|To sum up|In summary|To wrap up|In closing|Taking everything into account|All in all|All things considered|Overall)[,\s]+",
    caseSensitive: false,
  );

  /// Openers that carry logic (cause, concession, contrast, sequence).
  /// Deleting them silently changes what the text argues ("Therefore, X"
  /// asserts X follows from the previous sentence), so they are swapped for
  /// plainer connectors that keep the relation. Each entry rotates through
  /// variants so the output doesn't trade one repeated opener for another.
  static const Map<String, List<String>> _logicalOpeners = {
    'however': ['Yet', 'Still', 'Even so', 'At the same time'],
    'therefore': ['So', 'That is why', 'Because of this'],
    'consequently': ['So', 'As a result of this', 'Because of that'],
    'hence': ['So', 'That is why'],
    'as a result': ['So', 'Because of this'],
    'thus': ['So', 'That way'],
    'nevertheless': ['Still', 'Even so'],
    'nonetheless': ['Still', 'Even so'],
    'conversely': ['By contrast', 'On the flip side'],
    'on the other hand': ['But', 'Then again'],
    'ultimately': ['In the end', 'Eventually'],
    'firstly': ['First'],
    'secondly': ['Second'],
    'thirdly': ['Third'],
  };

  /// Formal register keeps a formal connector; casual registers get the
  /// shortest one.
  static const Map<String, String> _academicLogical = {
    'however': 'Yet',
    'therefore': 'For this reason',
    'consequently': 'For this reason',
    'hence': 'For this reason',
    'as a result': 'As a result of this',
    'thus': 'In this way',
    'nevertheless': 'Even so',
    'nonetheless': 'Even so',
    'conversely': 'By contrast',
    'on the other hand': 'By contrast',
    'ultimately': 'In the end',
    'firstly': 'First',
    'secondly': 'Second',
    'thirdly': 'Third',
  };

  static final RegExp _logicalOpener = RegExp(
    r'^(However|Therefore|Consequently|Hence|As a result|Thus|Nevertheless|Nonetheless|Conversely|On the other hand|Ultimately|Firstly|Secondly|Thirdly)(,\s*|\s+)',
    caseSensitive: false,
  );

  /// Strips filler transitions from sentence openers and softens logical
  /// ones (Therefore, Nevertheless, ...) to plain connectors that preserve
  /// the argument's structure.
  String stripAiTransitions(String text, {WritingToneProfile tone = WritingToneProfile.professional}) {
    final sentences = TextForensicsLexicons.splitSentences(text);
    if (sentences.isEmpty) return text;

    final formal = tone == WritingToneProfile.academic || tone == WritingToneProfile.professional;
    final rotation = <String, int>{};
    final modifiedSentences = <String>[];
    for (final sentence in sentences) {
      String s = sentence.trim();

      final filler = _fillerOpener.firstMatch(s);
      if (filler != null) {
        s = _capitalizeFirst(s.substring(filler.end).trim());
      } else {
        final logical = _logicalOpener.firstMatch(s);
        if (logical != null) {
          final key = logical.group(1)!.toLowerCase();
          final rest = s.substring(logical.end).trim();
          if (rest.isNotEmpty) {
            final String replacement;
            if (formal) {
              replacement = _academicLogical[key]!;
            } else {
              final variants = _logicalOpeners[key]!;
              final idx = rotation[key] ?? 0;
              rotation[key] = idx + 1;
              replacement = variants[idx % variants.length];
            }
            // "But" reads naturally without a comma; everything else keeps
            // it ("So many companies..." would read as "so many").
            final comma = replacement == 'But' ? ' ' : ', ';
            s = '$replacement$comma${_lowercaseFirstUnlessProper(rest)}';
          }
        }
      }
      if (s.isNotEmpty) {
        modifiedSentences.add(s);
      }
    }

    return modifiedSentences.join(' ');
  }

  String _capitalizeFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Lowercases the first letter of a clause that is being moved behind a
  /// connector, unless it looks like a proper noun, acronym, or "I".
  String _lowercaseFirstUnlessProper(String s) {
    if (s.isEmpty) return s;
    final firstWord = RegExp(r"^[A-Za-z']+").firstMatch(s)?.group(0) ?? '';
    if (firstWord.isEmpty) return s;
    const lowerable = {
      'the', 'a', 'an', 'this', 'that', 'these', 'those', 'it', 'its', 'they',
      'their', 'we', 'our', 'you', 'your', 'he', 'she', 'his', 'her', 'there',
      'many', 'most', 'some', 'each', 'every', 'all', 'such', 'one', 'both',
      'if', 'when', 'while', 'because', 'since', 'although', 'as', 'in', 'on',
      'at', 'for', 'by', 'with', 'without', 'after', 'before', 'no', 'not',
      'more', 'less', 'few', 'several', 'any', 'other', 'another', 'what',
      'how', 'why', 'who', 'researchers', 'users', 'people', 'companies',
      'teams', 'students', 'governments', 'organizations', 'businesses',
    };
    if (!lowerable.contains(firstWord.toLowerCase())) return s;
    return s[0].toLowerCase() + s.substring(1);
  }

  /// Re-capitalizes sentence starts after phrase deletion (e.g. removing
  /// "It is important to note that " from the front of a sentence would
  /// otherwise leave it starting lowercase).
  String _recapitalizeSentenceStarts(String text) {
    if (text.isEmpty) return text;
    // Leave camel-cased names alone ("iPhone", "eBay").
    String cap(String word) => RegExp(r'[A-Z]').hasMatch(word) ? word : word[0].toUpperCase() + word.substring(1);

    var out = text.replaceFirstMapped(RegExp(r'^[a-z][A-Za-z]*'), (m) => cap(m.group(0)!));
    out = out.replaceAllMapped(
      RegExp(r'(\S*)([.!?])(["\u201D\u2019)]?\s+)([a-z][A-Za-z]*)'),
      (m) {
        final word = '${m.group(1)}${m.group(2)}';
        if (_abbreviation.hasMatch(word)) return m.group(0)!;
        return '${m.group(1)}${m.group(2)}${m.group(3)}${cap(m.group(4)!)}';
      },
    );
    return out;
  }

  /// "e.g.", "i.e.", "U.S.", "et al.", "vs.", "etc." — a following lowercase
  /// word is not a new sentence.
  static final RegExp _abbreviation = RegExp(
    r'^(?:(?:[A-Za-z]\.){2,}|(?:al|etc|vs|cf|approx|fig|figs|eq|no|pp|vol|ed|eds|dr|mr|mrs|ms|prof|st|jr|sr|inc|ltd|co)\.)$',
    caseSensitive: false,
  );

  /// Replaces high-frequency AI stock words and academic boilerplates with
  /// authentic, everyday human expressions.
  String replaceAiStockPhrases(String text, {WritingToneProfile tone = WritingToneProfile.professional}) {
    String out = text;
    final isAcademic = tone == WritingToneProfile.academic;

    // Multi-word boilerplate replacements (case-insensitive)
    final phraseReplacements = <String, String>{
      // Multi-word specific cliches (ordered before generic sub-phrases)
      r'\bin doing so, they pave the way for a brighter future\b': 'this helps future progress',
      r'\bin doing so, we pave the way for a brighter future\b': 'this helps future progress',
      r'\bpave the way for a brighter future\b': 'build a better future',
      r'\bpaves the way for a brighter future\b': 'builds a better future',
      r'\bpaving the way for a brighter future\b': 'building a better future',
      r'\bstands at the forefront of innovation\b': 'leads in innovation',
      r'\bstand at the forefront of innovation\b': 'lead in innovation',
      r'\bat the forefront of innovation\b': 'leading in innovation',
      r'\ban integral part of the equation\b': 'essential',
      r'\ban integral part of the process\b': 'a key part of the process',
      r'\bserves as a cornerstone for\b': 'forms the foundation of',
      r'\bserves as a cornerstone of\b': 'forms the foundation of',
      r'\bstands as a cornerstone of\b': 'is a cornerstone of',
      r'\blies at the very heart of\b': 'is central to',
      r'\blies at the heart of\b': 'is central to',
      r'\blies at the core of\b': 'is central to',
      r'\b(?:serves|stands)\s+as\s+(?:an?\s+)?(?:enduring\s+|profound\s+)?testament\s+to\s+the\s+resilience\s+of\b': 'shows the resilience of',
      r'\b(?:a|this|the)?\s*(?:an?\s+)?(?:enduring\s+|profound\s+)?testament\s+to\s+the\s+resilience\s+of\b': 'shows the resilience of',
      r'\b(?:serves|stands)\s+as\s+(?:an?\s+)?(?:enduring\s+|profound\s+)?testament\s+to\b': 'shows',
      r'\ba testament to the enduring power of\b': 'shows the enduring strength of',
      r'\bstands as a testament to the enduring power of\b': 'shows the lasting strength of',
      r'\ba testament to the ever-evolving nature of\b': 'shows how it continues to change',
      r'\ba testament to the ever-evolving\b': 'shows the changing',
      r'\bstands as a testament to the ever-evolving\b': 'shows the changing',
      r'\ba testament to their commitment\b': 'shows their commitment',
      r'\ba testament to its commitment\b': 'shows its commitment',
      r'\ba testament to the dedication of\b': 'shows the dedication of',
      r'\bcontinue their journey toward\b': 'continue their work toward',
      r'\bcontinues their journey toward\b': 'continues their work toward',
      r'\bjourney toward excellence\b': 'work toward excellence',
      r'\bjourney toward\b': 'work toward',
      r'\bjourney towards\b': 'work toward',
      r'\bsetting the stage for\b': 'preparing for',
      r'\bsets the stage for\b': 'prepares for',
      r'\bset the stage for\b': 'prepared for',
      r'\bmarking a pivotal moment in\b': 'marking a turning point in',
      r'\bmarking a pivotal moment\b': 'marking a turning point',
      r'\bmarking a crucial moment in\b': 'marking a turning point in',
      r'\brich cultural tapestry\b': 'rich culture',
      r'\bquietly revolutionized\b': 'changed',
      r'\bquietly transformed\b': 'transformed',
      r'\bquietly changed\b': 'changed',
      r'\bcementing its status as\b': 'establishing it as',
      r'\bcementing its position as\b': 'confirming its position as',
      r'\bsolidifying its place in\b': 'securing its place in',
      r'\bsolidifying its status as\b': 'establishing it as',
      r'\bdelving into the intricacies of\b': 'examining the details of',
      r'\bdelve into the intricacies of\b': 'examine the details of',
      r'\bdelving into the nuances of\b': 'examining the nuances of',
      r'\bdelve into the nuances of\b': 'examine the nuances of',
      r'\bdelving into the realm of\b': 'exploring',
      r'\bdelve into the realm of\b': 'explore',
      r'\bunraveling the mysteries of\b': 'understanding',
      r'\bunravel the mysteries of\b': 'understand',
      r'\bboasts over\b': 'has over',
      r'\bboasts more than\b': 'has more than',
      r'\bboasts a\b': 'has a',
      r'\bboast a\b': 'have a',
      r'\bfeatures a diverse array of\b': 'includes many',
      r'\bfeatures a wide array of\b': 'includes many',
      r'\boffers a wide array of\b': 'provides many',
      r'\boffers a plethora of\b': 'provides many',
      r'\bfunctions as a\b': 'is a',
      r'\boperates as a\b': 'is a',
      r'\bfunctions as an\b': 'is an',
      r'\boperates as an\b': 'is an',
      r'\bever-evolving\b': 'evolving',
      r'\bactionable takeaways\b': 'practical takeaways',
      r'\bactionable steps\b': 'concrete steps',
      r'\bactionable recommendations\b': 'practical recommendations',
      r'\bfostering an environment where\b': 'creating an environment where',
      r'\bholds significant implications for\b': 'greatly affects',
      r'\bhold significant implications for\b': 'greatly affect',
      r'\bhas profound implications for\b': 'greatly affects',
      r'\bhave profound implications for\b': 'greatly affect',
      r'\bexplores the themes of\b': 'focuses on',
      r'\bexplore the themes of\b': 'focus on',
      r'\bexploring the themes of\b': 'focusing on',
      r'\bembarks on a perilous\b': 'sets out on a difficult',
      r'\bembark on a perilous\b': 'set out on a difficult',
      r'\bembarks on\b': 'starts',
      r'\bunderscore the importance of\b': 'show why it matters to have',
      r'\bin the face of overwhelming adversity\b': 'against all odds',
      r'\bin the face of adversity\b': 'when challenged',
      r'\btest his intellect and resolve\b': 'push him to the limit',
      r'\btests his intellect and resolve\b': 'pushes him to the limit',
      r'\bhighlighting how\b': 'showing how',
      r'\bThroughout his voyage\b': 'Along the way',
      r'\bpoised to reshape\b': 'ready to reshape',
      r'\bpoised to transform\b': 'ready to transform',
      r'\bgarnered significant attention\b': 'drew wide attention',
      r'\bgarner significant attention\b': 'draw wide attention',
      r'\bunravel the complexities of\b': 'understand the details of',
      r'\bunraveling the complexities of\b': 'understanding the details of',
      r'\bembark on this journey\b': 'begin this work',
      r'\bfoster meaningful connections\b': 'build real relationships',
      r'\bfosters meaningful connections\b': 'builds real relationships',
      r'\ba profound testament to\b': 'strong proof of',
      r'\bprofound testament to\b': 'strong proof of',
      r'\bbears testament to the relentless pursuit of\b': 'shows the work toward',
      r'\bat the precipice of\b': 'on the verge of',
      r'\b(?:a|this|the)?\s*watershed moment in\b': 'a turning point in',
      r'\b(?:a|this|the)?\s*watershed moment\b': 'a turning point',
      r'\bwatershed moment\b': 'turning point',
      r'\bwatershed moments\b': 'turning points',
      r'\bunwavering commitment to\b': 'dedication to',
      r'\bfostering an inclusive environment\b': 'building an inclusive environment',
      r'\bcatalyst for positive change\b': 'driver of improvement',
      r'\bcatalysts for positive change\b': 'drivers of improvement',
      r'\bfrom a holistic perspective\b': 'overall',
      r'\bbrings to the forefront the critical need\b': 'highlights the need',
      r'\ba seamless blend of form and function\b': 'both functional and well designed',
      r'\bnavigating uncharted waters\b': 'facing new challenges',
      r'\ba force to be reckoned with\b': 'influential',
      r'\bcrucial stepping stone\b': 'key step',
      r'\bcrucial stepping stones\b': 'key steps',
      r'\ba stark reminder of the perils of\b': 'a reminder of the risks of',
      r'\bpaves the way for unprecedented\b': 'enables new',
      r'\bpave the way for unprecedented\b': 'enable new',
      r'\bthe key takeaway is that\b': 'in short,',
      r'\ba shining example of\b': 'an example of',
      r'\bin essence, the fundamental truth is that\b': 'essentially,',
      r'\bit is widely regarded as\b': 'many consider it',
      r'\bshedding valuable light on\b': 'clarifying',
      r'\bsheds valuable light on\b': 'clarifies',
      r'\bshed valuable light on\b': 'clarify',
      r'\bhas far-reaching implications for\b': 'greatly affects',
      r'\bhave far-reaching implications for\b': 'greatly affect',
      r'\bserves to illustrate\b': 'illustrates',
      r'\bserve to illustrate\b': 'illustrate',
      r'\bplays an indispensable role in\b': 'is vital to',
      r'\bplay an indispensable role in\b': 'are vital to',
      // Academic fillers to completely strip or simplify cleanly
      r'\bit is important to note that\s*': '',
      r'\bit should be noted that\s*': '',
      r'\bit is worth noting that\s*': '',
      r'\bit is worth emphasizing that\s*': '',
      r'\bit is crucial to understand that\s*': '',
      r'\bit is crucial to recognize that\s*': '',
      r'\bit is crucial to remember that\s*': '',
      r'\bit is interesting to note that\s*': '',
      r'\ba closer look reveals that\s*': '',
      r'\ba closer examination of the data reveals that\s*': 'the data reveals that ',
      r'\ba closer examination of the data shows that\s*': 'the data shows that ',
      r'\ba closer examination reveals that\s*': 'examination reveals that ',
      r'\bone cannot overstate the importance of\s*': 'crucial is ',
      r'\bit is crucial to bear in mind that\s*': 'remember that ',
      // Kaggle DAIGT Empirical Formulaic Replacements
      r'\bvital to recognize that\s*': 'remember that ',
      r'\bimportant to consider\b': 'worth considering',
      r'\bis essential for\b': 'is needed for',
      r'\bare essential for\b': 'are needed for',
      r'\bbenefits and drawbacks of\b': 'pros and cons of',
      r'\bbenefits and drawbacks\b': 'pros and cons',
      r'\bpotential drawbacks\b': 'drawbacks',
      r'\bmindful of the fact that\b': 'aware that',
      r'\bfoster a sense of\b': 'create a sense of',
      r'\ba variety of advantages and disadvantages\b': 'both pros and cons',
      r'\ban invaluable tool\b': 'a very useful tool',
      r'\binformed decisions\b': 'better choices',
      r'\bhas the potential to\b': 'can',
      r'\bhave the potential to\b': 'can',
      r'\bthis can lead to\b': 'this causes',
      r'\bthis can lead\b': 'this leads',
      r'\bthis can help to\b': 'this helps',
      r'\bthis can help\b': 'this helps',
      r'\bthis can be\b': 'this is',
      r'\bthis means that\b': 'this means',
      r'\bcan lead to\b': 'can cause',
      r'\bcan help to\b': 'can help',
      r'\bcan also help to\b': 'also helps',
      r'\bcan also help\b': 'also helps',
      r'\bin this essay,?\s*': '',
      r'\bin this essay i will\b': 'here i',
      r'\bin this composition,?\s*': '',
      r'\bit is important to bear in mind that\s*': 'remember that ',
      r'\bit is essential to recognize that\s*': '',
      r'\bit is imperative that\s*': '',
      r'\bit is widely acknowledged that\s*': 'most agree that ',
      r'\bit goes without saying that\s*': 'clearly, ',
      r'\bneedless to say,\s*': '',
      r'\bit is safe to say that\s*': 'clearly, ',
      r'\bwithout a shadow of a doubt,\s*': 'certainly, ',
      r'\bnavigating the complexities of\b': 'handling the challenges of',
      r'\bnavigating the nuances of\b': 'understanding the nuances of',
      r'\bnavigating the intricacies of\b': 'working through',
      r'\bnavigating the\b': 'handling the',
      r'\bnavigate the\b': 'handle the',
      r"\bin today's ever-changing world\b": 'today',
      r"\bin today's fast-paced world\b": 'today',
      r"\bin today's rapidly evolving digital landscape\b": 'in our digital world',
      r"\bin today's rapidly evolving\b": 'in today’s changing',
      r"\bin today's dynamic landscape\b": 'today',
      r"\bin today's digital era\b": 'in our digital world',
      r"\bin today's interconnected world\b": 'today',
      r'\bin an era marked by\b': 'at a time of',
      r'\bin an era where\b': 'when',
      r'\bcannot be overstated\b': 'is undeniable',
      r'\ba wide array of\b': 'many',
      r'\ba diverse range of\b': 'different',
      if (!isAcademic) r'\ba multifaceted approach\b': 'a varied approach',
      r'\bmultifaceted\b': 'complex',
      r'\bthereby\b': 'and thus',
      r'\bmitigate\b': 'reduce',
      r'\bmitigates\b': 'reduces',
      r'\bmitigating\b': 'reducing',
      r'\bmitigated\b': 'reduced',
      r'\bsubstantial\b': 'large',
      r'\bsubstantially\b': 'significantly',
      r'\bcontemporary\b': 'modern',
      r'\bmerely\b': 'only',
      r'\bcharacterized by\b': 'marked by',
      r'\bfindings demonstrate that\b': 'findings show that',
      r'\bresults demonstrate that\b': 'results show that',
      r'\bdemonstrates that\b': 'shows that',
      r'\bdemonstrated that\b': 'showed that',
      r'\bdemonstrate that\b': 'show that',
      r'\bparadigm\b': 'model',
      r'\bin the realm of\b': 'in',
      r'\bin the world of\b': 'in',
      r'\bplays a pivotal role in\b': 'is key to',
      r'\bplay a pivotal role in\b': 'are key to',
      r'\bplays a crucial role in\b': 'is central to',
      r'\bplay a crucial role in\b': 'are central to',
      r'\bplays an essential role in\b': 'is vital to',
      r'\bplay an essential role in\b': 'are vital to',
      r'\bplays an integral role in\b': 'is central to',
      r'\bplay an integral role in\b': 'are central to',
      r'\bhas a significant impact on\b': 'greatly affects',
      r'\bhave a significant impact on\b': 'greatly affect',
      r'\bsheds light on the nuances of\b': 'explains',
      r'\bshed light on the nuances of\b': 'explain',
      r'\bsheds light on\b': 'clarifies',
      r'\bshed light on\b': 'clarify',
      r'\bshedding light on\b': 'clarifying',
      r'\bstands as a testament to the power of\b': 'shows the power of',
      r'\bserves as a testament to the power of\b': 'proves the power of',
      r'\bstands as a testament to\b': 'shows',
      r'\bserves as a testament to\b': 'proves',
      r'\ba testament to\b': 'proof of',
      r'\btestament to\b': 'evidence of',
      r'\bbears testament to\b': 'shows',
      r'\bserves as a stark reminder that\b': 'reminds us that',
      r'\bserves as a stark reminder\b': 'is a stark reminder',
      r'\bserves as a poignant reminder that\b': 'reminds us that',
      r'\bserves as a reminder that\b': 'reminds us that',
      r'\bstands as a beacon of\b': 'is a model for',
      r'\bserves as a vital beacon\b': 'acts as a guide',
      r'\bstands as a\b': 'is a',
      r'\bserves as a\b': 'acts as a',
      r'\bserves to\b': 'helps to',
      r'\bdelve deep into\b': 'examine',
      r'\bdelving deep into\b': 'examining',
      r'\bdelves deep into\b': 'examines',
      r'\bdelve deeper into\b': 'examine',
      r'\bdelving deeper into\b': 'examining',
      r'\bdelving deeper,': 'looking closer,',
      r'\bdelving deeper\b': 'looking closer',
      // Synonym pairs that the substitutions above can create ("not only crucial
      // but also pivotal" -> "crucial and key").
      r'\b(?:crucial|vital|essential|central) and (?:key|pivotal)\b': 'key',
      r'\b(?:key|pivotal) and (?:crucial|vital|essential|central)\b': 'key',
      r'\bdelves deeper into\b': 'examines',
      r'\bdelve deeper\b': 'look closer',
      r'\bdelve into\b': 'explore',
      r'\bdelving into\b': 'exploring',
      r'\bdelves into\b': 'explores',
      r'\bit is evident that\s*': '',
      r'\bthis highlights the importance of\b': 'this shows why it matters',
      r'\bhighlights the importance of\b': 'shows why it matters',
      r'\bin the context of\b': 'in',
      r'\bvarious aspects of\b': 'aspects of',
      r'\bvarious aspects\b': 'different aspects',
      r'\ba wide range of factors\b': 'multiple factors',
      r'\bdemonstrates the complexity of the issue\b': 'reveals the complexity of the issue',
      r'\bdemonstrates the complexity of\b': 'reveals the complexity of',
      r'\bdelve\b': 'look',
      r'\bdelved\b': 'looked',
      r'\bgame-changer in the realm of\b': 'major advance in',
      r'\bgame-changers\b': 'breakthroughs',
      r'\bpivotal turning point\b': 'key turning point',
      r'\bpivotal\b': 'key',
      r'\bvibrant tapestry\b': 'rich mix',
      r'\brich tapestry of\b': 'broad mix of',
      r'\brich tapestry\b': 'diverse mix',
      r'\btapestry of\b': 'blend of',
      r'\btapestry\b': 'fabric',
      r'\bdigital landscape\b': 'digital world',
      r'\bever-evolving landscape\b': 'changing landscape',
      r'\btransformative catalyst\b': 'turning point',
      r'\btransformative journey\b': 'major change',
      if (!isAcademic) r'\btransformative\b': 'impactful',
      r'\bfosters an environment of\b': 'builds an environment of',
      r'\bfosters innovation\b': 'encourages new ideas',
      r'\bfosters a sense of\b': 'builds a sense of',
      r'\bfostering\b': 'encouraging',
      r'\bfosters\b': 'encourages',
      r'\bfoster\b': 'encourage',
      r'\bunderscores the importance of\b': 'highlights',
      r'\bunderscores the need for\b': 'stresses the need for',
      r'\bunderscoring\b': 'highlighting',
      r'\bunderscores\b': 'highlights',
      r'\bunderscore\b': 'highlight',
      r'\bbeacon of hope\b': 'source of hope',
      r'\bbeacon of\b': 'model for',
      r'\bharness the full potential of\b': 'realize the potential of',
      r'\bharness the power of\b': 'use',
      r'\bharnessing the power of\b': 'using',
      r'\bharnessing\b': 'using',
      r'\bharness\b': 'use',
      r'\bunlock the full potential of\b': 'realize the potential of',
      r'\bunlocking the full potential of\b': 'opening up',
      r'\bunlock the power of\b': 'use',
      r'\bnestled in\b': 'located in',
      r'\bplethora of\b': 'wide range of',
      r'\bmeticulously\b': 'carefully',
      r'\bmeticulous\b': 'careful',
      if (!isAcademic) r'\bmultifaceted\b': 'complex',
      r'\bparamount\b': 'essential',
      r'\bis of paramount importance\b': 'is essential',
      r'\bcrucial cornerstone\b': 'key foundation',
      r'\bcornerstone of\b': 'foundation of',
      r'\bcornerstone\b': 'basis',
      r'\bseamlessly integrates\b': 'integrates smoothly',
      r'\bseamlessly integrate\b': 'integrate smoothly',
      r'\bseamlessly blending\b': 'blending smoothly',
      r'\bseamlessly blends\b': 'blends smoothly',
      r'\bseamless integration\b': 'smooth integration',
      r'\bseamlessly\b': 'smoothly',
      r'\bseamless\b': 'smooth',
      r'\bgroundbreaking\b': 'innovative',
      r'\bstreamlining\b': 'simplifying',
      r'\bstreamlines\b': 'simplifies',
      r'\bstreamline\b': 'simplify',
      r'\bparadigm shift\b': 'major shift',
      r'\bunpack\b': 'explain',
      r'\bunpacking\b': 'explaining',
      if (!isAcademic) r'\bholistic understanding\b': 'complete understanding',
      if (!isAcademic) r'\bholistic approach\b': 'comprehensive approach',
      if (!isAcademic) r'\bholistic\b': 'comprehensive',
      r'\bempower\b': 'enable',
      r'\bempowering\b': 'enabling',
      r'\belevate\b': 'lift',
      r'\belevating\b': 'lifting',
      r'\binvaluable\b': 'essential',
      r'\binterplay between\b': 'relationship between',
      r'\binterplay\b': 'dynamic',
      r'\bstriking a delicate balance\b': 'balancing',
      r'\bstrikes a delicate balance\b': 'balances',
      r'\ba double-edged sword\b': 'both an advantage and a risk',
      r'\bushering in a new era of\b': 'starting a new era of',
      r'\bushers in a new era of\b': 'starts a new era of',
      r'\breimagining the way we\b': 'changing how we',
      r'\breimagining how we\b': 'changing how we',
      r'\breimagine how we\b': 'change how we',
      r'\bcatalyzing change\b': 'driving change',
      r'\blies at the intersection of\b': 'connects',
      r'\blie at the intersection of\b': 'connect',
      r'\bat the intersection of\b': 'between',
      r'\bpaving a path forward\b': 'moving forward',
      r'\bpave a path forward\b': 'move forward',
      r'\bembodies the spirit of\b': 'reflects',
      r'\bis poised to revolutionize\b': 'will transform',
      r'\bpoised to revolutionize\b': 'set to transform',
      r'\ba symphony of\b': 'a blend of',
      r'\bharmonious blend of\b': 'mix of',
      r'\ba deep dive into\b': 'a detailed look at',
      r'\btake a deep dive into\b': 'examine',
      r'\bonly time will tell whether\b': 'we will see whether',
      r'\bit remains to be seen whether\b': 'we do not yet know if',
      // High-Frequency AI Tropes & Corporate Puffery
      r'\bspearheading the effort\b': 'leading the effort',
      r'\bspearheading the initiative\b': 'leading the project',
      r'\bspearheading\b': 'leading',
      r'\bspearheaded\b': 'led',
      r'\bspearhead\b': 'lead',
      r'\bbolstering\b': 'strengthening',
      r'\bbolsters\b': 'strengthens',
      r'\bbolster\b': 'strengthen',
      r'\bpaving the way for\b': 'leading to',
      r'\bpaves the way for\b': 'leads to',
      r'\bpave the way for\b': 'lead to',
      r'\ba myriad of\b': 'many',
      r'\bmyriad of\b': 'many',
      r'\bmyriad challenges\b': 'many challenges',
      r'\bmyriad opportunities\b': 'many opportunities',
      r'\bmyriad\b': 'countless',
      r'\bgame-changing potential\b': 'major potential',
      r'\bgame-changing\b': 'innovative',
      r'\bgame-changer\b': 'breakthrough',
      r'\bunleash the full potential of\b': 'realize the potential of',
      r'\bunleash the power of\b': 'enable',
      r'\bunleashing\b': 'freeing',
      r'\bunleashes\b': 'frees',
      r'\bunleash\b': 'free',
      r'\bresonate deeply with\b': 'connect with',
      r'\bresonates with readers\b': 'connects with readers',
      r'\bresonates with\b': 'connects with',
      r'\bresonate with\b': 'connect with',
      r'\bat the forefront of\b': 'leading',
      r'\bat the cutting edge of\b': 'leading in',
      r'\bcutting-edge\b': 'modern',
      r'\bembarking on a journey\b': 'starting',
      r'\bembark on a journey\b': 'begin',
      r'\bembark on\b': 'start',
      r'\bembarks upon\b': 'starts',
      r'\bembarking upon\b': 'starting',
      r'\bacts as a vital cog in\b': 'is an important part of',
      r'\bserves as a vital cog in\b': 'is an important part of',
      r'\bvital cog in the machine\b': 'essential component',
      r'\borchestrating a delicate balance\b': 'balancing',
      r'\borchestrating\b': 'coordinating',
      r'\borchestrates\b': 'coordinates',
      r'\bnavigating this labyrinth\b': 'working through this',
      r'\bpoised at the threshold of\b': 'approaching',
      r'\bstands ready to\b': 'can',
      r'\bis an indispensable asset\b': 'is valuable',
      r'\bare an indispensable asset\b': 'are valuable',
      r'\bharnessing synergies\b': 'working together',
      r'\bfoster a culture of\b': 'encourage',
      r'\bfostering a culture of\b': 'encouraging',
      r'\bunwavering resolve\b': 'determination',
      r'\brelentless pursuit of excellence\b': 'effort to improve',
      r'\bin the grand scheme of things\b': 'overall',
      r'\ba plethora of choices\b': 'many choices',
      r'\ba plethora of options\b': 'many options',
      r'\bthe dawn of a new era\b': 'a new period',
      r'\ba cornerstone of modern\b': 'central to modern',
      r'\bin sum, it is clear that\b': 'in summary,',
      r'\bin summary, it is evident that\b': 'in summary,',
      r'\ball in all, it is clear that\b': 'in short,',
      r'\bquintessential\b': 'classic',
      r'\bquintessentially\b': 'typically',
      r'\brevolutionizing\b': 'transforming',
      r'\brevolutionizes\b': 'transforms',
      r'\brevolutionize\b': 'transform',
      r'\bin order to\b': 'to',
      r'\bpoised to\b': 'ready to',
      r'\bpoised for\b': 'ready for',
      r'\bactionable insights\b': 'practical recommendations',
      r'\bactionable\b': 'practical',
      r'\bdemystifying the process\b': 'clarifying the process',
      r'\bdemystifying\b': 'clarifying',
      r'\bdemystifies\b': 'clarifies',
      r'\bdemystify\b': 'clarify',
      if (!isAcademic) r'\bcatalyst for\b': 'spark for',
      r'\bburgeoning field of\b': 'growing field of',
      r'\bburgeoning\b': 'growing',
      r'\bconundrum\b': 'challenge',
      r'\bdichotomy\b': 'division',
      r'\bepitome of\b': 'standard for',
      r'\bembodiment of\b': 'example of',
      r'\bindelible mark\b': 'lasting impact',
      r'\bindelible impression\b': 'lasting impression',
      r'\bvital role in shaping\b': 'key role in shaping',
      r'\bin conclusion, it is clear that\b': 'clearly,',
      r'\ball in all,\b': 'overall,',
      r'\bby and large\b': 'mostly',
      r'\bas we look to the future,\b': 'looking ahead,',
      r'\bfirst and foremost\b': 'primarily',
      // Modern LLM Tell Expansions
      r'\butilize\b': 'use',
      r'\butilizes\b': 'uses',
      r'\butilizing\b': 'using',
      r'\butilization of\b': 'use of',
      r'\butilization\b': 'use',
      r'\bleverage the power of\b': 'use',
      r'\bleveraging the power of\b': 'using',
      r'\bleveraging\b': 'using',
      r'\bleverages\b': 'uses',
      r'\bleverage\b': 'use',
      r'\brobust framework\b': 'reliable framework',
      r'\brobust\b': 'reliable',
      r'\bsynergy between\b': 'teamwork between',
      r'\bsynergies\b': 'advantages',
      r'\bsynergy\b': 'teamwork',
      r'\bat this point in time\b': 'now',
      r'\bdue to the fact that\b': 'because',
      r'\bfor the purpose of\b': 'to',
      r'\btakes into consideration\b': 'considers',
      r'\bgives rise to\b': 'causes',
      r'\bin light of the fact that\b': 'since',
      r'\bdelves into the complexities\b': 'examines the details',
      r'\bplays an instrumental role in\b': 'is key to',
      r'\bplay an instrumental role in\b': 'are key to',
      r'\bvital component of\b': 'key part of',
      r'\bvital component\b': 'key part',
      r'\bcatalyst for change\b': 'driver of change',
      r'\btransformative impact\b': 'major impact',
      r'\bdeep dive into\b': 'detailed look at',
      r'\bdeep dive\b': 'detailed look',
      r'\bholistic framework\b': 'comprehensive framework',
      r'\brobust methodology\b': 'solid methodology',
      r'\bnavigating the terrain\b': 'handling the challenges',
      r'\bfosters a culture of\b': 'builds a culture of',
      r'\bunlocks new possibilities\b': 'opens new possibilities',
      r'\bunlock new possibilities\b': 'open new possibilities',
      r'\bunleashes new potential\b': 'opens new potential',
      r'\bunleash new potential\b': 'open new potential',
      r'\bgroundbreaking innovation\b': 'new development',
      r'\bseamless synergy\b': 'effective teamwork',
      r'\bstands poised to\b': 'is ready to',
      r'\bstand poised to\b': 'are ready to',
      r'\bfacilitates the process of\b': 'simplifies',
      r'\bfacilitate the process of\b': 'simplify',
      r'\bin order to facilitate\b': 'to help with',
      r'\bat the heart of the matter\b': 'fundamentally',
      r'\bwith that being said,\b': 'still,',
      r'\bhaving said that,\b': 'still,',
      r'\bfor all intents and purposes,\b': 'effectively,',
      r'\bit is imperative to\b': 'we must',
      r'\bit is crucial to\b': 'we must',
      r'\bit is essential to\b': 'we must',
      r'\bit is worth pointing out that\b': '',
      r'\bit is important to highlight that\b': '',
      r'\bit is important to remember that\s*': '',
      r'\bbears witness to\b': 'shows',
      r'\bbear witness to\b': 'show',
      r'\ba stark contrast to\b': 'very different from',
      r'\bin stark contrast to\b': 'unlike',
      r'\bplays an active role in\b': 'actively helps',
      r'\bplay an active role in\b': 'actively help',
      r'\bplays an integral part in\b': 'is central to',
      r'\bplay an integral part in\b': 'are central to',
      r'\bhas the capacity to\b': 'can',
      r'\bhave the capacity to\b': 'can',
      r'\bholds the potential to\b': 'could',
      r'\bhold the potential to\b': 'could',
      r'\bin close proximity to\b': 'near',
      r'\bwith respect to\b': 'regarding',
      r'\bat the end of the day,?\s*': '',
      r'\ba testament to the fact that\b': 'proof that',
      r'\bis indicative of\b': 'indicates',
      r'\bare indicative of\b': 'indicate',
      r'\bbrings to light\b': 'reveals',
      r'\bbring to light\b': 'reveal',
      r'\bbrings to the forefront\b': 'highlights',
      r'\bbring to the forefront\b': 'highlight',
      r'\bstands as a testament\b': 'is proof',
      r'\bstand as a testament\b': 'are proof',
      r'\bcrucial component of\b': 'key part of',
      r'\bcrucial component\b': 'key part',
      r'\bcrucial components\b': 'key parts',
      r'\bpivotal component\b': 'key part',
      r'\bin an effort to\b': 'to',
      r'\bin the wake of\b': 'after',
      r'\bin light of these considerations\b': 'therefore',
      r'\bthe overarching goal of\b': 'the main goal of',
      r'\bthe overarching theme of\b': 'the main theme of',
      r'\boverarching\b': 'main',
      r'\bunderscores the necessity of\b': 'proves the need for',
      r'\bmarks a pivotal moment\b': 'marks a key moment',
      r'\bstands as a hallmark of\b': 'is a hallmark of',
      r'\bleaves an indelible mark on\b': 'deeply affects',
      r'\bleave an indelible mark on\b': 'deeply affect',
      r'\bsheds light upon\b': 'clarifies',
      r'\bshed light upon\b': 'clarify',
      r'\ba comprehensive overview of\b': 'an overview of',
      r'\bin the final analysis,?\s*': 'ultimately, ',
      r'\bwhen all is said and done,?\s*': 'ultimately, ',
      r'\ba profound impact on\b': 'a strong effect on',
      r'\bserves as an illustration of\b': 'illustrates',
      r'\bserves as an example of\b': 'exemplifies',
      r'\bby the same token,?\s*': 'likewise, ',
      r'\bon the other hand, it is important to\b': 'we must also',
    };

    for (final entry in phraseReplacements.entries) {
      final reg = RegExp(entry.key, caseSensitive: false);
      out = out.replaceAllMapped(reg, (match) {
        final matchedText = match.group(0)!;
        final replacement = entry.value;
        if (replacement.isEmpty) return '';
        // Preserve title case if original started with capital
        if (matchedText[0].toUpperCase() == matchedText[0] &&
            matchedText[0].toLowerCase() != matchedText[0]) {
          return replacement[0].toUpperCase() + replacement.substring(1);
        }
        return replacement;
      });
    }

    return out;
  }

  /// Applies register-specific tone modulation.
  String applyToneModulation(String text, WritingToneProfile tone) {
    String out = text;

    switch (tone) {
      case WritingToneProfile.casual:
      case WritingToneProfile.conversational:
        // Inject authentic conversational contractions
        final contractions = {
          r'\bdo not\b': "don't",
          r'\bcannot\b': "can't",
          r'\bcan not\b': "can't",
          r'\bwill not\b': "won't",
          r'\bis not\b': "isn't",
          r'\bare not\b': "aren't",
          r'\bit is\b': "it's",
          r'\bthey are\b': "they're",
          r'\bwe are\b': "we're",
          r'\bhave not\b': "haven't",
          r'\bhas not\b': "hasn't",
          r'\bwould not\b': "wouldn't",
          r'\bcould not\b': "couldn't",
        };
        for (final entry in contractions.entries) {
          out = out.replaceAllMapped(RegExp(entry.key, caseSensitive: false), (m) {
            final orig = m.group(0)!;
            final rep = entry.value;
            if (orig[0] == orig[0].toUpperCase()) {
              return rep[0].toUpperCase() + rep.substring(1);
            }
            return rep;
          });
        }
        break;

      case WritingToneProfile.direct:
        // Prune padding adverbs for direct, punchy style
        out = out.replaceAll(RegExp(r'\b(literally|virtually|essentially|basically)\s+', caseSensitive: false), '');
        break;

      case WritingToneProfile.academic:
      case WritingToneProfile.professional:
      case WritingToneProfile.natural:
        break;
    }

    return out;
  }

  /// Applies constraint and length modulation based on the Mini Settings choice:
  /// - 'concise': cuts filler adverbs, redundant subordinate bloat, wordy prepositions.
  /// - 'simple': converts Latinate and complex vocabulary into plain 8th-grade English.
  /// - 'technical': preserves domain jargon and precision.
  /// - 'detailed': preserves explanatory nuance and causal development.
  /// - 'balanced': natural, harmonious human pacing.
  String applyStyleConstraintModulation(String text, String style) {
    if (text.trim().isEmpty) return text;
    String out = text;
    final lowerStyle = style.toLowerCase().trim();

    switch (lowerStyle) {
      case 'concise':
        // 1. Cut wordy prepositions & filler conjunctions (Rules 19, 20, 24, 35)
        final conciseReplacements = <String, String>{
          r'\bdue to the fact that\b': 'because',
          r'\bowing to the fact that\b': 'because',
          r'\bin order to\b': 'to',
          r'\bwith the aim of\b': 'to',
          r'\bfor the purpose of\b': 'to',
          r'\bat this point in time\b': 'now',
          r'\bat the present moment\b': 'now',
          r'\bin spite of the fact that\b': 'although',
          r'\bdespite the fact that\b': 'although',
          r'\bin the event that\b': 'if',
          r'\bin case of\b': 'if',
          r'\bas a matter of fact\b': 'in fact',
          r'\bin point of fact\b': 'in fact',
          r'\ba large number of\b': 'many',
          r'\ba significant number of\b': 'many',
          r'\ba majority of\b': 'most',
          r'\bconduct an investigation into\b': 'investigate',
          r'\bconduct an inquiry into\b': 'examine',
          r'\bmake a determination\b': 'decide',
          r'\breach a conclusion\b': 'conclude',
          r'\bserve the purpose of\b': 'serve to',
          r'\bhas the ability to\b': 'can',
          r'\bhave the ability to\b': 'can',
          r'\bis in a position to\b': 'can',
          r'\bare in a position to\b': 'can',
          r'\bwith regard to\b': 'about',
          r'\bin reference to\b': 'about',
        };
        for (final entry in conciseReplacements.entries) {
          out = out.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
        }
        // 2. Prune redundant padding adverbs
        out = out.replaceAll(
          RegExp(r'\b(?:quite|fairly|rather|extremely|virtually|certainly|obviously)\s+', caseSensitive: false),
          '',
        );
        break;

      case 'simple':
        // Replace unnecessarily complicated or academic words with familiar alternatives (Rules 16, 23, 24, 25)
        final simpleReplacements = <String, String>{
          r'\butilize\b': 'use',
          r'\butilizes\b': 'uses',
          r'\butilizing\b': 'using',
          r'\butilization\b': 'use',
          r'\bdemonstrates?\b': 'shows',
          r'\bdemonstrated\b': 'showed',
          r'\bfacilitates?\b': 'helps',
          r'\bfacilitated\b': 'helped',
          r'\bcommences?\b': 'starts',
          r'\bcommenced\b': 'started',
          r'\bterminates?\b': 'ends',
          r'\bterminated\b': 'ended',
          r'\bsubsequently\b': 'then',
          r'\bnevertheless\b': 'still',
          r'\bconsequently\b': 'so',
          r'\bapproximately\b': 'about',
          r'\bsufficient\b': 'enough',
          r'\bimplement\b': 'apply',
          r'\bimplements\b': 'applies',
          r'\bimplemented\b': 'applied',
          r'\bpredominantly\b': 'mostly',
          r'\bexhibits?\b': 'shows',
          r'\belucidates?\b': 'explains',
          r'\belucidated\b': 'explained',
          r'\bascertain\b': 'learn',
          r'\bascertained\b': 'learned',
          r'\bfurnish\b': 'provide',
          r'\binterrogate\b': 'question',
          r'\bdisseminate\b': 'spread',
        };
        for (final entry in simpleReplacements.entries) {
          out = out.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
        }
        break;

      case 'technical':
      case 'detailed':
      case 'balanced':
      default:
        break;
    }

    return out;
  }

  /// Dissolves synthetic "not only X, but also Y" and staged contrast structures.
  String dissolveContrastAndStaging(String text) {
    String out = text;

    // Pattern: "[subject] not only [A], but also [B]" -> "[subject] [A]. [Pronoun] also [B]"
    final notOnlyWithSubjectPattern = RegExp(
      r'(\b[A-Za-z]+)\s+not only\s+(.+?)(?:,\s*|\s+)but also\s+([^,.;]+)',
      caseSensitive: false,
    );
    // Auxiliaries, copulas, and modals ("It is not only fast but also
    // cheap", "We can not only ... but also ...") cannot head a new sentence
    // on their own; splitting them yields "It is fast. It also cheap".
    // Collapse those to plain coordination, which is always grammatical
    // because "not only A but also B" coordinates like constituents.
    const auxiliaries = {
      'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am', 'can', 'could',
      'will', 'would', 'shall', 'should', 'may', 'might', 'must', 'do', 'does',
      'did', 'has', 'have', 'had', 'and', 'or', 'but', 'that', 'which', 'who',
    };
    out = out.replaceAllMapped(notOnlyWithSubjectPattern, (match) {
      final subj = match.group(1)?.trim() ?? '';
      final a = match.group(2)?.trim() ?? '';
      final b = match.group(3)?.trim() ?? '';
      final lowerSubj = subj.toLowerCase();
      if (auxiliaries.contains(lowerSubj) && a.isNotEmpty && b.isNotEmpty) {
        return '$subj $a and $b';
      }
      if (subj.isNotEmpty && a.isNotEmpty && b.isNotEmpty) {
        const pluralSubjects = {
          'they', 'we', 'people', 'users', 'students', 'researchers', 'engineers',
          'scientists', 'members', 'authors', 'doctors', 'patients', 'children', 'men', 'women',
        };
        const personPronouns = {'he', 'she'};
        if (personPronouns.contains(lowerSubj)) {
          return '$subj $a. $subj also $b';
        } else if (pluralSubjects.contains(lowerSubj) || (lowerSubj.endsWith('s') && !lowerSubj.endsWith('ss') && !lowerSubj.endsWith('us') && !lowerSubj.endsWith('is'))) {
          return '$subj $a. They also $b';
        } else {
          return '$subj $a. It also $b';
        }
      }
      return match.group(0)!;
    });

    // Fallback pattern: "not only [A], but also [B]" -> "[A] and [B]"
    final notOnlyPattern = RegExp(
      r'\bnot only\s+(.+?)(?:,\s*|\s+)but also\s+([^,.;]+)',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(notOnlyPattern, (match) {
      final a = match.group(1)?.trim() ?? '';
      final b = match.group(2)?.trim() ?? '';
      if (a.isNotEmpty && b.isNotEmpty) {
        return '$a and $b';
      }
      return match.group(0)!;
    });

    // Pattern: "It is not just about [A], it is about [B]" -> "It centers on [B] rather than just [A]"
    final notJustAboutPattern = RegExp(
      r'\bit(?:\x27s|\s+is)\s+not\s+(?:just|only|merely)\s+about\s+([^,]+),?\s*but\s+(?:also\s+|rather\s+)?about\s+([^,.;]+)',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(notJustAboutPattern, (match) {
      final a = match.group(1)?.trim() ?? '';
      final b = match.group(2)?.trim() ?? '';
      if (a.isNotEmpty && b.isNotEmpty) {
        return 'It centers on $b rather than just $a';
      }
      return match.group(0)!;
    });

    // Pattern: "not simply [A], but [B]" -> "[B] rather than [A]"
    final notSimplyPattern = RegExp(
      r'\bnot\s+simply\s+([^,]+),\s*but\s+(?:rather\s+)?([^,.;]+)',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(notSimplyPattern, (match) {
      final a = match.group(1)?.trim() ?? '';
      final b = match.group(2)?.trim() ?? '';
      if (a.isNotEmpty && b.isNotEmpty) {
        return '$b rather than $a';
      }
      return match.group(0)!;
    });

    // Pattern: "not merely/just [A], but (rather/also) [B]" -> "[B]" (Wikipedia §1)
    final notMerelyPattern = RegExp(
      r'\bnot\s+(?:merely|just)\s+([^,]+),\s*but\s+(?:also\s+|rather\s+)?([^,.;]+)',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(notMerelyPattern, (match) {
      final b = match.group(2)?.trim() ?? '';
      if (b.isNotEmpty) {
        return b;
      }
      return match.group(0)!;
    });

    // Pattern: "This is not [A], but [B]" -> "This is [B]"
    final thisIsNotPattern = RegExp(
      r'\b(this\s+is)\s+not\s+([^,]+),\s*but\s+(?:rather\s+)?([^,.;]+)',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(thisIsNotPattern, (match) {
      final b = match.group(2)?.trim() ?? '';
      if (b.isNotEmpty) {
        return 'This is $b';
      }
      return match.group(0)!;
    });

    return out;
  }

  /// Dissolves formulaic staged openers (e.g. "From X to Y...", "In today's fast-paced world...",
  /// "When it comes to X...", "One of the primary reasons is that...").
  String dissolveStagedOpeners(String text) {
    var out = text;

    // 1. "From [Gerund/Domain X] to [Gerund/Domain Y], [Subject] [Verb]..."
    final fromToPattern = RegExp(
      r'(?:^|[.!?]\s+)From\s+([^,]+?),\s*to\s+([^,]+?),\s*([A-Za-z]+)\s+',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(fromToPattern, (m) {
      final lead = m.group(0)!.startsWith(RegExp(r'[.!?]')) ? m.group(0)!.substring(0, 2) : '';
      final subj = m.group(3)!;
      return '$lead$subj ';
    });

    // 2. "In today's [modern/fast-paced/digital/interconnected] [world/society/landscape/era], [Clause]"
    final inTodaysWorldPattern = RegExp(
      r'(?:^|[.!?]\s+)In\s+today(?:\x27s|\s+is)\s+(?:modern\s+|fast-paced\s+|digital\s+|interconnected\s+|dynamic\s+)?(?:world|society|landscape|era|environment)[,\s]+',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(inTodaysWorldPattern, (m) {
      final lead = m.group(0)!.startsWith(RegExp(r'[.!?]')) ? m.group(0)!.substring(0, 2) : '';
      return '${lead}Today, ';
    });

    // 3. "When it comes to [Topic], [Clause]" -> "For [Topic], [Clause]"
    final whenItComesPattern = RegExp(
      r'(?:^|[.!?]\s+)When\s+it\s+comes\s+to\s+([^,]+?),\s*',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(whenItComesPattern, (m) {
      final lead = m.group(0)!.startsWith(RegExp(r'[.!?]')) ? m.group(0)!.substring(0, 2) : '';
      final topic = m.group(1)!.trim();
      return '${lead}For $topic, ';
    });

    // 4. "One of the (primary|main|key|most significant) (reasons|factors|benefits|drawbacks) is that [Clause]"
    final oneOfThePrimaryPattern = RegExp(
      r'(?:^|[.!?]\s+)One\s+of\s+the\s+(?:primary|main|key|most\s+significant|foremost)\s+(?:reasons|factors|benefits|drawbacks|advantages|disadvantages)\s+(?:is\s+that|is)\s+',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(oneOfThePrimaryPattern, (m) {
      final lead = m.group(0)!.startsWith(RegExp(r'[.!?]')) ? m.group(0)!.substring(0, 2) : '';
      return '${lead}Mainly, ';
    });

    // 5. "It is (important|essential|crucial|vital) to (remember|recognize|note|understand) that [Clause]"
    final itIsImportantPattern = RegExp(
      r'(?:^|[.!?]\s+)It\s+is\s+(?:important|essential|crucial|vital|imperative|worth\s+noting|worth\s+remembering)\s+to\s+(?:remember|recognize|note|understand|consider|acknowledge)\s+that\s+',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(itIsImportantPattern, (m) {
      final lead = m.group(0)!.startsWith(RegExp(r'[.!?]')) ? m.group(0)!.substring(0, 2) : '';
      return lead;
    });

    return out;
  }

  /// Dissolves predictable 3-beat parallel gerund lists
  /// (e.g. "reducing stress, improving focus, and promoting calm")
  /// into natural asymmetric structures.
  String dissolveParallelTriads(String text) {
    final triadPattern = RegExp(
      r'\b([a-z]+ing)\s+([^,]+?),\s+([a-z]+ing)\s+([^,]+?),\s+and\s+([a-z]+ing)\s+([^.!?]+)',
      caseSensitive: false,
    );
    return text.replaceAllMapped(triadPattern, (m) {
      final v1 = m.group(1)!;
      final o1 = m.group(2)!.trim();
      final v2 = m.group(3)!;
      final o2 = m.group(4)!.trim();
      final v3 = m.group(5)!;
      final o3 = m.group(6)!.trim();
      return '$v1 $o1 and $v2 $o2, while $v3 $o3';
    });
  }

  /// Reduces excessive em-dashes (limit to 1 per 150 words) to avoid LLM stylistic tell.
  String regulatePunctuation(String text) {
    final words = TextForensicsLexicons.extractWords(text);
    final maxAllowedDashes = max(1, (words.length / 150).floor());

    int dashCount = 0;
    return text.replaceAllMapped(TextForensicsLexicons.emDashPattern, (match) {
      dashCount++;
      if (dashCount > maxAllowedDashes) {
        return ',';
      }
      return match.group(0)!;
    });
  }

  /// Modulates sentence length to introduce human burstiness (target CV >= [minCv]).
  ///
  /// Greedy hill-climbing on the coefficient of variation: repeatedly try to
  /// split the longest splittable sentence at a natural clause boundary,
  /// keep the split only if it raises CV, and stop at the target or after
  /// roughly one split per three sentences (more reads as choppy). The
  /// previous single-split pass barely moved CV on documents longer than a
  /// few sentences.
  String optimizeBurstiness(String text, {double minCv = 0.52}) {
    var sentences = TextForensicsLexicons.splitSentences(text);
    if (sentences.isEmpty) return text;

    double cvOf(List<String> ss) {
      final lengths = ss.map((x) => TextForensicsLexicons.extractWords(x).length.toDouble()).toList();
      final mean = lengths.reduce((a, b) => a + b) / lengths.length;
      if (mean <= 0) return 0.0;
      final variance = lengths.map((l) => pow(l - mean, 2)).reduce((a, b) => a + b) / lengths.length;
      return sqrt(variance) / mean;
    }

    final maxSplits = max(1, (sentences.length / 3).ceil());
    var cv = cvOf(sentences);
    for (int k = 0; k < maxSplits; k++) {
      if (cv >= minCv && sentences.length >= 2) break;

      final order = List<int>.generate(sentences.length, (i) => i)
        ..sort((a, b) => TextForensicsLexicons.extractWords(sentences[b]).length
            .compareTo(TextForensicsLexicons.extractWords(sentences[a]).length));

      bool improved = false;
      for (final idx in order) {
        final parts = _trySplit(sentences[idx]);
        if (parts == null) continue;
        final candidate = [...sentences.sublist(0, idx), ...parts, ...sentences.sublist(idx + 1)];
        final candidateCv = cvOf(candidate);
        // A single sentence has CV 0 either way; splitting it is the only
        // way to create variance, so accept any split there.
        if (candidateCv > cv || sentences.length == 1) {
          sentences = candidate;
          cv = candidateCv;
          improved = true;
          break;
        }
      }
      if (!improved) break;
    }

    return sentences.join(' ');
  }

  static const Set<String> _clauseStarters = {
    'that', 'this', 'it', 'these', 'those', 'they', 'we', 'he', 'she', 'i',
    'you', 'the', 'its', 'their', 'our', 'my', 'your', 'his', 'her',
    'many', 'most', 'some', 'each', 'both', 'all', 'such', 'neither', 'none', 'one',
    'researchers', 'scientists', 'users', 'teams', 'engineers', 'people', 'companies', 'students',
  };

  static bool _isClauseStarter(String word) {
    final lower = word.toLowerCase();
    if (_clauseStarters.contains(lower)) return true;
    // Proper noun (capitalized) in non-first position
    if (word.length >= 2 && word[0] == word[0].toUpperCase() && word[0] != word[0].toLowerCase()) {
      return true;
    }
    return false;
  }

  /// Splits one sentence at a natural clause boundary, or returns null.
  List<String>? _trySplit(String s) {
    final wordCount = TextForensicsLexicons.extractWords(s).length;
    if (wordCount < 10) return null;

    String end(String x) => RegExp(r'[.!?]$').hasMatch(x) ? x : '$x.';
    bool viable(String first, String second) =>
        TextForensicsLexicons.extractWords(first).length >= 4 &&
        TextForensicsLexicons.extractWords(second).length >= 3;

    // 1. Sentence-final relative clause ", which [verb] ..." -> ". This [verb] ...".
    //    Only when the clause runs to the end: "The API, which is fast, is new"
    //    would otherwise become "The API. This is fast, is new."
    final whichMatch = RegExp(r',\s+which\s+([a-zA-Z]+)', caseSensitive: false).firstMatch(s);
    if (whichMatch != null) {
      final firstPart = s.substring(0, whichMatch.start).trim();
      final rest = s.substring(whichMatch.end).trim();
      if (!rest.contains(',') && viable(firstPart, rest)) {
        return [end(firstPart), end('This ${whichMatch.group(1)} $rest'.trim())];
      }
    }

    // 2. Semicolon "; " -> ". "
    final semiIndex = s.indexOf('; ');
    if (semiIndex != -1) {
      final firstPart = s.substring(0, semiIndex).trim();
      final secondPart = _capitalizeFirst(s.substring(semiIndex + 2).trim());
      if (viable(firstPart, secondPart)) return [end(firstPart), end(secondPart)];
    }

    // 3. Subordinate " that [verb]" in compound sentences.
    final thatMatch = RegExp(
      r'\s+that\s+(bolsters?|enhances?|improves?|helps?|creates?|drives?|allows?|enables?|reduces?|lifts?|boosts?|leads?|builds?|supports?|serves?|makes?)\s+',
      caseSensitive: false,
    ).firstMatch(s);
    if (thatMatch != null && wordCount >= 10) {
      final firstPart = s.substring(0, thatMatch.start).trim();
      var verb = thatMatch.group(1)!;
      if (!verb.endsWith('s')) verb = '${verb}s';
      final rest = s.substring(thatMatch.end).trim();
      if (viable(firstPart, rest)) return [end(firstPart), end('This $verb $rest'.trim())];
    }

    // 3.5. Instrumental clause " by [verb-ing] " -> ". This [verb-s] "
    final byIngMatch = RegExp(
      r'\s+by\s+([a-zA-Z]+ing)\s+',
      caseSensitive: false,
    ).firstMatch(s);
    if (byIngMatch != null && wordCount >= 11) {
      final firstPart = s.substring(0, byIngMatch.start).trim();
      final ingWord = byIngMatch.group(1)!.toLowerCase();
      String verb = 'helps';
      if (ingWord == 'simplifying') {
        verb = 'simplifies';
      } else if (ingWord == 'streamlining') {
        verb = 'streamlines';
      } else if (ingWord == 'optimizing') {
        verb = 'optimizes';
      } else if (ingWord == 'enhancing') {
        verb = 'enhances';
      } else if (ingWord == 'using' || ingWord == 'utilizing') {
        verb = 'uses';
      } else if (ingWord == 'providing') {
        verb = 'provides';
      } else if (ingWord.endsWith('ying')) {
        verb = '${ingWord.substring(0, ingWord.length - 4)}ies';
      } else {
        verb = '${ingWord.substring(0, ingWord.length - 3)}s';
      }
      final rest = s.substring(byIngMatch.end).trim();
      if (viable(firstPart, rest)) return [end(firstPart), end('This $verb $rest'.trim())];
    }

    // 4. Coordinating ", but|yet|so|though|although " and ", and <pronoun/determiner> ".
    final coordMatch = RegExp(r',\s+(and|but|yet|so|though|although)\s+([A-Za-z]+)', caseSensitive: false).firstMatch(s);
    if (coordMatch != null) {
      final firstPart = s.substring(0, coordMatch.start).trim();
      final conj = coordMatch.group(1)!.toLowerCase();
      final nextWord = coordMatch.group(2)!;
      final isList = conj == 'and' && firstPart.contains(',');
      final startsClause = _isClauseStarter(nextWord);
      if (!isList && startsClause) {
        final rest = s.substring(coordMatch.start + coordMatch.group(0)!.length - nextWord.length).trim();
        final String second;
        if (conj == 'and') {
          second = _capitalizeFirst(rest);
        } else if (conj == 'but' || conj == 'though' || conj == 'although') {
          second = 'Still, $rest';
        } else {
          second = '${_capitalizeFirst(conj)} $rest';
        }
        if (viable(firstPart, rest)) return [end(firstPart), end(second)];
      }
    }

    // 4.5. Uncomma contrast " but <clauseStarter> " in compound sentences (>= 14 words)
    final uncommaMatch = RegExp(r'\s+but\s+([A-Za-z]+)', caseSensitive: false).firstMatch(s);
    if (uncommaMatch != null && wordCount >= 14) {
      final firstPart = s.substring(0, uncommaMatch.start).trim();
      final nextWord = uncommaMatch.group(1)!;
      final startsClause = _isClauseStarter(nextWord);
      if (startsClause) {
        final rest = s.substring(uncommaMatch.start + uncommaMatch.group(0)!.length - nextWord.length).trim();
        final second = 'Still, $rest';
        if (viable(firstPart, rest)) return [end(firstPart), end(second)];
      }
    }

    // 5. Coordinating ", while|whereas " -> ". Meanwhile, "
    final whileMatch = RegExp(r',\s+(while|whereas)\s+([A-Za-z]+)', caseSensitive: false).firstMatch(s);
    if (whileMatch != null) {
      final firstPart = s.substring(0, whileMatch.start).trim();
      final nextWord = whileMatch.group(2)!;
      final rest = s.substring(whileMatch.start + whileMatch.group(0)!.length - nextWord.length).trim();
      if (viable(firstPart, rest)) return [end(firstPart), end('Meanwhile, $rest')];
    }

    // 6. Participial clause ", allowing/enabling [Subject] to [Verb]" -> ". This lets [Subject] [Verb]"
    final allowMatch = RegExp(r',\s+(allowing|enabling)\s+([^,]+?)\s+to\s+([a-zA-Z]+)', caseSensitive: false).firstMatch(s);
    if (allowMatch != null && wordCount >= 12) {
      final firstPart = s.substring(0, allowMatch.start).trim();
      final subj = allowMatch.group(2)!.trim();
      final verb = allowMatch.group(3)!.trim();
      final rest = s.substring(allowMatch.end).trim();
      final secondPart = 'This lets $subj $verb $rest'.trim();
      if (viable(firstPart, secondPart)) return [end(firstPart), end(secondPart)];
    }

    // 7. Consequence clause ", leading to [Noun/Clause]" -> ". This leads to [Noun/Clause]"
    final leadingMatch = RegExp(r',\s+leading\s+to\s+([^,.;]+)', caseSensitive: false).firstMatch(s);
    if (leadingMatch != null && wordCount >= 12) {
      final firstPart = s.substring(0, leadingMatch.start).trim();
      final rest = leadingMatch.group(1)!.trim();
      final secondPart = 'This leads to $rest'.trim();
      if (viable(firstPart, secondPart)) return [end(firstPart), end(secondPart)];
    }

    // 8. Consequence clause ", resulting in [Noun/Clause]" -> ". This results in [Noun/Clause]"
    final resultingMatch = RegExp(r',\s+resulting\s+in\s+([^,.;]+)', caseSensitive: false).firstMatch(s);
    if (resultingMatch != null && wordCount >= 12) {
      final firstPart = s.substring(0, resultingMatch.start).trim();
      final rest = resultingMatch.group(1)!.trim();
      final secondPart = 'This results in $rest'.trim();
      if (viable(firstPart, secondPart)) return [end(firstPart), end(secondPart)];
    }

    // 9. Explanatory clause ", because <clauseStarter>" (wordCount >= 14) -> ". This is because ..."
    final becauseMatch = RegExp(r',\s+because\s+([A-Za-z]+)', caseSensitive: false).firstMatch(s);
    if (becauseMatch != null && wordCount >= 14) {
      final firstPart = s.substring(0, becauseMatch.start).trim();
      final nextWord = becauseMatch.group(1)!;
      if (_clauseStarters.contains(nextWord.toLowerCase())) {
        final rest = s.substring(becauseMatch.start + becauseMatch.group(0)!.length - nextWord.length).trim();
        final secondPart = 'This is because $rest'.trim();
        if (viable(firstPart, secondPart)) return [end(firstPart), end(secondPart)];
      }
    }

    // 10. Participial clause ", showing/highlighting/proving/revealing [Clause]" -> ". This shows/proves [Clause]"
    final participialMatch = RegExp(
      r',\s+(showing|highlighting|proving|demonstrating|reflecting|illustrating|ensuring|revealing)\s+([^,.;]+)',
      caseSensitive: false,
    ).firstMatch(s);
    if (participialMatch != null && wordCount >= 11) {
      final firstPart = s.substring(0, participialMatch.start).trim();
      final pWord = participialMatch.group(1)!.toLowerCase();
      final rest = s.substring(participialMatch.start + participialMatch.group(0)!.length - participialMatch.group(2)!.length).trim();
      final verb = pWord.endsWith('ing') ? '${pWord.substring(0, pWord.length - 3)}s' : '${pWord}s';
      final secondPart = 'This $verb $rest'.trim();
      if (viable(firstPart, secondPart)) return [end(firstPart), end(secondPart)];
    }

    // 11. Temporal clause ", as (he|she|they|it|we)\s+" (wordCount >= 14) -> ". He/she/they/it/we ..."
    final asMatch = RegExp(r',\s+as\s+(he|she|they|it|we)\s+([^,.;]+)', caseSensitive: false).firstMatch(s);
    if (asMatch != null && wordCount >= 14) {
      final firstPart = s.substring(0, asMatch.start).trim();
      final pronoun = asMatch.group(1)!;
      final rest = s.substring(asMatch.start + asMatch.group(0)!.length - asMatch.group(2)!.length).trim();
      final secondPart = '${_capitalizeFirst(pronoun)} $rest'.trim();
      if (viable(firstPart, secondPart)) return [end(firstPart), end(secondPart)];
    }

    return null;
  }

  /// Strips conversational preamble and faux-candor conversational openers.
  String dissolveFauxCandorOpeners(String text) {
    final candor = RegExp(
      r'^(?:let(?:\x27s|\s+us)\s+(?:dive\s+in|explore|break\s+this\s+down)|here(?:\x27s|\s+is)\s+what\s+you\s+need\s+to\s+know|without\s+further\s+ado|honestly[?,]?|look,?\s+|here(?:\x27s|\s+is)\s+the\s+thing:?|the\s+truth\s+is,?\s*)\s*',
      caseSensitive: false,
    );
    final sentences = TextForensicsLexicons.splitSentences(text);
    if (sentences.isEmpty) return text;
    final modified = sentences.map((s) {
      final m = candor.firstMatch(s.trimLeft());
      if (m != null) {
        final rest = s.trimLeft().substring(m.end).trim();
        return _capitalizeFirst(rest);
      }
      return s;
    }).toList();
    return modified.join(' ');
  }

  /// Converts inflated passive copula expressions into direct active verbs.
  String dissolvePassiveCopulas(String text) {
    final copulas = {
      r'\bserves as an indicator of\b': 'indicates',
      r'\bserve as an indicator of\b': 'indicate',
      r'\bserves as an illustration of\b': 'illustrates',
      r'\bserve as an illustration of\b': 'illustrate',
      r'\bacts as a catalyst for\b': 'drives',
      r'\bact as a catalyst for\b': 'drive',
      r'\bis characterized by\b': 'features',
      r'\bare characterized by\b': 'feature',
      r'\bis reflective of\b': 'reflects',
      r'\bare reflective of\b': 'reflect',
      r'\bis of paramount importance\b': 'is vital',
      r'\bare of paramount importance\b': 'are vital',
      r'\bhas the capacity to\b': 'can',
      r'\bhave the capacity to\b': 'can',
      r'\bis widely considered to be\b': 'is seen as',
      r'\bare widely considered to be\b': 'are seen as',
      r'\bhas been demonstrated to\b': 'has shown to',
      r'\bhave been demonstrated to\b': 'have shown to',
      r'\bhas been shown to\b': 'has shown to',
      r'\bhave been shown to\b': 'have shown to',
      r'\bis known to have\b': 'has',
      r'\bare known to have\b': 'have',
      r'\bis believed to be\b': 'is',
      r'\bare believed to be\b': 'are',
      r'\bcan be seen as\b': 'serves as',
      r'\bcan be viewed as\b': 'is',
      r'\bare deemed to be\b': 'are',
      r'\bis deemed to be\b': 'is',
      r'\bwas found to be\b': 'proved',
      r'\bwere found to be\b': 'proved',
      r'\bhas been observed that\b': 'evidence shows that',
      r'\bit can be argued that\b': 'arguably,',
      r'\bplays a crucial role in\b': 'is central to',
      r'\bplays a vital role in\b': 'is central to',
      r'\bplays a pivotal role in\b': 'is key to',
      r'\bplays an important role in\b': 'helps with',
      r'\bplay a crucial role in\b': 'are central to',
      r'\bplay a vital role in\b': 'are central to',
      r'\bplay an important role in\b': 'help with',
      r'\bplay a key role in\b': 'are key to',
      r'\bcan lead to a wide range of\b': 'causes various',
      r'\bcan lead to a variety of\b': 'causes various',
    };
    var out = text;
    for (final entry in copulas.entries) {
      out = out.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
    }
    return out;
  }

  /// Cleans up any duplicate spaces, misplaced commas, or missing terminal periods.
  String cleanPunctuationAndSpacing(String text) {
    var out = text
        .replaceAll(RegExp(r'\s+,'), ',')
        .replaceAll(RegExp(r'\s+\.'), '.')
        .replaceAll(RegExp(r'\s+;'), ';')
        .replaceAll(RegExp(r'\s+:'), ':')
        .replaceAll(RegExp(r'\s+\?'), '?')
        .replaceAll(RegExp(r'\s+!'), '!')
        .replaceAll(RegExp(r',\s*,'), ',')
        .replaceAll(RegExp(r',\s*\.'), '.')
        .replaceAll(RegExp(r'\.\s*,'), '.')
        .replaceAll(RegExp(r';\s*;'), ';')
        .replaceAll(RegExp(r'\.\.+'), '.')
        .replaceAllMapped(RegExp(r'\b(the|and|or|in|at|to|that)\s+\1\b', caseSensitive: false), (m) => m.group(1)!)
        .replaceAllMapped(
          RegExp(r'\b(?:crucial|vital|essential|central|key|pivotal) and (?:crucial|vital|essential|central|key|pivotal)\b', caseSensitive: false),
          (m) => m.group(0)![0] == m.group(0)![0].toUpperCase() ? 'Key' : 'key',
        )
        .replaceAllMapped(RegExp(r'\ball (are|is|were|was) ', caseSensitive: false), (m) => '${m.group(1)} all ')
        .replaceAll(RegExp(r'(^|[.!?]\s+)[,;:]\s*'), r'$1')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();

    return out;
  }

  /// Eliminates empty one-line dramatic closures and platitudes.
  String dissolveOneLineClosers(String text) {
    final closers = RegExp(
      r'(?:that\s+is\s+the\s+real\s+win|read\s+that\s+again|let\s+that\s+sink\s+in|the\s+future\s+looks\s+bright|exciting\s+times\s+lie\s+ahead|only\s+time\s+will\s+tell|a\s+step\s+in\s+the\s+right\s+direction|and\s+that\s+makes\s+all\s+the\s+difference|and\s+that\s+is\s+what\s+truly\s+matters|the\s+journey\s+has\s+just\s+begun|the\s+old\s+rules\s+were\s+gone|the\s+possibilities\s+are\s+endless|the\s+choice\s+is\s+ours|and\s+the\s+rest\s+is\s+history|time\s+will\s+tell)\.?\s*$',
      caseSensitive: false,
    );
    final sentences = TextForensicsLexicons.splitSentences(text);
    if (sentences.length <= 1) return text;
    final last = sentences.last.trim();
    if (closers.hasMatch(last)) {
      return sentences.sublist(0, sentences.length - 1).join(' ');
    }
    return text;
  }

  /// Eliminates chatbot wrapper residue, greetings, and knowledge-cutoff disclaimers.
  String dissolveChatbotResidue(String text) {
    var out = text;
    // Strip initial greeting or opener wrapper sentence
    out = out.replaceFirst(
      RegExp(r'^(?:(?:Sure|Certainly|Of course|Great question|Glad to help|Absolutely)[!.,]?\s*)?(?:Here(?:\x27s|\s+is)\s+(?:an?\s+)?(?:overview|summary|breakdown|guide|explanation|list|look)\s+of\s+[^.!?]+[.!?]\s*|Here(?:\x27s|\s+is)\s+.*?:)?\s*', caseSensitive: false),
      '',
    );
    // Strip trailing conversational sign-offs (can be chained)
    out = out.replaceFirst(
      RegExp(r'(?:\s*\b(?:I hope this helps|Let me know if you(?:’|\x27)?d like me to (?:expand|modify|help)|Feel free to ask if you have any questions|Don(?:\x27|’)?t hesitate to reach out)[!.]?\s*)+$', caseSensitive: false),
      '',
    );
    // Strip knowledge cutoff disclaimers
    out = out.replaceAll(
      RegExp(r'\b(?:as of (?:my (?:last )?(?:knowledge )?cutoff(?:\s+(?:in|date)?\s+\d{4})?|\w+\s+\d{4})|based on available information|while specific details are limited),?\s*', caseSensitive: false),
      '',
    );
    return out.trim();
  }

  /// Dissolves phantom counter-arguments ("To be clear,", "Don't get me wrong,").
  String dissolvePhantomArguments(String text) {
    final phantoms = {
      r'\bto be clear,\s*': '',
      r'\bdon(?:\x27|’)?t get me wrong,\s*': '',
      r'\bthis is not to say that\s+': 'this does not mean that ',
      r'\bthis isn(?:\x27|’)?t mainly about\b': 'this is not about',
      r'\ba tempting approach would be to\b': 'one option is to',
      r'\bit would be easy to just\b': 'one could simply',
      r'\bsome might argue that\s+([^,]+),\s*but\s+': r'while some argue that $1, ',
    };
    var out = text;
    for (final entry in phantoms.entries) {
      out = out.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
    }
    return out;
  }

  /// Replaces faux-profound aphorisms and staged depth phrases with direct language.
  String dissolveAphorismsAndDeepSayings(String text) {
    final aphorisms = {
      r'\bat its core, what really matters is\b': 'what matters is',
      r'\bat its core,?\s*': '',
      r'\bat the heart of the matter lies\b': 'central to this is',
      r'\bat the heart of the matter,?\s*': '',
      r'\bthe real question is whether\b': 'the question is whether',
      r'\bthe deeper issue is\b': 'the main issue is',
      r'\bin reality, the fundamental truth is that\b': 'in practice,',
    };
    var out = text;
    for (final entry in aphorisms.entries) {
      out = out.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
    }
    return out;
  }

  /// Dissolves stacked qualifiers into direct assertions.
  String dissolveStackedQualifiers(String text) {
    final qualifiers = {
      r'\bcould potentially possibly\b': 'could',
      r'\bcould potentially\b': 'could',
      r'\bmight arguably\b': 'may',
      r'\bin some cases it may potentially\b': 'in some cases it may',
      r'\bit is also possible that it might\b': 'it may',
      r'\bit could arguably be said that\b': 'one could say that',
    };
    var out = text;
    for (final entry in qualifiers.entries) {
      out = out.replaceAll(RegExp(entry.key, caseSensitive: false), entry.value);
    }
    return out;
  }

  /// Dissolves hyphenated word pairs following copula verbs (Wikipedia Sign 10).
  String dissolveHyphenatedPredicatePairs(String text) {
    const pairs = [
      'high-quality',
      'cross-functional',
      'data-driven',
      'client-facing',
      'real-time',
      'well-known',
      'long-term',
      'end-to-end',
    ];
    var out = text;
    for (final pair in pairs) {
      final unhyphenated = pair.replaceAll('-', ' ');
      out = out.replaceAllMapped(
        RegExp(r'\b(is|are|was|were|remains|remain|seems|seem)\s+' + RegExp.escape(pair) + r'\b', caseSensitive: false),
        (m) => '${m.group(1)} $unhyphenated',
      );
    }
    return out;
  }
}

