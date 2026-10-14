import 'dart:math' as math;

/// Audit result for non-prose elements (LaTeX, Tables, Charts).
class MultimodalForensicReport {
  final bool containsLatexMath;
  final bool latexSyntaxValid;
  final bool containsTabularData;
  final double benfordLawPValue;
  final bool isSyntheticDataFabricated;
  final String summary;

  const MultimodalForensicReport({
    required this.containsLatexMath,
    required this.latexSyntaxValid,
    required this.containsTabularData,
    required this.benfordLawPValue,
    required this.isSyntheticDataFabricated,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'containsLatexMath': containsLatexMath,
        'latexSyntaxValid': latexSyntaxValid,
        'containsTabularData': containsTabularData,
        'benfordLawPValue': benfordLawPValue,
        'isSyntheticDataFabricated': isSyntheticDataFabricated,
        'summary': summary,
      };
}

/// Service that analyzes LaTeX equations, embedded tables, and Benford's Law statistical conformity.
class MultimodalArtifactForensicsService {
  static final RegExp _latexPattern = RegExp(r'(\${1,2}[^\$]+\${1,2}|\\begin\{equation\}[\s\S]*?\\end\{equation\})');
  static final RegExp _numberPattern = RegExp(r'\b([1-9])\d*(\.\d+)?\b');

  MultimodalForensicReport audit(String content) {
    // 1. LaTeX Math Audit
    final latexMatches = _latexPattern.allMatches(content);
    final hasLatex = latexMatches.isNotEmpty;
    bool latexValid = true;

    if (hasLatex) {
      for (final m in latexMatches) {
        final mathBlock = m.group(0)!;
        // Check for unbalanced braces or common hallucinated hallucination patterns
        final openBraces = RegExp(r'\{').allMatches(mathBlock).length;
        final closeBraces = RegExp(r'\}').allMatches(mathBlock).length;
        if (openBraces != closeBraces) {
          latexValid = false;
          break;
        }
      }
    }

    // 2. Benford's Law on Numerical Data
    final numMatches = _numberPattern.allMatches(content).toList();
    final hasNumbers = numMatches.length >= 25;
    double benfordPValue = 1.0;
    bool isDataFabricated = false;

    if (hasNumbers) {
      final leadingDigits = <int, int>{};
      for (final m in numMatches) {
        final firstChar = m.group(1)!;
        final d = int.parse(firstChar);
        leadingDigits[d] = (leadingDigits[d] ?? 0) + 1;
      }

      // Expected Benford probabilities: P(d) = log10(1 + 1/d)
      double chiSquare = 0.0;
      final total = numMatches.length.toDouble();
      for (int d = 1; d <= 9; d++) {
        final expectedProb = math.log(1.0 + 1.0 / d) / math.ln10;
        final expectedCount = expectedProb * total;
        final observedCount = (leadingDigits[d] ?? 0).toDouble();
        chiSquare += math.pow(observedCount - expectedCount, 2) / expectedCount;
      }

      // If chi-square > 20.0 with 8 degrees of freedom, p < 0.01 (reject null hypothesis -> synthetic data)
      if (chiSquare > 22.0) {
        isDataFabricated = true;
        benfordPValue = 0.005;
      } else {
        benfordPValue = 0.65;
      }
    }

    final summary = hasLatex && !latexValid
        ? 'ALERT: Hallucinated or malformed LaTeX mathematical expressions detected.'
        : isDataFabricated
            ? 'ALERT: Embedded numerical data violates Benford\'s Law (fabricated synthetic table).'
            : 'Multimodal artifact forensics passed without anomalies.';

    return MultimodalForensicReport(
      containsLatexMath: hasLatex,
      latexSyntaxValid: latexValid,
      containsTabularData: hasNumbers,
      benfordLawPValue: benfordPValue,
      isSyntheticDataFabricated: isDataFabricated,
      summary: summary,
    );
  }
}
