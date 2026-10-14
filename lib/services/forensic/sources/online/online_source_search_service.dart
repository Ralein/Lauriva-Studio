import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../reach/reach_models.dart';
import '../../../reach/reach_page_reader.dart';
import '../source_repository.dart';
import 'community_retrievers.dart';
import 'keyless_web_retrievers.dart';
import 'scholarly_retrievers.dart';
import 'source_query_generator.dart';
import 'source_page_enricher.dart';
import 'source_retriever.dart';
import 'web_search_retrievers.dart';

/// In-memory LRU + TTL cache of retriever responses.
///
/// Keys are SHA-256 hashes of `retrieverId|query` — re-scanning the same or a
/// lightly edited document (the normal humanize → re-check loop) repeats most
/// queries, and hashing means the cache never holds user text verbatim.
/// Only successful responses are cached, so a transient outage is retried on
/// the next scan instead of being remembered as "no sources".
class OnlineHitCache {
  final int capacity;
  final Duration ttl;
  final DateTime Function() _now;
  final LinkedHashMap<String, _CacheEntry> _entries = LinkedHashMap();

  OnlineHitCache({this.capacity = 256, this.ttl = const Duration(hours: 6), DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  static String keyFor(String retrieverId, String query) =>
      sha256.convert(utf8.encode('$retrieverId|${query.toLowerCase()}')).toString();

  List<OnlineSourceHit>? get(String key) {
    final e = _entries.remove(key);
    if (e == null) return null;
    if (_now().difference(e.storedAt) > ttl) return null;
    _entries[key] = e; // re-insert as most recently used
    return e.hits;
  }

  void put(String key, List<OnlineSourceHit> hits) {
    _entries.remove(key);
    _entries[key] = _CacheEntry(hits, _now());
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  int get length => _entries.length;
  void clear() => _entries.clear();
}

class _CacheEntry {
  final List<OnlineSourceHit> hits;
  final DateTime storedAt;
  const _CacheEntry(this.hits, this.storedAt);
}

/// Diagnostics for one online search pass.
class OnlineSourceSearchResult {
  final List<SourceQuery> queries;
  final List<OnlineSourceHit> hits;
  final List<SourceCorpusDocument> documents;

  /// Per retriever: number of successful / failed / skipped / cached calls.
  final Map<String, Map<String, int>> retrieverStats;
  final bool deadlineExceeded;

  /// Web documents whose snippet was replaced by the full page text.
  final int enrichedPages;

  const OnlineSourceSearchResult({
    required this.queries,
    required this.hits,
    required this.documents,
    required this.retrieverStats,
    this.deadlineExceeded = false,
    this.enrichedPages = 0,
  });

  static const empty = OnlineSourceSearchResult(queries: [], hits: [], documents: [], retrieverStats: {});
}

/// Online source retrieval tier for plagiarism checking.
///
/// The on-device corpus holds a handful of documents, so on real submissions
/// source recall was ~0. This service finds *candidate* sources online —
/// distinctive excerpts → scholarly/web search APIs in parallel → dedup →
/// [SourceCorpusDocument]s — and hands them to the existing
/// [SourceSimilarityService] alignment, which alone decides what matches.
/// Search APIs are only a recall step: a topically similar abstract that the
/// aligner cannot align contributes nothing to the score.
///
/// Resilience: every retriever is throttled, time-limited, and
/// circuit-broken independently; a retriever that fails once is not queried
/// again in the same scan; and the whole pass has an [overallDeadline] after
/// which whatever arrived is used. [search] never throws.
///
/// Privacy: see [SourceQueryGenerator] — only its excerpts are transmitted,
/// and the caller must only invoke this when the user opted in.
class OnlineSourceSearchService {
  final List<SourceRetriever> retrievers;
  final SourceQueryGenerator queryGenerator;
  final OnlineHitCache cache;
  final Duration overallDeadline;
  final int resultsPerQuery;

  /// Cap on documents handed to the aligner (bounds isolate payload size and
  /// alignment cost; abstracts are ~200 words each).
  final int maxDocuments;

  /// Hits with less text than this are dropped: a title or a 10-word snippet
  /// cannot support a defensible alignment.
  final int minContentWords;

  /// Reads full pages for the most promising web candidates; null disables enrichment.
  final PageReader? pageReader;

  /// Time allowed for page enrichment. [overallDeadline] + this must stay
  /// under the coordinator's 8 s search timeout.
  final Duration enrichmentBudget;

  OnlineSourceSearchService({
    required this.retrievers,
    this.queryGenerator = const SourceQueryGenerator(),
    OnlineHitCache? cache,
    // Must stay under the coordinator's own search timeout (8 s full forensic, 10 s source scan),
    // otherwise the coordinator gives up first and the partial hits gathered here are discarded.
    this.overallDeadline = const Duration(seconds: 5),
    this.resultsPerQuery = 5,
    this.maxDocuments = 40,
    this.minContentWords = 12,
    this.pageReader,
    this.enrichmentBudget = const Duration(milliseconds: 2200),
  }) : cache = cache ?? OnlineHitCache();

  /// Production wiring: the keyless scholarly APIs, keyless general-web search
  /// (Bing / Brave result pages, best-effort) plus the keyed web search backends, which stay disabled until [apiKeyLookup] returns a key
  /// for `brave_search` / `serper`.
  factory OnlineSourceSearchService.withDefaults({
    http.Client? client,
    String? Function(String keyId)? apiKeyLookup,
    PageReader? pageReader,
  }) {
    final c = client ?? http.Client();
    String? key(String id) {
      try {
        return apiKeyLookup?.call(id);
      } catch (_) {
        return null;
      }
    }

    return OnlineSourceSearchService(retrievers: [
      DuckDuckGoInstantRetriever(client: c),
      WikipediaRetriever(client: c),
      WikinewsRetriever(client: c),
      BingWebRetriever(client: c),
      BraveWebRetriever(client: c),
      ExaMcpRetriever(client: c),
      StackExchangeRetriever(client: c),
      HackerNewsRetriever(client: c),
      EuropePmcRetriever(client: c),
      OpenAlexRetriever(client: c, apiKeyProvider: () => key('openalex')),
      CrossrefRetriever(client: c),
      DoajRetriever(client: c),
      NcbiPubMedRetriever(client: c),
      SemanticScholarRetriever(client: c, apiKeyProvider: () => key('semantic_scholar')),
      ArxivRetriever(client: c),
      BraveSearchRetriever(client: c, apiKeyProvider: () => key(BraveSearchRetriever.keyId)),
      SerperSearchRetriever(client: c, apiKeyProvider: () => key(SerperSearchRetriever.keyId)),
    ], pageReader: pageReader ?? ReachPageReader(client: c));
  }

  /// Convenience: only the corpus documents.
  Future<List<SourceCorpusDocument>> fetchSourceDocuments(String text) async => (await search(text)).documents;

  static bool _isTextbookLike(String text) {
    final words = RegExp(r'[a-zA-Z0-9]+').allMatches(text);
    if (words.length < 50) return false;
    final lower = text.toLowerCase();
    final firstPerson = RegExp(r'\b(i|me|my|mine)\b');
    return !firstPerson.hasMatch(lower);
  }

  /// Runs the full online retrieval pass. Never throws.
  Future<OnlineSourceSearchResult> search(String text) async {
    try {
      final queries = List<SourceQuery>.of(queryGenerator.generate(text));
      if (queries.isEmpty) return OnlineSourceSearchResult.empty;

      if (_isTextbookLike(text)) {
        final bestPhraseQuery = queries.firstWhere(
          (q) => q.exactPhrase != null && q.exactPhrase!.trim().isNotEmpty,
          orElse: () => queries.first,
        );
        final phrase = bestPhraseQuery.exactPhrase ?? bestPhraseQuery.text;
        queries.add(SourceQuery(
          text: '$phrase site:openstax.org',
          keywords: bestPhraseQuery.keywords,
          sentenceIndex: bestPhraseQuery.sentenceIndex,
          exactPhrase: bestPhraseQuery.exactPhrase,
          siteFilter: 'openstax.org',
        ));
      }

      final active = retrievers.where((r) {
        try {
          return r.isEnabled;
        } catch (_) {
          return false;
        }
      }).toList();
      if (active.isEmpty) {
        return OnlineSourceSearchResult(queries: queries, hits: const [], documents: const [], retrieverStats: const {});
      }

      // Results land here as they arrive, so a deadline keeps partial work.
      final collected = <OnlineSourceHit>[];
      final stats = <String, Map<String, int>>{
        for (final r in active) r.id: {'ok': 0, 'failed': 0, 'skipped': 0, 'cached': 0},
      };
      final tasks = [for (final r in active) _runRetriever(r, queries, collected, stats[r.id]!)];

      var deadlineExceeded = false;
      try {
        await Future.wait(tasks).timeout(overallDeadline);
      } on TimeoutException {
        deadlineExceeded = true;
        debugPrint('[OnlineSourceSearch] deadline reached; using ${collected.length} hit(s) received so far.');
      }

      final snapshot = List<OnlineSourceHit>.of(collected);
      final unique = deduplicate(snapshot);
      final documents = <SourceCorpusDocument>[];
      for (final hit in unique) {
        if (documents.length >= maxDocuments) break;
        if (OnlineTextUtils.wordCount(hit.content) < minContentWords) continue;
        documents.add(hit.toCorpusDocument());
      }
      var finalDocs = documents;
      var enrichedPages = 0;
      final reader = pageReader;
      if (reader != null && documents.isNotEmpty) {
        try {
          final enricher = SourcePageEnricher(reader: reader, budget: enrichmentBudget);
          finalDocs = await enricher
              .enrich(text, documents)
              .timeout(enrichmentBudget + const Duration(milliseconds: 400), onTimeout: () => documents);
          enrichedPages = identical(finalDocs, documents) ? 0 : enricher.lastEnrichedCount;
        } catch (e) {
          debugPrint('[OnlineSourceSearch] page enrichment failed: $e');
          finalDocs = documents;
        }
      }
      return OnlineSourceSearchResult(
        queries: queries,
        hits: unique,
        documents: finalDocs,
        retrieverStats: stats,
        deadlineExceeded: deadlineExceeded,
        enrichedPages: enrichedPages,
      );
    } catch (e) {
      if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
      debugPrint('[OnlineSourceSearch] search failed: $e');
      return OnlineSourceSearchResult.empty;
    }
  }

  /// Queries one retriever sequentially (its throttle spaces the calls),
  /// stopping at its per-scan budget or its first failure — an API that just
  /// timed out would most likely time out again, and each attempt costs the
  /// user up to a full timeout of waiting.
  Future<void> _runRetriever(
    SourceRetriever retriever,
    List<SourceQuery> queries,
    List<OnlineSourceHit> sink,
    Map<String, int> stat,
  ) async {
    int sent = 0;
    for (final q in queries) {
      if (q.siteFilter != null && retriever is! HtmlWebSearchRetriever) {
        // Site filter queries (e.g. site:openstax.org) are only for general-web HTML search engines
        continue;
      }
      final cacheKey = OnlineHitCache.keyFor(retriever.id, q.text);
      final cached = cache.get(cacheKey);
      if (cached != null) {
        stat['cached'] = stat['cached']! + 1;
        sink.addAll(cached);
        continue;
      }
      if (sent >= retriever.maxQueriesPerScan) break;
      sent++;
      final outcome = await retriever.search(q, limit: resultsPerQuery);
      if (outcome.succeeded) {
        stat['ok'] = stat['ok']! + 1;
        cache.put(cacheKey, outcome.hits);
        sink.addAll(outcome.hits);
      } else if (outcome.skipped) {
        stat['skipped'] = stat['skipped']! + 1;
        continue;
      } else {
        stat['failed'] = stat['failed']! + 1;
        if (outcome.isRateLimited || stat['failed']! >= 2) {
          break;
        }
      }
    }
  }

  /// Merges hits that refer to the same work (shared DOI, URL, or normalized
  /// title). The same paper routinely comes back from OpenAlex, Crossref and
  /// Semantic Scholar; the copy with the longest text wins (e.g. an S2
  /// abstract over a truncated snippet), keeping first-seen order.
  static List<OnlineSourceHit> deduplicate(List<OnlineSourceHit> hits) {
    final result = <OnlineSourceHit>[];
    final keyToIndex = <String, int>{};
    for (final hit in hits) {
      final keys = hit.dedupKeys;
      int? existing;
      for (final k in keys) {
        existing = keyToIndex[k];
        if (existing != null) break;
      }
      if (existing == null) {
        result.add(hit);
        for (final k in keys) {
          keyToIndex[k] = result.length - 1;
        }
        continue;
      }
      final current = result[existing];
      if (hit.content.length > current.content.length) {
        result[existing] = OnlineSourceHit(
          retrieverId: hit.retrieverId,
          title: hit.title,
          content: hit.content,
          authors: hit.authors.isNotEmpty ? hit.authors : current.authors,
          year: hit.year ?? current.year,
          // A DOI is the most durable link; keep it from whichever copy had it.
          doi: hit.doi ?? current.doi,
          url: hit.url ?? current.url,
          category: hit.category,
        );
      }
      for (final k in [...keys, ...result[existing].dedupKeys]) {
        keyToIndex[k] = existing;
      }
    }
    return result;
  }
}
