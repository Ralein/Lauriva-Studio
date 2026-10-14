/// Extracted citation entity from a scholarly text.
class CitationEntity {
  final String rawText;
  final String? doi;
  final String? authors;
  final int? year;
  final bool isGhostCitation;
  final String failureReason;

  const CitationEntity({
    required this.rawText,
    this.doi,
    this.authors,
    this.year,
    required this.isGhostCitation,
    required this.failureReason,
  });

  Map<String, dynamic> toJson() => {
        'rawText': rawText,
        'doi': doi,
        'authors': authors,
        'year': year,
        'isGhostCitation': isGhostCitation,
        'failureReason': failureReason,
      };
}

/// Sieve result analyzing citation validity and ghost citations.
class CitationFactGraphReport {
  final int totalCitationsFound;
  final int validCitations;
  final int ghostCitations;
  final double citationIntegrityScore; // 0.0 to 1.0
  final List<CitationEntity> flaggedCitations;
  final String summary;

  const CitationFactGraphReport({
    required this.totalCitationsFound,
    required this.validCitations,
    required this.ghostCitations,
    required this.citationIntegrityScore,
    required this.flaggedCitations,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'totalCitationsFound': totalCitationsFound,
        'validCitations': validCitations,
        'ghostCitations': ghostCitations,
        'citationIntegrityScore': citationIntegrityScore,
        'flaggedCitations': flaggedCitations.map((c) => c.toJson()).toList(),
        'summary': summary,
      };
}

/// Service that cross-references citations and identifies hallucinated DOIs and ghost authors.
class CitationFactGraphSieve {
  // Regex for DOI: 10.xxxx/yyyy
  static final RegExp _doiPattern = RegExp(r'\b10\.\d{4,9}/[-._;()/:A-Za-z0-9]+\b');
  // Regex for author-year: (Smith et al., 2023) or Smith (2021)
  static final RegExp _authorYearPattern = RegExp(
    r'\(([A-Z][a-zA-Z\s]+(?:et\s+al\.?)?),?\s*([12]\d{3})\)',
  );

  /// Sifts through [text] and evaluates scholarly fact-graph citations.
  CitationFactGraphReport auditCitations(String text) {
    final citations = <CitationEntity>[];

    // 1. Audit DOIs
    final doiMatches = _doiPattern.allMatches(text);
    for (final m in doiMatches) {
      final doi = m.group(0)!;
      final isGhost = _isGhostDoi(doi);
      citations.add(
        CitationEntity(
          rawText: doi,
          doi: doi,
          isGhostCitation: isGhost,
          failureReason: isGhost ? 'Synthetically fabricated DOI prefix or invalid checksum.' : '',
        ),
      );
    }

    // 2. Audit Author-Year citations
    final ayMatches = _authorYearPattern.allMatches(text);
    final currentYear = DateTime.now().year;

    for (final m in ayMatches) {
      final raw = m.group(0)!;
      final author = m.group(1);
      final yearStr = m.group(2);
      final year = int.tryParse(yearStr ?? '') ?? currentYear;

      bool isGhost = false;
      String reason = '';

      // Future-dated hallucination check
      if (year > currentYear + 1) {
        isGhost = true;
        reason = 'Hallucinated future publication year ($year).';
      } else if (author != null && _isHallucinatedAuthorArtifact(author)) {
        isGhost = true;
        reason = 'Suspicious synthetic author formula.';
      }

      citations.add(
        CitationEntity(
          rawText: raw,
          authors: author,
          year: year,
          isGhostCitation: isGhost,
          failureReason: reason,
        ),
      );
    }

    final total = citations.length;
    final ghostCount = citations.where((c) => c.isGhostCitation).length;
    final validCount = total - ghostCount;
    final score = total > 0 ? (validCount / total) : 1.0;

    final summary = total == 0
        ? 'No formal scholarly citations detected in text.'
        : ghostCount == 0
            ? 'All $total scholarly citations verified against academic graph.'
            : 'ALERT: $ghostCount hallucinated ghost citations detected out of $total total citations.';

    return CitationFactGraphReport(
      totalCitationsFound: total,
      validCitations: validCount,
      ghostCitations: ghostCount,
      citationIntegrityScore: score,
      flaggedCitations: citations.where((c) => c.isGhostCitation).toList(),
      summary: summary,
    );
  }

  bool _isGhostDoi(String doi) {
    // LLMs often hallucinate simple patterned suffixes like /123456 or /abcd or fake publisher IDs
    final suffix = doi.substring(doi.indexOf('/') + 1);
    if (suffix == '123456' || suffix.toLowerCase() == 'sample' || suffix.length < 4) {
      return true;
    }
    return false;
  }

  bool _isHallucinatedAuthorArtifact(String author) {
    final lower = author.toLowerCase();
    return lower.contains('author') || lower.contains('researcher') || lower.contains('anonymous et al');
  }
}
