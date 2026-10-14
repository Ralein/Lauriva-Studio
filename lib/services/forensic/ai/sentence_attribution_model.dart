import 'dart:math';
import '../../text_forensics_lexicons.dart';

/// Per-sentence AI attribution with the cues that drove it.
class SentenceAttribution {
  final double aiProbability; // 0.0 to 100.0
  final List<String> tells;

  const SentenceAttribution({required this.aiProbability, required this.tells});
}

/// Hierarchical (empirical-Bayes) sentence attribution.
///
/// A single sentence is far too short for distributional stylometry: its
/// burstiness is always 0, its type-token ratio is always near 1, and every
/// length-gated model shrinks it toward 50%. Running the document classifier
/// on each sentence in isolation therefore mostly measures sentence length,
/// not authorship.
///
/// Instead each sentence starts from a *local prior* — the document-level
/// posterior blended with the posterior of the sliding windows that contain
/// it — and is updated in log-odds space by sentence-local lexical evidence
/// whose strength does not depend on length (stock vocabulary, formulaic
/// scaffolding, chatbot residue, first-person voice, contractions, ...).
/// Each cue contributes an approximate log-likelihood ratio, the standard
/// naive-Bayes combination. Evidence is lightly smoothed with neighbouring
/// sentences, since AI-drafted passages arrive in contiguous runs rather
/// than isolated sentences.
///
/// Net effect: a clean sentence in a human document stays low, a sentence
/// full of stock phrasing inside a human document is still surfaced, and
/// sentences in an AI document are separated by how much evidence they
/// actually carry instead of all scoring the same.
class SentenceAttributionModel {
  /// How strongly the (already calibrated) local prior anchors each sentence.
  /// < 1 so a single document-level verdict cannot saturate every sentence.
  final double priorStrength;

  /// Share of a sentence's evidence contributed by each adjacent sentence.
  final double neighbourWeight;

  const SentenceAttributionModel({this.priorStrength = 1.0, this.neighbourWeight = 0.15});

  static final RegExp _contrast = RegExp(
    r"\b(?:it(?:'s|\s+is)\s+not\s+(?:just|only|merely)\b|not\s+(?:only|just|merely)\s+[^,.?!]+,?\s*but\b)",
    caseSensitive: false,
  );
  static final RegExp _wrapper = RegExp(
    r"\b(?:as\s+an\s+ai|i\s+hope\s+this\s+helps|great\s+question|certainly!|would\s+you\s+like\s+me\s+to)",
    caseSensitive: false,
  );
  static final RegExp _stagedOpener = RegExp(
    r"\b(?:let(?:'s|\s+us)\s+(?:dive|delve|explore|break)|here(?:'s|\s+is)\s+(?:the\s+thing|what\s+you\s+need)|at\s+its\s+core|in\s+today(?:'s)?\s+(?:fast-paced|digital|ever|rapidly|modern)|in\s+the\s+(?:ever-evolving|rapidly\s+evolving)|stands\s+as\s+a\s+testament|plays\s+a\s+(?:crucial|pivotal|vital|key)\s+role)",
    caseSensitive: false,
  );
  static final RegExp _participleOpener = RegExp(
    r"^\s*(?:By\s+(?:leveraging|integrating|analyzing|streamlining|utilizing|fostering|combining|optimizing|introducing|employing)|Addressing\s+these|Recognizing\s+the|To\s+(?:effectively\s+)?(?:navigate|address|foster|leverage|mitigate|ensure))\b",
    caseSensitive: false,
  );
  static final RegExp _participleTail = RegExp(
    r',\s+(?:thereby\s+)?(?:highlighting|underscoring|emphasizing|ensuring|enabling|reflecting|symbolizing|fostering|showcasing|paving|allowing|mitigating|optimizing)\b',
    caseSensitive: false,
  );
  static final RegExp _triad = RegExp(r'\b[a-zA-Z]{3,},\s+[a-zA-Z]{3,},\s+and\s+[a-zA-Z]{3,}\b');
  static final RegExp _contraction = RegExp(r"[a-zA-Z](?:n't|'re|'m|'ll|'ve|'d)\b", caseSensitive: false);
  static final RegExp _firstPersonSingular = RegExp(r"\b(?:i|me|my|mine|myself|i'm|i've|i'd|i'll)\b", caseSensitive: false);
  static final RegExp _informal = RegExp(
    r"\b(?:honestly|anyway|kinda|gonna|wanna|yeah|nope|okay|ok|stuff|guess|lol|basically|pretty much|turns out)\b",
    caseSensitive: false,
  );

  /// Scores [sentences]. [documentAiProbability] and each entry of
  /// [localPriors] (if given, one per sentence) are on a 0-100 scale.
  List<SentenceAttribution> score(
    List<String> sentences, {
    required double documentAiProbability,
    List<double?>? localPriors,
    double documentBurstiness = 0.5,
  }) {
    if (sentences.isEmpty) return const [];

    final evidence = <double>[];
    final tells = <List<String>>[];
    for (final s in sentences) {
      final r = _localEvidence(s, documentBurstiness);
      evidence.add(r.llr);
      tells.add(r.tells);
    }

    final results = <SentenceAttribution>[];
    for (int i = 0; i < sentences.length; i++) {
      final prev = i > 0 ? evidence[i - 1] : evidence[i];
      final next = i + 1 < sentences.length ? evidence[i + 1] : evidence[i];
      final smoothed = (1 - 2 * neighbourWeight) * evidence[i] + neighbourWeight * (prev + next);

      final local = localPriors != null && i < localPriors.length ? localPriors[i] : null;
      final priorPct = local == null ? documentAiProbability : 0.5 * documentAiProbability + 0.5 * local;
      final prior = (priorPct / 100.0).clamp(0.02, 0.98);
      final logit = priorStrength * log(prior / (1 - prior)) + smoothed;
      final p = 1.0 / (1.0 + exp(-logit.clamp(-12.0, 12.0)));
      results.add(SentenceAttribution(aiProbability: (p * 100.0).clamp(0.0, 100.0), tells: tells[i]));
    }
    return results;
  }

  ({double llr, List<String> tells}) _localEvidence(String sentence, double docBurstiness) {
    double llr = 0.0;
    final tells = <String>[];
    final lower = sentence.toLowerCase();
    final words = TextForensicsLexicons.extractWords(sentence);
    final n = words.length;

    // --- Machine-authorship cues ---
    if (_wrapper.hasMatch(sentence)) {
      llr += 3.0;
      tells.add('Chatbot wrapper residue');
    }

    int stock = 0;
    final stockHits = <String>{};
    for (final w in words) {
      final lw = w.toLowerCase();
      if (TextForensicsLexicons.aiStockWords.contains(lw)) {
        stock++;
        stockHits.add(lw);
      }
    }
    if (stock > 0) {
      llr += 0.45 * min(stock, 3);
      for (final w in stockHits) {
        tells.add('AI word: "$w"');
      }
    }

    final trimmed = lower.trimLeft();
    if (TextForensicsLexicons.transitionOpeners.any((t) => trimmed.startsWith('$t,') || trimmed.startsWith('$t '))) {
      llr += 0.55;
      tells.add('Formal transition opener');
    }
    if (_contrast.hasMatch(sentence)) {
      llr += 0.7;
      tells.add('Not X but Y contrast');
    }
    if (_stagedOpener.hasMatch(sentence)) {
      llr += 0.6;
      tells.add('Staged / inflated framing');
    }
    if (_participleOpener.hasMatch(sentence)) {
      llr += 0.55;
      tells.add('Formulaic participial / purpose opener');
    }
    int boilerplate = 0;
    for (final bp in TextForensicsLexicons.academicBoilerplates) {
      if (lower.contains(bp)) boilerplate++;
    }
    if (boilerplate > 0) {
      llr += 0.5 * min(boilerplate, 2);
      tells.add('Boilerplate phrase');
    }
    if (_participleTail.hasMatch(sentence)) {
      llr += 0.5;
      tells.add('Shallow -ing participle tail');
    }
    if (_triad.hasMatch(sentence)) {
      llr += 0.3;
      tells.add('Forced triad');
    }
    if (TextForensicsLexicons.emDashPattern.hasMatch(sentence)) {
      llr += 0.2;
      tells.add('Em dash usage');
    }
    if (TextForensicsLexicons.markdownBlockPattern.hasMatch(sentence) ||
        TextForensicsLexicons.markdownBoldPattern.hasMatch(sentence)) {
      llr += 0.5;
      tells.add('Markdown formatting artifact');
    }
    // Metronomic mid-length sentence inside a low-variance document.
    if (docBurstiness < 0.35 && n >= 14 && n <= 26) {
      llr += 0.15;
    }

    // --- Human-authorship cues ---
    if (_firstPersonSingular.hasMatch(sentence)) llr -= 0.4;
    if (_contraction.hasMatch(sentence)) llr -= 0.3;
    if (_informal.hasMatch(sentence)) llr -= 0.4;
    final end = sentence.trimRight();
    if (end.endsWith('?') || end.endsWith('!')) llr -= 0.2;
    if (n > 0 && n < 5 && tells.isEmpty) llr -= 0.25;
    if (n > 35) llr -= 0.15;

    return (llr: llr, tells: tells);
  }
}
