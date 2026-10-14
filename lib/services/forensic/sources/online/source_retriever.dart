import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../circuit_breaker.dart';
import '../match_tokenizer.dart';
import '../source_repository.dart';

/// A search query derived from the user's document by [SourceQueryGenerator].
///
/// Only these short excerpts — never the full document — leave the device.
class SourceQuery {
  /// Space-joined excerpt (≤ ~25 words, punctuation stripped, emails / URLs /
  /// long digit runs redacted) sent to full-text relevance APIs.
  final String text;

  /// The handful of most distinctive words of [text], for APIs whose query
  /// language degrades on long free-text input (arXiv ORs bare terms, so a
  /// 25-word query matches a million papers; an AND of five rare words
  /// pinpoints the source).
  final List<String> keywords;

  /// Index of the sentence (in the source document) the query was taken from.
  final int sentenceIndex;

  /// Distinctive 5-8 token verbatim content phrase for quoted web searches.
  final String? exactPhrase;

  /// Optional site filter (e.g. 'openstax.org') for targeted site-specific web searches.
  final String? siteFilter;

  const SourceQuery({
    required this.text,
    required this.keywords,
    required this.sentenceIndex,
    this.exactPhrase,
    this.siteFilter,
  });

  @override
  String toString() => 'SourceQuery($text, exactPhrase: $exactPhrase, siteFilter: $siteFilter)';
}

/// One published source returned by an online retriever.
///
/// Retrievers only see titles, abstracts, and search snippets — never full
/// text — so [content] is the abstract (scholarly APIs) or snippet (web).
class OnlineSourceHit {
  final String retrieverId;
  final String title;
  final String content;
  final List<String> authors;
  final int? year;
  final String? url;
  final String? doi;
  final SourceCategory category;

  const OnlineSourceHit({
    required this.retrieverId,
    required this.title,
    required this.content,
    this.authors = const [],
    this.year,
    this.url,
    this.doi,
    this.category = SourceCategory.academic,
  });

  /// Normalized DOI (lower-case, resolver prefix removed) or null.
  String? get normalizedDoi {
    final d = doi?.trim().toLowerCase();
    if (d == null || d.isEmpty) return null;
    return d
        .replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/'), '')
        .replaceFirst(RegExp(r'^doi:'), '');
  }

  /// URL normalized for de-duplication: scheme, `www.`, trailing slash,
  /// query/fragment, and arXiv version suffixes do not make a new source.
  String? get normalizedUrl {
    final u = url?.trim().toLowerCase();
    if (u == null || u.isEmpty) return null;
    var n = u
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '')
        .replaceFirst(RegExp(r'[?#].*$'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    n = n.replaceFirst(RegExp(r'(arxiv\.org/(abs|pdf)/[0-9.]+)v\d+$'), r'$1');
    return n;
  }

  /// Title folded to lower-case alphanumerics for cross-API de-duplication
  /// (Crossref, OpenAlex and Semantic Scholar all index the same papers).
  String get normalizedTitle => title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Every identity key this hit can be matched on, strongest first.
  List<String> get dedupKeys => [
        if (normalizedDoi != null) 'doi:$normalizedDoi',
        if (normalizedUrl != null) 'url:$normalizedUrl',
        if (normalizedTitle.length >= 12) 'title:$normalizedTitle',
      ];

  /// Best link for the report: a DOI resolves permanently, a landing URL may not.
  String? get displayUrl {
    final d = normalizedDoi;
    if (d != null) return 'https://doi.org/$d';
    return url;
  }

  /// Display title in the same "Title (Author et al., Year)" shape as the
  /// built-in corpus, so the existing source list renders it unchanged.
  String get displayTitle {
    final parts = <String>[];
    if (authors.isNotEmpty) {
      final surname = authors.first.trim().split(RegExp(r'\s+')).last;
      parts.add(authors.length > 1 ? '$surname et al.' : surname);
    }
    if (year != null) parts.add('$year');
    return parts.isEmpty ? title : '$title (${parts.join(', ')})';
  }

  /// Converts the hit into a corpus document the existing
  /// [SourceSimilarityService] pipeline can align against. The id is derived
  /// from the strongest identity key so the same paper found by two APIs (or
  /// two scans) always gets the same id.
  SourceCorpusDocument toCorpusDocument() {
    final key = dedupKeys.isNotEmpty ? dedupKeys.first : 'title:$normalizedTitle';
    return SourceCorpusDocument(
      id: 'online_${retrieverId}_${MatchTokenizer.fnv1a(key).toRadixString(16)}',
      title: displayTitle,
      author: authors.isEmpty ? null : authors.take(3).join(', ') + (authors.length > 3 ? ' et al.' : ''),
      url: displayUrl,
      category: category,
      content: content,
    );
  }
}

/// Reservation-based request throttle: each call reserves the next free slot
/// [minInterval] after the previous one, so concurrent callers are spaced out
/// without a queue. Shared across scans because API rate limits are per
/// client, not per scan.
class RequestThrottle {
  final Duration minInterval;
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);

  RequestThrottle(this.minInterval);

  Future<void> acquire() async {
    if (minInterval <= Duration.zero) return;
    final now = DateTime.now();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(minInterval);
    final wait = slot.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }
}

/// Thrown by a retriever when an API answered with a non-success status.
class RetrieverHttpException implements Exception {
  final String retrieverId;
  final int statusCode;
  const RetrieverHttpException(this.retrieverId, this.statusCode);

  @override
  String toString() => 'RetrieverHttpException($retrieverId, HTTP $statusCode)';
}

/// A single online source backend (OpenAlex, Crossref, a web search API...).
///
/// Subclasses implement [fetch] and may throw freely; callers go through
/// [search], which applies throttling, a hard timeout, and a per-retriever
/// circuit breaker, and converts every failure into a [RetrieverOutcome]
/// instead of an exception. One slow or broken API therefore only costs its
/// own candidates, never the scan.
abstract class SourceRetriever {
  final http.Client client;
  final Duration timeout;
  final RequestThrottle throttle;
  final CircuitBreaker breaker;

  /// Upper bound on queries this backend receives per scan — sized to its
  /// published rate limit (arXiv asks for one request every 3 s, keyless
  /// Semantic Scholar shares a 1 rps pool) and, for paid web search, quota.
  final int maxQueriesPerScan;

  SourceRetriever({
    required this.client,
    required String name,
    this.timeout = const Duration(seconds: 7),
    Duration minInterval = Duration.zero,
    this.maxQueriesPerScan = 6,
    CircuitBreaker? breaker,
  })  : throttle = RequestThrottle(minInterval),
        breaker = breaker ??
            CircuitBreaker(
              name: 'source_retriever_$name',
              failureThreshold: 3,
              cooldownDuration: const Duration(seconds: 15),
            );

  /// Stable identifier (also used in document ids and cache keys).
  String get id;

  /// Whether the backend can be used right now (keyed web search is only
  /// enabled when the user has stored a key).
  bool get isEnabled => true;

  /// Performs one API request. May throw; see [search].
  @protected
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5});

  /// Trips the circuit breaker open with a custom cooldown (default: 10 minutes)
  /// so subsequent scans in this session skip this retriever.
  void tripLongCooldown({Duration duration = const Duration(minutes: 10)}) {
    breaker.tripWithCooldown(duration);
  }

  /// Safe entry point: never throws.
  Future<RetrieverOutcome> search(SourceQuery query, {int limit = 5}) async {
    if (!isEnabled) return const RetrieverOutcome.skipped();
    if (breaker.isOpen) return const RetrieverOutcome.skipped();
    try {
      await throttle.acquire();
      final hits = await breaker.execute(() => fetch(query, limit: limit).timeout(timeout));
      return RetrieverOutcome.success(hits);
    } catch (e) {
      if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
      debugPrint('[SourceRetriever:$id] query failed: $e');
      final is429 = (e is RetrieverHttpException &&
              (e.statusCode == 429 || (e.retrieverId == 'stackexchange' && e.statusCode == 400))) ||
          e.toString().contains('429') ||
          e.toString().contains('1015') ||
          e.toString().contains('throttle_violation');
      if (is429) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return RetrieverOutcome.failure(e.toString(), isRateLimited: is429);
    }
  }

  /// GET helper that turns non-2xx responses into [RetrieverHttpException].
  @protected
  Future<String> getBody(Uri uri, {Map<String, String>? headers}) async {
    final response = await client.get(uri, headers: {'User-Agent': userAgent, ...?headers});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RetrieverHttpException(id, response.statusCode);
    }
    return response.body;
  }

  /// Identifies the app (not the user) — Crossref and OpenAlex route
  /// requests carrying a contact address into their faster "polite" pools.
  static const String userAgent = 'Lauriva/3.6 (source-check; mailto:support@lauriva.app)';
  static const String contactEmail = 'support@lauriva.app';
}

/// Result of one [SourceRetriever.search] call.
class RetrieverOutcome {
  final List<OnlineSourceHit> hits;
  final bool succeeded;
  final bool skipped;
  final String? error;
  final bool isRateLimited;

  const RetrieverOutcome.success(this.hits)
      : succeeded = true,
        skipped = false,
        error = null,
        isRateLimited = false;
  const RetrieverOutcome.failure(this.error, {this.isRateLimited = false})
      : hits = const [],
        succeeded = false,
        skipped = false;
  const RetrieverOutcome.skipped()
      : hits = const [],
        succeeded = false,
        skipped = true,
        error = null,
        isRateLimited = false;
}

/// Text clean-up shared by the retrievers.
class OnlineTextUtils {
  OnlineTextUtils._();

  static final RegExp _tag = RegExp(r'<[^>]+>');
  static final RegExp _ws = RegExp(r'\s+');

  /// Strips HTML/JATS/XML tags and decodes the common entities. Crossref
  /// abstracts arrive as JATS (`<jats:p>…</jats:p>`), Brave snippets carry
  /// `<strong>` highlights, and arXiv summaries are XML-escaped.
  static String stripMarkup(String? input) {
    if (input == null || input.isEmpty) return '';
    var s = input.replaceAll(_tag, ' ');
    s = decodeEntities(s);
    // Snippet ellipses join unrelated fragments; make them sentence breaks
    // so the paraphrase tier never scores a stitched pseudo-sentence.
    s = s.replaceAll(RegExp(r'\s*(\.\.\.|…)\s*'), '. ');
    return s.replaceAll(_ws, ' ').trim();
  }

  static String decodeEntities(String s) {
    return s
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  static int wordCount(String s) => RegExp(r"[A-Za-z0-9]+").allMatches(s).length;
}
