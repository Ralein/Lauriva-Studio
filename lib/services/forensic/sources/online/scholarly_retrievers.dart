import 'dart:convert';

import 'source_retriever.dart';

/// OpenAlex works search (https://docs.openalex.org) — keyless, ~250M works,
/// generous rate limits. The broadest free scholarly index, so it gets the
/// largest query budget.
///
/// Abstracts are delivered as `abstract_inverted_index` (word → positions)
/// for licensing reasons; [reconstructAbstract] rebuilds the plain text.
class OpenAlexRetriever extends SourceRetriever {
  final String? Function()? apiKeyProvider;

  OpenAlexRetriever({
    required super.client,
    this.apiKeyProvider,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 120),
    super.maxQueriesPerScan = 8,
    super.breaker,
  }) : super(name: 'openalex');

  @override
  String get id => 'openalex';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final key = apiKeyProvider?.call();
    final uri = Uri.https('api.openalex.org', '/works', {
      'search': query.text,
      'per-page': '$limit',
      'select': 'id,doi,display_name,publication_year,authorships,abstract_inverted_index,primary_location',
      'mailto': SourceRetriever.contactEmail,
      if (key != null && key.isNotEmpty) 'api_key': key,
    });
    final body = await getBody(uri);
    final results = (jsonDecode(body) as Map<String, dynamic>)['results'] as List<dynamic>? ?? const [];
    final hits = <OnlineSourceHit>[];
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final abstract = reconstructAbstract(r['abstract_inverted_index']);
      final title = (r['display_name'] ?? r['title']) as String?;
      if (title == null || title.trim().isEmpty) continue;
      final authors = <String>[
        for (final a in (r['authorships'] as List<dynamic>? ?? const []))
          if (a is Map<String, dynamic> && a['author'] is Map<String, dynamic>)
            ((a['author'] as Map<String, dynamic>)['display_name'] as String? ?? '').trim(),
      ]..removeWhere((a) => a.isEmpty);
      final location = r['primary_location'] as Map<String, dynamic>?;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(title),
        content: abstract,
        authors: authors,
        year: (r['publication_year'] as num?)?.toInt(),
        doi: r['doi'] as String?,
        url: location?['landing_page_url'] as String? ?? r['id'] as String?,
      ));
    }
    return hits;
  }

  /// Rebuilds abstract text from OpenAlex's `{word: [positions]}` index.
  static String reconstructAbstract(Object? invertedIndex) {
    if (invertedIndex is! Map) return '';
    final byPosition = <int, String>{};
    invertedIndex.forEach((word, positions) {
      if (word is! String || positions is! List) return;
      for (final p in positions) {
        if (p is num) byPosition[p.toInt()] = word;
      }
    });
    if (byPosition.isEmpty) return '';
    final ordered = byPosition.keys.toList()..sort();
    return OnlineTextUtils.stripMarkup(ordered.map((p) => byPosition[p]).join(' '));
  }
}

/// Crossref REST works search (https://api.crossref.org) — keyless, the DOI
/// registry for most journals. Only a minority of records carry an
/// abstract (JATS XML), so results are filtered to `has-abstract:true`;
/// title-only records cannot be aligned against prose.
class CrossrefRetriever extends SourceRetriever {
  CrossrefRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 250),
    super.maxQueriesPerScan = 6,
    super.breaker,
  }) : super(name: 'crossref');

  @override
  String get id => 'crossref';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final uri = Uri.https('api.crossref.org', '/works', {
      'query': query.text,
      'rows': '$limit',
      'filter': 'has-abstract:true',
      'select': 'DOI,title,author,abstract,URL,published,issued',
      'mailto': SourceRetriever.contactEmail,
    });
    final body = await getBody(uri);
    final message = (jsonDecode(body) as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    final items = message?['items'] as List<dynamic>? ?? const [];
    final hits = <OnlineSourceHit>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final titles = item['title'] as List<dynamic>? ?? const [];
      if (titles.isEmpty || titles.first is! String) continue;
      final authors = <String>[
        for (final a in (item['author'] as List<dynamic>? ?? const []))
          if (a is Map<String, dynamic>)
            [a['given'] as String? ?? '', a['family'] as String? ?? a['name'] as String? ?? '']
                .where((p) => p.isNotEmpty)
                .join(' '),
      ]..removeWhere((a) => a.isEmpty);
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(titles.first as String),
        // Crossref abstracts often open with a literal "Abstract" heading.
        content: OnlineTextUtils.stripMarkup(item['abstract'] as String?).replaceFirst(RegExp(r'^Abstract[:.]?\s+', caseSensitive: false), ''),
        authors: authors,
        year: _year(item['published']) ?? _year(item['issued']),
        doi: item['DOI'] as String?,
        url: item['URL'] as String?,
      ));
    }
    return hits;
  }

  static int? _year(Object? dateObj) {
    if (dateObj is! Map) return null;
    final parts = dateObj['date-parts'];
    if (parts is List && parts.isNotEmpty && parts.first is List && (parts.first as List).isNotEmpty) {
      final y = (parts.first as List).first;
      if (y is num) return y.toInt();
    }
    return null;
  }
}

/// Semantic Scholar Graph API paper search
/// (https://api.semanticscholar.org/api-docs/graph). Keyless requests share
/// a global, frequently exhausted pool (HTTP 429), so the budget is small and
/// requests are spaced at 1 rps; an optional key (`semantic_scholar`) lifts
/// that. Strong coverage of CS / biomedical abstracts.
class SemanticScholarRetriever extends SourceRetriever {
  final String? Function()? apiKeyProvider;

  SemanticScholarRetriever({
    required super.client,
    this.apiKeyProvider,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 1100),
    super.maxQueriesPerScan = 3,
    super.breaker,
  }) : super(name: 'semantic_scholar');

  @override
  String get id => 'semantic_scholar';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final key = apiKeyProvider?.call();
    final uri = Uri.https('api.semanticscholar.org', '/graph/v1/paper/search', {
      'query': query.text,
      'limit': '$limit',
      'fields': 'title,abstract,authors,year,url,externalIds',
    });
    final body = await getBody(uri, headers: {
      if (key != null && key.isNotEmpty) 'x-api-key': key,
    });
    final data = (jsonDecode(body) as Map<String, dynamic>)['data'] as List<dynamic>? ?? const [];
    final hits = <OnlineSourceHit>[];
    for (final p in data) {
      if (p is! Map<String, dynamic>) continue;
      final title = p['title'] as String?;
      if (title == null || title.trim().isEmpty) continue;
      final ext = p['externalIds'] as Map<String, dynamic>?;
      final arxivId = ext?['ArXiv'] as String?;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(title),
        content: OnlineTextUtils.stripMarkup(p['abstract'] as String?),
        authors: [
          for (final a in (p['authors'] as List<dynamic>? ?? const []))
            if (a is Map<String, dynamic> && a['name'] is String) (a['name'] as String).trim(),
        ],
        year: (p['year'] as num?)?.toInt(),
        doi: ext?['DOI'] as String?,
        url: arxivId != null ? 'https://arxiv.org/abs/$arxivId' : p['url'] as String?,
      ));
    }
    return hits;
  }
}

/// arXiv API (https://info.arxiv.org/help/api) — keyless Atom feed of
/// preprints, whose abstracts are the most commonly copied text in student
/// CS/physics/maths work.
///
/// Queries use [SourceQuery.keywords] as an AND over the abstract field:
/// arXiv ORs bare space-separated terms, so free text returns near-random
/// papers, while five rare words ANDed together usually isolate the source.
/// arXiv asks clients for one request every 3 seconds, hence the tiny budget.
///
/// The feed is parsed with regular expressions rather than an XML package:
/// the Atom shape is flat and stable, and it avoids a new dependency.
class ArxivRetriever extends SourceRetriever {
  ArxivRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(seconds: 3),
    super.maxQueriesPerScan = 2,
    super.breaker,
  }) : super(name: 'arxiv');

  @override
  String get id => 'arxiv';

  static final RegExp _entry = RegExp(r'<entry>([\s\S]*?)</entry>');

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final terms = query.keywords
        .map((k) => k.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''))
        .where((k) => k.length >= 3)
        .take(5)
        .toList();
    if (terms.length < 2) return const [];
    final uri = Uri.https('export.arxiv.org', '/api/query', {
      'search_query': terms.map((t) => 'abs:$t').join(' AND '),
      'max_results': '$limit',
    });
    return parseFeed(await getBody(uri), retrieverId: id);
  }

  /// Parses an arXiv Atom feed into hits. Public for tests.
  static List<OnlineSourceHit> parseFeed(String xml, {String retrieverId = 'arxiv'}) {
    final hits = <OnlineSourceHit>[];
    for (final m in _entry.allMatches(xml)) {
      final e = m.group(1)!;
      final title = OnlineTextUtils.stripMarkup(_tagText(e, 'title'));
      if (title.isEmpty) continue;
      final idUrl = _tagText(e, 'id').trim();
      final published = _tagText(e, 'published');
      final doi = _tagText(e, 'arxiv:doi').trim();
      hits.add(OnlineSourceHit(
        retrieverId: retrieverId,
        title: title,
        content: OnlineTextUtils.stripMarkup(_tagText(e, 'summary')),
        authors: [
          for (final a in RegExp(r'<author>\s*<name>([\s\S]*?)</name>').allMatches(e))
            OnlineTextUtils.decodeEntities(a.group(1)!.trim()),
        ],
        year: published.length >= 4 ? int.tryParse(published.substring(0, 4)) : null,
        doi: doi.isEmpty ? null : doi,
        url: idUrl.isEmpty ? null : idUrl.replaceFirst('http://', 'https://'),
      ));
    }
    return hits;
  }

  static String _tagText(String xml, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>').firstMatch(xml);
    return m?.group(1) ?? '';
  }
}

/// DOAJ (Directory of Open Access Journals) REST API (https://doaj.org/api/v2/docs)
/// Keyless, covers >10 million peer-reviewed articles from open-access journals worldwide.
class DoajRetriever extends SourceRetriever {
  DoajRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 300),
    super.maxQueriesPerScan = 4,
    super.breaker,
  }) : super(name: 'doaj');

  @override
  String get id => 'doaj';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final uri = Uri.https('doaj.org', '/api/v2/search/articles/${Uri.encodeComponent(query.text)}', {
      'pageSize': '$limit',
    });
    final body = await getBody(uri);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? const [];
    final hits = <OnlineSourceHit>[];
    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final bib = item['bibjson'] as Map<String, dynamic>?;
      if (bib == null) continue;
      final title = bib['title'] as String?;
      if (title == null || title.trim().isEmpty) continue;
      final abstract = bib['abstract'] as String?;
      final yearStr = bib['year']?.toString();
      final year = yearStr != null ? int.tryParse(yearStr) : null;
      final authors = <String>[
        for (final a in (bib['author'] as List<dynamic>? ?? const []))
          if (a is Map<String, dynamic> && a['name'] is String)
            (a['name'] as String).trim(),
      ]..removeWhere((a) => a.isEmpty);

      String? doi;
      for (final idObj in (bib['identifier'] as List<dynamic>? ?? const [])) {
        if (idObj is Map<String, dynamic> && idObj['type'] == 'doi') {
          doi = idObj['id'] as String?;
          break;
        }
      }

      String? url;
      for (final link in (bib['link'] as List<dynamic>? ?? const [])) {
        if (link is Map<String, dynamic> && link['url'] is String) {
          url = link['url'] as String;
          break;
        }
      }

      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(title),
        content: OnlineTextUtils.stripMarkup(abstract),
        authors: authors,
        year: year,
        doi: doi,
        url: doi != null ? 'https://doi.org/$doi' : url,
      ));
    }
    return hits;
  }
}

/// NCBI PubMed E-utilities API (https://www.ncbi.nlm.nih.gov/books/NBK25500/)
/// Keyless, official US National Library of Medicine search covering >36 million
/// biomedical and life-sciences citations.
class NcbiPubMedRetriever extends SourceRetriever {
  NcbiPubMedRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 350),
    super.maxQueriesPerScan = 3,
    super.breaker,
  }) : super(name: 'ncbi_pubmed');

  @override
  String get id => 'ncbi_pubmed';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final searchUri = Uri.https('eutils.ncbi.nlm.nih.gov', '/entrez/eutils/esearch.fcgi', {
      'db': 'pubmed',
      'term': query.text,
      'retmode': 'json',
      'retmax': '$limit',
      'email': SourceRetriever.contactEmail,
    });
    final searchBody = await getBody(searchUri);
    final searchData = jsonDecode(searchBody) as Map<String, dynamic>;
    final esearch = searchData['esearchresult'] as Map<String, dynamic>?;
    final idList = (esearch?['idlist'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    if (idList.isEmpty) return const [];

    final summaryUri = Uri.https('eutils.ncbi.nlm.nih.gov', '/entrez/eutils/esummary.fcgi', {
      'db': 'pubmed',
      'id': idList.join(','),
      'retmode': 'json',
      'email': SourceRetriever.contactEmail,
    });
    final summaryBody = await getBody(summaryUri);
    final summaryData = jsonDecode(summaryBody) as Map<String, dynamic>;
    final result = summaryData['result'] as Map<String, dynamic>? ?? const {};

    final hits = <OnlineSourceHit>[];
    for (final pmid in idList) {
      final doc = result[pmid] as Map<String, dynamic>?;
      if (doc == null) continue;
      final title = doc['title'] as String?;
      if (title == null || title.trim().isEmpty) continue;
      final authors = <String>[
        for (final a in (doc['authors'] as List<dynamic>? ?? const []))
          if (a is Map<String, dynamic> && a['name'] is String)
            (a['name'] as String).trim(),
      ]..removeWhere((a) => a.isEmpty);

      final pubDate = doc['pubdate'] as String? ?? '';
      final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(pubDate);
      final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;

      String? doi;
      for (final idObj in (doc['articleids'] as List<dynamic>? ?? const [])) {
        if (idObj is Map<String, dynamic> && idObj['idtype'] == 'doi') {
          doi = idObj['value'] as String?;
          break;
        }
      }

      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(title),
        content: OnlineTextUtils.stripMarkup(title),
        authors: authors,
        year: year,
        doi: doi,
        url: doi != null ? 'https://doi.org/$doi' : 'https://pubmed.ncbi.nlm.nih.gov/$pmid/',
      ));
    }
    return hits;
  }
}

