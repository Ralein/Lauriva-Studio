import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../reach/reach_models.dart';
import '../match_tokenizer.dart';
import '../source_repository.dart';

/// Upgrades search-snippet web sources to full page text before alignment.
///
/// Search APIs return short snippets, so a genuine copy of a web page often
/// shows tiny coverage. After the online search has picked candidates, this
/// fetches the few most promising pages (ranked by how strongly their snippet
/// already overlaps the user's text) and, when the page text matches the user
/// text at least as well as the snippet did, swaps it in as the document
/// content so the aligner confirms the copy against the real page.
///
/// Never throws. The returned list has the same length, order, ids, titles and
/// urls as the input; a document is only ever replaced by something that
/// matches at least as much, so the snippet's own evidence is never lost.
class SourcePageEnricher {
  final PageReader reader;
  final int maxPages;
  final int maxCharsPerPage;
  final int maxTotalChars;
  final Duration budget;

  /// Shared stemmed content 4-grams a snippet needs to be worth a fetch.
  static const int minSnippetOverlap = 2;
  static const int _gramSize = 4;

  /// Pages enriched by the most recent [enrich] call.
  int lastEnrichedCount = 0;

  SourcePageEnricher({
    required this.reader,
    this.maxPages = 4,
    this.maxCharsPerPage = 60000,
    this.maxTotalChars = 200000,
    this.budget = const Duration(milliseconds: 2500),
  });

  Future<List<SourceCorpusDocument>> enrich(String userText, List<SourceCorpusDocument> docs) async {
    lastEnrichedCount = 0;
    try {
      if (docs.isEmpty || maxPages <= 0 || userText.trim().isEmpty) return docs;
      final userGrams = MatchTokenizer.contentNgrams(MatchTokenizer.tokenize(userText), _gramSize);
      if (userGrams.isEmpty) return docs;

      // Cheap ranking: snippet overlap with the user text.
      final candidates = <_Candidate>[];
      for (var i = 0; i < docs.length; i++) {
        final d = docs[i];
        if (d.category != SourceCategory.web || !_isHttp(d.url)) continue;
        final overlap = _overlap(userGrams, d.matchTokens);
        if (overlap < minSnippetOverlap) continue;
        candidates.add(_Candidate(i, overlap));
      }
      if (candidates.isEmpty) return docs;
      candidates.sort((a, b) => b.overlap != a.overlap ? b.overlap.compareTo(a.overlap) : a.index.compareTo(b.index));

      final picked = <_Candidate>[];
      final seenUrls = <String>{};
      for (final c in candidates) {
        if (picked.length >= maxPages) break;
        if (seenUrls.add(docs[c.index].url!)) picked.add(c);
      }

      final urls = [for (final c in picked) docs[c.index].url!];
      final Map<String, ReachPage> pages = await reader
          .readMany(urls, maxChars: maxCharsPerPage, deadline: budget)
          .timeout(budget + const Duration(milliseconds: 300), onTimeout: () => const <String, ReachPage>{});
      if (pages.isEmpty) return docs;

      final result = List<SourceCorpusDocument>.of(docs);
      var remaining = maxTotalChars;
      var enriched = 0;
      for (final c in picked) {
        if (remaining <= 0) break;
        final doc = docs[c.index];
        final page = pages[doc.url!];
        if (page == null) continue;
        var text = page.text.trim();
        if (text.length <= doc.content.length) continue; // nothing to gain
        final cap = remaining < maxCharsPerPage ? remaining : maxCharsPerPage;
        if (text.length > cap) text = text.substring(0, cap);
        if (_overlap(userGrams, MatchTokenizer.tokenize(text)) < c.overlap) continue;
        result[c.index] = SourceCorpusDocument(
          id: doc.id,
          title: doc.title,
          author: doc.author,
          url: doc.url,
          category: doc.category,
          content: text,
          fullTextOffset: doc.fullTextOffset,
          oaUrl: doc.oaUrl,
          fullTextSource: page.via.isEmpty ? doc.fullTextSource : 'reach_${page.via}',
        );
        remaining -= text.length;
        enriched++;
      }
      lastEnrichedCount = enriched;
      return result;
    } catch (e) {
      if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
      debugPrint('[SourcePageEnricher] enrichment skipped: $e');
      return docs;
    }
  }

  static bool _isHttp(String? url) {
    if (url == null) return false;
    final u = Uri.tryParse(url.trim());
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
  }

  static int _overlap(Set<String> userGrams, List<MatchToken> tokens) {
    final grams = MatchTokenizer.contentNgrams(tokens, _gramSize);
    var n = 0;
    for (final g in grams) {
      if (userGrams.contains(g)) n++;
    }
    return n;
  }
}

class _Candidate {
  final int index;
  final int overlap;
  const _Candidate(this.index, this.overlap);
}
