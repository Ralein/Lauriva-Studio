import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/sources/compact_corpus_index.dart';
import 'package:lauriva/services/forensic/sources/match_tokenizer.dart';
import 'package:lauriva/services/forensic/sources/winnowing_engine.dart';

const _dir = 'tool/corpus/build/tests/fixture';

class _MapBundle extends CachingAssetBundle {
  final Map<String, Uint8List> files;
  _MapBundle(this.files);

  @override
  Future<ByteData> load(String key) async {
    final f = files[key];
    if (f == null) throw FlutterError('missing $key');
    return ByteData.sublistView(f);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final blob = File('$_dir/index.lsc').readAsBytesSync();
  final info = jsonDecode(File('$_dir/index_info.json').readAsStringSync()) as Map<String, dynamic>;
  final fixture = jsonDecode(File('$_dir/queries.json').readAsStringSync()) as Map<String, dynamic>;
  final queries = (fixture['queries'] as List).cast<Map<String, dynamic>>();
  final expected = (fixture['expected'] as List).cast<Map<String, dynamic>>();

  late CompactCorpusIndex idx;
  setUp(() => idx = CompactCorpusIndex.fromSource(MemoryByteSource(blob)));

  test('header and doc table parse identically to the Python writer', () {
    expect(idx.fpCount, info['fp_count']);
    expect(idx.blockSize, info['block_size']);
    expect(idx.docCount, info['doc_count']);
    expect(idx.k, 4);
    expect(idx.w, 4);
    expect(idx.hashBits, 28);
    (info['sample_docs'] as Map<String, dynamic>).forEach((id, d) {
      final got = idx.docInfo(int.parse(id));
      expect(got.title, d['title']);
      expect(got.family, d['family']);
      expect(got.key, d['key']);
      expect(got.url, startsWith('https://example.org/'));
    });
  });

  test('every probed hash resolves to exactly its documents; absent hashes resolve to none', () {
    for (final p in (info['probe_present'] as List)) {
      expect(idx.docsForTruncatedHash(p[0] as int), (p[1] as List).cast<int>());
    }
    for (final h in (info['probe_absent'] as List)) {
      expect(idx.docsForTruncatedHash(h as int), isEmpty);
    }
  });

  test('decisions equal the Python reference on every fixture query', () {
        for (var i = 0; i < queries.length; i++) {
      final tokens = MatchTokenizer.tokenize(queries[i]['text'] as String);
      final fps = idx.queryFingerprints(tokens);
      final reports = idx.reportSources(fps, tokens.length);
      final exp = expected[i];
      expect(fps.length, exp['n_fps'], reason: exp['label']);
      final expReports = (exp['reports'] as List).cast<Map<String, dynamic>>();
      expect(reports.length >= expReports.length, isTrue, reason: exp['label']);
      for (var j = 0; j < expReports.length; j++) {
        expect(reports[j].docId, expReports[j]['doc'], reason: '${exp['label']}#$j');
        expect(reports[j].coveredTokens, expReports[j]['covered'], reason: '${exp['label']}#$j');
        expect(reports[j].coverage, closeTo((expReports[j]['coverage'] as num).toDouble(), 1e-12));
      }
      if (expReports.isEmpty) expect(reports, isEmpty, reason: exp['label']);
      if (expReports.isNotEmpty) expect(idx.docInfo(reports.first.docId).title, exp['top_title']);
    }
  });

  test('file-backed source gives the same answers as the in-memory source', () {
    final tmp = File('${Directory.systemTemp.path}/lsc_test_${DateTime.now().microsecondsSinceEpoch}.lsc')..writeAsBytesSync(blob);
    try {
      final fileIdx = CompactCorpusIndex.fromSource(FileByteSource.open(tmp.path));
      for (var i = 0; i < queries.length; i += 3) {
        final tokens = MatchTokenizer.tokenize(queries[i]['text'] as String);
        final fps = idx.queryFingerprints(tokens);
        final a = idx.reportSources(fps, tokens.length).map((r) => '${r.docId}:${r.coveredTokens}').toList();
        final b = fileIdx.reportSources(fps, tokens.length).map((r) => '${r.docId}:${r.coveredTokens}').toList();
        expect(b, a);
      }
      fileIdx.close();
    } finally {
      tmp.deleteSync();
    }
  });

  test('edited copies are attributed to the right source; unrelated text reports nothing', () {
    var positives = 0;
    var correct = 0;
    for (var i = 0; i < queries.length; i++) {
      final trueDoc = queries[i]['true_doc'] as int;
      final tokens = MatchTokenizer.tokenize(queries[i]['text'] as String);
      final reports = idx.reportSources(idx.queryFingerprints(tokens), tokens.length);
      if (trueDoc >= 0) {
        positives++;
        if (reports.isNotEmpty && reports.first.docId == trueDoc) correct++;
      }
    }
    expect(correct, positives); // verbatim, 10-15% swaps, reorder, light synonyms
    final short = MatchTokenizer.tokenize('too short');
    expect(idx.reportSources(idx.queryFingerprints(short), short.length), isEmpty);
  });

  test('rejects data that is not an LSC1 index', () {
    expect(() => CompactCorpusIndex.fromSource(MemoryByteSource(Uint8List(200))), throwsFormatException);
  });

  test('truncateHash matches the Python mixing function', () {
    expect(CompactCorpusIndex.truncateHash(0x811C9DC5, 32), 0x811C9DC5);
    for (final h in [0, 1, 0xFFFFFFFF, 0x811C9DC5]) {
      expect(CompactCorpusIndex.truncateHash(h, 24), lessThan(1 << 24));
    }
    expect(CompactCorpusIndex.truncateHash(1, 28), (((1 * 0x9E3779B1) & 0xFFFFFFFF) >> 4));
  });

  test('ensureReady extracts the bundled asset once and opens it for any isolate', () async {
    final cacheFile = File(CompactCorpusIndex.cachePath);
    final sideFile = File('${CompactCorpusIndex.cachePath}.id');
    if (cacheFile.existsSync()) cacheFile.deleteSync();
    if (sideFile.existsSync()) sideFile.deleteSync();
    CompactCorpusIndex.install(null);
    final bundle = _MapBundle({
      CompactCorpusIndex.assetPath: blob,
      CompactCorpusIndex.idAssetPath: Uint8List.fromList(utf8.encode('test-build-id')),
    });
    final opened = await CompactCorpusIndex.ensureReady(bundle: bundle);
    expect(opened, isNotNull);
    expect(cacheFile.lengthSync(), blob.length);
    expect(sideFile.readAsStringSync(), 'test-build-id');
    expect(CompactCorpusIndex.current, same(opened));
    // second call with a changed asset id re-extracts
    CompactCorpusIndex.install(null);
    final bundle2 = _MapBundle({
      CompactCorpusIndex.assetPath: blob,
      CompactCorpusIndex.idAssetPath: Uint8List.fromList(utf8.encode('other-id')),
    });
    await CompactCorpusIndex.ensureReady(bundle: bundle2);
    expect(sideFile.readAsStringSync(), 'other-id');
    CompactCorpusIndex.install(null);
    cacheFile.deleteSync();
    sideFile.deleteSync();
    expect(await CompactCorpusIndex.ensureReady(bundle: _MapBundle({})), isNull); // no corpus bundled -> null, no throw
  });

  test('WinnowingEngine instance parameters follow the index header', () {
    expect(idx.engine.k, idx.k);
    expect(idx.engine.w, idx.w);
    expect(WinnowingEngine(k: idx.k, w: idx.w).guaranteedDetectionThreshold, idx.w + idx.k - 1);
  });
}
