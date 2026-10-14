/// Authorship attribution class for an individual clause.
enum AuthorshipClass {
  /// Class 0 (🟢): Novel conceptual framing, idiosyncratic metaphors, personal lived experience.
  humanInception,

  /// Class 1 (🟡): Structurally assisted prose, bullet expansion, stylistic polishing.
  humanPromptedAiExpanded,

  /// Class 2 (🔴): Direct synthetic prose without human conceptual intervention.
  pureMachineGeneration,
}

/// A specific clause span with micro-authorship attribution.
class ClauseAuthorshipSpan {
  final int startIndex;
  final int endIndex;
  final String text;
  final AuthorshipClass authorshipClass;
  final double confidence;
  final String justification;

  const ClauseAuthorshipSpan({
    required this.startIndex,
    required this.endIndex,
    required this.text,
    required this.authorshipClass,
    required this.confidence,
    required this.justification,
  });

  Map<String, dynamic> toJson() => {
        'startIndex': startIndex,
        'endIndex': endIndex,
        'text': text,
        'authorshipClass': authorshipClass.name,
        'confidence': confidence,
        'justification': justification,
      };
}

/// The comprehensive collaborative micro-authorship report.
class MicroAuthorshipReport {
  final double quantifiedAuthorshipIndex; // QAI: 0.0% to 100.0%
  final List<ClauseAuthorshipSpan> clauses;
  final int humanClauseCount;
  final int assistedClauseCount;
  final int machineClauseCount;
  final String institutionalCertificateSummary;

  const MicroAuthorshipReport({
    required this.quantifiedAuthorshipIndex,
    required this.clauses,
    required this.humanClauseCount,
    required this.assistedClauseCount,
    required this.machineClauseCount,
    required this.institutionalCertificateSummary,
  });

  Map<String, dynamic> toJson() => {
        'quantifiedAuthorshipIndex': quantifiedAuthorshipIndex,
        'clauses': clauses.map((c) => c.toJson()).toList(),
        'humanClauseCount': humanClauseCount,
        'assistedClauseCount': assistedClauseCount,
        'machineClauseCount': machineClauseCount,
        'institutionalCertificateSummary': institutionalCertificateSummary,
      };
}

/// Service that decomposes documents into clause-level collaborative micro-authorship
/// heatmaps and calculates the Quantified Authorship Index (QAI).
class MicroAuthorshipHeatmapService {
  // Regex splitting on clause boundaries (commas, semicolons, dashes, conjuncts)
  static final RegExp _clauseBoundary = RegExp(r'([,;:\—\-]|\b(and|but|while|whereas|although|because)\b)');

  /// Decomposes [text] and evaluates token-level authorship origins.
  MicroAuthorshipReport analyze(String text) {
    if (text.trim().isEmpty) {
      return const MicroAuthorshipReport(
        quantifiedAuthorshipIndex: 100.0,
        clauses: [],
        humanClauseCount: 0,
        assistedClauseCount: 0,
        machineClauseCount: 0,
        institutionalCertificateSummary: 'Empty document.',
      );
    }

    final rawClauses = _extractClauses(text);
    final spans = <ClauseAuthorshipSpan>[];

    int humanCount = 0;
    int assistedCount = 0;
    int machineCount = 0;
    double weightedHumanScore = 0.0;

    for (final c in rawClauses) {
      final classification = _classifyClause(c.text);
      spans.add(
        ClauseAuthorshipSpan(
          startIndex: c.start,
          endIndex: c.end,
          text: c.text,
          authorshipClass: classification.item1,
          confidence: classification.item2,
          justification: classification.item3,
        ),
      );

      switch (classification.item1) {
        case AuthorshipClass.humanInception:
          humanCount++;
          weightedHumanScore += 1.0;
          break;
        case AuthorshipClass.humanPromptedAiExpanded:
          assistedCount++;
          weightedHumanScore += 0.50; // Assisted writing earns 50% QAI credit
          break;
        case AuthorshipClass.pureMachineGeneration:
          machineCount++;
          weightedHumanScore += 0.0;
          break;
      }
    }

    final totalClauses = rawClauses.length;
    final qai = totalClauses > 0
        ? ((weightedHumanScore / totalClauses) * 100.0).clamp(0.0, 100.0)
        : 100.0;

    final summary = 'Quantified Authorship Index (QAI): ${qai.toStringAsFixed(1)}%. '
        '($humanCount Human Inception, $assistedCount Assisted/Polished, $machineCount Pure Synthetic).';

    return MicroAuthorshipReport(
      quantifiedAuthorshipIndex: qai,
      clauses: spans,
      humanClauseCount: humanCount,
      assistedClauseCount: assistedCount,
      machineClauseCount: machineCount,
      institutionalCertificateSummary: summary,
    );
  }

  List<_RawClause> _extractClauses(String text) {
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final results = <_RawClause>[];
    int currentOffset = 0;

    for (final sentence in sentences) {
      final sTrim = sentence.trim();
      if (sTrim.isEmpty) continue;

      final startPos = text.indexOf(sTrim, currentOffset);
      final subMatches = _clauseBoundary.allMatches(sTrim).toList();

      if (subMatches.isEmpty) {
        results.add(_RawClause(text: sTrim, start: startPos, end: startPos + sTrim.length));
      } else {
        int clauseStart = 0;
        for (final m in subMatches) {
          final chunk = sTrim.substring(clauseStart, m.start).trim();
          if (chunk.length >= 8) {
            results.add(_RawClause(
              text: chunk,
              start: startPos + clauseStart,
              end: startPos + m.start,
            ));
          }
          clauseStart = m.end;
        }
        if (clauseStart < sTrim.length) {
          final remainder = sTrim.substring(clauseStart).trim();
          if (remainder.length >= 8) {
            results.add(_RawClause(
              text: remainder,
              start: startPos + clauseStart,
              end: startPos + sTrim.length,
            ));
          }
        }
      }
      currentOffset = startPos + sTrim.length;
    }

    return results;
  }

  // Returns (Class, Confidence, Justification)
  _ClassificationTuple _classifyClause(String clauseText) {
    final lower = clauseText.toLowerCase();

    // Machine indicators
    final machineMarkers = [
      'it is essential to', 'furthermore', 'rigorous evaluation',
      'epistemic hedging', 'test-time compute', 'in conclusion',
      'moreover', 'delves into', 'tapestry of', 'serves as a testament',
    ];
    // Human markers
    final humanMarkers = [
      'i felt', 'in my experience', 'we realized that',
      'honestly', 'weirdly enough', 'in our kitchen', 'my brother',
    ];

    for (final m in humanMarkers) {
      if (lower.contains(m)) {
        return _ClassificationTuple(
          AuthorshipClass.humanInception,
          0.94,
          'Personal experiential anchor and idiosyncratic framing.',
        );
      }
    }

    for (final m in machineMarkers) {
      if (lower.contains(m)) {
        return _ClassificationTuple(
          AuthorshipClass.pureMachineGeneration,
          0.91,
          'Metronomic synthetic transition marker.',
        );
      }
    }

    // Default to assisted if syntactically polished but devoid of unique markers
    if (clauseText.split(RegExp(r'\s+')).length > 12) {
      return _ClassificationTuple(
        AuthorshipClass.humanPromptedAiExpanded,
        0.75,
        'Elaborated clause structure characteristic of stylistic assistance.',
      );
    }

    return _ClassificationTuple(
      AuthorshipClass.humanInception,
      0.82,
      'Organic clause flow.',
    );
  }
}

class _RawClause {
  final String text;
  final int start;
  final int end;
  const _RawClause({required this.text, required this.start, required this.end});
}

class _ClassificationTuple {
  final AuthorshipClass item1;
  final double item2;
  final String item3;
  const _ClassificationTuple(this.item1, this.item2, this.item3);
}
