import 'dart:convert';

import '../source_repository.dart';
import 'source_retriever.dart';

/// Keyless general-web search for the online tier.
///
/// Scholarly APIs only index papers; most copied student text comes from
/// blogs, study sites and essay mills. No free official web-search API exists,
/// so [BingWebRetriever] and [BraveWebRetriever] read the public result pages
/// a browser would get, from the user's own device, a few queries per scan.
/// They return titles + snippets only (never fetched pages) and are
/// best-effort: a CAPTCHA, a markup change or an outage surfaces as a failed
/// outcome, which the retriever's circuit breaker turns into a quiet skip.
/// The offline corpus and the other retrievers are never affected.
abstract class HtmlWebSearchRetriever extends SourceRetriever {
  HtmlWebSearchRetriever({
    required super.client,
    required super.name,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 900),
    super.maxQueriesPerScan = 3,
    super.breaker,
  });

  /// Result pages are served to a mobile browser UA; the default app UA is
  /// served a reduced or blocked page by some engines.
  static const String browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  static const int maxPageChars = 600000;

  /// Quoted verbatim phrase when available: the strongest copy signal.
  /// If a site filter is specified, it is appended (e.g. `site:openstax.org`).
  String searchTerms(SourceQuery query) {
    final phrase = query.exactPhrase?.trim();
    final base = (phrase != null && phrase.isNotEmpty) ? '"$phrase"' : query.text;
    if (query.siteFilter != null && query.siteFilter!.trim().isNotEmpty) {
      return '$base site:${query.siteFilter!.trim()}';
    }
    return base;
  }

  Uri buildUri(String terms);

  /// Parses a result page into hits. Visible for tests.
  List<OnlineSourceHit> parse(String html, {int limit = 5});

  /// True when [html] is a genuine "no results" page rather than a challenge.
  bool isNoResultsPage(String html);

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final body = await getBody(buildUri(searchTerms(query)), headers: {
      'User-Agent': browserUserAgent,
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-US,en;q=0.9',
    });
    // Results sit at the top of the page; a cap keeps a hostile or garbage body from stalling the UI isolate.
    final page = body.length > maxPageChars ? body.substring(0, maxPageChars) : body;
    final hits = parse(page, limit: limit);
    if (hits.isEmpty && !isNoResultsPage(page)) {
      // Challenge / consent / changed markup: fail so the breaker counts it
      // and the empty answer is not cached as "no sources".
      throw RetrieverHttpException(id, 202);
    }
    return hits;
  }

  static final RegExp _anchor = RegExp(r'''<a\b[^>]{0,500}?href\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  /// First absolute http(s) link in [html], or null.
  static String? firstLink(String html) {
    for (final m in _anchor.allMatches(html)) {
      final href = OnlineTextUtils.decodeEntities(m.group(1)!);
      if (href.startsWith('http://') || href.startsWith('https://')) return href;
    }
    return null;
  }
}

/// Bing result page (`bing.com/search`).
class BingWebRetriever extends HtmlWebSearchRetriever {
  BingWebRetriever({
    required super.client,
    super.timeout,
    super.minInterval,
    super.maxQueriesPerScan,
    super.breaker,
  }) : super(name: 'bing');

  @override
  String get id => 'bing';

  @override
  Uri buildUri(String terms) => Uri.https('www.bing.com', '/search', {'q': terms, 'setlang': 'en'});

  @override
  bool isNoResultsPage(String html) => html.contains('b_no"') || html.contains('No results found');

  static final RegExp _item = RegExp(r'<li class="b_algo"[^>]{0,500}>(.*?)(?=<li class="b_algo"|</ol>|$)', dotAll: true);
  static final RegExp _heading = RegExp(r'<h2[^>]{0,500}>(.{0,2000}?)</h2>', dotAll: true);
  static final RegExp _caption = RegExp(r'<div class="b_caption[^"]{0,120}"[^>]{0,500}>(.{0,6000}?)</div>', dotAll: true);
  static final RegExp _paragraph = RegExp(r'<p[^>]{0,500}>(.{0,4000}?)</p>', dotAll: true);
  static final RegExp _wrappingLink = RegExp(r'''<a\b[^>]{0,500}?href\s*=\s*["'](https?://[^"']+)["'][^>]{0,500}>\s*<h2''', caseSensitive: false);

  @override
  List<OnlineSourceHit> parse(String html, {int limit = 5}) {
    final hits = <OnlineSourceHit>[];
    for (final m in _item.allMatches(html)) {
      if (hits.length >= limit) break;
      final block = m.group(1)!;
      final heading = _heading.firstMatch(block)?.group(1);
      if (heading == null) continue;
      // The anchor either sits inside the <h2> or wraps it.
      final url = unwrapRedirect(HtmlWebSearchRetriever.firstLink(heading) ?? _wrappingLink.firstMatch(block)?.group(1));
      final title = OnlineTextUtils.stripMarkup(heading);
      final caption = _caption.firstMatch(block)?.group(1) ?? '';
      final snippet = OnlineTextUtils.stripMarkup(_paragraph.firstMatch(caption)?.group(1) ?? caption)
          .replaceFirst(RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{4}\s*[·.]?\s*'), '');
      if (url == null || title.isEmpty || snippet.isEmpty) continue;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: title,
        content: _terminate(snippet),
        url: url,
        category: SourceCategory.web,
      ));
    }
    return hits;
  }

  /// Bing sometimes wraps targets as `bing.com/ck/a?...&u=a1<base64url>`.
  static String? unwrapRedirect(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.endsWith('bing.com') || !uri.path.startsWith('/ck/')) return url;
    final u = uri.queryParameters['u'];
    if (u == null || !u.startsWith('a1')) return null;
    try {
      var b64 = u.substring(2).replaceAll('-', '+').replaceAll('_', '/');
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final decoded = utf8.decode(base64.decode(b64));
      return decoded.startsWith('http') ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// Brave Search result page (`search.brave.com/search`), no key.
class BraveWebRetriever extends HtmlWebSearchRetriever {
  BraveWebRetriever({
    required super.client,
    super.timeout,
    super.minInterval,
    super.maxQueriesPerScan,
    super.breaker,
  }) : super(name: 'brave_web');

  @override
  String get id => 'brave_web';

  @override
  Uri buildUri(String terms) => Uri.https('search.brave.com', '/search', {'q': terms, 'source': 'web'});

  @override
  bool isNoResultsPage(String html) => html.contains('did not match any') || html.contains('No results');

  static final RegExp _item = RegExp(r'<div class="snippet[^"]{0,120}"[^>]{0,500}data-type="web"');
  static final RegExp _title = RegExp(r'<div class="title[^"]{0,120}"[^>]{0,500}>(.{0,1000}?)</div>', dotAll: true);
  static final RegExp _content = RegExp(r'<div class="content[^"]{0,120}"[^>]{0,500}>(.{0,4000}?)</div>', dotAll: true);

  @override
  List<OnlineSourceHit> parse(String html, {int limit = 5}) {
    final starts = _item.allMatches(html).map((m) => m.start).toList();
    final hits = <OnlineSourceHit>[];
    for (var i = 0; i < starts.length && hits.length < limit; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : html.length;
      final block = html.substring(starts[i], end);
      final url = HtmlWebSearchRetriever.firstLink(block);
      final title = OnlineTextUtils.stripMarkup(_title.firstMatch(block)?.group(1));
      final snippet = OnlineTextUtils.stripMarkup(_content.firstMatch(block)?.group(1))
          .replaceFirst(RegExp(r'^\d{1,2} [A-Z][a-z]+ \d{4}\s*[-–]\s*'), '');
      if (url == null || title.isEmpty || snippet.isEmpty) continue;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: title,
        content: _terminate(snippet),
        url: url,
        category: SourceCategory.web,
      ));
    }
    return hits;
  }
}

/// Europe PMC REST API (https://europepmc.org/RestfulWebService) — keyless,
/// full-text search over open-access biomedical and life-science literature,
/// which scholarly abstract indexes only reach by title and abstract.
class EuropePmcRetriever extends SourceRetriever {
  EuropePmcRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 250),
    super.maxQueriesPerScan = 4,
    super.breaker,
  }) : super(name: 'europe_pmc');

  @override
  String get id => 'europe_pmc';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final phrase = query.exactPhrase?.trim();
    final terms = (phrase != null && phrase.isNotEmpty) ? '"$phrase"' : query.keywords.join(' ');
    final body = await getBody(Uri.https('www.ebi.ac.uk', '/europepmc/webservices/rest/search', {
      'query': terms,
      'format': 'json',
      'resultType': 'core',
      'pageSize': '$limit',
    }));
    return parseResponse(body);
  }

  List<OnlineSourceHit> parseResponse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final results = (data['resultList'] as Map<String, dynamic>?)?['result'] as List<dynamic>? ?? const [];
    final hits = <OnlineSourceHit>[];
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final title = OnlineTextUtils.stripMarkup(r['title'] as String?);
      final abstractText = OnlineTextUtils.stripMarkup(r['abstractText'] as String?);
      if (title.isEmpty || abstractText.isEmpty) continue;
      final authors = (r['authorString'] as String? ?? '')
          .split(',')
          .map((a) => a.trim().replaceAll(RegExp(r'\.$'), ''))
          .where((a) => a.isNotEmpty)
          .toList();
      final pmcid = r['pmcid'] as String?;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: title,
        content: _terminate(abstractText),
        authors: authors,
        year: int.tryParse('${r['pubYear'] ?? ''}'),
        doi: r['doi'] as String?,
        url: pmcid != null ? 'https://europepmc.org/article/PMC/$pmcid' : null,
        category: SourceCategory.academic,
      ));
    }
    return hits;
  }
}

/// Exa public MCP endpoint (https://mcp.exa.ai/mcp) — keyless semantic web search.
/// Unlike result-page snippets it returns the matching *passages* of each page
/// ("highlights"), which is what the source aligner needs. One JSON-RPC POST per
/// query, answered as a server-sent event. Best-effort like the other web
/// retrievers: it is a free public endpoint, so rate limits or outages surface as
/// a failed outcome and the circuit breaker quietly skips it.
class ExaMcpRetriever extends SourceRetriever {
  ExaMcpRetriever({
    required super.client,
    super.timeout = const Duration(seconds: 12),
    super.minInterval = const Duration(milliseconds: 700),
    super.maxQueriesPerScan = 3,
    super.breaker,
  }) : super(name: 'exa');

  @override
  String get id => 'exa';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final phrase = query.exactPhrase?.trim();
    final terms = (phrase != null && phrase.isNotEmpty) ? '"$phrase" ${query.keywords.take(4).join(' ')}' : query.text;
    final response = await client.post(
      Uri.https('mcp.exa.ai', '/mcp'),
      headers: {
        'User-Agent': SourceRetriever.userAgent,
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'web_search_exa',
          'arguments': {'query': terms, 'numResults': limit},
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RetrieverHttpException(id, response.statusCode);
    }
    return parseResponse(response.body);
  }

  /// Parses the SSE (or plain JSON) body into hits. Visible for tests.
  List<OnlineSourceHit> parseResponse(String body) {
    final payload = _jsonPayload(body);
    if (payload == null) throw const FormatException('exa: unparseable response');
    if (payload['error'] != null) throw StateError('exa: ${payload['error']}');
    final result = payload['result'] as Map<String, dynamic>?;
    if (result?['isError'] == true) throw StateError('exa: tool error');
    final blocks = (result?['content'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((c) => c['text'])
        .whereType<String>()
        .join('\n\n---\n\n');
    final hits = <OnlineSourceHit>[];
    for (final block in blocks.split(RegExp(r'\n\s*---\s*\n'))) {
      final title = RegExp(r'^Title:[ \t]*(.*)$', multiLine: true).firstMatch(block)?.group(1)?.trim() ?? '';
      final url = RegExp(r'^URL:[ \t]*(\S+)', multiLine: true).firstMatch(block)?.group(1);
      final highlightsAt = block.indexOf(RegExp(r'^Highlights:', multiLine: true));
      if (title.isEmpty || url == null || highlightsAt < 0) continue;
      final content = OnlineTextUtils.stripMarkup(block.substring(highlightsAt + 'Highlights:'.length));
      if (content.isEmpty) continue;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: OnlineTextUtils.stripMarkup(title),
        content: _terminate(content),
        url: url,
        category: SourceCategory.web,
      ));
    }
    return hits;
  }

  static Map<String, dynamic>? _jsonPayload(String body) {
    try {
      final data = body.split('\n').where((l) => l.startsWith('data:')).map((l) => l.substring(5).trim()).toList();
      final decoded = jsonDecode(data.isNotEmpty ? data.first : body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

String _terminate(String s) {
  final t = s.trim();
  if (t.isEmpty || RegExp(r'[.!?]$').hasMatch(t)) return t;
  return '$t.';
}
