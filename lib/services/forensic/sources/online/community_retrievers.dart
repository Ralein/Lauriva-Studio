import 'dart:convert';

import '../source_repository.dart';
import 'source_retriever.dart';

/// Keyless community Q&A / forum retrievers for the online tier.
///
/// Students and essay writers copy from answers and forum posts, which the
/// scholarly APIs never index. Both backends are free public endpoints with
/// small keyless quotas, so each receives at most two queries per scan and is
/// best-effort: any failure is thrown from `fetch` and the base class turns it
/// into a failed outcome that the circuit breaker quietly skips.

/// Stack Exchange API 2.3 `search/excerpts` (https://api.stackexchange.com/docs).
///
/// The keyless quota is 300 requests/day/IP, hence `maxQueriesPerScan = 2`.
/// One site is searched per query, chosen by [siteFor].
class StackExchangeRetriever extends SourceRetriever {
  StackExchangeRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 500),
    super.maxQueriesPerScan = 2,
    super.breaker,
  }) : super(name: 'stackexchange');

  @override
  String get id => 'stackexchange';

  /// Default site when no topic keyword matches.
  static const String defaultSite = 'stackoverflow';

  /// Topic keyword -> Stack Exchange site.
  static const Map<String, List<String>> siteKeywords = {
    'cooking': ['cooking', 'cook', 'baking', 'bake', 'recipe', 'ingredient', 'ingredients', 'fry', 'egg', 'eggs', 'yolk', 'boil', 'dough', 'batter', 'microwave', 'dish', 'dishes', 'flour', 'sugar', 'meat', 'vegetable', 'sauce', 'kitchen', 'culinary', 'pan'],
    'gardening': ['gardening', 'garden', 'plant', 'plants', 'compost', 'shrub', 'soil', 'branch', 'branches', 'lettuce', 'corn', 'flower', 'flowering', 'bolted', 'fountain', 'prune', 'tree', 'crop', 'leaf', 'leaves', 'seed', 'seeds', 'weed', 'weeds'],
    'travel': ['travel', 'flight', 'airline', 'airport', 'tourist', 'tourism', 'visa', 'passport', 'knife', 'checked', 'baggage', 'destination', 'hotel', 'passenger', 'customs', 'border', 'trip', 'embassy'],
    'diy': ['diy', 'homeimprovement', 'repair', 'plumbing', 'pipe', 'wood', 'paint', 'screw', 'tools', 'drill', 'carpentry', 'electrical', 'insulation', 'roof', 'drywall', 'ceiling'],
    'money': ['money', 'personalfinance', 'tax', 'mortgage', 'investing', 'investment', 'stock', 'stocks', 'broker', 'credit', 'interest', 'retirement', 'loan', 'ira', '401k'],
    'music': ['music', 'instrument', 'guitar', 'piano', 'harmonics', 'pitch', 'tone', 'scale', 'chord', 'harmony', 'tempo', 'frequency'],
    'superuser': ['windows', 'linux', 'macos', 'browser', 'operating', 'software', 'desktop', 'keyboard', 'terminal', 'command', 'driver'],
    'biology': ['biology', 'cell', 'cells', 'plant', 'plants', 'photosynthesis', 'dna', 'protein', 'enzyme', 'organism', 'species', 'evolution', 'mitochondria', 'chlorophyll', 'bacteria', 'virus'],
    'chemistry': ['chemistry', 'chemical', 'molecule', 'molecules', 'reaction', 'compound', 'acid', 'bond', 'electron', 'oxidation'],
    'physics': ['physics', 'quantum', 'gravity', 'relativity', 'momentum', 'velocity', 'thermodynamics', 'photon', 'wavelength', 'schrodinger', 'force', 'energy', 'acceleration', 'mass', 'particle', 'black', 'hole'],
    'history': ['history', 'historical', 'empire', 'revolution', 'medieval', 'ancient', 'dynasty', 'colonial'],
    'english': ['grammar', 'syntax', 'etymology', 'idiom', 'metaphor', 'sentence', 'vocabulary', 'adjective', 'adverb', 'pronoun', 'punctuation', 'spelling', 'quote', 'sic', 'clause'],
    'philosophy': ['philosophy', 'philosophical', 'ethics', 'metaphysics', 'epistemology', 'existential', 'kant', 'utilitarian'],
    'economics': ['economics', 'economy', 'inflation', 'monetary', 'supply', 'demand', 'gdp', 'fiscal', 'market'],
    'math': ['math', 'mathematics', 'theorem', 'calculus', 'algebra', 'integral', 'derivative', 'matrix', 'probability', 'equation', 'proof'],
  };

  /// Returns a ranked list of candidate Stack Exchange sites for [text].
  static List<String> sitesFor(String text) {
    final words = RegExp(r'[a-z0-9]+').allMatches(text.toLowerCase()).map((m) => m.group(0)!).toSet();
    final scores = <String, int>{};
    for (final entry in siteKeywords.entries) {
      final matches = entry.value.where(words.contains).length;
      if (matches > 0) scores[entry.key] = matches;
    }
    final sorted = scores.keys.toList()..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    if (sorted.isEmpty) return [defaultSite];
    return sorted;
  }

  /// Picks the top Stack Exchange site for [text] using [siteKeywords].
  static String siteFor(String text) => sitesFor(text).first;

  DateTime _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    if (DateTime.now().isBefore(_backoffUntil)) throw StateError('stackexchange: backing off');
    final phrase = query.exactPhrase?.trim();
    var terms = (phrase != null && phrase.isNotEmpty) ? '"$phrase"' : query.text;
    if (terms.length > 80) {
      final cut = terms.substring(0, 80);
      final lastSpace = cut.lastIndexOf(' ');
      terms = (lastSpace > 20 ? cut.substring(0, lastSpace) : cut).trim();
      if (phrase != null && phrase.isNotEmpty && !terms.endsWith('"')) {
        terms = '$terms"';
      }
    }
    final candidates = sitesFor(query.text);
    // Query up to 2 candidate sites in parallel
    final sitesToQuery = candidates.take(2).toList();
    if (sitesToQuery.isEmpty) sitesToQuery.add(defaultSite);

    Exception? lastError;
    final tasks = sitesToQuery.map((site) async {
      try {
        final body = await getBody(Uri.https('api.stackexchange.com', '/2.3/search/excerpts', {
          'order': 'desc',
          'sort': 'relevance',
          'q': terms,
          'site': site,
          'pagesize': '$limit',
        }));
        if (body.contains('1015') || body.contains('throttle_violation')) {
          _backoffUntil = DateTime.now().add(const Duration(minutes: 5));
          throw const RetrieverHttpException('stackexchange', 429);
        }
        return parseResponse(body, site: site);
      } on StackExchangeBackoff catch (e) {
        _backoffUntil = DateTime.now().add(Duration(seconds: e.seconds));
        rethrow;
      } on RetrieverHttpException catch (e) {
        if (e.statusCode == 400 || e.statusCode == 429) {
          _backoffUntil = DateTime.now().add(const Duration(minutes: 5));
        }
        lastError = e;
        return <OnlineSourceHit>[];
      } catch (e) {
        if (e is Exception) lastError = e;
        return <OnlineSourceHit>[];
      }
    });

    final results = await Future.wait(tasks);
    final allHits = [for (final list in results) ...list];
    if (allHits.isEmpty && lastError != null) {
      throw lastError!;
    }
    return allHits;
  }

  /// Parses a `search/excerpts` response. Throws on API error payloads and on
  /// a `backoff` request so the breaker engages. Visible for tests.
  List<OnlineSourceHit> parseResponse(String body, {String site = defaultSite}) {
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) throw const FormatException('stackexchange: unexpected response');
    if (data['error_id'] != null) {
      throw StateError('stackexchange: ${data['error_name'] ?? data['error_id']}: ${data['error_message'] ?? ''}');
    }
    final backoff = data['backoff'];
    if (backoff is num) throw StackExchangeBackoff(backoff.toInt());
    final host = site == 'stackoverflow' ? 'stackoverflow.com' : '$site.stackexchange.com';
    final hits = <OnlineSourceHit>[];
    for (final item in data['items'] as List<dynamic>? ?? const []) {
      if (item is! Map<String, dynamic>) continue;
      final title = OnlineTextUtils.stripMarkup(item['title'] as String?);
      final bodyText = OnlineTextUtils.stripMarkup(item['body'] as String?);
      final content = bodyText.isNotEmpty ? bodyText : OnlineTextUtils.stripMarkup(item['excerpt'] as String?);
      final qid = item['question_id'];
      if (title.isEmpty || content.isEmpty || qid == null) continue;
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: title,
        content: _terminate(content),
        url: 'https://$host/questions/$qid',
        category: SourceCategory.web,
      ));
    }
    return hits;
  }
}

/// Thrown when Stack Exchange asks the client to wait [seconds] before retrying.
class StackExchangeBackoff implements Exception {
  final int seconds;
  const StackExchangeBackoff(this.seconds);

  @override
  String toString() => 'StackExchangeBackoff(${seconds}s)';
}

/// Hacker News via the Algolia search API (https://hn.algolia.com/api), keyless.
/// Stories and comments only; short one-liners are skipped because they carry
/// too little text to align against.
class HackerNewsRetriever extends SourceRetriever {
  HackerNewsRetriever({
    required super.client,
    super.timeout,
    super.minInterval = const Duration(milliseconds: 500),
    super.maxQueriesPerScan = 2,
    super.breaker,
  }) : super(name: 'hackernews');

  @override
  String get id => 'hackernews';

  /// Hits with fewer words than this are skipped.
  static const int minWords = 12;

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async {
    final phrase = query.exactPhrase?.trim();
    final terms = (phrase != null && phrase.isNotEmpty) ? '"$phrase"' : query.text;
    final body = await getBody(Uri.https('hn.algolia.com', '/api/v1/search', {
      'query': terms,
      'tags': '(story,comment)',
      'hitsPerPage': '$limit',
    }));
    return parseResponse(body);
  }

  /// Parses an Algolia search response. Visible for tests.
  List<OnlineSourceHit> parseResponse(String body) {
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) throw const FormatException('hackernews: unexpected response');
    if (data['message'] is String && data['hits'] == null) {
      throw StateError('hackernews: ${data['message']}');
    }
    final hits = <OnlineSourceHit>[];
    for (final h in data['hits'] as List<dynamic>? ?? const []) {
      if (h is! Map<String, dynamic>) continue;
      final content = OnlineTextUtils.stripMarkup((h['comment_text'] ?? h['story_text']) as String?);
      final objectId = h['objectID'];
      if (objectId == null || OnlineTextUtils.wordCount(content) < minWords) continue;
      final rawTitle = OnlineTextUtils.stripMarkup((h['story_title'] ?? h['title']) as String?);
      hits.add(OnlineSourceHit(
        retrieverId: id,
        title: rawTitle.isEmpty ? 'Hacker News comment' : rawTitle,
        content: _terminate(content),
        url: 'https://news.ycombinator.com/item?id=$objectId',
        category: SourceCategory.web,
      ));
    }
    return hits;
  }
}

String _terminate(String s) {
  final t = s.trim();
  if (t.isEmpty || RegExp(r'[.!?]$').hasMatch(t)) return t;
  return '$t.';
}
