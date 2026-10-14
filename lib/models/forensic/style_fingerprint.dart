import 'dart:math';

/// A multidimensional linguistic fingerprint capturing authorial habits across
/// surface rhythm, punctuation, vocabulary, and syntactic structure.
class StyleFingerprint {
  // Surface Cadence
  final double meanSentenceLength;
  final double sentenceLengthStdDev;
  final double sentenceLengthSkew;
  final double meanParagraphLength;
  final double burstiness;

  // Punctuation Distribution
  final double commaRate; // per 100 words
  final double semicolonRate;
  final double colonRate;
  final double emDashRate;
  final double questionRate;
  final double punctuationEntropy;

  // Vocabulary Profile
  final double typeTokenRatio; // TTR
  final double guiraudR;
  final double hapaxRatio; // Words occurring once / total unique
  final double functionWordRatio;
  final double contractionDensity;

  // Structural Patterns
  final double transitionOpenerRate;
  final double conjunctionDensity;
  final double structuralTemplateEntropy;

  const StyleFingerprint({
    required this.meanSentenceLength,
    required this.sentenceLengthStdDev,
    required this.sentenceLengthSkew,
    required this.meanParagraphLength,
    required this.burstiness,
    required this.commaRate,
    required this.semicolonRate,
    required this.colonRate,
    required this.emDashRate,
    required this.questionRate,
    required this.punctuationEntropy,
    required this.typeTokenRatio,
    required this.guiraudR,
    required this.hapaxRatio,
    required this.functionWordRatio,
    required this.contractionDensity,
    required this.transitionOpenerRate,
    required this.conjunctionDensity,
    required this.structuralTemplateEntropy,
  });

  /// Default empty/baseline fingerprint.
  factory StyleFingerprint.empty() {
    return const StyleFingerprint(
      meanSentenceLength: 0.0,
      sentenceLengthStdDev: 0.0,
      sentenceLengthSkew: 0.0,
      meanParagraphLength: 0.0,
      burstiness: 0.0,
      commaRate: 0.0,
      semicolonRate: 0.0,
      colonRate: 0.0,
      emDashRate: 0.0,
      questionRate: 0.0,
      punctuationEntropy: 0.0,
      typeTokenRatio: 0.0,
      guiraudR: 0.0,
      hapaxRatio: 0.0,
      functionWordRatio: 0.0,
      contractionDensity: 0.0,
      transitionOpenerRate: 0.0,
      conjunctionDensity: 0.0,
      structuralTemplateEntropy: 0.0,
    );
  }

  /// Calculates normalized multidimensional Euclidean distance between two fingerprints.
  /// Distance ranges roughly from 0.0 (identical style) to 1.0+ (marked divergence).
  double distanceTo(StyleFingerprint other) {
    // Normalization scales for heterogeneous features
    final diffs = <double>[
      ((meanSentenceLength - other.meanSentenceLength) / 25.0).clamp(-2.0, 2.0),
      ((sentenceLengthStdDev - other.sentenceLengthStdDev) / 15.0).clamp(-2.0, 2.0),
      (burstiness - other.burstiness).clamp(-1.0, 1.0),
      ((commaRate - other.commaRate) / 5.0).clamp(-2.0, 2.0),
      ((emDashRate - other.emDashRate) / 2.0).clamp(-2.0, 2.0),
      (punctuationEntropy - other.punctuationEntropy).clamp(-1.5, 1.5),
      (typeTokenRatio - other.typeTokenRatio).clamp(-1.0, 1.0),
      (hapaxRatio - other.hapaxRatio).clamp(-1.0, 1.0),
      (functionWordRatio - other.functionWordRatio).clamp(-1.0, 1.0),
      (contractionDensity - other.contractionDensity).clamp(-1.0, 1.0),
      (transitionOpenerRate - other.transitionOpenerRate).clamp(-1.0, 1.0),
      (structuralTemplateEntropy - other.structuralTemplateEntropy).clamp(-1.0, 1.0),
    ];

    double sumSq = 0.0;
    for (final d in diffs) {
      sumSq += d * d;
    }
    return sqrt(sumSq / diffs.length);
  }

  Map<String, dynamic> toJson() => {
        'meanSentenceLength': meanSentenceLength,
        'sentenceLengthStdDev': sentenceLengthStdDev,
        'sentenceLengthSkew': sentenceLengthSkew,
        'meanParagraphLength': meanParagraphLength,
        'burstiness': burstiness,
        'commaRate': commaRate,
        'semicolonRate': semicolonRate,
        'colonRate': colonRate,
        'emDashRate': emDashRate,
        'questionRate': questionRate,
        'punctuationEntropy': punctuationEntropy,
        'typeTokenRatio': typeTokenRatio,
        'guiraudR': guiraudR,
        'hapaxRatio': hapaxRatio,
        'functionWordRatio': functionWordRatio,
        'contractionDensity': contractionDensity,
        'transitionOpenerRate': transitionOpenerRate,
        'conjunctionDensity': conjunctionDensity,
        'structuralTemplateEntropy': structuralTemplateEntropy,
      };
}

/// Stylistic transition shift between two document windows or sections.
enum StyleShiftType {
  none(label: 'Consistent Style'),
  humanToAi(label: 'Human to AI Shift'),
  aiToHuman(label: 'AI to Human Shift'),
  mixedTurbulence(label: 'Stylistic Turbulence');

  final String label;
  const StyleShiftType({required this.label});
}

/// Captured stylistic transition between two document segments.
class StyleShift {
  final int fromWindow;
  final int toWindow;
  final double distance;
  final StyleShiftType type;
  final String description;

  const StyleShift({
    required this.fromWindow,
    required this.toWindow,
    required this.distance,
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'fromWindow': fromWindow,
        'toWindow': toWindow,
        'distance': distance,
        'type': type.name,
        'description': description,
      };
}
