import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Outcome of trying to obtain open-access full text for one work.
enum FullTextStatus {
  ok('ok'),

  /// Unpaywall / Europe PMC say the work has no legal OA copy.
  notOa('not_oa'),

  /// OA exists, but only as PDF — skipped (no PDF parser by design).
  oaPdfOnly('oa_pdf_only'),

  /// OA page fetched but it held no parseable body text (abstract-only
  /// landing page, metadata-only JATS, article too short).
  noFullText('no_fulltext'),

  /// The source has no record for the identifier (HTTP 404, empty search).
  notFound('not_found'),

  /// The work carries no identifier any full-text source can resolve.
  noRoute('no_route'),
  error('error'),
  timeout('timeout'),

  /// The host's politeness interval would push the request past the stage
  /// deadline, so it was not sent.
  rateLimited('rate_limited'),

  /// The per-scan text budget was already spent.
  budgetExhausted('budget_exhausted');

  final String wireName;
  const FullTextStatus(this.wireName);

  /// Definitive answers worth caching (a transient error is retried next scan).
  bool get cacheable =>
      this == ok || this == notOa || this == oaPdfOnly || this == noFullText || this == notFound;
}

/// Which open-access channel produced the text.
enum FullTextVia {
  arxivHtml('arxiv_html'),
  ar5ivHtml('ar5iv_html'),
  europePmcJats('europepmc_jats'),
  unpaywallHtml('unpaywall_html'),
  unpaywallJats('unpaywall_jats'),
  wikipedia('wikipedia');

  final String wireName;
  const FullTextVia(this.wireName);
}

/// Result of one full-text lookup: the cleaned body text (when [status] is
/// [FullTextStatus.ok]) and the public URL a reader can open to verify it.
class FullTextOutcome {
  final FullTextStatus status;
  final String text;
  final String? oaUrl;
  final FullTextVia? via;

  const FullTextOutcome(this.status, {this.text = '', this.oaUrl, this.via});

  bool get isOk => status == FullTextStatus.ok && text.isNotEmpty;

  FullTextOutcome truncated(int maxChars) {
    if (text.length <= maxChars) return this;
    // Cut on a paragraph boundary when one exists in the last quarter.
    var cut = text.lastIndexOf('\n\n', maxChars);
    if (cut < maxChars * 0.75) cut = maxChars;
    return FullTextOutcome(status, text: text.substring(0, cut), oaUrl: oaUrl, via: via);
  }

  @override
  String toString() => 'FullTextOutcome(${status.wireName}, ${text.length} chars, via: ${via?.wireName}, $oaUrl)';
}

/// In-memory LRU + TTL cache of full-text outcomes keyed by a SHA-256 of the
/// work identity (DOI / arXiv id / PMCID / Wikipedia URL) — the same pattern
/// as `OnlineHitCache`. Only [FullTextStatus.cacheable] outcomes are stored.
/// Capacity is small on purpose: each entry can hold up to one capped work
/// (≤ 60k chars), so 24 entries bound the cache at a few MB on mobile.
class FullTextCache {
  final int capacity;
  final Duration ttl;
  final Duration negativeTtl;
  final DateTime Function() _now;
  final LinkedHashMap<String, ({FullTextOutcome outcome, DateTime storedAt})> _entries = LinkedHashMap();

  FullTextCache({
    this.capacity = 24,
    this.ttl = const Duration(hours: 24),
    this.negativeTtl = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  static String keyFor(String workKey) => sha256.convert(utf8.encode('fulltext|${workKey.toLowerCase()}')).toString();

  FullTextOutcome? get(String key) {
    final e = _entries.remove(key);
    if (e == null) return null;
    final maxAge = e.outcome.isOk ? ttl : negativeTtl;
    if (_now().difference(e.storedAt) > maxAge) return null;
    _entries[key] = e;
    return e.outcome;
  }

  void put(String key, FullTextOutcome outcome) {
    if (!outcome.status.cacheable) return;
    _entries.remove(key);
    _entries[key] = (outcome: outcome, storedAt: _now());
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  int get length => _entries.length;
  void clear() => _entries.clear();
}

/// Per-host politeness gate: at most one request in flight and at least
/// [minInterval] between request starts. Unlike a plain throttle it is
/// deadline-aware — [run] returns `null` without sending anything when the
/// next free slot lies beyond the caller's deadline, so a 15 s crawl delay
/// never stalls a scan.
class HostGate {
  final Duration minInterval;
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _tail = Future<void>.value();

  HostGate(this.minInterval);

  Future<T?> run<T>(DateTime deadline, Future<T> Function() body) async {
    final now = DateTime.now();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    if (slot.isAfter(deadline)) return null;
    _nextSlot = slot.add(minInterval);
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      final wait = slot.difference(DateTime.now());
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (DateTime.now().isAfter(deadline)) return null;
      return await body();
    } finally {
      done.complete();
    }
  }
}
