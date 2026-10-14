import 'dart:math';
import 'text_forensics_lexicons.dart';
import 'forensic/ai/gbdt_classifier.dart';
import 'forensic/ai/platt_calibrator.dart';
import 'forensic/ai/ngram_language_model.dart';
import 'forensic/ai/feature_vector_cache.dart';

/// Statistical confidence level based on passage token length and feature signal stability.
enum AiConfidenceLevel {
  insufficient(label: 'Insufficient Evidence', badge: 'SHORT PASSAGE', minWords: 0),
  low(label: 'Low Confidence', badge: 'PRELIMINARY', minWords: 50),
  moderate(label: 'Moderate Confidence', badge: 'EVALUATED', minWords: 150),
  high(label: 'High Confidence', badge: 'HIGH CERTAINTY', minWords: 500);

  final String label;
  final String badge;
  final int minWords;

  const AiConfidenceLevel({
    required this.label,
    required this.badge,
    required this.minWords,
  });

  static AiConfidenceLevel fromWordCount(int count) {
    if (count < 50) return AiConfidenceLevel.insufficient;
    if (count < 150) return AiConfidenceLevel.low;
    if (count < 500) return AiConfidenceLevel.moderate;
    return AiConfidenceLevel.high;
  }
}

/// Ternary classification representing calibrated authorship attribution.
enum AiAuthorshipClass {
  likelyHuman(
    label: 'Likely Human Written',
    badge: 'HUMAN WRITTEN',
    description: 'High syntactic entropy, natural burstiness, and asymmetric pacing typical of authentic human prose.',
  ),
  mixedOrEdited(
    label: 'Mixed / Human-Edited AI',
    badge: 'MIXED / EDITED',
    description: 'Blended characteristics. Likely an AI draft substantially edited by a human or human prose with formulaic AI fragments.',
  ),
  likelyAi(
    label: 'Likely AI-Generated',
    badge: 'LIKELY AI',
    description: 'Compressed syntactic variance, characteristic transition openers, and predictable rhetorical scaffolding.',
  ),
  inconclusive(
    label: 'Inconclusive / Short Text',
    badge: 'INSUFFICIENT DATA',
    description: 'Sample does not contain enough tokens to reliably infer stylometric distribution.',
  ),
  uncertain(
    label: 'Uncertain / Borderline Evidence',
    badge: 'UNCERTAIN',
    description: 'The available evidence is insufficient for a reliable determination.',
  );

  final String label;
  final String badge;
  final String description;

  const AiAuthorshipClass({
    required this.label,
    required this.badge,
    required this.description,
  });
}

/// Diagnostic signal identified during forensic feature analysis.
class ForensicSignal {
  final String family;
  final String name;
  final double score;
  final String description;

  const ForensicSignal({
    required this.family,
    required this.name,
    required this.score,
    required this.description,
  });
}

/// Comprehensive forensic inspection result produced by [AiForensicService].
class AiForensicResult {
  final double aiProbability; // 0.0 to 100.0
  final double humanProbability; // 0.0 to 100.0
  final double uncertainty; // 0.0 to 1.0
  final AiConfidenceLevel confidenceLevel;
  final AiAuthorshipClass authorshipClass;
  final List<ForensicSignal> detectedSignals;
  final List<double> featureVector;
  final String defensibleSummary;

  const AiForensicResult({
    required this.aiProbability,
    required this.humanProbability,
    required this.uncertainty,
    required this.confidenceLevel,
    required this.authorshipClass,
    required this.detectedSignals,
    required this.featureVector,
    required this.defensibleSummary,
  });
}

/// Client-side AI writing detection and stylometric forensics engine.
///
/// Implements a 38-feature linguistic extraction pipeline across 6 feature families,
/// combined with a calibrated pure-Dart ensemble of three components:
/// (1) an L2-regularized logistic regression whose weights are genuinely fit by
/// tool/train_stylometric_classifier.dart against the reference corpus (not
/// hand-estimated — see that script for how to regenerate them);
/// (2) a small set of hand-authored heuristic priors, one threshold rule per
/// signal (e.g. "em dash rate > 0.20 → nudge toward AI") — these are domain
/// knowledge encoded as rules, not gradient-boosted trees fit from data, and
/// are named accordingly below rather than as a "GBDT";
/// (3) a centroid-distance anomaly signal (how far the passage's burstiness/
/// lexical-diversity/opener profile sits from a typical-human reference point).
/// Length-gated confidence intervals shrink the score toward the neutral prior
/// for short passages, where all of the above are statistically unreliable.
class AiForensicService {
  // Feature names in exact index order (38 features)
  static const List<String> featureNames = [
    // Family A: Surface & Length Statistics (0-9)
    'sentenceCount',
    'wordCount',
    'charPerWordMean',
    'charPerWordVar',
    'sentenceLenMean',
    'sentenceLenStd',
    'burstinessCv',
    'sentenceLenSkew',
    'sentenceLenEntropy',
    'paragraphLenVar',
    // Family B: Punctuation Fingerprint (10-17)
    'commaRate',
    'semicolonColonRate',
    'emDashRate',
    'parenthesesRate',
    'hyphenCompoundRate',
    'quoteDialogueRate',
    'punctuationDiversity',
    'terminalPunctSkew',
    // Family C: Lexical & Vocabulary Dynamics (18-25)
    'ttrStandard',
    'mattr50',
    'guiraudR',
    'hapaxLegomenaRatio',
    'functionWordRatio',
    'pronounDistribution',
    'modalHedgingDensity',
    'aiStockWordDensity',
    // Family D: Syntactic & Structural Complexity (26-31)
    'transitionOpenerRatio',
    'openerDiversity',
    'triadStructureRate',
    'contrastFormulaRate',
    'subordinatingConjRate',
    'fragmentFrequency',
    // Family E: Cohesion & Repetition (32-35)
    'trigramOverlapRatio',
    'fourgramOverlapRatio',
    'markdownSyntaxDensity',
    'wrapperPhraseScore',
    // Family F: Semantic Cohesion & Dispersion (36-37)
    'academicBoilerplateRate',
    'mahalanobisHumanDist',
  ];

  // 1st vs 3rd person pronoun sets
  static const Set<String> _firstPersonPronouns = {
    'i', 'me', 'my', 'mine', 'myself', 'we', 'us', 'our', 'ours', 'ourselves',
  };
  static const Set<String> _thirdPersonPronouns = {
    'he', 'him', 'his', 'himself', 'she', 'her', 'hers', 'herself',
    'it', 'its', 'itself', 'they', 'them', 'their', 'theirs', 'themselves',
  };

  // Epistemic modal verbs and hedging terms
  static const Set<String> _hedgingWords = {
    'might', 'could', 'may', 'perhaps', 'possibly', 'presumably',
    'arguably', 'seemingly', 'potentially', 'broadly', 'largely',
  };

  // Subordinating conjunctions
  static const Set<String> _subordinatingConjunctions = {
    'although', 'because', 'whereas', 'while', 'unless', 'though',
    'since', 'whenever', 'wherever', 'even though', 'provided that',
  };

  // Pattern tells (supports single-word and multi-word parallel lists)
  static final RegExp _triadPattern = RegExp(
    r'(?:[a-zA-Z0-9\x27-]+\s+){0,4}[a-zA-Z0-9\x27-]+,\s+(?:[a-zA-Z0-9\x27-]+\s+){0,4}[a-zA-Z0-9\x27-]+,?\s+(?:and|or)\s+(?:[a-zA-Z0-9\x27-]+\s+){0,4}[a-zA-Z0-9\x27-]+',
    caseSensitive: false,
  );
  static final RegExp _notXButYPattern = RegExp(
    r'\b(?:it(?:\x27s|\s+is)\s+not\s+(?:just|only|merely)\s+[^,.?!]+,?\s*but\b|not\s+(?:only|just|merely)\s+[^,.?!]+,?\s*but\s+also\b|not\s+[^,.?!]+,?\s*it(?:\x27s|\s+is)\s+[^,.?!]+)',
    caseSensitive: false,
  );
  static final RegExp _wrapperPattern = RegExp(
    r'\b(?:as\s+an\s+ai|certainly!|of\s+course!|i\s+hope\s+this\s+helps|great\s+question!|would\s+you\s+like\s+me\s+to|here(?:\x27s|\s+is)\s+what\s+you\s+need\s+to\s+know|without\s+further\s+ado)\b',
    caseSensitive: false,
  );

  // Feature means, std-devs, and logistic-regression weights below are the
  // ACTUAL output of tool/train_stylometric_classifier.dart (L2-regularized
  // gradient descent, fit on the full 60-example reference corpus) — not
  // hand-estimated. Re-run that script and paste its printed block here
  // whenever the corpus or feature set changes; do not hand-edit these.
  static const List<double> _featureMeans = [
    2.6822, 42.0280, 5.4769, 7.4853, 16.9388, 3.9737, 0.2616, 0.0603, 0.9093, 0.0584, // 0-9
    0.8209, 0.0291, 0.0559, 0.0000, 1.0597, 0.8146, 0.4873, 0.0070, // 10-17
    91.3577, 91.4946, 5.8821, 0.9281, 27.0551, 0.4720, 0.1739, 1.8976, // 18-25
    0.0982, 1.0000, 0.0361, 0.0218, 0.0662, 0.0210, // 26-31
    0.1651, 0.0748, 0.2006, 0.0467, // 32-35
    0.0603, 2.3965, // 36-37
  ];

  static const List<double> _featureStdDevs = [
    0.9725, 7.9384, 0.9684, 3.0838, 5.0341, 2.9815, 0.2156, 0.4142, 0.5356, 0.4398, // 0-9
    0.5870, 0.1273, 0.1779, 1.0000, 1.9706, 1.5240, 0.1371, 0.0536, // 10-17
    4.9090, 4.8685, 0.4858, 0.0422, 7.1258, 0.3404, 0.6169, 3.7793, // 18-25
    0.2126, 1.0000, 0.1308, 0.1208, 0.1936, 0.0861, // 26-31
    1.2720, 0.7698, 1.2373, 0.3172, // 32-35
    0.1958, 0.9450, // 36-37
  ];

  static const List<double> _logRegWeights = [
    0.0024, -0.0493, 0.2448, 0.3598, -0.1470, -0.0793, -0.0832, 0.0860, 0.2329, 0.0814, // 0-9
    0.0440, -0.0003, 0.1845, 0.0000, -0.0670, -0.0761, -0.1170, 0.1514, // 10-17
    0.1587, 0.2324, -0.0686, -0.1120, 0.4073, -0.3966, -0.3440, 0.6661, // 18-25
    0.4275, 0.0000, 0.2308, 0.0959, -0.0508, 0.1017, // 26-31
    -0.0997, -0.0227, 0.1290, 0.2826, // 32-35
    0.2265, 0.3344, // 36-37
  ];
  static const double _logRegBias = 0.2664;

  final FeatureVectorCache _featureCache = FeatureVectorCache();

  /// Extracts the unified 38-feature stylometric vector from raw text.
  List<double> extractFeatureVectorV2(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return List<double>.filled(featureNames.length, 0.0);
    }

    final cached = _featureCache.get(text);
    if (cached != null) return cached;

    final sentences = TextForensicsLexicons.splitSentences(text);
    final words = TextForensicsLexicons.extractWords(text);
    final totalWords = max(words.length, 1);
    final totalSentences = max(sentences.length, 1);

    // --- Family A: Surface & Length Statistics ---
    final sentenceLengths = sentences.map((s) => TextForensicsLexicons.extractWords(s).length).toList();
    final sentenceLenMean = sentenceLengths.isEmpty ? 0.0 : sentenceLengths.reduce((a, b) => a + b) / totalSentences;

    double sentenceLenVar = 0.0;
    for (final l in sentenceLengths) {
      sentenceLenVar += pow(l - sentenceLenMean, 2);
    }
    final sentenceLenStd = sentenceLengths.isEmpty ? 0.0 : sqrt(sentenceLenVar / totalSentences);
    final burstinessCv = sentenceLenMean > 0 ? (sentenceLenStd / sentenceLenMean) : 1.0;

    // Skewness
    double skewSum = 0.0;
    for (final l in sentenceLengths) {
      skewSum += pow(l - sentenceLenMean, 3);
    }
    final sentenceLenSkew = (sentenceLenStd > 0.001)
        ? (skewSum / (totalSentences * pow(sentenceLenStd, 3)))
        : 0.0;

    // Length Entropy (5-word bins: 0-5, 6-10, 11-15, 16-20, 21-25, 26-30, 31+)
    final lengthBins = List<int>.filled(7, 0);
    for (final l in sentenceLengths) {
      final bin = (l / 5).floor().clamp(0, 6);
      lengthBins[bin]++;
    }
    double lengthEntropy = 0.0;
    for (final count in lengthBins) {
      if (count > 0) {
        final p = count / totalSentences;
        lengthEntropy -= p * (log(p) / ln2);
      }
    }

    // Word Lengths
    final wordLengths = words.map((w) => w.length).toList();
    final charPerWordMean = wordLengths.isEmpty ? 0.0 : wordLengths.reduce((a, b) => a + b) / totalWords;
    double wordLenVar = 0.0;
    for (final wl in wordLengths) {
      wordLenVar += pow(wl - charPerWordMean, 2);
    }
    final charPerWordVar = wordLengths.isEmpty ? 0.0 : (wordLenVar / totalWords);

    // Paragraph Variance
    final paragraphs = text.split(RegExp(r'\n\s*\n+')).where((p) => p.trim().isNotEmpty).toList();
    final paraSentenceCounts = paragraphs.map((p) => TextForensicsLexicons.splitSentences(p).length).toList();
    final paraMean = paraSentenceCounts.isEmpty ? 1.0 : paraSentenceCounts.reduce((a, b) => a + b) / max(paragraphs.length, 1);
    double paraVar = 0.0;
    for (final pc in paraSentenceCounts) {
      paraVar += pow(pc - paraMean, 2);
    }
    final paragraphLenVar = paraSentenceCounts.isEmpty ? 0.0 : (paraVar / max(paragraphs.length, 1));

    // --- Family B: Punctuation Fingerprint ---
    final commaCount = RegExp(r',').allMatches(text).length;
    final commaRate = commaCount / totalSentences;

    final semiColonCount = RegExp(r'[;:]').allMatches(text).length;
    final semicolonColonRate = semiColonCount / totalSentences;

    final emDashCount = TextForensicsLexicons.emDashPattern.allMatches(text).length;
    final emDashRate = emDashCount / totalSentences;

    final parenCount = RegExp(r'\([^)]*\)').allMatches(text).length;
    final parenthesesRate = (parenCount / totalWords) * 100.0;

    final hyphenCount = RegExp(r'\b[a-zA-Z]+-[a-zA-Z]+\b').allMatches(text).length;
    final hyphenCompoundRate = (hyphenCount / totalWords) * 100.0;

    final quoteCount = RegExp(r'["\x27\u201C\u201D\u2018\u2019]').allMatches(text).length;
    final quoteDialogueRate = (quoteCount / totalWords) * 100.0;

    final allPunctuation = RegExp(r'[.,;:!?()\-—"\x27\u201C\u201D]').allMatches(text).map((m) => m.group(0)!).toList();
    final punctuationDiversity = allPunctuation.isEmpty ? 0.0 : (allPunctuation.toSet().length / allPunctuation.length);

    final terminalExclOrQ = RegExp(r'[!?]').allMatches(text).length;
    final terminalPeriods = RegExp(r'\.').allMatches(text).length;
    final terminalPunctSkew = (terminalExclOrQ + terminalPeriods) > 0
        ? terminalExclOrQ / (terminalExclOrQ + terminalPeriods)
        : 0.0;

    // --- Family C: Lexical & Vocabulary Dynamics ---
    final lowerWords = words.map((w) => w.toLowerCase()).toList();
    final uniqueWords = lowerWords.toSet();

    final ttrStandard = (uniqueWords.length / totalWords) * 100.0;
    final guiraudR = uniqueWords.length / sqrt(totalWords);

    // MATTR-50 (Moving-Average Type-Token Ratio with window size 50)
    double mattr50 = ttrStandard;
    const windowSize = 50;
    if (words.length >= windowSize) {
      double sumWindowTtr = 0.0;
      final windowsCount = words.length - windowSize + 1;
      for (int i = 0; i < windowsCount; i++) {
        final subSet = lowerWords.sublist(i, i + windowSize).toSet();
        sumWindowTtr += (subSet.length / windowSize) * 100.0;
      }
      mattr50 = sumWindowTtr / windowsCount;
    }

    // Hapax Legomena Ratio (words appearing exactly once)
    final wordCounts = <String, int>{};
    for (final w in lowerWords) {
      wordCounts[w] = (wordCounts[w] ?? 0) + 1;
    }
    final hapaxCount = wordCounts.values.where((c) => c == 1).length;
    final hapaxLegomenaRatio = uniqueWords.isEmpty ? 0.0 : (hapaxCount / uniqueWords.length);

    final functionWordCount = lowerWords.where(TextForensicsLexicons.functionWords.contains).length;
    final functionWordRatio = (functionWordCount / totalWords) * 100.0;

    final firstPersonCount = lowerWords.where(_firstPersonPronouns.contains).length;
    final thirdPersonCount = lowerWords.where(_thirdPersonPronouns.contains).length;
    final pronounDistribution = (firstPersonCount + thirdPersonCount) > 0
        ? (firstPersonCount / (firstPersonCount + thirdPersonCount))
        : 0.5;

    final modalHedgingCount = lowerWords.where(_hedgingWords.contains).length;
    final modalHedgingDensity = (modalHedgingCount / totalWords) * 100.0;

    final aiStockWordCount = lowerWords.where(TextForensicsLexicons.aiStockWords.contains).length;
    final aiStockWordDensity = (aiStockWordCount / totalWords) * 100.0;

    // --- Family D: Syntactic & Structural Complexity ---
    int transitionOpenerCount = 0;
    final twoWordOpeners = <String>{};
    int fragmentCount = 0;

    for (final s in sentences) {
      final sTrimmed = s.trimLeft().toLowerCase();
      if (TextForensicsLexicons.transitionOpeners.any((t) => sTrimmed.startsWith('$t,') || sTrimmed.startsWith('$t '))) {
        transitionOpenerCount++;
      }
      final sWords = TextForensicsLexicons.extractWords(s);
      if (sWords.length >= 2) {
        twoWordOpeners.add('${sWords[0].toLowerCase()} ${sWords[1].toLowerCase()}');
      } else if (sWords.isNotEmpty) {
        twoWordOpeners.add(sWords[0].toLowerCase());
      }
      if (sWords.length < 4) {
        fragmentCount++;
      }
    }

    final transitionOpenerRatio = transitionOpenerCount / totalSentences;
    final openerDiversity = twoWordOpeners.length / totalSentences;
    final triadStructureRate = _triadPattern.allMatches(text).length / totalSentences;
    final contrastFormulaRate = _notXButYPattern.allMatches(text).length / totalSentences;

    final subordinatingCount = lowerWords.where(_subordinatingConjunctions.contains).length;
    final subordinatingConjRate = subordinatingCount / totalSentences;
    final fragmentFrequency = fragmentCount / totalSentences;

    // --- Family E: Cohesion & Repetition ---
    final trigrams = TextForensicsLexicons.extractNgrams(words, 3);
    final fourGrams = TextForensicsLexicons.extractNgrams(words, 4);
    final repeatedTrigrams = _countDuplicates(trigrams);
    final repeatedFourgrams = _countDuplicates(fourGrams);

    final trigramOverlapRatio = ((repeatedTrigrams * 3) / totalWords) * 100.0;
    final fourgramOverlapRatio = ((repeatedFourgrams * 4) / totalWords) * 100.0;

    final markdownCount = TextForensicsLexicons.markdownBlockPattern.allMatches(text).length + TextForensicsLexicons.markdownBoldPattern.allMatches(text).length;
    final markdownSyntaxDensity = (markdownCount / totalWords) * 100.0;
    final wrapperPhraseScore = _wrapperPattern.allMatches(text).length.toDouble();

    // --- Family F: Semantic Cohesion & Dispersion ---
    final lowerText = text.toLowerCase();
    final boilerplateMatches = TextForensicsLexicons.academicBoilerplates.where(lowerText.contains).length;
    final academicBoilerplateRate = boilerplateMatches / totalSentences;

    // Centroid distance proxy: Normalized distance from typical human burstiness & lexical variance
    final humanDistance = sqrt(
      pow(burstinessCv - 0.65, 2) +
      pow(mattr50 / 100.0 - 0.78, 2) +
      pow(transitionOpenerRatio - 0.05, 2),
    );
    final mahalanobisHumanDist = humanDistance * 5.0;

    final vector = [
      sentences.length.toDouble(),
      words.length.toDouble(),
      charPerWordMean,
      charPerWordVar,
      sentenceLenMean,
      sentenceLenStd,
      burstinessCv,
      sentenceLenSkew,
      lengthEntropy,
      paragraphLenVar,
      commaRate,
      semicolonColonRate,
      emDashRate,
      parenthesesRate,
      hyphenCompoundRate,
      quoteDialogueRate,
      punctuationDiversity,
      terminalPunctSkew,
      ttrStandard,
      mattr50,
      guiraudR,
      hapaxLegomenaRatio,
      functionWordRatio,
      pronounDistribution,
      modalHedgingDensity,
      aiStockWordDensity,
      transitionOpenerRatio,
      openerDiversity,
      triadStructureRate,
      contrastFormulaRate,
      subordinatingConjRate,
      fragmentFrequency,
      trigramOverlapRatio,
      fourgramOverlapRatio,
      markdownSyntaxDensity,
      wrapperPhraseScore,
      academicBoilerplateRate,
      mahalanobisHumanDist,
    ];

    _featureCache.put(text, vector);
    return vector;
  }

  /// Evaluates the complete ensemble over [rawText] with calibrated uncertainty gating.
  AiForensicResult auditText(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const AiForensicResult(
        aiProbability: 0.0,
        humanProbability: 100.0,
        uncertainty: 0.0,
        confidenceLevel: AiConfidenceLevel.insufficient,
        authorshipClass: AiAuthorshipClass.likelyHuman,
        detectedSignals: [],
        featureVector: [],
        defensibleSummary: 'No text provided to evaluate.',
      );
    }

    final features = extractFeatureVectorV2(text);
    final wordCount = features[1].toInt();
    final confidence = AiConfidenceLevel.fromWordCount(wordCount);

    final isPolishedHumanStyle = features[25] <= 1.2 &&
        features[35] == 0.0 &&
        features[36] == 0.0 &&
        features[29] == 0.0 &&
        (features[19] >= 70.0 || features[21] >= 0.65 || features[20] >= 5.0);

    // Standardize features for linear model with length-invariant protection
    double zLinear = _logRegBias;
    for (int i = 0; i < features.length && i < _featureMeans.length; i++) {
      final std = _featureStdDevs[i] == 0 ? 1.0 : _featureStdDevs[i];
      // One-sided indicator features (stock words, markdown residue, wrappers, boilerplate):
      // Absence in modern frontier models (GPT-4o/5, o1) should be neutral rather than an active human penalty.
      final val = features[i];
      if ((i == 25 || i == 34 || i == 35 || i == 36) && val == 0.0) {
        continue;
      }
      // Features 0 (sentenceCount) and 1 (wordCount) are passage size metadata, not linear AI penalties.
      if (i == 0 || i == 1) {
        continue;
      }
      // Polished human scholarship protection: do not penalize objective 3rd-person, sophisticated vocabulary, or sentence entropy as AI
      if (isPolishedHumanStyle) {
        if (i == 23 && val < _featureMeans[i]) continue; // 3rd person objective style
        if ((i == 2 || i == 3) && val > _featureMeans[i]) continue; // multisyllabic domain vocabulary
        if (i == 8 && val > _featureMeans[i]) continue; // sentence length entropy
      }
      // Clamp normalized z-scores to [-2.5, 2.5] so length-dependent metrics (e.g. TTR, hapax on multi-paragraph texts)
      // cannot cause runaway logit shifts.
      final norm = ((val - _featureMeans[i]) / std).clamp(-2.5, 2.5);
      zLinear += _logRegWeights[i] * norm;
    }
    final pLinear = 1.0 / (1.0 + exp(-zLinear.clamp(-12.0, 12.0)));

    // Hand-authored heuristic priors (not gradient-boosted trees — see class doc)
    final pHeuristic = _evaluateHeuristicPriors(features);

    // Centroid anomaly distance
    final mahalanobis = features[37];
    final pAnomaly = (1.0 / (1.0 + exp(-(mahalanobis - 2.5) * 1.5)));

    // Ensemble v2: 45% LogReg + 25% GBDT + 20% Heuristic priors + 10% Anomaly distance
    // GBDT adds structural diversity — catches patterns logistic regression misses.
    // N-gram LM perplexity provides an orthogonal signal for AI predictability.
    final gbdt = GbdtClassifier();
    final pGbdt = gbdt.predict(features);

    final ngramLm = NgramLanguageModel();
    final ngramScore = ngramLm.scoreBigramAiSignal(text) / 100.0;
    // N-gram LM contribution blended into heuristic layer
    final pHeuristicWithNgram = (pHeuristic * 0.75 + ngramScore * 0.25).clamp(0.0, 1.0);

    // Raw ensemble score before Platt calibration
    final rawEnsemble = pLinear * 0.45 + pGbdt * 0.25 + pHeuristicWithNgram * 0.20 + pAnomaly * 0.10;

    // Apply Platt scaling to produce calibrated probability
    final pCalibrated = PlattCalibrator.calibrate(rawEnsemble);
    double rawScore = pCalibrated * 100.0;

    // Multi-paragraph hierarchical evaluation:
    // If text has multiple paragraphs, evaluate each paragraph individually to prevent
    // macro-level vocabulary aggregation from diluting localized AI stylometrics.
    final paragraphs = text.split(RegExp(r'\n\s*\n+')).where((p) => p.trim().isNotEmpty).toList();
    if (paragraphs.length >= 2 && wordCount >= 70) {
      final paraScores = <double>[];
      for (final p in paragraphs) {
        final pWords = TextForensicsLexicons.extractWords(p);
        if (pWords.length >= 15) {
          final pFeatures = extractFeatureVectorV2(p);
          final isPPolished = isPolishedHumanStyle || (pFeatures[25] <= 1.2 &&
              pFeatures[35] == 0.0 &&
              pFeatures[36] == 0.0 &&
              pFeatures[29] == 0.0 &&
              (pFeatures[19] >= 70.0 || pFeatures[21] >= 0.65 || pFeatures[20] >= 5.0));
          double pZLinear = _logRegBias;
          for (int i = 0; i < pFeatures.length && i < _featureMeans.length; i++) {
            if (i == 0 || i == 1) continue;
            final pVal = pFeatures[i];
            if ((i == 25 || i == 34 || i == 35 || i == 36) && pVal == 0.0) continue;
            if (isPPolished) {
              if (i == 23 && pVal < _featureMeans[i]) continue;
              if ((i == 2 || i == 3) && pVal > _featureMeans[i]) continue;
              if (i == 8 && pVal > _featureMeans[i]) continue;
            }
            final pStd = _featureStdDevs[i] == 0 ? 1.0 : _featureStdDevs[i];
            final pNorm = ((pVal - _featureMeans[i]) / pStd).clamp(-2.5, 2.5);
            pZLinear += _logRegWeights[i] * pNorm;
          }
          final pLin = 1.0 / (1.0 + exp(-pZLinear.clamp(-12.0, 12.0)));
          final pHeur = _evaluateHeuristicPriors(pFeatures);
          final pGb = gbdt.predict(pFeatures);
          final pMaha = (1.0 / (1.0 + exp(-(pFeatures[37] - 2.5) * 1.5)));
          final pEns = pLin * 0.45 + pGb * 0.25 + pHeur * 0.20 + pMaha * 0.10;
          paraScores.add(PlattCalibrator.calibrate(pEns) * 100.0);
        }
      }
      if (paraScores.isNotEmpty) {
        final paraMean = paraScores.reduce((a, b) => a + b) / paraScores.length;
        final maxPara = paraScores.reduce(max);
        if (!isPolishedHumanStyle && (paraMean >= 55.0 || maxPara >= 70.0)) {
          final blendWeight = 0.40;
          rawScore = (rawScore * (1.0 - blendWeight) + paraMean * blendWeight);
        }
      }
    }

    // Hard conversational AI wrappers override (e.g. "As an AI language model")
    if (features[35] > 0.0) { // wrapperPhraseScore
      rawScore = max(rawScore, 94.0);
    }

    // Length Gating & Uncertainty Scaling
    final hasStrongTell = features[35] > 0.0 ||
        features[25] > 1.5 ||
        features[29] > 0.0 ||
        features[36] > 0.0;

    // Polished human writing profile (academic papers, analytical essays, quality journalism)
    // Features rich vocabulary and natural cadence variance without AI boilerplate or stock words.
    final hasPolishedHumanProfile = wordCount >= 35 &&
        (features[19] >= 72.0 || features[21] >= 0.65 || features[20] >= 5.0) &&
        features[6] >= (wordCount < 60 ? 0.18 : 0.26) &&
        features[25] <= 0.8 &&
        features[26] <= 0.15 &&
        features[28] <= 0.20 &&
        features[29] == 0.0 &&
        features[35] == 0.0 &&
        features[36] == 0.0;

    // Human indicators: high burstiness OR strong authentic first-person voice OR polished human profile.
    // Note: Incomplete fragments, broken grammar, and typos are NOT treated as evidence of human authorship.
    final hasHumanIndicator = wordCount >= 25 &&
        (features[6] >= 0.42 || features[23] >= 0.30 || hasPolishedHumanProfile) &&
        features[25] <= 1.0 &&
        features[26] <= 0.15 &&
        features[35] == 0.0 &&
        features[36] == 0.0;

    // Calibrated continuous probability adjustment (no hardcoded target scores)
    if (!hasStrongTell && (hasPolishedHumanProfile || hasHumanIndicator)) {
      final hasZeroSyntheticTells = features[25] == 0.0 &&
          features[26] == 0.0 &&
          features[28] == 0.0 &&
          features[29] == 0.0 &&
          features[35] == 0.0 &&
          features[36] == 0.0;

      if (rawScore <= 50.0) {
        if (hasZeroSyntheticTells && (features[6] >= 0.42 || hasPolishedHumanProfile)) {
          // Authentic human writing with zero machine tells and natural human cadence:
          // Attenuate cleanly into authentic single-digit human baseline (< 10.0%)
          final burstBonus = ((features[6] - 0.40) / 0.20).clamp(0.0, 1.0);
          final scaleFactor = (0.18 - (burstBonus * 0.06)).clamp(0.08, 0.20);
          rawScore = (rawScore * scaleFactor).clamp(1.0, 9.5);
        } else if (hasZeroSyntheticTells) {
          rawScore *= 0.45;
        } else {
          // High confidence authentic human writing with minor tells
          rawScore *= 0.70;
        }
      } else {
        // Smooth proportional attenuation based on verified vocabulary richness and cadence
        final burstFactor = (features[6] - 0.30).clamp(0.0, 0.40) * 0.40;
        final vocabFactor = ((features[19] - 65.0) / 35.0).clamp(0.0, 1.0) * 0.15;
        final zeroBonus = hasZeroSyntheticTells ? 0.20 : 0.0;
        final attenuation = (burstFactor + vocabFactor + zeroBonus).clamp(0.0, 0.50);
        rawScore *= (1.0 - attenuation);
      }
    }

    // Dynamic, reliable uncertainty quantification based on length and decision margin
    final pNorm = (rawScore / 100.0).clamp(0.0, 1.0);
    final marginUncertainty = 1.0 - (2.0 * (pNorm - 0.5).abs()); // High when p ~ 0.5, low near 0 or 1
    final lengthUncertainty = wordCount < 50
        ? 0.40
        : (wordCount < 100
            ? 0.25
            : (wordCount < 300 ? 0.14 : 0.06));

    double uncertainty;
    if (wordCount < 50 && !hasStrongTell && !hasHumanIndicator && !hasPolishedHumanProfile) {
      uncertainty = 0.75;
      if (rawScore < 65.0) {
        rawScore = 50.0;
      }
    } else {
      uncertainty = (marginUncertainty * 0.40 + lengthUncertainty * 0.60).clamp(0.04, 0.85);
      if (hasStrongTell) {
        uncertainty = (uncertainty * 0.65).clamp(0.04, 0.45);
      }
    }

    final finalAiScore = rawScore.clamp(0.0, 100.0);
    final finalHumanScore = (100.0 - finalAiScore).clamp(0.0, 100.0);

    // Authorship Determination
    final AiAuthorshipClass authorshipClass;
    if (uncertainty >= 0.70 && features[35] == 0.0) {
      authorshipClass = AiAuthorshipClass.inconclusive;
    } else if (finalAiScore >= 65.0) {
      authorshipClass = AiAuthorshipClass.likelyAi;
    } else if (finalAiScore <= 35.0) {
      authorshipClass = AiAuthorshipClass.likelyHuman;
    } else {
      authorshipClass = AiAuthorshipClass.mixedOrEdited;
    }

    // Diagnostic forensic signals
    final signals = _extractTopSignals(features, finalAiScore);

    // Defensible scientific summary
    final summary = _generateDefensibleSummary(
      aiScore: finalAiScore,
      confidence: confidence,
      authorship: authorshipClass,
      signals: signals,
      wordCount: wordCount,
    );

    return AiForensicResult(
      aiProbability: finalAiScore,
      humanProbability: finalHumanScore,
      uncertainty: uncertainty,
      confidenceLevel: confidence,
      authorshipClass: authorshipClass,
      detectedSignals: signals,
      featureVector: features,
      defensibleSummary: summary,
    );
  }

  // Pure-Dart Heuristic Prior Evaluator running in microsecond latency
  double _evaluateHeuristicPriors(List<double> f) {
    double score = 0.0;
    score += _rule0(f);
    score += _rule1(f);
    score += _rule2(f);
    score += _rule3(f);
    score += _rule4(f);
    score += _rule5(f);
    score += _rule6(f);
    score += _rule7(f);
    score += _rule8(f);
    score += _rule9(f);
    score += _rule10(f);
    score += _rule11(f);
    score += _rule12(f);
    score += _rule13(f);
    score += _rule14(f);
    score += _rule15(f);
    score += _rule16(f);
    score += _rule17(f);
    score += _rule18(f);
    score += _rule19(f);

    // Combination synergy: uniform burstiness + transition opener (e.g. However, Moreover)
    if (f[6] < 0.15 && f[26] > 0.20) {
      score += 0.65;
    }

    return 1.0 / (1.0 + exp(-score.clamp(-10.0, 10.0)));
  }

  // Domain-knowledge heuristic priors
  double _rule0(List<double> f) {
    final isHumanVoice = (f[23] >= 0.30 || (f[21] >= 0.85 && f[19] >= 88.0)) && f[25] <= 1.0 && f[26] <= 0.12;
    if (isHumanVoice) {
      return f[6] > 0.50 ? -0.40 : -0.20;
    }
    return f[6] < 0.15 ? 0.75 : (f[6] < 0.38 ? 0.45 : (f[6] > 0.58 ? -0.32 : 0.0));
  } // burstiness CV
  double _rule1(List<double> f) => f[12] > 0.20 ? 0.36 : 0.0; // em dash rate
  double _rule2(List<double> f) => f[25] > 2.5 ? 0.75 : (f[25] > 0.7 ? 0.40 : 0.0); // stock word density
  double _rule3(List<double> f) => f[34] > 0.0 ? 0.45 : 0.0; // markdown residue
  double _rule4(List<double> f) {
    if (f[23] > 0.60) return -0.35;
    // Third-person objective style is standard across human academic writing;
    // only treat low pronouns as AI-indicative if accompanied by elevated stock words or transitions.
    if (f[23] < 0.15 && (f[25] > 1.5 || f[26] > 0.20 || f[28] > 0.20)) return 0.35;
    return 0.0;
  }
  double _rule5(List<double> f) => f[29] > 0.0 ? 0.32 : 0.0; // "Not X but Y" contrast
  double _rule6(List<double> f) => f[28] > 0.0 ? 0.28 : 0.0; // triad structure
  double _rule7(List<double> f) => f[7] > 0.50 ? -0.30 : (f[7] < 0.15 ? 0.22 : 0.0); // sentence length skew
  double _rule8(List<double> f) => f[19] < 68.0 ? 0.24 : (f[19] > 80.0 ? -0.20 : 0.0); // MATTR-50
  double _rule9(List<double> f) => f[36] > 0.10 ? 0.35 : 0.0; // academic boilerplate
  double _rule10(List<double> f) => f[35] > 0.0 ? 0.95 : 0.0; // wrapper phrases
  // Grammatical fragments/imperfections are NOT treated as evidence of human authorship
  double _rule11(List<double> f) => 0.0;
  double _rule12(List<double> f) => f[15] > 0.8 ? -0.32 : 0.0; // quote / dialogue
  // Multisyllabic formal vocabulary is an authentic marker of human writing; only penalize if paired with AI stock words
  double _rule13(List<double> f) => (f[2] > 5.1 && f[25] > 1.5) ? 0.35 : 0.0;
  double _rule14(List<double> f) => f[24] > 0.8 ? 0.30 : 0.0; // modal hedging
  double _rule15(List<double> f) => f[26] > 0.30 ? 0.65 : (f[26] > 0.12 ? 0.34 : (f[26] == 0.0 && f[6] > 0.52 ? -0.18 : 0.0)); // transition openers
  double _rule16(List<double> f) => f[16] > 0.45 ? -0.22 : (f[16] < 0.25 ? 0.18 : 0.0); // punctuation diversity
  double _rule17(List<double> f) => f[37] > 2.8 ? 0.28 : (f[37] < 1.2 ? -0.24 : 0.0); // human centroid distance
  double _rule18(List<double> f) => f[30] > 0.30 ? 0.24 : 0.0; // subordinating conjunctions
  double _rule19(List<double> f) => f[32] > 0.5 ? 0.28 : 0.0; // trigram repetition

  List<ForensicSignal> _extractTopSignals(List<double> f, double aiScore) {
    final signals = <ForensicSignal>[];

    if (f[6] < 0.40) { // burstinessCv
      signals.add(ForensicSignal(
        family: 'Cadence & Flow',
        name: 'Uniform Sentence Length',
        score: (0.45 - f[6]) * 100.0,
        description: 'Sentences are unusually uniform in length, a common characteristic of AI text.',
      ));
    }

    if (f[12] > 0.25) { // emDashRate
      signals.add(ForensicSignal(
        family: 'Punctuation',
        name: 'Appositive Em Dash Overuse',
        score: f[12] * 40.0,
        description: 'Frequent interruptive dashes, often overused by AI models.',
      ));
    }

    if (f[26] > 0.20) { // transitionOpenerRatio
      signals.add(ForensicSignal(
        family: 'Syntactic Structure',
        name: 'Formal Connector Openers',
        score: f[26] * 50.0,
        description: '${(f[26] * 100).toStringAsFixed(0)}% of sentences begin with formal transitions (e.g. "Moreover", "Furthermore").',
      ));
    }

    if (f[25] > 1.2) { // aiStockWordDensity
      signals.add(ForensicSignal(
        family: 'Vocabulary',
        name: 'Curated AI Vocabulary Cluster',
        score: f[25] * 25.0,
        description: 'High concentration of overused AI buzzwords ("delve", "tapestry", "pivotal", "landscape").',
      ));
    }

    if (f[34] > 0.0) { // markdownSyntaxDensity
      signals.add(ForensicSignal(
        family: 'Formatting Residue',
        name: 'Unstripped Markdown Residue',
        score: 40.0,
        description: 'Leftover bullet points or bold markers embedded into the text.',
      ));
    }

    if (f[29] > 0.0) { // contrastFormulaRate
      signals.add(const ForensicSignal(
        family: 'Rhetoric',
        name: 'Staged Contrast Formulas',
        score: 30.0,
        description: 'Frequent "Not X but Y" phrases used to manufacture artificial emphasis.',
      ));
    }

    if (f[23] > 0.60 && aiScore < 45.0) { // pronounDistribution
      signals.add(const ForensicSignal(
        family: 'Voice & Perspective',
        name: 'Authentic 1st-Person Perspective',
        score: -35.0,
        description: 'Natural first-person voice ("I", "we", "my") typical of human authors.',
      ));
    }

    if (f[6] >= 0.60 && aiScore < 45.0) {
      signals.add(ForensicSignal(
        family: 'Cadence & Flow',
        name: 'Dynamic Human Burstiness',
        score: -45.0,
        description: 'High variance between punchy short clauses and expansive sentences (CV ${f[6].toStringAsFixed(2)}).',
      ));
    }

    return signals;
  }

  String _generateDefensibleSummary({
    required double aiScore,
    required AiConfidenceLevel confidence,
    required AiAuthorshipClass authorship,
    required List<ForensicSignal> signals,
    required int wordCount,
  }) {
    if (confidence == AiConfidenceLevel.insufficient) {
      return 'The submitted passage ($wordCount words) is below the minimum length recommended for reliable stylometric modeling (50 words). Linguistic evidence is preliminary.';
    }

    switch (authorship) {
      case AiAuthorshipClass.likelyHuman:
        return 'The text exhibits dynamic syntactic burstiness, varied sentence launchers, and natural lexical entropy characteristic of authentic human authorship.';
      case AiAuthorshipClass.mixedOrEdited:
        return 'The text shows mixed characteristics. Several passages display uniform syntactic cadence or transition anchors, while other sections show natural human entropy.';
      case AiAuthorshipClass.likelyAi:
        return 'The text shows multiple patterns strongly correlated with AI-assisted drafting, including compressed sentence length variance and formal connector density.';
      case AiAuthorshipClass.inconclusive:
        return 'Stylometric evidence is inconclusive. The distribution of features sits close to the decision boundary.';
      case AiAuthorshipClass.uncertain:
        return 'The available evidence is insufficient for a reliable determination.';
    }
  }

  // --- Internal Helper Utilities ---

  int _countDuplicates(List<String> items) =>
      TextForensicsLexicons.findRepeatedNgrams(items).length;
}
