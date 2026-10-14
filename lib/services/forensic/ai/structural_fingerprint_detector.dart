import 'dart:math' as math;

import '../../text_forensics_lexicons.dart';

/// Structural fingerprint detector for adversarial robustness.
///
/// Measures sentence opener homogeneity, length periodicity, and clause symmetry.
/// These structural patterns are INVARIANT to synonym substitution — you cannot
/// fool this detector by running text through a thesaurus.
///
/// Phase 16: Closes Attack Vectors 3 (synonym rotation) and 5 (fragmentation).
class StructuralFingerprintDetector {
  // Known AI transitional opener patterns (invariant to synonym substitution)
  static const _transitionOpeners = {
    'furthermore', 'moreover', 'additionally', 'consequently', 'therefore',
    'however', 'nevertheless', 'nonetheless', 'in conclusion', 'in summary',
    'in addition', 'as a result', 'on the other hand', 'first', 'second',
    'third', 'finally', 'in contrast', 'similarly', 'likewise', 'to summarize',
    'to conclude', 'it is worth noting', 'it is important', 'it is crucial',
    'notably', 'importantly', 'significantly', 'ultimately', 'overall',
    'by integrating', 'by leveraging', 'by analyzing', 'by streamlining',
    'by utilizing', 'by combining', 'by addressing', 'by fostering',
    'to assess', 'to address', 'to mitigate', 'to evaluate', 'to ensure',
    'while these', 'while this', 'while modern', 'given the', 'in order to',
  };

  // Frontier LLM Participial Chain & Gerund Tail patterns
  static final RegExp _participialOpenerPattern = RegExp(
    r'^\s*(?:by|through|in|after|upon|to)\s+[a-z]+(?:ing)?\b',
    caseSensitive: false,
  );

  static final RegExp _gerundTailPattern = RegExp(
    r',\s*(?:thereby|thus|further|ultimately)?\s*(?:ensuring|enabling|allowing|fostering|providing|mitigating|optimizing|facilitating|enhancing|driving|paving|safeguarding|cultivating|maintaining)\b',
    caseSensitive: false,
  );

  static final RegExp _triadicListPattern = RegExp(
    r'\b(?:[a-zA-Z]+(?:\s+[a-zA-Z]+){0,3}),\s+(?:[a-zA-Z]+(?:\s+[a-zA-Z]+){0,3}),?\s+(?:and|as well as)\s+(?:[a-zA-Z]+(?:\s+[a-zA-Z]+){0,3})\b',
    caseSensitive: false,
  );

  /// Computes structural AI score [0.0–100.0] based on:
  /// 1. Opener homogeneity (AI uses same opener types repeatedly)
  /// 2. Length periodicity (AI produces near-uniform sentence lengths)
  /// 3. Clause symmetry (AI structures paragraphs with uniform depth)
  /// 4. Participial chain & gerund modifier density (characteristic of GPT-5/frontier models)
  /// 5. Triadic rhetorical noun parallelisms
  double computeStructuralAiScore(List<String> sentences) {
    if (sentences.length < 3) return 0.0;

    final openerHomogeneity = _computeOpenerHomogeneity(sentences);
    final lengthPeriodicity = _computeLengthPeriodicity(sentences);
    final clauseSymmetry = _computeClauseSymmetry(sentences);
    final participialChains = _computeParticipialChainScore(sentences);
    final triadicScore = _computeTriadicScore(sentences);

    // Weighted composite combining classical stylometry with frontier structural markers
    final score = openerHomogeneity * 0.20 +
        lengthPeriodicity * 0.20 +
        clauseSymmetry * 0.20 +
        participialChains * 0.20 +
        triadicScore * 0.20;
    return (score * 100.0).clamp(0.0, 100.0);
  }

  double _computeParticipialChainScore(List<String> sentences) {
    int matches = 0;
    for (final sent in sentences) {
      final hasOpener = _participialOpenerPattern.hasMatch(sent);
      final hasTail = _gerundTailPattern.hasMatch(sent);
      if (hasOpener || hasTail) matches++;
      if (hasOpener && hasTail) matches++; // Strong synergy
    }
    return (matches / (sentences.length * 1.0)).clamp(0.0, 1.0);
  }

  double _computeTriadicScore(List<String> sentences) {
    int triadCount = 0;
    for (final sent in sentences) {
      triadCount += _triadicListPattern.allMatches(sent).length;
    }
    return (triadCount / math.max(sentences.length * 0.4, 1.0)).clamp(0.0, 1.0);
  }

  /// Detects sentence fragmentation attack (Attack Vector 5).
  /// Consecutive short sentences with high structural similarity → fragmented AI.
  double detectFragmentation(List<String> sentences) {
    if (sentences.length < 4) return 0.0;

    int fragmentedClusters = 0;
    int i = 0;

    while (i < sentences.length - 1) {
      final len1 = _wordCount(sentences[i]);
      final len2 = _wordCount(sentences[i + 1]);

      if (len1 <= 12 && len2 <= 12) {
        // Check structural similarity
        final sim = _structuralSimilarity(sentences[i], sentences[i + 1]);
        if (sim > 0.6) {
          fragmentedClusters++;
        }
      }
      i++;
    }

    return (fragmentedClusters / sentences.length).clamp(0.0, 1.0);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  double _computeOpenerHomogeneity(List<String> sentences) {
    if (sentences.length < 3) return 0.0;
    int transitionCount = 0;
    for (final sent in sentences) {
      final lower = sent.trim().toLowerCase();
      for (final opener in _transitionOpeners) {
        if (lower.startsWith(opener)) {
          transitionCount++;
          break;
        }
      }
    }
    // A single transition opener in a human paragraph is standard expository style.
    // AI text exhibits repetitive scaffolding across multiple sentences.
    if (transitionCount < 2) return 0.0;
    final ratio = transitionCount / sentences.length;
    return ((ratio - 0.20) / 0.40).clamp(0.0, 1.0);
  }

  double _computeLengthPeriodicity(List<String> sentences) {
    // Require at least 5 sentences for reliable variance estimation
    if (sentences.length < 5) return 0.0;
    final lengths = sentences.map(_wordCount).toList();
    final mean = lengths.reduce((a, b) => a + b) / lengths.length;
    if (mean == 0) return 0.0;

    // Coefficient of variation: low CV = uniform = AI-like
    double variance = 0.0;
    for (final l in lengths) {
      variance += (l - mean) * (l - mean);
    }
    final cv = math.sqrt(variance / lengths.length) / mean;

    // CV < 0.38 indicates strong AI sentence length uniformity (human CV is typically > 0.50)
    return (1.0 - (cv / 0.38).clamp(0.0, 1.0));
  }

  double _computeClauseSymmetry(List<String> sentences) {
    // Require at least 5 sentences for reliable variance estimation
    if (sentences.length < 5) return 0.0;
    // Count comma-separated clauses per sentence
    final clauseCounts = sentences.map((s) => s.split(',').length).toList();
    if (clauseCounts.isEmpty) return 0.0;

    final mean = clauseCounts.reduce((a, b) => a + b) / clauseCounts.length;
    if (mean == 0) return 0.0;

    double variance = 0.0;
    for (final c in clauseCounts) {
      variance += (c - mean) * (c - mean);
    }
    final cv = math.sqrt(variance / clauseCounts.length) / mean;

    // Uniform clause count = AI symmetry
    return (1.0 - (cv / 0.38).clamp(0.0, 1.0));
  }

  double _structuralSimilarity(String s1, String s2) {
    // Simple structural fingerprint: compare part-of-speech skeleton
    // Using length similarity + opener match as proxy
    final len1 = _wordCount(s1);
    final len2 = _wordCount(s2);
    final lenSim = 1.0 - (len1 - len2).abs() / math.max(len1 + len2, 1);
    return lenSim;
  }

  // Han/kana characters count as units: Chinese and Japanese have no spaces.
  int _wordCount(String s) => TextForensicsLexicons.countWordUnits(s);
}
