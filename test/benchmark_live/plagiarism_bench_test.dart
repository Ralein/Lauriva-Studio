// Live plagiarism source-finding benchmark. SKIPPED unless PLAG_BENCH_OUT is set.
//
//   PLAG_BENCH_OUT=/tmp/plag.jsonl flutter test test/benchmark_live/plagiarism_bench_test.dart --timeout=none
//
// Env: PLAG_BENCH_DATASET (default tool/eval/plagiarism_bench/dataset.jsonl),
//      PLAG_BENCH_PIPELINES (comma list of offline,online,hybrid,prod; default all),
//      PLAG_BENCH_IDFILE (file of item ids to run, one per line), PLAG_BENCH_LIMIT (max items), PLAG_BENCH_ONLY (comma list of item-id substrings).
// Resumable: one JSON line per (item, pipeline) is appended to PLAG_BENCH_OUT; existing pairs are skipped.
// Drives OnlineSourceSearchService + SourceSimilarityService with a fresh SourceRepository per item (not the
// coordinator: the coordinator adds fetched docs to the process-global SourceRepository.baselineLiterature,
// which would leak sources between items and contaminate the ablation).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lauriva/services/forensic/sources/compact_corpus_index.dart';
import 'package:lauriva/services/forensic/sources/online/online_source_search_service.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';
import 'package:lauriva/services/reach/reach_page_reader.dart';

void _openIndex() {
  CompactCorpusIndex.install(CompactCorpusIndex.fromSource(FileByteSource.open(CompactCorpusIndex.assetPath)));
}

void _noIndex() {
  CompactCorpusIndex.install(null);
  if (CompactCorpusIndex.current != null) {
    throw StateError('an offline index is still reachable; online-only pipeline would be contaminated');
  }
}

Map<String, dynamic> _evidence(dynamic ev) => {
      'overall': ev.overallSimilarityScore,
      'coverage': ev.documentCoveragePercent,
      'matches': [
        for (final m in ev.matches)
          {
            'title': m.sourceTitle,
            'url': m.sourceUrl,
            'tokens': m.tokenCount,
            'sim': m.similarityPercent,
            'in': m.matchedIn,
            'type': m.matchType.toString(),
          }
      ],
    };

void main() {
  final out = Platform.environment['PLAG_BENCH_OUT'];
  test('plagiarism source-finding benchmark', () async {
    final outFile = File(out!);
    final datasetPath = Platform.environment['PLAG_BENCH_DATASET'] ?? 'tool/eval/plagiarism_bench/dataset.jsonl';
    final pipes = (Platform.environment['PLAG_BENCH_PIPELINES'] ?? 'offline,online,hybrid,prod').split(',');
    final limit = int.tryParse(Platform.environment['PLAG_BENCH_LIMIT'] ?? '') ?? 1 << 30;
    final only = (Platform.environment['PLAG_BENCH_ONLY'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
    final idFile = Platform.environment['PLAG_BENCH_IDFILE'];
    final idSet = idFile == null ? null : File(idFile).readAsLinesSync().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final items = [
      for (final l in File(datasetPath).readAsLinesSync())
        if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>
    ].where((i) => idSet == null || idSet.contains(i['id'])).where((i) => only.isEmpty || only.any((o) => (i['id'] as String).contains(o))).take(limit).toList();

    final done = <String>{};
    if (outFile.existsSync()) {
      for (final l in outFile.readAsLinesSync()) {
        try {
          final r = jsonDecode(l) as Map<String, dynamic>;
          done.add('${r['id']}|${r['pipeline']}');
        } catch (_) {}
      }
    }
    outFile.parent.createSync(recursive: true);
    void write(Map<String, dynamic> r) =>
        outFile.writeAsStringSync('${jsonEncode(r)}\n', mode: FileMode.append, flush: true);

    final needsNet = pipes.any((p) => p != 'offline');
    final client = http.Client();
    final base = OnlineSourceSearchService.withDefaults(client: client);
    final cache = OnlineHitCache();
    // identical retrievers/deadline/cache; only the page reader differs
    final plain = OnlineSourceSearchService(retrievers: base.retrievers, cache: cache);
    final enriched = OnlineSourceSearchService(retrievers: base.retrievers, cache: cache, pageReader: ReachPageReader(client: client));

    Future<OnlineSourceSearchResult> search(OnlineSourceSearchService s, String text) async {
      var r = await s.search(text);
      final okTotal = r.retrieverStats.values.fold<int>(0, (a, m) => a + (m['ok'] ?? 0) + (m['cached'] ?? 0));
      if (r.documents.isEmpty && okTotal == 0) {
        await Future<void>.delayed(const Duration(seconds: 4)); // retry once on total network failure
        r = await s.search(text);
      }
      return r;
    }

    Map<String, dynamic> analyze(List<dynamic> docs, String text, {required bool index}) {
      final repo = SourceRepository(loadDefaultCorpus: false);
      for (final d in docs) {
        repo.addDocument(d);
      }
      if (index) {
        _openIndex();
      } else {
        _noIndex();
      }
      final sw = Stopwatch()..start();
      final ev = SourceSimilarityService(repository: repo).analyzeDocument(text);
      return {..._evidence(ev), 'analyze_ms': sw.elapsedMilliseconds};
    }

    Map<String, dynamic> statsJson(OnlineSourceSearchResult r) => {
          'n_hits': r.hits.length,
          'n_docs': r.documents.length,
          'enriched': r.enrichedPages,
          'deadline': r.deadlineExceeded,
          'retrievers': r.retrieverStats,
        };

    var n = 0;
    for (final item in items) {
      n++;
      final id = item['id'] as String;
      final text = item['text'] as String;
      final todo = [for (final p in pipes) if (!done.contains('$id|$p')) p];
      if (todo.isEmpty) continue;
      try {
        if (todo.contains('offline')) {
          final a = analyze(const [], text, index: true);
          write({'id': id, 'pipeline': 'offline', 'latency_ms': a['analyze_ms'], ...a});
        }
        OnlineSourceSearchResult? plainRes;
        int plainMs = 0;
        if (todo.contains('online') || todo.contains('hybrid')) {
          final sw = Stopwatch()..start();
          plainRes = await search(plain, text);
          plainMs = sw.elapsedMilliseconds;
          if (todo.contains('online')) {
            final a = analyze(plainRes.documents, text, index: false);
            write({'id': id, 'pipeline': 'online', 'latency_ms': plainMs + (a['analyze_ms'] as int), 'search_ms': plainMs, ...statsJson(plainRes), ...a});
          }
          if (todo.contains('hybrid')) {
            final a = analyze(plainRes.documents, text, index: true);
            write({'id': id, 'pipeline': 'hybrid', 'latency_ms': plainMs + (a['analyze_ms'] as int), 'search_ms': plainMs, ...statsJson(plainRes), ...a});
          }
        }
        if (todo.contains('prod')) {
          final sw = Stopwatch()..start();
          final r = await search(enriched, text);
          final ms = sw.elapsedMilliseconds;
          final a = analyze(r.documents, text, index: true);
          write({'id': id, 'pipeline': 'prod', 'latency_ms': ms + (a['analyze_ms'] as int), 'search_ms': ms, ...statsJson(r), ...a});
        }
      } catch (e, st) {
        write({'id': id, 'pipeline': todo.join('+'), 'error': '$e', 'stack': '$st'.split('\n').take(3).join(' | ')});
      }
      if (needsNet) await Future<void>.delayed(const Duration(seconds: 1));
      if (n % 25 == 0) stdout.writeln('[plagbench] $n/${items.length}');
    }
    client.close();
    CompactCorpusIndex.install(null);
  }, skip: out == null ? 'set PLAG_BENCH_OUT to run the live benchmark' : false, timeout: Timeout.none);
}
