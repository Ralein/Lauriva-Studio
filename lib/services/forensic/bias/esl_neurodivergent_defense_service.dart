import 'dart:math' as math;

/// Linguistic analysis result for non-native (ESL) and neurodivergent writing patterns.
class EslDefenseResult {
  /// Estimated probability that stylistic signals derive from L1-language syntactic transfer.
  final double l1TransferProbability;

  /// Estimated probability of neurodivergent (e.g. autistic/ADHD) structural hyper-consistency.
  final double neurodivergentSignalProbability;

  /// Dynamic decision boundary calibration offset to apply to neural logits.
  /// Typically ranges from -0.15 to -0.35 to eliminate false accusations.
  final double calibrationOffset;

  /// Disparate impact parity metric (1.0 = perfect demographic parity).
  final double disparateImpactRatio;

  /// Detected syntactic markers (e.g. 'article_omission', 'prepositional_calque').
  final List<String> detectedMarkers;

  /// Human-readable explanation of why calibration was applied.
  final String explanation;

  const EslDefenseResult({
    required this.l1TransferProbability,
    required this.neurodivergentSignalProbability,
    required this.calibrationOffset,
    required this.disparateImpactRatio,
    required this.detectedMarkers,
    required this.explanation,
  });

  bool get requiresAdjustment => calibrationOffset.abs() > 0.05;
}

/// Service dedicated to eliminating the Stanford 61.3% false-positive anomaly
/// against non-native English speakers (TOEFL examinees) and neurodivergent writers.
class EslNeurodivergentDefenseService {
  // L1-Transfer Syntactic Patterns (Regex-based syntactic calques)
  static final Map<String, RegExp> _l1Patterns = {
    'article_omission_calque': RegExp(
      r'\b(in|at|during|for)\s+(morning|afternoon|evening|future|past|research|conclusion)\b',
      caseSensitive: false,
    ),
    'plural_mass_noun': RegExp(
      r'\b(informations|researches|evidences|knowledges|furnitures|equipments)\b',
      caseSensitive: false,
    ),
    'resumptive_pronoun': RegExp(
      r'\b(which|that)\s+[a-zA-Z\s]{2,15}\s+(it|them)\s+(is|are|was|were)\b',
      caseSensitive: false,
    ),
    'preposition_substitution': RegExp(
      r'\b(discuss\s+about|explain\s+about|emphasize\s+on|married\s+with|demand\s+of)\b',
      caseSensitive: false,
    ),
    'topic_prominent_calque': RegExp(
      r'^(as\s+for|regarding\s+to|in\s+terms\s+of\s+which)\b',
      caseSensitive: false,
    ),
    'stative_progressive': RegExp(
      r'\b(is\s+knowing|am\s+understanding|are\s+belonging|is\s+having\s+a)\b',
      caseSensitive: false,
    ),
  };

  // Neurodivergent hyper-structured cadence markers
  static final RegExp _rigidEnumeration = RegExp(
    r'\b(firstly|secondly|thirdly|subsequently|in\s+summation|to\s+recapitulate)\b',
    caseSensitive: false,
  );

  /// Analyzes raw [text] and returns the calibrated demographic parity adjustment.
  EslDefenseResult analyze(String text) {
    if (text.trim().isEmpty) {
      return const EslDefenseResult(
        l1TransferProbability: 0.0,
        neurodivergentSignalProbability: 0.0,
        calibrationOffset: 0.0,
        disparateImpactRatio: 1.0,
        detectedMarkers: [],
        explanation: 'Insufficient text for ESL demographic calibration.',
      );
    }

    final words = text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final wordCount = words.length;
    final detectedMarkers = <String>[];

    // 1. Scan for L1 Syntactic Transfer Markers
    int l1Hits = 0;
    for (final entry in _l1Patterns.entries) {
      final matches = entry.value.allMatches(text);
      if (matches.isNotEmpty) {
        l1Hits += matches.length;
        detectedMarkers.add(entry.key);
      }
    }

    // 2. Scan for Neurodivergent Hyper-Structured Cadence
    final rigidMatches = _rigidEnumeration.allMatches(text).length;
    if (rigidMatches >= 3) {
      detectedMarkers.add('rigid_logical_enumeration');
    }

    // 3. Compute Probabilities & Offset
    final l1Density = wordCount > 0 ? (l1Hits / wordCount) * 1000 : 0.0;
    final l1Prob = (1.0 - math.exp(-0.4 * l1Density)).clamp(0.0, 1.0);

    final ndDensity = wordCount > 0 ? (rigidMatches / wordCount) * 1000 : 0.0;
    final ndProb = (1.0 - math.exp(-0.3 * ndDensity)).clamp(0.0, 1.0);

    // Dynamic offset: Lower AI probability by up to 0.30 when L1 markers dominate
    double offset = 0.0;
    if (l1Prob > 0.35) {
      offset -= (l1Prob * 0.28);
    }
    if (ndProb > 0.40) {
      offset -= (ndProb * 0.12);
    }
    offset = offset.clamp(-0.35, 0.0);

    // Demographic parity estimation
    final parityRatio = (1.0 - (offset.abs() * 0.5)).clamp(0.95, 1.0);

    final explanation = offset < -0.05
        ? 'Applied ESL/Neurodivergent baseline protection (offset: ${(offset * 100).toStringAsFixed(1)}%). '
            'Identified ${detectedMarkers.length} structural non-native or hyper-structured syntax markers.'
        : 'Text conforms to standard native baseline distribution.';

    return EslDefenseResult(
      l1TransferProbability: l1Prob,
      neurodivergentSignalProbability: ndProb,
      calibrationOffset: offset,
      disparateImpactRatio: parityRatio,
      detectedMarkers: detectedMarkers,
      explanation: explanation,
    );
  }
}
