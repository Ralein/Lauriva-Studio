import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/sources/compact_corpus_index.dart';
import 'package:lauriva/services/forensic/sources/match_tokenizer.dart';

/// Checks the SHIPPED asset (assets/source_corpus_v2.bin), not a fixture.
void main() {
  final asset = File(CompactCorpusIndex.assetPath);
  // Ground truth for "is in the index": the raw arXiv records the shipped index was built from (gitignored).
  final rawArxiv = File('tool/corpus/raw/arxiv.jsonl');

  /// Evenly spaced sample of raw abstracts, shaped like the old seed docs (`title`, `content`).
  List<Map<String, dynamic>> sampleAbstracts({int count = 300}) {
    final lines = rawArxiv.readAsLinesSync();
    final step = (lines.length / count).floor().clamp(1, lines.length);
    return [
      for (var i = 0; i < lines.length; i += step)
        () {
          final r = jsonDecode(lines[i]) as Map<String, dynamic>;
          return <String, dynamic>{'title': r['title'], 'content': r['text']};
        }(),
    ];
  }

  late CompactCorpusIndex idx;
  setUp(() => idx = CompactCorpusIndex.fromSource(FileByteSource.open(asset.path)));
  tearDown(() => idx.close());

  test('shipped asset is a valid LSC1 index with attributions and a matching build id', () {
    expect(asset.existsSync(), isTrue);
    expect(idx.docCount, greaterThan(100));
    expect(idx.fpCount, greaterThan(10000));
    expect((idx.meta['families'] as List).every((f) => (f['attribution'] as String).isNotEmpty && (f['license'] as String).isNotEmpty), isTrue);
    expect(File('assets/source_corpus_v2_attributions.txt').readAsStringSync(), contains('fingerprints'));
    expect(File(CompactCorpusIndex.idAssetPath).readAsStringSync().trim(), hasLength(32));
    expect(asset.lengthSync(), lessThan(40 * 1000 * 1000));
  });

  test('sampled bundled arXiv abstracts are found verbatim and attributed to itself (document level)', () {
    if (!rawArxiv.existsSync()) {
      markTestSkipped('tool/corpus/raw not present');
      return;
    }
    final seed = sampleAbstracts();
    var found = 0;
    var attributed = 0;
    for (final d in seed) {
      final content = (d['content'] as String?) ?? '';
      final tokens = MatchTokenizer.tokenize(content);
      if (tokens.length < 60) continue;
      final reports = idx.reportSources(idx.queryFingerprints(tokens), tokens.length);
      if (reports.isNotEmpty) {
        found++;
        if (idx.docInfo(reports.first.docId).title == d['title']) attributed++;
      }
    }
    expect(found / seed.length, greaterThanOrEqualTo(0.99));
    expect(attributed / found, greaterThanOrEqualTo(0.99));
  });

  test('light edits of bundled abstracts (10% word swaps) are still attributed correctly', () {
    if (!rawArxiv.existsSync()) {
      markTestSkipped('tool/corpus/raw not present');
      return;
    }
    final seed = sampleAbstracts();
    final words = ['system', 'approach', 'results', 'model', 'data', 'method', 'network', 'analysis', 'framework', 'study'];
    var total = 0;
    var ok = 0;
    for (final d in seed) {
      final w = ((d['content'] as String?) ?? '').split(RegExp(r'\s+'));
      if (w.length < 80) continue;
      for (var i = 7; i < w.length; i += 10) {
        w[i] = words[(i ~/ 10) % words.length];
      }
      final text = w.join(' ');
      final tokens = MatchTokenizer.tokenize(text);
      final reports = idx.reportSources(idx.queryFingerprints(tokens), tokens.length);
      total++;
      if (reports.isNotEmpty && idx.docInfo(reports.first.docId).title == d['title']) ok++;
    }
    expect(ok / total, greaterThanOrEqualTo(0.95));
  });

  test('human text never triggers a source; verified verbatim copies of corpus books ARE detected (>=1,000 human texts)', () {
    final files = [
      'tool/eval/data/modern_val.jsonl',
      'tool/eval/data/diverse_val.jsonl',
      'tool/eval/data/academic_val.jsonl',
      'tool/eval/data/modern_test.jsonl',
    ].map(File.new).where((f) => f.existsSync()).toList();
    if (files.isEmpty) {
      markTestSkipped('tool/eval/data not present');
      return;
    }
    // Human samples that are literal excerpts of corpus books (tool/corpus/build/verify_shipped.py): reporting them is correct.
    final copiesJson = jsonDecode(File('tool/corpus/build/tests/shipped_true_copies.json').readAsStringSync()) as Map<String, dynamic>;
    final trueCopies = {for (final c in (copiesJson['true_copies'] as List)) c['md5'] as String};
    var n = 0;
    var copiesSeen = 0;
    var copiesDetected = 0;
    final hits = <String>[];
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        final r = jsonDecode(line) as Map<String, dynamic>;
        if (r['label'] != 0) continue;
        final text = r['text'] as String;
        final tokens = MatchTokenizer.tokenize(text);
        if (tokens.length < 50) continue;
        n++;
        final reports = idx.reportSources(idx.queryFingerprints(tokens), tokens.length);
        if (trueCopies.contains(md5.convert(utf8.encode(text.trim())).toString())) {
          copiesSeen++;
          if (reports.isNotEmpty) copiesDetected++;
        } else if (reports.isNotEmpty) {
          hits.add('${idx.docInfo(reports.first.docId).title} cov=${reports.first.coverage.toStringAsFixed(2)}');
        }
      }
    }
    expect(n, greaterThanOrEqualTo(1000));
    expect(hits, isEmpty, reason: 'false plagiarism accusations: $hits');
    expect(copiesDetected, copiesSeen, reason: 'a verified verbatim copy of a corpus book was not reported');
  });
}
