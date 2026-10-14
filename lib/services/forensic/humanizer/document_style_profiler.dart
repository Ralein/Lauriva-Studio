import 'dart:math';
import '../../text_forensics_lexicons.dart';

/// Lightweight authorial style profile extracted from the source document
/// to enforce consistent voice, formality, and syntax across all chunks.
class DocumentStyleProfile {
  final double formality; // 0.0 (casual) to 1.0 (academic/formal)
  final double meanSentenceLength; // in words
  final double sentenceLengthStdDev;
  final double firstPersonRatio; // 1st person pronouns per 100 words
  final double thirdPersonRatio; // 3rd person pronouns per 100 words
  final double contractionDensity; // contractions per 100 words
  final double passiveVoiceRatio; // passive verb constructions per sentence
  final double vocabularyComplexity; // avg characters per word
  final bool isAcademic;
  final bool prefersContractions;

  const DocumentStyleProfile({
    required this.formality,
    required this.meanSentenceLength,
    required this.sentenceLengthStdDev,
    required this.firstPersonRatio,
    required this.thirdPersonRatio,
    required this.contractionDensity,
    required this.passiveVoiceRatio,
    required this.vocabularyComplexity,
    required this.isAcademic,
    required this.prefersContractions,
  });

  /// Default baseline profile for standard academic/professional prose.
  factory DocumentStyleProfile.standard() {
    return const DocumentStyleProfile(
      formality: 0.75,
      meanSentenceLength: 18.0,
      sentenceLengthStdDev: 6.0,
      firstPersonRatio: 0.2,
      thirdPersonRatio: 2.5,
      contractionDensity: 0.0,
      passiveVoiceRatio: 0.25,
      vocabularyComplexity: 5.2,
      isAcademic: true,
      prefersContractions: false,
    );
  }

  /// Generates concise, structured style constraints for inclusion in the rewrite prompt.
  String toPromptInstructions() {
    final buffer = StringBuffer();
    if (isAcademic) {
      buffer.writeln('- Maintain scholarly, academic rigor with formal register.');
    } else if (formality > 0.6) {
      buffer.writeln('- Maintain a polished, professional tone.');
    } else {
      buffer.writeln('- Maintain an accessible, natural conversational tone.');
    }

    if (prefersContractions) {
      buffer.writeln('- Natural contractions (e.g. don\'t, it\'s, wouldn\'t) are acceptable where natural.');
    } else {
      buffer.writeln('- Avoid informal contractions; preserve formal unabbreviated phrasing.');
    }

    if (firstPersonRatio > 1.5) {
      buffer.writeln('- Preserve first-person authorial perspective ("we", "our", "I").');
    } else if (thirdPersonRatio > 1.0) {
      buffer.writeln('- Maintain objective third-person perspective.');
    }

    buffer.writeln(
      '- Target sentence rhythm: vary length around ~${meanSentenceLength.round()} words '
      '(mix short punches with rich multi-clause sentences).',
    );
    return buffer.toString().trim();
  }
}

/// Profiler that inspects the source document to extract syntactic and stylistic markers.
class DocumentStyleProfiler {
  static final RegExp _contractionsRegex = RegExp(
    r"\b\w+(?:'t|'re|'ve|'ll|'d|'s)\b",
    caseSensitive: false,
  );

  static final RegExp _firstPersonRegex = RegExp(
    r'\b(?:i|me|my|mine|we|us|our|ours)\b',
    caseSensitive: false,
  );

  static final RegExp _thirdPersonRegex = RegExp(
    r'\b(?:he|him|his|she|her|hers|they|them|their|theirs|it|its|the author|the authors|the researchers)\b',
    caseSensitive: false,
  );

  static final RegExp _passiveVoiceRegex = RegExp(
    r'\b(?:is|are|was|were|be|been|being)\s+(?:[a-z]+ed|[a-z]+en|shown|seen|found|observed|conducted|analyzed|noted|tested)\b',
    caseSensitive: false,
  );

  static final RegExp _academicWordsRegex = RegExp(
    r'\b(?:furthermore|moreover|consequently|nonetheless|nevertheless|paradigm|substantiate|empirical|methodology|implication|phenomenon|synthesis|qualitative|quantitative|elucidate|postulate|dichotomy)\b',
    caseSensitive: false,
  );

  /// Analyzes [text] and returns a [DocumentStyleProfile].
  DocumentStyleProfile profile(String text) {
    final clean = text.trim();
    if (clean.isEmpty) {
      return DocumentStyleProfile.standard();
    }

    final sentences = TextForensicsLexicons.splitSentences(clean);
    final words = TextForensicsLexicons.extractWords(clean);
    final totalWords = max(words.length, 1);
    final totalSentences = max(sentences.length, 1);

    // Sentence length distribution
    final sentenceLengths = <int>[];
    for (final s in sentences) {
      final sWords = TextForensicsLexicons.extractWords(s);
      if (sWords.isNotEmpty) {
        sentenceLengths.add(sWords.length);
      }
    }

    final meanLength = sentenceLengths.isEmpty
        ? 16.0
        : sentenceLengths.reduce((a, b) => a + b) / sentenceLengths.length;

    double variance = 0.0;
    for (final l in sentenceLengths) {
      variance += pow(l - meanLength, 2);
    }
    final stdDev = sentenceLengths.isEmpty ? 4.0 : sqrt(variance / sentenceLengths.length);

    // Pronouns & Contractions
    final firstPersonMatches = _firstPersonRegex.allMatches(clean).length;
    final thirdPersonMatches = _thirdPersonRegex.allMatches(clean).length;
    final contractionMatches = _contractionsRegex.allMatches(clean).length;
    final passiveMatches = _passiveVoiceRegex.allMatches(clean).length;
    final academicMatches = _academicWordsRegex.allMatches(clean).length;

    final firstPersonRatio = (firstPersonMatches / totalWords) * 100.0;
    final thirdPersonRatio = (thirdPersonMatches / totalWords) * 100.0;
    final contractionDensity = (contractionMatches / totalWords) * 100.0;
    final passiveRatio = passiveMatches / totalSentences;

    // Vocabulary complexity (avg characters per word)
    final totalChars = words.fold<int>(0, (sum, w) => sum + w.length);
    final avgWordLength = totalChars / totalWords;

    final academicScore = (academicMatches / totalWords) * 100.0;
    final isAcademic = academicScore > 0.8 || (avgWordLength > 5.1 && contractionDensity < 0.8);

    double formality = 0.5;
    if (isAcademic) formality += 0.25;
    if (contractionDensity < 0.5) formality += 0.15;
    if (passiveRatio > 0.2) formality += 0.1;
    formality = formality.clamp(0.0, 1.0);

    return DocumentStyleProfile(
      formality: formality,
      meanSentenceLength: meanLength,
      sentenceLengthStdDev: stdDev,
      firstPersonRatio: firstPersonRatio,
      thirdPersonRatio: thirdPersonRatio,
      contractionDensity: contractionDensity,
      passiveVoiceRatio: passiveRatio,
      vocabularyComplexity: avgWordLength,
      isAcademic: isAcademic,
      prefersContractions: contractionDensity > 1.2,
    );
  }
}
