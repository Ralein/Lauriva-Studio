import 'dart:math';
import '../../../models/forensic/style_fingerprint.dart';
import '../../text_forensics_lexicons.dart';
import '../normalization/text_normalizer.dart';
import '../document/document_segmenter.dart';

/// Result container for hierarchical stylometric extraction.
class StylometricExtractionResult {
  final StyleFingerprint fingerprint;
  final Map<String, double> surfaceMetrics;
  final Map<String, double> punctuationMetrics;
  final Map<String, double> lexicalMetrics;
  final Map<String, double> structuralMetrics;
  final List<String> sentenceTemplates;

  const StylometricExtractionResult({
    required this.fingerprint,
    required this.surfaceMetrics,
    required this.punctuationMetrics,
    required this.lexicalMetrics,
    required this.structuralMetrics,
    required this.sentenceTemplates,
  });
}

/// Hierarchical stylometric feature extractor (Families A, B, C, D)
/// supporting multi-family forensic attribution, authorial consistency profiling,
/// and sliding-window segmentation.
class StylometricFeatureExtractor {
  static const Set<String> _pronounsFirstPerson = {
    'i', 'me', 'my', 'mine', 'myself', 'we', 'us', 'our', 'ours', 'ourselves'
  };

  static const Set<String> _pronounsThirdPerson = {
    'he', 'him', 'his', 'himself', 'she', 'her', 'hers', 'herself',
    'it', 'its', 'itself', 'they', 'them', 'their', 'theirs', 'themselves'
  };

  static const Set<String> _hedgingWords = {
    'perhaps', 'possibly', 'apparent', 'apparently', 'presumably', 'conceivably',
    'suggests', 'suggested', 'indicates', 'tends', 'tended', 'seemingly',
    'arguably', 'roughly', 'broadly', 'largely', 'partially'
  };

  static const Set<String> _modalVerbs = {
    'can', 'could', 'may', 'might', 'must', 'shall', 'should', 'will', 'would', 'ought'
  };

  static const Set<String> _coordinatingConjunctions = {
    'and', 'but', 'or', 'nor', 'for', 'yet', 'so'
  };

  static const Set<String> _subordinatingConjunctions = {
    'although', 'because', 'since', 'unless', 'while', 'whereas', 'though',
    'if', 'even', 'until', 'before', 'after', 'whether'
  };

  /// Epistemic markers and reasoning residue characteristic of 2027 frontier reasoning models (DeepSeek R1, o1/o3, Claude 3.7).
  static const Set<String> _reasoningArtifactPhrases = {
    'upon reflection',
    'it is crucial to evaluate',
    'it is important to evaluate',
    'it is essential to assess',
    'having weighed',
    'having considered',
    'let us examine',
    'let us explore',
    'let us consider',
    'on a deeper level',
    'it becomes evident',
    'a closer look reveals',
    'it is worth considering',
    'from a broader perspective',
    'navigating the complexities',
    'serves as a testament',
    'plays an indispensable role',
    'at the intersection of',
    'delving into',
    'fostering a',
    // Empirical Kaggle DAIGT high-probability AI phrases
    'important to consider',
    'to ensure that',
    'it is essential to',
    'is essential for',
    'in the face of',
    'has the potential to',
    'when faced with',
    'benefits and drawbacks',
    'research has shown that',
    'can be incredibly',
    'potential drawbacks',
    'pros and cons of',
    'foster a sense of',
    'vital to recognize',
  };

  /// Convenience method to extract features directly from raw text.
  StylometricExtractionResult extractFromText(String rawText) {
    final normalizer = TextNormalizer();
    final normDoc = normalizer.normalize(rawText);
    final segmenter = DocumentSegmenter();
    return extract(segmenter.segment(normDoc));
  }

  /// Extracts comprehensive stylometric features from a [SegmentedDocument].
  StylometricExtractionResult extract(SegmentedDocument doc) {
    final words = TextForensicsLexicons.extractWords(doc.normalizedDocument.normalizedText);
    final totalWords = max(words.length, 1);
    final totalChars = max(doc.normalizedDocument.normalizedText.length, 1);
    final totalSentences = max(doc.sentences.length, 1);
    final totalParagraphs = max(doc.paragraphs.length, 1);

    // ─────────────────────────────────────────────────────────────────────────
    // FAMILY A: Surface Statistics
    // ─────────────────────────────────────────────────────────────────────────
    final wordLengths = words.map((w) => w.length.toDouble()).toList();
    final meanWordLen = wordLengths.isNotEmpty ? wordLengths.reduce((a, b) => a + b) / totalWords : 0.0;
    
    double wordLenVar = 0.0;
    double wordLenSkew = 0.0;
    if (wordLengths.length > 1) {
      for (final l in wordLengths) {
        final diff = l - meanWordLen;
        wordLenVar += diff * diff;
      }
      wordLenVar /= wordLengths.length;
      final stdWord = sqrt(wordLenVar);
      if (stdWord > 0) {
        for (final l in wordLengths) {
          final diff = l - meanWordLen;
          wordLenSkew += pow(diff / stdWord, 3);
        }
        wordLenSkew /= wordLengths.length;
      }
    }

    final sentenceWordCounts = doc.sentences.map((s) => s.wordCount.toDouble()).toList();
    final meanSentLen = sentenceWordCounts.isNotEmpty
        ? sentenceWordCounts.reduce((a, b) => a + b) / totalSentences
        : 0.0;

    double sentLenVar = 0.0;
    double sentLenSkew = 0.0;
    double sentLenKurtosis = 0.0;
    if (sentenceWordCounts.length > 1) {
      for (final c in sentenceWordCounts) {
        final diff = c - meanSentLen;
        sentLenVar += diff * diff;
      }
      sentLenVar /= sentenceWordCounts.length;
      final stdSent = sqrt(sentLenVar);
      if (stdSent > 0) {
        for (final c in sentenceWordCounts) {
          final diff = c - meanSentLen;
          final z = diff / stdSent;
          sentLenSkew += pow(z, 3);
          sentLenKurtosis += pow(z, 4);
        }
        sentLenSkew /= sentenceWordCounts.length;
        sentLenKurtosis = (sentLenKurtosis / sentenceWordCounts.length) - 3.0; // Excess kurtosis
      }
    }
    final sentStdDev = sqrt(sentLenVar);
    final burstiness = meanSentLen > 0 ? (sentStdDev / meanSentLen) : 0.0;

    final paraWordCounts = doc.paragraphs.map((p) => TextForensicsLexicons.extractWords(p.text).length.toDouble()).toList();
    final meanParaLen = paraWordCounts.isNotEmpty
        ? paraWordCounts.reduce((a, b) => a + b) / totalParagraphs
        : 0.0;

    final surfaceMetrics = <String, double>{
      'charCount': totalChars.toDouble(),
      'wordCount': totalWords.toDouble(),
      'sentenceCount': totalSentences.toDouble(),
      'paragraphCount': totalParagraphs.toDouble(),
      'meanWordLength': meanWordLen,
      'wordLengthVariance': wordLenVar,
      'wordLengthSkew': wordLenSkew,
      'meanSentenceLength': meanSentLen,
      'sentenceLengthVariance': sentLenVar,
      'sentenceLengthStdDev': sentStdDev,
      'sentenceLengthSkew': sentLenSkew,
      'sentenceLengthKurtosis': sentLenKurtosis,
      'burstiness': burstiness,
      'meanParagraphLength': meanParaLen,
    };

    // ─────────────────────────────────────────────────────────────────────────
    // FAMILY B: Punctuation Fingerprint
    // ─────────────────────────────────────────────────────────────────────────
    final rawText = doc.normalizedDocument.normalizedText;
    final commaCount = RegExp(r',').allMatches(rawText).length;
    final semicolonCount = RegExp(r';').allMatches(rawText).length;
    final colonCount = RegExp(r':').allMatches(rawText).length;
    final periodCount = RegExp(r'\.').allMatches(rawText).length;
    final questionCount = RegExp(r'\?').allMatches(rawText).length;
    final exclamationCount = RegExp(r'!').allMatches(rawText).length;
    final emDashCount = TextForensicsLexicons.emDashPattern.allMatches(rawText).length;
    final quoteCount = RegExp(r'["\x27\u201C\u201D\u2018\u2019]').allMatches(rawText).length;
    final parenCount = RegExp(r'[()]').allMatches(rawText).length;

    final commaRate = (commaCount * 100.0) / totalWords;
    final semicolonRate = (semicolonCount * 100.0) / totalWords;
    final colonRate = (colonCount * 100.0) / totalWords;
    final emDashRate = (emDashCount * 100.0) / totalWords;
    final questionRate = (questionCount * 100.0) / totalWords;

    // Shannon Entropy over punctuation distribution
    final punctCounts = [commaCount, semicolonCount, colonCount, periodCount, questionCount, exclamationCount, emDashCount, quoteCount, parenCount];
    final totalPunct = punctCounts.reduce((a, b) => a + b);
    double punctEntropy = 0.0;
    if (totalPunct > 0) {
      for (final count in punctCounts) {
        if (count > 0) {
          final p = count / totalPunct;
          punctEntropy -= p * (log(p) / ln2);
        }
      }
    }

    final punctuationMetrics = <String, double>{
      'commaRate': commaRate,
      'semicolonRate': semicolonRate,
      'colonRate': colonRate,
      'emDashRate': emDashRate,
      'questionRate': questionRate,
      'punctuationEntropy': punctEntropy,
      'colonSemicolonRatio': (semicolonCount > 0) ? (colonCount / semicolonCount) : colonCount.toDouble(),
      'commaPeriodRatio': (periodCount > 0) ? (commaCount / periodCount) : commaCount.toDouble(),
    };

    // ─────────────────────────────────────────────────────────────────────────
    // FAMILY C: Vocabulary Dynamics
    // ─────────────────────────────────────────────────────────────────────────
    final wordFreqs = <String, int>{};
    int functionWordCount = 0;
    int firstPersonCount = 0;
    int thirdPersonCount = 0;
    int contractionCount = 0;
    int hedgingCount = 0;
    int modalCount = 0;

    for (final w in words) {
      final lower = w.toLowerCase();
      wordFreqs[lower] = (wordFreqs[lower] ?? 0) + 1;

      if (TextForensicsLexicons.functionWords.contains(lower)) functionWordCount++;
      if (_pronounsFirstPerson.contains(lower)) firstPersonCount++;
      if (_pronounsThirdPerson.contains(lower)) thirdPersonCount++;
      if (lower.contains("'") || lower.contains('’')) contractionCount++;
      if (_hedgingWords.contains(lower)) hedgingCount++;
      if (_modalVerbs.contains(lower)) modalCount++;
    }

    final uniqueCount = wordFreqs.length;
    final ttr = uniqueCount / totalWords;
    final guiraudR = uniqueCount / sqrt(totalWords);

    int hapaxCount = 0; // Occurring exactly once
    int disCount = 0;   // Occurring exactly twice
    wordFreqs.forEach((_, count) {
      if (count == 1) hapaxCount++;
      if (count == 2) disCount++;
    });

    final hapaxRatio = uniqueCount > 0 ? (hapaxCount / uniqueCount) : 0.0;
    final disRatio = uniqueCount > 0 ? (disCount / uniqueCount) : 0.0;
    final functionWordRatio = functionWordCount / totalWords;
    final contractionDensity = (contractionCount * 100.0) / totalWords;
    final hedgingDensity = (hedgingCount * 100.0) / totalWords;
    final modalDensity = (modalCount * 100.0) / totalWords;

    // Vocabulary burstiness across paragraphs (new vocab introduction rate)
    final seenVocab = <String>{};
    final paraNoveltyRates = <double>[];
    for (final p in doc.paragraphs) {
      final pWords = TextForensicsLexicons.extractWords(p.text).map((w) => w.toLowerCase()).toList();
      if (pWords.isEmpty) continue;
      int novelInPara = 0;
      for (final pw in pWords) {
        if (!seenVocab.contains(pw)) {
          novelInPara++;
          seenVocab.add(pw);
        }
      }
      paraNoveltyRates.add(novelInPara / pWords.length);
    }
    final vocabBurstinessMean = paraNoveltyRates.isNotEmpty
        ? paraNoveltyRates.reduce((a, b) => a + b) / paraNoveltyRates.length
        : 0.0;

    final lexicalMetrics = <String, double>{
      'typeTokenRatio': ttr,
      'guiraudR': guiraudR,
      'hapaxRatio': hapaxRatio,
      'disLegomenaRatio': disRatio,
      'functionWordRatio': functionWordRatio,
      'contractionDensity': contractionDensity,
      'hedgingDensity': hedgingDensity,
      'modalDensity': modalDensity,
      'firstPersonRatio': firstPersonCount / totalWords,
      'thirdPersonRatio': thirdPersonCount / totalWords,
      'vocabBurstiness': vocabBurstinessMean,
    };

    // ─────────────────────────────────────────────────────────────────────────
    // FAMILY D: Sentence Structural Fingerprint & Template Repetition
    // ─────────────────────────────────────────────────────────────────────────
    int transitionOpenerCount = 0;
    int coordConjCount = 0;
    int subordConjCount = 0;
    final templates = <String>[];

    for (final sent in doc.sentences) {
      final sWords = TextForensicsLexicons.extractWords(sent.text);
      if (sWords.isEmpty) continue;

      final firstLower = sWords.first.toLowerCase();
      if (TextForensicsLexicons.transitionOpeners.contains(firstLower)) {
        transitionOpenerCount++;
      }

      for (final sw in sWords) {
        final sl = sw.toLowerCase();
        if (_coordinatingConjunctions.contains(sl)) coordConjCount++;
        if (_subordinatingConjunctions.contains(sl)) subordConjCount++;
      }

      // Generate structural template abstraction for sentence rhythm
      templates.add(_generateSentenceTemplate(sWords));
    }

    final transitionOpenerRate = (transitionOpenerCount * 100.0) / totalSentences;
    final conjunctionDensity = ((coordConjCount + subordConjCount) * 100.0) / totalWords;

    // Structural template repetition & entropy
    final templateCounts = <String, int>{};
    for (final t in templates) {
      templateCounts[t] = (templateCounts[t] ?? 0) + 1;
    }
    double templateEntropy = 0.0;
    if (templates.isNotEmpty) {
      for (final count in templateCounts.values) {
        final p = count / templates.length;
        templateEntropy -= p * (log(p) / ln2);
      }
    }

    final lowerRaw = doc.normalizedDocument.normalizedText.toLowerCase();
    int reasoningArtifactMatches = 0;
    for (final phrase in _reasoningArtifactPhrases) {
      if (lowerRaw.contains(phrase)) {
        reasoningArtifactMatches += RegExp(RegExp.escape(phrase)).allMatches(lowerRaw).length;
      }
    }
    final reasoningArtifactRate = (reasoningArtifactMatches * 100.0) / totalSentences;

    // Ghostbuster Cadence Anomaly: flat metronomic lengths typical of synthetic LLM generation
    final syntheticCadenceScore = (burstiness < 0.28 && meanSentLen >= 12.0 && meanSentLen <= 26.0)
        ? (1.0 - (burstiness / 0.28)).clamp(0.0, 1.0)
        : 0.0;

    // Subword/Polysyllabic complexity ratio
    final polysyllabicCount = words.where((w) => w.length > 9).length;
    final subwordComplexityRatio = (polysyllabicCount / totalWords);

    final structuralMetrics = <String, double>{
      'transitionOpenerRate': transitionOpenerRate,
      'conjunctionDensity': conjunctionDensity,
      'templateEntropy': templateEntropy,
      'uniqueTemplateRatio': templates.isNotEmpty ? (templateCounts.length / templates.length) : 1.0,
      'reasoningArtifactDensity': reasoningArtifactRate,
      'syntheticCadenceScore': syntheticCadenceScore,
      'subwordComplexityRatio': subwordComplexityRatio,
    };

    // ─────────────────────────────────────────────────────────────────────────
    // Assemble Master StyleFingerprint
    // ─────────────────────────────────────────────────────────────────────────
    final fingerprint = StyleFingerprint(
      meanSentenceLength: meanSentLen,
      sentenceLengthStdDev: sentStdDev,
      sentenceLengthSkew: sentLenSkew,
      meanParagraphLength: meanParaLen,
      burstiness: burstiness,
      commaRate: commaRate,
      semicolonRate: semicolonRate,
      colonRate: colonRate,
      emDashRate: emDashRate,
      questionRate: questionRate,
      punctuationEntropy: punctEntropy,
      typeTokenRatio: ttr,
      guiraudR: guiraudR,
      hapaxRatio: hapaxRatio,
      functionWordRatio: functionWordRatio,
      contractionDensity: contractionDensity,
      transitionOpenerRate: transitionOpenerRate,
      conjunctionDensity: conjunctionDensity,
      structuralTemplateEntropy: templateEntropy,
    );

    return StylometricExtractionResult(
      fingerprint: fingerprint,
      surfaceMetrics: surfaceMetrics,
      punctuationMetrics: punctuationMetrics,
      lexicalMetrics: lexicalMetrics,
      structuralMetrics: structuralMetrics,
      sentenceTemplates: templates,
    );
  }

  /// Generates a coarse POS/rhetorical structural pattern for a sentence.
  /// Example: "Moreover, the system improves efficiency" -> "TRANS DET NOUN VERB NOUN"
  String _generateSentenceTemplate(List<String> words) {
    final tokens = <String>[];
    for (int i = 0; i < words.length && i < 8; i++) { // Sample first 8 tokens for rhythm
      final w = words[i].toLowerCase();
      if (i == 0 && TextForensicsLexicons.transitionOpeners.contains(w)) {
        tokens.add('TRANS');
      } else if (w == 'the' || w == 'a' || w == 'an' || w == 'this' || w == 'that') {
        tokens.add('DET');
      } else if (_pronounsFirstPerson.contains(w) || _pronounsThirdPerson.contains(w)) {
        tokens.add('PRON');
      } else if (_coordinatingConjunctions.contains(w) || _subordinatingConjunctions.contains(w)) {
        tokens.add('CONJ');
      } else if (_modalVerbs.contains(w)) {
        tokens.add('MODAL');
      } else if (w.endsWith('ing')) {
        tokens.add('V_ING');
      } else if (w.endsWith('ed')) {
        tokens.add('V_ED');
      } else if (w.endsWith('ly')) {
        tokens.add('ADV');
      } else {
        tokens.add('W');
      }
    }
    return tokens.join('_');
  }
}
