/// Flagged logical fallacy or shallow coherence violation.
class LogicalAnomaly {
  final String fallacyType;
  final String passageSnippet;
  final double severity; // 0.0 to 1.0
  final String explanation;

  const LogicalAnomaly({
    required this.fallacyType,
    required this.passageSnippet,
    required this.severity,
    required this.explanation,
  });

  Map<String, dynamic> toJson() => {
        'fallacyType': fallacyType,
        'passageSnippet': passageSnippet,
        'severity': severity,
        'explanation': explanation,
      };
}

/// Sieve result from neuro-symbolic logic auditing.
class NeuroSymbolicReport {
  final double logicalCoherenceScore; // 0.0 to 1.0
  final bool hasShallowCoherenceAnomaly;
  final List<LogicalAnomaly> anomalies;
  final String auditSummary;

  const NeuroSymbolicReport({
    required this.logicalCoherenceScore,
    required this.hasShallowCoherenceAnomaly,
    required this.anomalies,
    required this.auditSummary,
  });

  Map<String, dynamic> toJson() => {
        'logicalCoherenceScore': logicalCoherenceScore,
        'hasShallowCoherenceAnomaly': hasShallowCoherenceAnomaly,
        'anomalies': anomalies.map((a) => a.toJson()).toList(),
        'auditSummary': auditSummary,
      };
}

/// Service that parses text for formal logical non-sequiturs and synthetic reasoning contradictions.
class LogicFallacySieve {
  static final List<_FallacyPattern> _rules = [
    _FallacyPattern(
      type: 'circular_reasoning',
      regex: RegExp(
        r'\b(because|since)\s+[a-zA-Z\s]{4,30}\s+(is|are|was|were)\s+true,\s*(therefore|thus|hence)\s+[a-zA-Z\s]{4,30}\s+(is|are)\s+true\b',
        caseSensitive: false,
      ),
      explanation: 'Circular premise assertion (begging the question).',
      severity: 0.85,
    ),
    _FallacyPattern(
      type: 'illicit_quantifier_shift',
      regex: RegExp(
        r'\b(some|certain)\s+[a-zA-Z\s]{2,20}\s+are\s+[a-zA-Z\s]{2,20},\s*(therefore|thus)\s+all\s+[a-zA-Z\s]{2,20}\s+must\b',
        caseSensitive: false,
      ),
      explanation: 'Illicit existential-to-universal quantifier shift.',
      severity: 0.90,
    ),
    _FallacyPattern(
      type: 'hasty_synthetic_hedging',
      regex: RegExp(
        r'\bwhile\s+it\s+is\s+true\s+that\s+[a-zA-Z\s]{5,40},\s*it\s+is\s+equally\s+clear\s+that\s+the\s+opposite\b',
        caseSensitive: false,
      ),
      explanation: 'Symmetric antithesis hedge indicating synthetic chain-of-thought balancing.',
      severity: 0.78,
    ),
  ];

  /// Audits [text] for formal logic fallacies and syntactic reasoning contradictions.
  NeuroSymbolicReport audit(String text) {
    final anomalies = <LogicalAnomaly>[];

    for (final rule in _rules) {
      final matches = rule.regex.allMatches(text);
      for (final m in matches) {
        final snippet = m.group(0)!;
        anomalies.add(
          LogicalAnomaly(
            fallacyType: rule.type,
            passageSnippet: snippet.length > 80 ? '${snippet.substring(0, 80)}...' : snippet,
            severity: rule.severity,
            explanation: rule.explanation,
          ),
        );
      }
    }

    final hasAnomalies = anomalies.isNotEmpty;
    final coherence = hasAnomalies ? (1.0 - (anomalies.length * 0.2)).clamp(0.2, 0.95) : 1.0;
    final summary = hasAnomalies
        ? 'Flagged ${anomalies.length} shallow coherence reasoning anomalies characteristic of synthetic generation.'
        : 'Zero formal logical contradictions detected in predicate analysis.';

    return NeuroSymbolicReport(
      logicalCoherenceScore: coherence,
      hasShallowCoherenceAnomaly: hasAnomalies,
      anomalies: anomalies,
      auditSummary: summary,
    );
  }
}

class _FallacyPattern {
  final String type;
  final RegExp regex;
  final String explanation;
  final double severity;
  const _FallacyPattern({
    required this.type,
    required this.regex,
    required this.explanation,
    required this.severity,
  });
}
