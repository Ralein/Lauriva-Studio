import 'dart:convert';

import '../source_repository.dart';
import 'source_retriever.dart';

/// Optional keyed general-web search. Scholarly APIs only index papers; most
/// copied student text comes from Wikipedia, blogs, and essay mills, which
/// only a web index reaches. Both providers here are paid/quota'd, so they
/// run only when the user has stored their own key, get a small per-scan
/// budget, and return titles + snippets (never fetched full pages — that
/// would multiply requests and raise scraping/ToS issues).
abstract class KeyedWebSearchRetriever extends SourceRetriever {
  /// Resolves the stored key at call time, so adding or removing a key in
  /// settings takes effect on the next scan without rebuilding services.
  final String? Function() apiKeyProvider;

  KeyedWebSearchRetriever({
    required super.client,
    required super.name,
    required this.apiKeyProvider,
    super.timeout,
    super.minInterval,
    super.maxQueriesPerScan = 4,
    super.breaker,
  });

  String? get apiKey {
    final k = apiKeyProvider()?.trim();
    return (k == null || k.isEmpty) ? null : k;
  }

  @override
  bool get isEnabled => apiKey != null;
}

/// Brave Search Web API (https://api.search.brave.com) — storage key id
/// `brave_search`. Free tier is 1 request/second.
class BraveSearchRetriever extends KeyedWebSearchRetriever {
  static const String keyId = 'brave_search';

  BraveSearchRetriever({
    required super.client,
    required super.apiKeyProvider,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 1100),
    super.maxQueriesPerScan,
    super.breaker,
  }) : super(name: 'brave_search');

  @override
  String get id => 'brave';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final key = apiKey;
    if (key == null) return const [];
    final searchTerms = (query.exactPhrase != null && query.exactPhrase!.trim().isNotEmpty)
        ? '"${query.exactPhrase!.trim()}"'
        : query.text;
    final uri = Uri.https('api.search.brave.com', '/res/v1/web/search', {
      'q': searchTerms,
      'count': '$limit',
      'text_decorations': 'false',
      'safesearch': 'moderate',
    });
    final body = await getBody(uri, headers: {
      'Accept': 'application/json',
      'X-Subscription-Token': key,
    });
    final web = (jsonDecode(body) as Map<String, dynamic>)['web'] as Map<String, dynamic>?;
    final results = web?['results'] as List<dynamic>? ?? const [];
    final hits = <OnlineSourceHit>[];
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final title = r['title'] as String?;
      final url = r['url'] as String?;
      if (title == null || url == null) continue;
      final snippets = <String>[
        if (r['description'] is String) r['description'] as String,
        for (final s in (r['extra_snippets'] as List<dynamic>? ?? const []))
          if (s is String) s,
      ];
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(title),
        content: snippets.map(OnlineTextUtils.stripMarkup).map(_terminate).join(' '),
        url: url,
        category: SourceCategory.web,
      ));
    }
    return hits;
  }
}

/// Serper.dev Google Search API (https://serper.dev) — storage key id `serper`.
class SerperSearchRetriever extends KeyedWebSearchRetriever {
  static const String keyId = 'serper';

  SerperSearchRetriever({
    required super.client,
    required super.apiKeyProvider,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 200),
    super.maxQueriesPerScan,
    super.breaker,
  }) : super(name: 'serper');

  @override
  String get id => 'serper';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final key = apiKey;
    if (key == null) return const [];
    final searchTerms = (query.exactPhrase != null && query.exactPhrase!.trim().isNotEmpty)
        ? '"${query.exactPhrase!.trim()}"'
        : query.text;
    final response = await client.post(
      Uri.https('google.serper.dev', '/search'),
      headers: {
        'User-Agent': SourceRetriever.userAgent,
        'Content-Type': 'application/json',
        'X-API-KEY': key,
      },
      body: jsonEncode({'q': searchTerms, 'num': limit}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RetrieverHttpException(id, response.statusCode);
    }
    final organic = (jsonDecode(response.body) as Map<String, dynamic>)['organic'] as List<dynamic>? ?? const [];
    final hits = <OnlineSourceHit>[];
    for (final r in organic) {
      if (r is! Map<String, dynamic>) continue;
      final title = r['title'] as String?;
      final url = r['link'] as String?;
      if (title == null || url == null) continue;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(title),
        content: _terminate(OnlineTextUtils.stripMarkup(r['snippet'] as String?)),
        url: url,
        category: SourceCategory.web,
      ));
    }
    return hits;
  }
}

/// Wikipedia Search API (https://www.mediawiki.org/wiki/API:Search) — keyless,
/// covers >60M encyclopedia articles across all domains. Catches common student
/// copy-paste and foundational definitions without requiring any API keys.
class WikipediaRetriever extends SourceRetriever {
  WikipediaRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 300),
    super.maxQueriesPerScan = 4,
    super.breaker,
  }) : super(name: 'wikipedia');

  @override
  String get id => 'wikipedia';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    // Quoted phrase first (verbatim copying); the unquoted query below is the fallback.
    final searchTerms = (query.exactPhrase != null && query.exactPhrase!.trim().isNotEmpty)
        ? '"${query.exactPhrase!.trim()}"'
        : query.text;

    // 1. Primary: MediaWiki generator=search with prop=extracts (plain text article introductions)
    var uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': searchTerms,
      'gsrlimit': '$limit',
      'prop': 'extracts',
      'exintro': '1',
      'explaintext': '1',
      'exlimit': '$limit',
      'format': 'json',
    });
    var body = await getBody(uri);
    var data = jsonDecode(body) as Map<String, dynamic>;
    var queryObj = data['query'] as Map<String, dynamic>?;
    var pages = queryObj?['pages'] as Map<String, dynamic>?;

    final hits = <OnlineSourceHit>[];
    void extractHits(Map<String, dynamic>? pageMap) {
      if (pageMap == null || pageMap.isEmpty) return;
      for (final p in pageMap.values) {
        if (p is! Map<String, dynamic>) continue;
        final title = p['title'] as String?;
        final extract = p['extract'] as String?;
        if (title == null || title.trim().isEmpty) continue;
        final content = (extract != null && extract.trim().isNotEmpty)
            ? OnlineTextUtils.stripMarkup(extract)
            : '';
        if (content.length < 20) continue;
        final slug = Uri.encodeComponent(title.replaceAll(' ', '_'));
        hits.add(OnlineSourceHit(
          retrieverId: id,
          title: 'Wikipedia: $title',
          content: _terminate(content),
          url: 'https://en.wikipedia.org/wiki/$slug',
          category: SourceCategory.web,
        ));
      }
    }

    extractHits(pages);

    // 2. Fallback to unquoted query.text if exact phrase yielded 0 hits
    if (hits.isEmpty && searchTerms != query.text) {
      uri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': query.text,
        'gsrlimit': '$limit',
        'prop': 'extracts',
        'exintro': '1',
        'explaintext': '1',
        'exlimit': '$limit',
        'format': 'json',
      });
      body = await getBody(uri);
      data = jsonDecode(body) as Map<String, dynamic>;
      queryObj = data['query'] as Map<String, dynamic>?;
      pages = queryObj?['pages'] as Map<String, dynamic>?;
      extractHits(pages);
    }

    // 3. Fallback to snippet search only if generator=search returned 0 hits
    if (hits.isEmpty) {
      final snippetUri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': query.text,
        'utf8': '1',
        'format': 'json',
        'srlimit': '$limit',
        'srprop': 'snippet',
      });
      final snipBody = await getBody(snippetUri);
      final snipData = jsonDecode(snipBody) as Map<String, dynamic>;
      final snipResults = (snipData['query'] as Map<String, dynamic>?)?['search'] as List<dynamic>? ?? const [];
      for (final r in snipResults) {
        if (r is! Map<String, dynamic>) continue;
        final title = r['title'] as String?;
        final snippet = r['snippet'] as String?;
        if (title == null || title.trim().isEmpty) continue;
        final cleanSnippet = OnlineTextUtils.stripMarkup(snippet);
        final slug = Uri.encodeComponent(title.replaceAll(' ', '_'));
        hits.add(OnlineSourceHit(
          retrieverId: id,
          title: 'Wikipedia: $title',
          content: _terminate(cleanSnippet),
          url: 'https://en.wikipedia.org/wiki/$slug',
          category: SourceCategory.web,
        ));
      }
    }

    return hits;
  }
}

/// DuckDuckGo Instant Answer API (https://duckduckgo.com/api) — keyless, zero-config,
/// provides authoritative encyclopedia definitions and summaries for general topics.
class DuckDuckGoInstantRetriever extends SourceRetriever {
  DuckDuckGoInstantRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 150),
    super.maxQueriesPerScan = 4,
    super.breaker,
  }) : super(name: 'duckduckgo');

  @override
  String get id => 'duckduckgo';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final uri = Uri.https('api.duckduckgo.com', '/', {
      'q': query.text,
      'format': 'json',
      'no_html': '1',
      'skip_disambig': '1',
    });
    final body = await getBody(uri);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final hits = <OnlineSourceHit>[];

    final heading = data['Heading'] as String? ?? '';
    final abstractText = data['Abstract'] as String? ?? data['AbstractText'] as String? ?? '';
    final url = data['AbstractURL'] as String? ?? '';

    if (abstractText.trim().isNotEmpty) {
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: heading.isNotEmpty ? heading : 'DuckDuckGo Knowledge: ${query.text}',
        content: _terminate(OnlineTextUtils.stripMarkup(abstractText)),
        url: url.isNotEmpty ? url : 'https://duckduckgo.com/?q=${Uri.encodeComponent(query.text)}',
        category: SourceCategory.web,
      ));
    }

    final related = data['RelatedTopics'] as List<dynamic>? ?? const [];
    for (final item in related) {
      if (hits.length >= limit) break;
      if (item is! Map<String, dynamic>) continue;
      final text = item['Text'] as String?;
      final firstUrl = item['FirstURL'] as String?;
      if (text != null && text.trim().length > 30) {
        hits.add(OnlineSourceHit(
          retrieverId: id,
          title: text.length > 50 ? '${text.substring(0, 47)}...' : text,
          content: _terminate(OnlineTextUtils.stripMarkup(text)),
          url: firstUrl,
          category: SourceCategory.web,
        ));
      }
    }

    return hits;
  }
}

/// Keyless Wikinews search via MediaWiki API against `en.wikinews.org`.
/// Catches news excerpts and current-event copies without API keys.
class WikinewsRetriever extends SourceRetriever {
  WikinewsRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 300),
    super.maxQueriesPerScan = 4,
    super.breaker,
  }) : super(name: 'wikinews');

  @override
  String get id => 'wikinews';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final searchTerms = (query.exactPhrase != null && query.exactPhrase!.trim().isNotEmpty)
        ? '"${query.exactPhrase!.trim()}"'
        : query.text;

    // 1. Primary: MediaWiki generator=search with prop=extracts (plain text article introductions)
    var uri = Uri.https('en.wikinews.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': searchTerms,
      'gsrlimit': '$limit',
      'prop': 'extracts',
      'exintro': '1',
      'explaintext': '1',
      'exlimit': '$limit',
      'format': 'json',
    });
    var body = await getBody(uri);
    var data = jsonDecode(body) as Map<String, dynamic>;
    var queryObj = data['query'] as Map<String, dynamic>?;
    var pages = queryObj?['pages'] as Map<String, dynamic>?;

    final hits = <OnlineSourceHit>[];
    void extractHits(Map<String, dynamic>? pageMap) {
      if (pageMap == null || pageMap.isEmpty) return;
      for (final p in pageMap.values) {
        if (p is! Map<String, dynamic>) continue;
        final title = p['title'] as String?;
        final extract = p['extract'] as String?;
        if (title == null || title.trim().isEmpty) continue;
        final content = (extract != null && extract.trim().isNotEmpty)
            ? OnlineTextUtils.stripMarkup(extract)
            : '';
        if (content.length < 20) continue;
        final slug = Uri.encodeComponent(title.replaceAll(' ', '_'));
        hits.add(OnlineSourceHit(
          retrieverId: id,
          title: 'Wikinews: $title',
          content: _terminate(content),
          url: 'https://en.wikinews.org/wiki/$slug',
          category: SourceCategory.web,
        ));
      }
    }

    extractHits(pages);

    // 2. Fallback to unquoted query.text if exact phrase yielded 0 hits
    if (hits.isEmpty && searchTerms != query.text) {
      uri = Uri.https('en.wikinews.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': query.text,
        'gsrlimit': '$limit',
        'prop': 'extracts',
        'exintro': '1',
        'explaintext': '1',
        'exlimit': '$limit',
        'format': 'json',
      });
      body = await getBody(uri);
      data = jsonDecode(body) as Map<String, dynamic>;
      queryObj = data['query'] as Map<String, dynamic>?;
      pages = queryObj?['pages'] as Map<String, dynamic>?;
      extractHits(pages);
    }

    // 3. Fallback to snippet search only if generator=search returned 0 hits
    if (hits.isEmpty) {
      final snippetUri = Uri.https('en.wikinews.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': query.text,
        'utf8': '1',
        'format': 'json',
        'srlimit': '$limit',
        'srprop': 'snippet',
      });
      final snipBody = await getBody(snippetUri);
      final snipData = jsonDecode(snipBody) as Map<String, dynamic>;
      final snipResults = (snipData['query'] as Map<String, dynamic>?)?['search'] as List<dynamic>? ?? const [];
      for (final r in snipResults) {
        if (r is! Map<String, dynamic>) continue;
        final title = r['title'] as String?;
        final snippet = r['snippet'] as String?;
        if (title == null || title.trim().isEmpty) continue;
        final cleanSnippet = OnlineTextUtils.stripMarkup(snippet);
        final slug = Uri.encodeComponent(title.replaceAll(' ', '_'));
        hits.add(OnlineSourceHit(
          retrieverId: id,
          title: 'Wikinews: $title',
          content: _terminate(cleanSnippet),
          url: 'https://en.wikinews.org/wiki/$slug',
          category: SourceCategory.web,
        ));
      }
    }

    return hits;
  }
}

/// Ends each snippet with a period so adjacent snippets never merge into one
/// pseudo-sentence during paraphrase alignment.
String _terminate(String s) {
  final t = s.trim();
  if (t.isEmpty || RegExp(r'[.!?]$').hasMatch(t)) return t;
  return '$t.';
}
