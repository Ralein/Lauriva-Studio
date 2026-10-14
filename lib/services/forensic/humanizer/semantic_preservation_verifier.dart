import 'dart:math';

/// Qualitative preservation verdict after humanizing or rewriting a document.
enum SemanticPreservationVerdict {
  excellent,
  acceptable,
  divergent,
  factualDriftAlert,
}

/// Comprehensive report on semantic, factual, and stylometric changes
/// between original input and humanized output.
class SemanticPreservationReport {
  final double preservationScore; // 0.0 to 1.0
  final SemanticPreservationVerdict verdict;
  final List<String> preservedEntities;
  final List<String> missingEntities;
  final List<String> preservedNumbers;
  final List<String> missingNumbers;
  final List<String> introducedNumbers;
  final List<String> preservedCitations;
  final List<String> missingCitations;
  final double lexicalAnchorOverlap;
  final double aiProbabilityBefore;
  final double aiProbabilityAfter;
  final double burstinessBefore;
  final double burstinessAfter;
  final String summary;

  /// Explicit negation cues (not, never, no, n't, ...) in each text,
  /// excluding the rhetorical "not only / not just / not merely".
  final int negationsBefore;
  final int negationsAfter;

  final List<String> preservedUnits;
  final List<String> missingUnits;
  final bool hasRelationalDrift;

  /// Ratio of humanized word count vs original word count.
  final double lengthRatio;

  const SemanticPreservationReport({
    required this.preservationScore,
    required this.verdict,
    required this.preservedEntities,
    required this.missingEntities,
    required this.preservedNumbers,
    required this.missingNumbers,
    required this.introducedNumbers,
    required this.preservedCitations,
    required this.missingCitations,
    required this.lexicalAnchorOverlap,
    required this.aiProbabilityBefore,
    required this.aiProbabilityAfter,
    required this.burstinessBefore,
    required this.burstinessAfter,
    required this.summary,
    this.negationsBefore = 0,
    this.negationsAfter = 0,
    this.preservedUnits = const [],
    this.missingUnits = const [],
    this.hasRelationalDrift = false,
    this.lengthRatio = 1.0,
  });

  /// Net reduction in AI likelihood (positive means AI score dropped).
  double get aiReduction => aiProbabilityBefore - aiProbabilityAfter;

  /// Net increase in burstiness (positive means text has more human-like rhythm).
  double get burstinessGain => burstinessAfter - burstinessBefore;

  /// Whether numerical drift or hallucination was detected.
  bool get hasNumericalDrift => missingNumbers.isNotEmpty || introducedNumbers.isNotEmpty;

  /// Whether unit of measurement or currency drift was detected.
  bool get hasUnitDrift => missingUnits.isNotEmpty;

  /// Whether citations were lost in translation.
  bool get hasCitationLoss => missingCitations.isNotEmpty;

  /// Whether the rewrite dropped below the 80% length floor.
  bool get hasLengthUnderflow => lengthRatio < 0.80;

  /// Whether the rewrite altered negation counts or inverted relational direction.
  bool get hasPolarityDrift =>
      hasRelationalDrift || (negationsBefore != negationsAfter);

  Map<String, dynamic> toJson() => {
    'preservationScore': preservationScore,
    'verdict': verdict.name,
    'preservedEntities': preservedEntities,
    'missingEntities': missingEntities,
    'preservedNumbers': preservedNumbers,
    'missingNumbers': missingNumbers,
    'introducedNumbers': introducedNumbers,
    'preservedCitations': preservedCitations,
    'missingCitations': missingCitations,
    'preservedUnits': preservedUnits,
    'missingUnits': missingUnits,
    'hasRelationalDrift': hasRelationalDrift,
    'lexicalAnchorOverlap': lexicalAnchorOverlap,
    'aiProbabilityBefore': aiProbabilityBefore,
    'aiProbabilityAfter': aiProbabilityAfter,
    'burstinessBefore': burstinessBefore,
    'burstinessAfter': burstinessAfter,
    'summary': summary,
    'negationsBefore': negationsBefore,
    'negationsAfter': negationsAfter,
    'lengthRatio': lengthRatio,
    'hasLengthUnderflow': hasLengthUnderflow,
    'hasPolarityDrift': hasPolarityDrift,
  };
}

/// Verifies factual and semantic preservation between an original draft
/// and its rewritten/humanized counterpart.
class SemanticPreservationVerifier {
  static final RegExp _numberPattern = RegExp(
    r'(?:[\$€£¥₹])?\b\d+(?:[,\.]\d+)*(?:%|\s+per\s?cent\b|[kKmMbB]\b|st\b|nd\b|rd\b|th\b)?',
    caseSensitive: false,
  );

  static final RegExp _citationPattern = RegExp(
    r'(?:\((?:[A-Z][a-zA-Z\s\.\-]+(?:et\s+al\.?)?,?\s*(?:19|20)\d{2}[a-z]?|[A-Z][a-zA-Z\s\.\-]+\s+\d{1,4}|\d+(?:[\s,\-–]\d+)*)\)|\[\^?[A-Za-z0-9]+(?:[\s,\-–][A-Za-z0-9]+)*\])',
  );

  /// Analyzes preservation of key entities, numbers, and citations,
  /// while tracking forensic improvements.
  SemanticPreservationReport verify({
    required String originalText,
    required String humanizedText,
    double aiProbabilityBefore = 0.0,
    double aiProbabilityAfter = 0.0,
    double burstinessBefore = 0.0,
    double burstinessAfter = 0.0,
  }) {
    // 1. Extract Numbers & Quantities. Display forms are reported; matching
    //    uses canonical values so "1,000" = "1000", "5 percent" = "5%",
    //    and a figure spelled out ("five") still counts as preserved.
    final originalNumbers = _extractNumbers(originalText);
    final humanizedNumbers = _extractNumbers(humanizedText);
    final humanizedKeys = {
      ...humanizedNumbers.map(_canonicalNumber),
      ..._spelledNumberKeys(humanizedText),
    };
    final originalKeys = {
      ...originalNumbers.map(_canonicalNumber),
      ..._spelledNumberKeys(originalText),
    };

    final preservedNumbers = <String>[];
    final missingNumbers = <String>[];
    for (final num in originalNumbers) {
      if (humanizedKeys.contains(_canonicalNumber(num))) {
        preservedNumbers.add(num);
      } else {
        missingNumbers.add(num);
      }
    }

    final introducedNumbers = <String>[];
    for (final num in humanizedNumbers) {
      if (!originalKeys.contains(_canonicalNumber(num))) {
        introducedNumbers.add(num);
      }
    }

    // 2. Extract Citations & References
    final originalCitations = _extractCitations(originalText);
    final humanizedCitations = _extractCitations(humanizedText);

    final preservedCitations = <String>[];
    final missingCitations = <String>[];
    for (final cite in originalCitations) {
      if (humanizedCitations.contains(cite)) {
        preservedCitations.add(cite);
      } else {
        missingCitations.add(cite);
      }
    }

    // 2.5 Extract Units of Measurement and Currency
    final originalUnits = _extractUnitsAndCurrencies(originalText);
    final humanizedUnits = _extractUnitsAndCurrencies(humanizedText);
    final preservedUnits = <String>[];
    final missingUnits = <String>[];
    for (final u in originalUnits) {
      if (humanizedUnits.contains(u)) {
        preservedUnits.add(u);
      } else {
        missingUnits.add(u);
      }
    }

    // 3. Extract Named Entities & Capitalized Tokens (ignoring sentence starters)
    // An entity counts as preserved if it appears anywhere in the rewrite,
    // including as the first word of a sentence (which extraction skips).
    final originalEntities = _extractNamedEntities(originalText);

    final preservedEntities = <String>[];
    final missingEntities = <String>[];
    for (final ent in originalEntities) {
      final entRegex = RegExp('\\b${RegExp.escape(ent)}\\b');
      final noHyphenEnt = ent.replaceAll('-', '');
      final noHyphenText = humanizedText.replaceAll('-', '');
      if (entRegex.hasMatch(humanizedText) ||
          (noHyphenEnt.length >= 3 && RegExp('\\b${RegExp.escape(noHyphenEnt)}\\b').hasMatch(noHyphenText))) {
        preservedEntities.add(ent);
      } else {
        missingEntities.add(ent);
      }
    }

    // 4. Lexical Content Anchor Overlap (Jaccard on non-stop content words)
    final origContentWords = _extractContentWords(originalText);
    final humanContentWords = _extractContentWords(humanizedText);
    final intersection = origContentWords.intersection(humanContentWords);
    final union = origContentWords.union(humanContentWords);
    final lexicalOverlap = union.isEmpty ? 1.0 : intersection.length / union.length;

    // 5. Compute Preservation Score (0.0 to 1.0)
    double factualFidelity = 1.0;

    // Missing numbers penalty
    if (originalNumbers.isNotEmpty) {
      final numRatio = preservedNumbers.length / originalNumbers.length;
      factualFidelity *= (0.3 + 0.7 * numRatio);
    }
    // Introduced numbers penalty (potential hallucination)
    if (introducedNumbers.isNotEmpty) {
      factualFidelity -= min(0.25, introducedNumbers.length * 0.08);
    }

    // Missing units penalty
    if (originalUnits.isNotEmpty) {
      final unitRatio = preservedUnits.length / originalUnits.length;
      factualFidelity *= (0.4 + 0.6 * unitRatio);
    }

    // Missing citation penalty
    if (originalCitations.isNotEmpty) {
      final citeRatio = preservedCitations.length / originalCitations.length;
      factualFidelity *= (0.4 + 0.6 * citeRatio);
    }

    // Named entities fidelity
    if (originalEntities.isNotEmpty) {
      final entRatio = preservedEntities.length / originalEntities.length;
      factualFidelity *= (0.5 + 0.5 * entRatio);
    }

    // Negation polarity and relational drift
    final negationsBefore = _countNegations(originalText);
    final negationsAfter = _countNegations(humanizedText);
    final relationalDrift = _detectRelationalDrift(originalText, humanizedText);
    final polarityDrift = relationalDrift || (negationsBefore != negationsAfter);
    if (polarityDrift) {
      factualFidelity *= 0.75;
    }

    // Length floor guard: penalize outputs that drop below 80% of original word count
    final origWords = originalText.trim().isEmpty ? 0 : originalText.trim().split(RegExp(r'\s+')).length;
    final humanWords = humanizedText.trim().isEmpty ? 0 : humanizedText.trim().split(RegExp(r'\s+')).length;
    final lengthRatio = origWords == 0 ? 1.0 : (humanWords / origWords);
    if (lengthRatio < 0.80) {
      factualFidelity *= max(0.2, lengthRatio);
    }

    // Code and LaTeX formula preservation: verify technical artifacts were not dropped
    final origCodeBlocks = RegExp(r'```[\s\S]*?```').allMatches(originalText).length;
    final humanCodeBlocks = RegExp(r'```[\s\S]*?```').allMatches(humanizedText).length;
    if (origCodeBlocks > 0 && humanCodeBlocks < origCodeBlocks) {
      factualFidelity *= 0.5;
    }

    final origLatexBlocks = RegExp(r'\$\$[\s\S]*?\$\$').allMatches(originalText).length;
    final humanLatexBlocks = RegExp(r'\$\$[\s\S]*?\$\$').allMatches(humanizedText).length;
    if (origLatexBlocks > 0 && humanLatexBlocks < origLatexBlocks) {
      factualFidelity *= 0.5;
    }

    // Balance factual fidelity (85%) with lexical anchor overlap (15%)
    // Paraphrasing intentionally alters vocabulary, so factual retention is primary.
    double score = (factualFidelity * 0.85) + (lexicalOverlap * 0.15);
    score = score.clamp(0.0, 1.0);

    // 6. Verdict Determination
    SemanticPreservationVerdict verdict;
    if ((missingNumbers.isNotEmpty && originalNumbers.length > 1) ||
        missingUnits.isNotEmpty ||
        relationalDrift) {
      verdict = SemanticPreservationVerdict.factualDriftAlert;
    } else if (score >= 0.75 &&
        missingNumbers.isEmpty &&
        missingCitations.isEmpty &&
        !polarityDrift &&
        missingUnits.isEmpty &&
        lengthRatio >= 0.80) {
      verdict = SemanticPreservationVerdict.excellent;
    } else if (score >= 0.50 && lengthRatio >= 0.80) {
      verdict = SemanticPreservationVerdict.acceptable;
    } else {
      verdict = SemanticPreservationVerdict.divergent;
    }

    // 7. Human-friendly Summary
    final summary = _buildSummary(
      verdict: verdict,
      score: score,
      missingNumbers: missingNumbers,
      introducedNumbers: introducedNumbers,
      missingUnits: missingUnits,
      missingCitations: missingCitations,
      aiReduction: aiProbabilityBefore - aiProbabilityAfter,
      aiScaleIsPercent: aiProbabilityBefore > 1.0 || aiProbabilityAfter > 1.0,
      polarityDrift: polarityDrift,
      negationsBefore: negationsBefore,
      negationsAfter: negationsAfter,
      lengthRatio: lengthRatio,
    );

    return SemanticPreservationReport(
      preservationScore: score,
      verdict: verdict,
      preservedEntities: preservedEntities.toList(),
      missingEntities: missingEntities.toList(),
      preservedNumbers: preservedNumbers.toList(),
      missingNumbers: missingNumbers.toList(),
      introducedNumbers: introducedNumbers.toList(),
      preservedCitations: preservedCitations.toList(),
      missingCitations: missingCitations.toList(),
      preservedUnits: preservedUnits.toList(),
      missingUnits: missingUnits.toList(),
      hasRelationalDrift: relationalDrift,
      lexicalAnchorOverlap: lexicalOverlap,
      aiProbabilityBefore: aiProbabilityBefore,
      aiProbabilityAfter: aiProbabilityAfter,
      burstinessBefore: burstinessBefore,
      burstinessAfter: burstinessAfter,
      summary: summary,
      negationsBefore: negationsBefore,
      negationsAfter: negationsAfter,
      lengthRatio: lengthRatio,
    );
  }

  Set<String> _extractNumbers(String text) {
    return _numberPattern
        .allMatches(text)
        .map((m) => m.group(0)!.trim().toLowerCase())
        .toSet();
  }

  /// Canonical comparison key: no thousands separators or currency symbols,
  /// lowercase magnitude suffix, "%" kept (18 and 18% are different facts).
  static String _canonicalNumber(String n) {
    var k = n.toLowerCase().replaceAll(RegExp(r'\s*per\s?cent'), '%').replaceAll(RegExp(r'[\$€£¥₹\s]'), '');
    k = k.replaceAll(RegExp(r'(?<=\d)(?:st|nd|rd|th)\b'), '');
    // "1,000" / "1,000,000" -> digits; leave decimal commas like "3,5" alone.
    if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?').hasMatch(k)) k = k.replaceAll(',', '');
    // "2.50" -> "2.5", "3.0" -> "3"
    k = k.replaceFirstMapped(RegExp(r'^(\d+)\.(\d*?)0+(?=\D|$)'), (m) => m.group(2)!.isEmpty ? m.group(1)! : '${m.group(1)}.${m.group(2)}');
    return k;
  }

  static const Map<String, int> _numberWords = {
    'zero': 0, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
    'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
    'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
    'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70,
    'eighty': 80, 'ninety': 90, 'hundred': 100, 'dozen': 12,
    'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5,
    'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10,
  };

  /// Keys for spelled-out figures ("five", "twenty percent"). "one" is
  /// excluded: it is usually a pronoun ("one might argue").
  static Set<String> _spelledNumberKeys(String text) {
    final keys = <String>{};
    final pattern = RegExp(r'\b([a-z]+)(\s+(?:percent|per\s+cent))?\b', caseSensitive: false);
    for (final m in pattern.allMatches(text)) {
      final v = _numberWords[m.group(1)!.toLowerCase()];
      if (v == null) continue;
      keys.add(m.group(2) != null ? '$v%' : '$v');
    }
    // Digits followed by "percent" are the same fact as "N%".
    for (final m in RegExp(r'\b(\d+(?:\.\d+)?)\s+(?:percent|per\s+cent)\b', caseSensitive: false).allMatches(text)) {
      keys.add('${m.group(1)}%');
    }
    return keys;
  }

  static final RegExp _negationPattern = RegExp(
    r"\b(?:not|no|never|none|nobody|nothing|neither|nor|without|cannot|unable\s+to|fail\s+to|fails\s+to|failed\s+to|failing\s+to|hardly|scarcely)\b|n't\b",
    caseSensitive: false,
  );
  static final RegExp _rhetoricalNot = RegExp(r'\bnot\s+(?:only|just|merely)\b', caseSensitive: false);

  /// Public accessor for negation counting with rhetorical exceptions excluded.
  static int countNegations(String text) => _countNegations(text);

  static int _countNegations(String text) {
    return _negationPattern.allMatches(text).length - _rhetoricalNot.allMatches(text).length;
  }

  Set<String> _extractCitations(String text) {
    return _citationPattern
        .allMatches(text)
        .map((m) => m.group(0)!.trim())
        .toSet();
  }

  Set<String> _extractNamedEntities(String text) {
    final entities = <String>{};
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    for (final sent in sentences) {
      final words = sent.split(RegExp(r'\s+'));
      // Skip the very first word since it's capitalized by sentence start rule
      for (int i = 1; i < words.length; i++) {
        final clean = words[i].replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
        if (clean.length > 2 && clean[0].toUpperCase() == clean[0] && clean[0].toLowerCase() != clean[0]) {
          entities.add(clean);
        }
      }
    }
    // Also capture camelCase or internal uppercase terms anywhere (e.g., iPhone, eBay, ChatGPT, OpenAI, arXiv, PubMed)
    for (final m in RegExp(r'\b[a-zA-Z]*[a-z]+[A-Z][a-zA-Z0-9]*\b').allMatches(text)) {
      final word = m.group(0)!;
      if (word.length >= 3) entities.add(word);
    }
    // Also capture all-caps acronyms (e.g., NASA, UNESCO, GDP, LLM, BERT, API, GPU) anywhere, including sentence starts
    for (final m in RegExp(r'\b[A-Z]{2,}(?:[0-9]+)?\b').allMatches(text)) {
      final word = m.group(0)!;
      entities.add(word);
    }
    return entities;
  }

  Set<String> _extractContentWords(String text) {
    const stopWords = {
      'the', 'and', 'a', 'to', 'of', 'in', 'is', 'that', 'for', 'it', 'as', 'was',
      'with', 'be', 'by', 'on', 'not', 'he', 'i', 'this', 'are', 'or', 'an', 'from',
      'at', 'which', 'you', 'have', 'were', 'their', 'one', 'all', 'we', 'can', 'her',
      'has', 'there', 'been', 'if', 'more', 'when', 'will', 'would', 'who', 'so',
      'no', 'they', 'out', 'up', 'my', 'about', 'than', 'into', 'them', 'these',
    };
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet();
  }

  static final RegExp _unitPattern = RegExp(
    r'(?:[\$€£¥₹]|\b(?:USD|EUR|GBP|JPY|INR|CHF|CAD|AUD|KRW|CNY|BRL|MXN|SGD|HKD|NZD|SEK|NOK|TRY|ZAR|AED|SAR)\b|\b\d+(?:[,\.]\d+)*\s*(?:kg|mg|g|km|cm|mm|m|GHz|MHz|kHz|Hz|THz|GB|MB|KB|TB|PB|dB|ms|rpm|°C|°F|K|mph|km/h|psi|bar|Pa|kPa|MPa|GPa|mol|mmol|μm|um|nm|pm|ns|μs|us|sec|min|hr|hrs|bps|Kbps|Mbps|Gbps|Tbps|W|kW|MW|GW|TW|J|kJ|MJ|kWh|MWh|V|kV|mV|mA|A|percent|%)\b)',
    caseSensitive: false,
  );

  Set<String> _extractUnitsAndCurrencies(String text) {
    return _unitPattern
        .allMatches(text)
        .map((m) => m.group(0)!.trim().toLowerCase())
        .toSet();
  }

  static final RegExp _upwardPattern = RegExp(
    r'\b(?:increase|increases|increased|increasing|growth|grows|grew|growing|rise|rises|rose|rising|risen|boost|boosts|boosted|boosting|higher|highest|gain|gains|gained|gaining|surge|surges|surged|surging|accelerate|accelerated)\b',
    caseSensitive: false,
  );
  static final RegExp _downwardPattern = RegExp(
    r'\b(?:decrease|decreases|decreased|decreasing|reduction|reductions|reduce|reduces|reduced|reducing|drop|drops|dropped|dropping|fall|falls|fell|falling|fallen|decline|declines|declined|declining|lower|lowest|shrink|shrinks|shrank|shrinking|slowdown|diminish|diminished)\b',
    caseSensitive: false,
  );

  static final RegExp _temporalBeforePattern = RegExp(
    r'\b(?:before|prior\s+to|preceding|preceded\s+by|antecedent\s+to|earlier\s+than)\b',
    caseSensitive: false,
  );
  static final RegExp _temporalAfterPattern = RegExp(
    r'\b(?:after|subsequent\s+to|following|succeeded\s+by|later\s+than)\b',
    caseSensitive: false,
  );
  static final RegExp _causalAntecedentPattern = RegExp(
    r'\b(?:caused\s+by|due\s+to|resulting\s+from|attributed\s+to|triggered\s+by)\b',
    caseSensitive: false,
  );
  static final RegExp _causalConsequentPattern = RegExp(
    r'\b(?:causes|leads\s+to|results\s+in|triggers|produces)\b',
    caseSensitive: false,
  );

  bool _detectRelationalDrift(String original, String rewritten) {
    final origUp = _upwardPattern.allMatches(original).length;
    final origDown = _downwardPattern.allMatches(original).length;
    final rewUp = _upwardPattern.allMatches(rewritten).length;
    final rewDown = _downwardPattern.allMatches(rewritten).length;

    // Inversion between strictly upward and downward
    if (origUp > 0 && origDown == 0 && rewDown > 0 && rewUp == 0) return true;
    if (origDown > 0 && origUp == 0 && rewUp > 0 && rewDown == 0) return true;

    // Inversion of temporal sequence
    final origBefore = _temporalBeforePattern.allMatches(original).length;
    final origAfter = _temporalAfterPattern.allMatches(original).length;
    final rewBefore = _temporalBeforePattern.allMatches(rewritten).length;
    final rewAfter = _temporalAfterPattern.allMatches(rewritten).length;
    if (origBefore > 0 && origAfter == 0 && rewAfter > 0 && rewBefore == 0) return true;
    if (origAfter > 0 && origBefore == 0 && rewBefore > 0 && rewAfter == 0) return true;

    // Inversion of causal direction
    final origCause = _causalAntecedentPattern.allMatches(original).length;
    final origEffect = _causalConsequentPattern.allMatches(original).length;
    final rewCause = _causalAntecedentPattern.allMatches(rewritten).length;
    final rewEffect = _causalConsequentPattern.allMatches(rewritten).length;
    if (origCause > 0 && origEffect == 0 && rewEffect > 0 && rewCause == 0) return true;
    if (origEffect > 0 && origCause == 0 && rewCause > 0 && rewEffect == 0) return true;

    return false;
  }

  String _buildSummary({
    required SemanticPreservationVerdict verdict,
    required double score,
    required List<String> missingNumbers,
    required List<String> introducedNumbers,
    required List<String> missingUnits,
    required List<String> missingCitations,
    required double aiReduction,
    bool aiScaleIsPercent = false,
    bool polarityDrift = false,
    int negationsBefore = 0,
    int negationsAfter = 0,
    double lengthRatio = 1.0,
  }) {
    final buffer = StringBuffer();
    final pct = (score * 100).toStringAsFixed(0);

    switch (verdict) {
      case SemanticPreservationVerdict.excellent:
        buffer.write('High factual fidelity ($pct% match). Core entities, facts, and structure preserved.');
        break;
      case SemanticPreservationVerdict.acceptable:
        buffer.write('Good semantic preservation ($pct%). Core concepts intact with moderate rephrasing.');
        break;
      case SemanticPreservationVerdict.divergent:
        buffer.write('Substantial structural deviation ($pct% fidelity). Core phrasing was heavily altered.');
        break;
      case SemanticPreservationVerdict.factualDriftAlert:
        buffer.write('Factual drift warning: Numbers or quantities from the original were lost during rewrite.');
        break;
    }

    if (missingNumbers.isNotEmpty) {
      buffer.write(' Missing figures: ${missingNumbers.take(3).join(', ')}.');
    }
    if (introducedNumbers.isNotEmpty) {
      buffer.write(' New figures introduced: ${introducedNumbers.take(2).join(', ')}.');
    }
    if (missingUnits.isNotEmpty) {
      buffer.write(' Missing units/currencies: ${missingUnits.take(3).join(', ')}.');
    }
    if (missingCitations.isNotEmpty) {
      buffer.write(' Notice: ${missingCitations.length} citation(s) were altered or dropped.');
    }
    if (lengthRatio < 0.80) {
      buffer.write(' Output dropped below 80% of original length (${(lengthRatio * 100).toStringAsFixed(0)}%).');
    }
    if (polarityDrift) {
      if (negationsBefore != negationsAfter) {
        buffer.write(' Negation count changed ($negationsBefore vs $negationsAfter) — polarity mismatch guard triggered.');
      } else {
        buffer.write(' Negation or directional polarity changed — check that no claim was inverted.');
      }
    }
    // Callers pass AI probabilities either as 0-1 or 0-100; report points.
    final reductionPoints = aiScaleIsPercent ? aiReduction : aiReduction * 100;
    if (reductionPoints > 15) {
      buffer.write(' AI likelihood decreased by ${reductionPoints.toStringAsFixed(0)} points.');
    }

    return buffer.toString();
  }
}
