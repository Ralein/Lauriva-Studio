/// Techniques identified during adversarial evasion inspection.
enum EvasionTechnique {
  homoglyphSubstitution('Homoglyph Replacement', 'Cyrillic or Greek lookalikes swapped to break n-gram matching'),
  zeroWidthInjection('Invisible Character Injection', 'Zero-width spaces or joiners inserted between syllables'),
  softHyphenSpoofing('Soft Hyphen Masking', 'Soft hyphens injected to disrupt word tokenization'),
  artificialPunctuation('Synthetic Punctuation Jitter', 'Unnatural spacing or punctuation inserted to mimic burstiness');

  final String label;
  final String description;
  const EvasionTechnique(this.label, this.description);
}

/// Forensic evidence detailing detected adversarial evasion attempts.
class AdversarialObfuscationEvidence {
  final bool evasionAttemptDetected;
  final int homoglyphCount;
  final int hiddenCharacterCount;
  final List<EvasionTechnique> techniquesDetected;
  final List<String> flaggedExamples;
  final String sanitizedText;
  final String defensibleSummary;

  const AdversarialObfuscationEvidence({
    required this.evasionAttemptDetected,
    required this.homoglyphCount,
    required this.hiddenCharacterCount,
    required this.techniquesDetected,
    required this.flaggedExamples,
    required this.sanitizedText,
    required this.defensibleSummary,
  });

  const AdversarialObfuscationEvidence.clean(String text)
      : evasionAttemptDetected = false,
        homoglyphCount = 0,
        hiddenCharacterCount = 0,
        techniquesDetected = const [],
        flaggedExamples = const [],
        sanitizedText = text,
        defensibleSummary = 'No adversarial obfuscation or homoglyph evasion detected.';

  Map<String, dynamic> toJson() {
    return {
      'evasionAttemptDetected': evasionAttemptDetected,
      'homoglyphCount': homoglyphCount,
      'hiddenCharacterCount': hiddenCharacterCount,
      'techniquesDetected': techniquesDetected.map((t) => t.label).toList(),
      'flaggedExamples': flaggedExamples,
      'defensibleSummary': defensibleSummary,
    };
  }
}

/// Detects and de-cloaks adversarial evasion techniques used to bypass AI detectors.
class AdversarialObfuscationDetector {
  // Comprehensive mapping of Cyrillic and Greek homoglyphs to Latin equivalents
  static const Map<int, String> _homoglyphs = {
    // Cyrillic Lowercase
    0x0430: 'a', // Cyrillic Small Letter A
    0x0441: 'c', // Cyrillic Small Letter Es
    0x0435: 'e', // Cyrillic Small Letter Ie
    0x0456: 'i', // Cyrillic Small Letter Byelorussian-Ukrainian I
    0x0458: 'j', // Cyrillic Small Letter Je
    0x043E: 'o', // Cyrillic Small Letter O
    0x0440: 'p', // Cyrillic Small Letter Er
    0x0455: 's', // Cyrillic Small Letter Dze
    0x0443: 'y', // Cyrillic Small Letter U
    0x0445: 'x', // Cyrillic Small Letter Ha

    // Cyrillic Uppercase
    0x0410: 'A', // Cyrillic Capital Letter A
    0x0412: 'B', // Cyrillic Capital Letter Ve
    0x0421: 'C', // Cyrillic Capital Letter Es
    0x0415: 'E', // Cyrillic Capital Letter Ie
    0x041D: 'H', // Cyrillic Capital Letter En
    0x0406: 'I', // Cyrillic Capital Letter Byelorussian-Ukrainian I
    0x0408: 'J', // Cyrillic Capital Letter Je
    0x041A: 'K', // Cyrillic Capital Letter Ka
    0x041C: 'M', // Cyrillic Capital Letter Em
    0x041E: 'O', // Cyrillic Capital Letter O
    0x0420: 'P', // Cyrillic Capital Letter Er
    0x0422: 'T', // Cyrillic Capital Letter Te
    0x0425: 'X', // Cyrillic Capital Letter Ha
    0x0423: 'Y', // Cyrillic Capital Letter U

    // Greek Lowercase
    0x03B1: 'a', // Greek Small Letter Alpha
    0x03B5: 'e', // Greek Small Letter Epsilon
    0x03B9: 'i', // Greek Small Letter Iota
    0x03BF: 'o', // Greek Small Letter Omicron
    0x03C1: 'p', // Greek Small Letter Rho
    0x03C5: 'u', // Greek Small Letter Upsilon
    0x03BD: 'v', // Greek Small Letter Nu

    // Greek Uppercase
    0x0391: 'A', // Greek Capital Letter Alpha
    0x0392: 'B', // Greek Capital Letter Beta
    0x0395: 'E', // Greek Capital Letter Epsilon
    0x0397: 'H', // Greek Capital Letter Eta
    0x0399: 'I', // Greek Capital Letter Iota
    0x039A: 'K', // Greek Capital Letter Kappa
    0x039C: 'M', // Greek Capital Letter Mu
    0x039D: 'N', // Greek Capital Letter Nu
    0x039F: 'O', // Greek Capital Letter Omicron
    0x03A1: 'P', // Greek Capital Letter Rho
    0x03A4: 'T', // Greek Capital Letter Tau
    0x03A7: 'X', // Greek Capital Letter Chi
    0x03A5: 'Y', // Greek Capital Letter Upsilon
    0x0396: 'Z', // Greek Capital Letter Zeta
  };

  // Invisible and non-printing character codes
  static const Set<int> _invisibleCharCodes = {
    0x200B, // Zero-width space
    0x200C, // Zero-width non-joiner
    0x200D, // Zero-width joiner
    0xFEFF, // Zero-width no-break space / BOM
    0x2060, // Word joiner
    0x00AD, // Soft hyphen
    0x202A, // LTR embedding
    0x202B, // RTL embedding
    0x202C, // Pop directional formatting
    0x202D, // LTR override
    0x202E, // RTL override
  };

  /// Inspects [text] and produces de-cloaked text and adversarial evidence.
  AdversarialObfuscationEvidence inspect(String text) {
    if (text.isEmpty) {
      return const AdversarialObfuscationEvidence.clean('');
    }

    final sanitizedBuffer = StringBuffer();
    final techniques = <EvasionTechnique>{};
    final examples = <String>[];

    int homoglyphCount = 0;
    int hiddenCount = 0;

    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      final char = text[i];

      // Check invisible characters
      if (_invisibleCharCodes.contains(code)) {
        hiddenCount++;
        if (code == 0x00AD) {
          techniques.add(EvasionTechnique.softHyphenSpoofing);
        } else {
          techniques.add(EvasionTechnique.zeroWidthInjection);
        }
        continue;
      }

      // Check homoglyphs
      if (_homoglyphs.containsKey(code)) {
        homoglyphCount++;
        techniques.add(EvasionTechnique.homoglyphSubstitution);
        final replacement = _homoglyphs[code]!;
        sanitizedBuffer.write(replacement);

        if (examples.length < 5) {
          final contextStart = (i - 3).clamp(0, text.length);
          final contextEnd = (i + 4).clamp(0, text.length);
          examples.add('Character "$char" (U+${code.toRadixString(16).toUpperCase()}) in "${text.substring(contextStart, contextEnd)}" -> replaced with "$replacement"');
        }
        continue;
      }

      sanitizedBuffer.write(char);
    }

    final evasionDetected = homoglyphCount > 0 || hiddenCount > 0;

    String summary;
    if (!evasionDetected) {
      summary = 'Clean document: zero adversarial homoglyphs or invisible characters detected.';
    } else {
      final parts = <String>[];
      if (homoglyphCount > 0) parts.add('$homoglyphCount homoglyph substitution(s)');
      if (hiddenCount > 0) parts.add('$hiddenCount hidden/zero-width character(s)');
      summary = 'Adversarial evasion attempt identified: ${parts.join(', ')} were stripped to de-cloak the text.';
    }

    return AdversarialObfuscationEvidence(
      evasionAttemptDetected: evasionDetected,
      homoglyphCount: homoglyphCount,
      hiddenCharacterCount: hiddenCount,
      techniquesDetected: techniques.toList(),
      flaggedExamples: examples,
      sanitizedText: sanitizedBuffer.toString(),
      defensibleSummary: summary,
    );
  }

  /// Attack 3: Grammar error injection detection.
  /// Human grammar errors cluster spatially, whereas synthetic error injection
  /// follows a uniform Poisson distribution across sentences.
  double errorClusteringCoefficient(String text) {
    if (text.trim().isEmpty) return 0.0;
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.isNotEmpty).toList();
    if (sentences.length < 4) return 0.0;

    final errorCounts = <int>[];
    for (final s in sentences) {
      int errors = 0;
      if (RegExp(r'\s{2,}').hasMatch(s)) errors++;
      if (RegExp(r',\s*,').hasMatch(s)) errors++;
      if (RegExp(r'\s+[.,!?;:]').hasMatch(s)) errors++;
      if (s.isNotEmpty && s[0] != s[0].toUpperCase() && RegExp(r'^[a-z]').hasMatch(s)) errors++;
      errorCounts.add(errors);
    }

    final totalErrors = errorCounts.reduce((a, b) => a + b);
    if (totalErrors < 3) return 0.0;

    final mean = totalErrors / errorCounts.length;
    double variance = 0.0;
    for (final c in errorCounts) {
      variance += (c - mean) * (c - mean);
    }
    variance /= errorCounts.length;

    final fano = mean > 0 ? (variance / mean) : 1.0;
    if (fano < 0.8) {
      return (1.0 - fano).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// Attack 4: Sentence fragmentation detection.
  /// Detects artificial splitting of sentences into consecutive short fragments (< 8 words)
  /// that share high pairwise token overlap to game burstiness variance.
  double fragmentationScore(List<String> sentences) {
    if (sentences.length < 3) return 0.0;

    int shortConsecutivePairs = 0;
    double totalOverlap = 0.0;

    for (int i = 0; i < sentences.length - 1; i++) {
      final wordsA = sentences[i].toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
      final wordsB = sentences[i + 1].toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

      if (wordsA.length < 8 && wordsB.length < 8 && wordsA.isNotEmpty && wordsB.isNotEmpty) {
        final intersection = wordsA.intersection(wordsB).length;
        final union = wordsA.union(wordsB).length;
        final jaccard = union > 0 ? (intersection / union) : 0.0;

        shortConsecutivePairs++;
        totalOverlap += jaccard;
      }
    }

    if (shortConsecutivePairs == 0) return 0.0;
    final avgOverlap = totalOverlap / shortConsecutivePairs;
    return (avgOverlap * (shortConsecutivePairs / (sentences.length - 1))).clamp(0.0, 1.0);
  }
}
