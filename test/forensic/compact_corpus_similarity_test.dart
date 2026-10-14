import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/sources/compact_corpus_index.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';

const _dir = 'tool/corpus/build/tests/fixture';

void main() {
  final blob = File('$_dir/index.lsc').readAsBytesSync();
  final fixture = jsonDecode(File('$_dir/queries.json').readAsStringSync()) as Map<String, dynamic>;
  final queries = (fixture['queries'] as List).cast<Map<String, dynamic>>();
  final expected = (fixture['expected'] as List).cast<Map<String, dynamic>>();
  late SourceSimilarityService service;

  setUp(() {
    CompactCorpusIndex.install(CompactCorpusIndex.fromSource(MemoryByteSource(blob)));
    // Only the compact index may contribute: no seed corpus in the repository.
    service = SourceSimilarityService(repository: SourceRepository(loadDefaultCorpus: false));
  });
  tearDown(() => CompactCorpusIndex.install(null));

  int firstWith(String prefix) => queries.indexWhere((q) => (q['label'] as String).startsWith(prefix) && (expected[queries.indexOf(q)]['reports'] as List).isNotEmpty);

  test('verbatim copy is reported with the right source title, a derived URL and query-sourced text', () {
    final i = firstWith('verbatim');
    final text = queries[i]['text'] as String;
    final evidence = service.analyzeDocument(text);
    expect(evidence.matches, isNotEmpty);
    expect(evidence.matches.first.sourceTitle, expected[i]['top_title']);
    expect(evidence.matches.first.sourceUrl, startsWith('https://example.org/'));
    for (final m in evidence.matches) {
      expect(text.contains(m.matchedText), isTrue, reason: 'snippets must be cut from the query, never the source');
      expect(m.sourceExcerpt, isNull);
    }
    expect(evidence.documentCoveragePercent, greaterThan(40));
    expect(evidence.overallSimilarityScore, greaterThan(40));
  });

  test('every fixture positive the index reports surfaces its title in the evidence', () {
    var checked = 0;
    for (var i = 0; i < queries.length; i++) {
      final reports = expected[i]['reports'] as List;
      if (queries[i]['true_doc'] as int < 0 || reports.isEmpty) continue;
      final evidence = service.analyzeDocument(queries[i]['text'] as String);
      expect(evidence.matches.map((m) => m.sourceTitle), contains(expected[i]['top_title']), reason: queries[i]['label']);
      checked++;
    }
    expect(checked, greaterThan(15));
  });

  test('unrelated text and text the index does not report stay clean', () {
    var checked = 0;
    for (var i = 0; i < queries.length; i++) {
      if ((expected[i]['reports'] as List).isNotEmpty) continue;
      final evidence = service.analyzeDocument(queries[i]['text'] as String);
      expect(evidence.matches.where((m) => m.sourceTitle.contains('fixture doc')), isEmpty, reason: queries[i]['label']);
      checked++;
    }
    expect(checked, greaterThan(20));
  });

  test('a properly quoted and cited passage earns citation credit (low score)', () {
    final i = firstWith('verbatim');
    final copied = queries[i]['text'] as String;
    final text = 'As the author argues, "$copied" (Smith, 2020).';
    final evidence = service.analyzeDocument(text);
    expect(evidence.matches, isNotEmpty);
    expect(evidence.overallSimilarityScore, lessThan(15));
  });

  test('without an installed index the service behaves as before', () {
    CompactCorpusIndex.install(null);
    final evidence = SourceSimilarityService(repository: SourceRepository(loadDefaultCorpus: false))
        .analyzeDocument(queries[firstWith('verbatim')]['text'] as String);
    expect(evidence.matches.where((m) => m.sourceTitle.contains('fixture doc')), isEmpty);
    expect(evidence.overallSimilarityScore, 0.0);
  });
}
