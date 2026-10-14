import 'dart:convert';
import 'package:http/http.dart' as http;

/// Citation style enumeration.
enum CitationStyle { apa7, mla9, chicago, ieee, harvard }

/// Extension for human-readable label.
extension CitationStyleLabel on CitationStyle {
  String get label {
    switch (this) {
      case CitationStyle.apa7:    return 'APA 7th';
      case CitationStyle.mla9:    return 'MLA 9th';
      case CitationStyle.chicago: return 'Chicago 17th';
      case CitationStyle.ieee:    return 'IEEE';
      case CitationStyle.harvard: return 'Harvard';
    }
  }
}

/// Structured metadata about an academic source.
class SourceMetadata {
  final String title;
  final List<String> authors;
  final int? year;
  final String? publisherOrJournal;
  final String? url;
  final String? doi;
  final int? volume;
  final int? issue;
  final String? pages;
  final String? edition;
  final String? city;

  const SourceMetadata({
    required this.title,
    this.authors = const [],
    this.year,
    this.publisherOrJournal,
    this.url,
    this.doi,
    this.volume,
    this.issue,
    this.pages,
    this.edition,
    this.city,
  });

  factory SourceMetadata.fromCrossRefJson(Map<String, dynamic> json) {
    final titleList = json['title'] as List<dynamic>? ?? [];
    final title = titleList.isNotEmpty ? titleList.first as String : 'Unknown Title';

    final authorList = json['author'] as List<dynamic>? ?? [];
    final authors = authorList.map<String>((a) {
      final given  = (a as Map<String, dynamic>)['given']  as String? ?? '';
      final family = a['family'] as String? ?? '';
      return '$family${given.isNotEmpty ? ", $given" : ""}';
    }).toList();

    final publishedDate = json['published-print'] ?? json['published-online'];
    final rawParts = publishedDate?['date-parts'];
    final datePartsList = rawParts as List<dynamic>?;
    final innerParts = (datePartsList?.isNotEmpty == true) ? datePartsList!.first as List<dynamic>? : null;
    final year = (innerParts?.isNotEmpty == true) ? innerParts!.first as int? : null;

    final containerTitle =
        (json['container-title'] as List<dynamic>?)?.isNotEmpty == true
            ? (json['container-title'] as List<dynamic>).first as String?
            : null;

    return SourceMetadata(
      title: title,
      authors: authors,
      year: year,
      publisherOrJournal: containerTitle,
      url: json['URL'] as String?,
      doi: json['DOI'] as String?,
      volume: int.tryParse(json['volume']?.toString() ?? ''),
      issue: int.tryParse(json['issue']?.toString() ?? ''),
      pages: json['page'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'authors': authors,
        'year': year,
        'publisherOrJournal': publisherOrJournal,
        'url': url,
        'doi': doi,
        'volume': volume,
        'issue': issue,
        'pages': pages,
        'edition': edition,
        'city': city,
      };

  factory SourceMetadata.fromJson(Map<String, dynamic> json) => SourceMetadata(
        title: json['title'] as String? ?? '',
        authors: (json['authors'] as List<dynamic>?)?.cast<String>() ?? [],
        year: json['year'] as int?,
        publisherOrJournal: json['publisherOrJournal'] as String?,
        url: json['url'] as String?,
        doi: json['doi'] as String?,
        volume: json['volume'] as int?,
        issue: json['issue'] as int?,
        pages: json['pages'] as String?,
        edition: json['edition'] as String?,
        city: json['city'] as String?,
      );
}

/// Result from a live academic API query.
class CitationSearchResult {
  final SourceMetadata metadata;
  final double relevanceScore;
  const CitationSearchResult({required this.metadata, required this.relevanceScore});
}

/// Core citation formatter: APA 7, MLA 9, Chicago 17, IEEE, Harvard.
/// Also exposes live CrossRef & Semantic Scholar query methods.
class CitationGeneratorService {
  static const _crossrefBase        = 'https://api.crossref.org/works';
  static const _semanticScholarBase = 'https://api.semanticscholar.org/graph/v1';

  String formatCitation(SourceMetadata source, CitationStyle style) {
    switch (style) {
      case CitationStyle.apa7:    return _formatApa7(source);
      case CitationStyle.mla9:    return _formatMla9(source);
      case CitationStyle.chicago: return _formatChicago(source);
      case CitationStyle.ieee:    return _formatIeee(source);
      case CitationStyle.harvard: return _formatHarvard(source);
    }
  }

  Map<CitationStyle, String> formatAll(SourceMetadata source) => {
        for (final s in CitationStyle.values) s: formatCitation(source, s),
      };

  // ── APA 7th ─────────────────────────────────────────────────────────────────
  String _formatApa7(SourceMetadata s) {
    final authorStr = _apaAuthors(s.authors);
    final year = s.year != null ? '(${s.year})' : '(n.d.)';
    final title = s.publisherOrJournal != null ? s.title : '*${s.title}*';

    final buf = StringBuffer('$authorStr $year. $title.');
    if (s.publisherOrJournal != null) {
      buf.write(' *${s.publisherOrJournal}*');
      if (s.volume != null) {
        buf.write(', *${s.volume}*');
        if (s.issue != null) buf.write('(${s.issue})');
      }
      if (s.pages != null) buf.write(', ${s.pages}');
      buf.write('.');
    }
    if (s.doi != null) {
      buf.write(' https://doi.org/${s.doi}');
    } else if (s.url != null) {
      buf.write(' ${s.url}');
    }
    return buf.toString().trim();
  }

  String _apaAuthors(List<String> authors) {
    if (authors.isEmpty) return 'Unknown Author';
    if (authors.length == 1) return _apaOne(authors[0]);
    if (authors.length <= 20) {
      final rest = authors.sublist(0, authors.length - 1).map(_apaOne).join(', ');
      return '$rest, & ${_apaOne(authors.last)}';
    }
    final first19 = authors.sublist(0, 19).map(_apaOne).join(', ');
    return '$first19, . . . ${_apaOne(authors.last)}';
  }

  String _apaOne(String author) {
    final parts = author.split(', ');
    if (parts.length < 2) return author;
    final initials = parts[1].split(' ').map((n) => n.isNotEmpty ? '${n[0]}.' : '').join(' ');
    return '${parts[0]}, $initials';
  }

  // ── MLA 9th ─────────────────────────────────────────────────────────────────
  String _formatMla9(SourceMetadata s) {
    final authorStr = _mlaAuthors(s.authors);
    final title = s.publisherOrJournal != null ? '"${s.title}."' : '*${s.title}*.';
    final buf = StringBuffer('$authorStr $title');
    if (s.publisherOrJournal != null) {
      buf.write(' *${s.publisherOrJournal}*,');
      if (s.volume != null) buf.write(' vol. ${s.volume},');
      if (s.issue != null)  buf.write(' no. ${s.issue},');
      if (s.year != null)   buf.write(' ${s.year},');
      if (s.pages != null)  buf.write(' pp. ${s.pages}.');
    } else {
      if (s.year != null) buf.write(' ${s.year}.');
    }
    if (s.doi != null) {
      buf.write(' doi:${s.doi}.');
    } else if (s.url != null) {
      buf.write(' ${s.url}.');
    }
    return buf.toString().trim();
  }

  String _mlaAuthors(List<String> authors) {
    if (authors.isEmpty) return 'Unknown Author.';
    if (authors.length == 1) return '${authors[0]}.';
    if (authors.length == 2) return '${authors[0]}, and ${authors[1]}.';
    return '${authors[0]}, et al.';
  }

  // ── Chicago 17 (Author-Date) ─────────────────────────────────────────────────
  String _formatChicago(SourceMetadata s) {
    final authorStr = _chicagoAuthors(s.authors);
    final year = s.year ?? 'n.d.';
    final buf = StringBuffer('$authorStr $year. "${s.title}."');
    if (s.publisherOrJournal != null) {
      buf.write(' *${s.publisherOrJournal}*');
      if (s.volume != null) {
        buf.write(' ${s.volume}');
        if (s.issue != null) buf.write(' (${s.issue})');
      }
      if (s.pages != null) buf.write(': ${s.pages}');
      buf.write('.');
    }
    if (s.doi != null) {
      buf.write(' https://doi.org/${s.doi}.');
    } else if (s.url != null) {
      buf.write(' ${s.url}.');
    }
    return buf.toString().trim();
  }

  String _chicagoAuthors(List<String> authors) {
    if (authors.isEmpty) return 'Unknown Author.';
    if (authors.length == 1) return '${authors[0]}.';
    if (authors.length <= 3) return '${authors.join(', and ')}.';
    return '${authors[0]}, et al.';
  }

  // ── IEEE ─────────────────────────────────────────────────────────────────────
  String _formatIeee(SourceMetadata s) {
    final authorsFormatted = s.authors.map((a) {
      final parts = a.split(', ');
      if (parts.length < 2) return a;
      final initials = parts[1].split(' ').map((n) => n.isNotEmpty ? '${n[0]}.' : '').join(' ');
      return '$initials ${parts[0]}';
    }).join(', ');

    final buf = StringBuffer('$authorsFormatted, "${s.title},"');
    if (s.publisherOrJournal != null) {
      buf.write(' *${s.publisherOrJournal}*,');
      if (s.volume != null) buf.write(' vol. ${s.volume},');
      if (s.issue != null)  buf.write(' no. ${s.issue},');
      if (s.pages != null)  buf.write(' pp. ${s.pages},');
    }
    if (s.year != null) buf.write(' ${s.year}.');
    if (s.doi != null)  buf.write(' doi: ${s.doi}.');
    return buf.toString().trim();
  }

  // ── Harvard ──────────────────────────────────────────────────────────────────
  String _formatHarvard(SourceMetadata s) {
    final authorStr = _harvardAuthors(s.authors);
    final year = s.year != null ? '(${s.year})' : '(n.d.)';
    final buf = StringBuffer('$authorStr $year \'${s.title}\',');
    if (s.publisherOrJournal != null) {
      buf.write(' *${s.publisherOrJournal}*,');
      if (s.volume != null) buf.write(' vol. ${s.volume},');
      if (s.issue != null)  buf.write(' no. ${s.issue},');
      if (s.pages != null)  buf.write(' pp. ${s.pages}.');
    }
    if (s.doi != null) {
      buf.write(' Available at: https://doi.org/${s.doi}');
    } else if (s.url != null) {
      buf.write(' Available at: ${s.url}');
    }
    return buf.toString().trim();
  }

  String _harvardAuthors(List<String> authors) {
    if (authors.isEmpty) return 'Unknown Author';
    if (authors.length <= 3) return authors.join(', ');
    return '${authors[0]} et al.';
  }

  // ── Live CrossRef Query ───────────────────────────────────────────────────────
  Future<List<CitationSearchResult>> queryCrossRef(String query, {int limit = 5}) async {
    try {
      final uri = Uri.parse(
        '$_crossrefBase?query.bibliographic=${Uri.encodeQueryComponent(query)}'
        '&rows=$limit'
        '&select=title,author,published-print,published-online,DOI,URL,container-title,volume,issue,page',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Lauriva/3.5 (mailto:support@lauriva.app)'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data  = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['message']?['items'] as List<dynamic>?) ?? [];
      return items.map((item) {
        final meta  = SourceMetadata.fromCrossRefJson(item as Map<String, dynamic>);
        final score = (item['score'] as num?)?.toDouble() ?? 0.0;
        return CitationSearchResult(metadata: meta, relevanceScore: score);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<CitationSearchResult>> querySemanticScholar(String query, {int limit = 5}) async {
    try {
      final uri = Uri.parse(
        '$_semanticScholarBase/paper/search'
        '?query=${Uri.encodeQueryComponent(query)}'
        '&limit=$limit'
        '&fields=title,authors,year,venue,externalIds,openAccessPdf',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'Lauriva/3.5'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data  = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['data'] as List<dynamic>?) ?? [];
      return items.map((item) {
        final m = item as Map<String, dynamic>;
        final authorNames = ((m['authors'] as List<dynamic>?) ?? [])
            .map<String>((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .toList();
        final doi = ((m['externalIds'] as Map<String, dynamic>?)?['DOI']) as String?;
        final url = ((m['openAccessPdf'] as Map<String, dynamic>?)?['url']) as String?;
        return CitationSearchResult(
          metadata: SourceMetadata(
            title: m['title'] as String? ?? 'Unknown',
            authors: authorNames,
            year: m['year'] as int?,
            publisherOrJournal: m['venue'] as String?,
            doi: doi,
            url: url,
          ),
          relevanceScore: 1.0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
