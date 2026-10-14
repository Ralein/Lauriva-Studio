import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/forensic/sources/online/online_source_search_service.dart';
import 'package:lauriva/services/forensic/sources/online/source_page_enricher.dart';
import 'package:lauriva/services/forensic/sources/online/source_retriever.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';
import 'package:lauriva/services/reach/reach_models.dart';

class FakeReader implements PageReader {
  final Map<String, String> pages;
  final Object? error;
  final Duration delay;
  List<String> requested = [];
  int calls = 0;

  FakeReader(this.pages, {this.error, this.delay = Duration.zero});

  @override
  Future<Map<String, ReachPage>> readMany(List<String> urls,
      {int maxChars = 60000, Duration deadline = const Duration(seconds: 8), int concurrency = 3}) async {
    calls++;
    requested = List.of(urls);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return {
      for (final u in urls)
        if (pages.containsKey(u)) u: ReachPage(url: u, title: 't', text: pages[u]!, via: 'fake'),
    };
  }

  @override
  Future<ReachPage?> read(String url, {int maxChars = 60000}) async => null;

  @override
  Future<List<ChannelHealth>> doctor() async => const [];
}

const _passage =
    'Coral reefs are among the most biologically diverse ecosystems on the planet, sheltering roughly a quarter of all marine species '
    'despite covering less than one percent of the ocean floor. Rising sea temperatures cause corals to expel the symbiotic algae living '
    'in their tissues, a process known as bleaching that leaves colonies pale and vulnerable to disease. Repeated bleaching events across '
    'the last decade have devastated reef systems from the Caribbean to the Great Barrier Reef, and recovery typically requires many years '
    'of stable conditions. Ocean acidification compounds the problem because lower carbonate availability slows the growth of the calcium '
    'skeletons that build reef structures. Local pressures such as nutrient runoff, destructive fishing and coastal development further '
    'weaken resilience, which means that protecting water quality and managing fisheries can buy reefs valuable time while global emissions '
    'are reduced. Restoration projects that transplant heat tolerant fragments show promise, although scientists caution that they cannot '
    'replace ambitious climate action over the coming decades.';

String _filler(int chars, [String seed = 'lorem']) {
  final sb = StringBuffer();
  var i = 0;
  while (sb.length < chars) {
    sb.write('$seed${i % 97}x harbor ledger${i % 31} quartz meadow$i drifts beyond ');
    i++;
  }
  return sb.toString().substring(0, chars);
}

SourceCorpusDocument _doc(String id, String content,
    {String? url, SourceCategory category = SourceCategory.web}) {
  return SourceCorpusDocument(id: id, title: 'Title $id', url: url, category: category, content: content);
}

String _firstSentence() => '${_passage.split('. ').first}.';

void main() {
  group('SourcePageEnricher candidate choice', () {
    test('fetches only high-overlap web docs; skips academic, url-less and unrelated', () async {
      final reader = FakeReader({'https://a.example/p': '${_filler(500)} $_passage'});
      final docs = [
        _doc('web', _firstSentence(), url: 'https://a.example/p'),
        _doc('acad', _firstSentence(), url: 'https://b.example/p', category: SourceCategory.academic),
        _doc('nourl', _firstSentence()),
        _doc('ftp', _firstSentence(), url: 'ftp://c.example/p'),
        _doc('unrelated', _filler(400), url: 'https://d.example/p'),
      ];
      final out = await SourcePageEnricher(reader: reader).enrich(_passage, docs);
      expect(reader.requested, ['https://a.example/p']);
      expect(out.map((d) => d.id), docs.map((d) => d.id));
      expect(out.map((d) => d.url), docs.map((d) => d.url));
      expect(out.map((d) => d.title), docs.map((d) => d.title));
      expect(out[0].content, contains('Restoration projects'));
      for (var i = 1; i < docs.length; i++) {
        expect(identical(out[i], docs[i]), isTrue);
      }
    });

    test('respects maxPages and takes the strongest snippets first', () async {
      final sentences = _passage.split('. ');
      final docs = [
        for (var i = 0; i < 6; i++)
          _doc('d$i', sentences.take(1 + i).join('. '), url: 'https://s$i.example/p'),
      ];
      final reader = FakeReader({for (final d in docs) d.url!: '${_filler(300)} $_passage'});
      await SourcePageEnricher(reader: reader, maxPages: 2).enrich(_passage, docs);
      expect(reader.requested.length, 2);
      expect(reader.requested, containsAll(['https://s5.example/p', 'https://s4.example/p']));
    });

    test('respects maxTotalChars', () async {
      final docs = [
        for (var i = 0; i < 3; i++) _doc('d$i', _firstSentence(), url: 'https://t$i.example/p'),
      ];
      final page = '$_passage ${_filler(3000)}';
      final reader = FakeReader({for (final d in docs) d.url!: page});
      final enricher = SourcePageEnricher(reader: reader, maxTotalChars: 5000, maxCharsPerPage: 2500);
      final out = await enricher.enrich(_passage, docs);
      final total = out.fold<int>(0, (a, d) => a + (identical(d, docs[out.indexOf(d)]) ? 0 : d.content.length));
      expect(total, lessThanOrEqualTo(5000));
      expect(out.where((d) => d.content.length > 1000).length, 2);
      expect(out.every((d) => d.content.length <= 2500 || d.content.length == docs[0].content.length), isTrue);
    });
  });

  group('SourcePageEnricher replacement', () {
    test('page text raises end-to-end coverage versus the snippet alone', () async {
      final doc = _doc('wiki', _firstSentence(), url: 'https://reefs.example/article');
      final page = '${_filler(1500, 'intro')} $_passage ${_filler(1500, 'outro')}';
      final enricher = SourcePageEnricher(reader: FakeReader({doc.url!: page}));
      final out = await enricher.enrich(_passage, [doc]);
      expect(enricher.lastEnrichedCount, 1);

      double coverage(SourceCorpusDocument d) {
        final repo = SourceRepository(loadDefaultCorpus: false)..addDocument(d);
        return SourceSimilarityService(repository: repo).analyzeDocument(_passage).documentCoveragePercent;
      }

      final before = coverage(doc);
      final after = coverage(out.single);
      // ignore: avoid_print
      print('coverage snippet=$before page=$after');
      expect(after, greaterThan(before + 30));
      expect(after, greaterThan(70));
    });

    test('keeps the snippet when the page matches less', () async {
      final doc = _doc('wiki', _passage.split('. ').take(4).join('. '), url: 'https://x.example/p');
      final page = '${_filler(4000)} ${_passage.split('. ').first}.';
      final out = await SourcePageEnricher(reader: FakeReader({doc.url!: page})).enrich(_passage, [doc]);
      expect(identical(out.single, doc), isTrue);
    });

    test('reader failure, timeout and empty map leave docs untouched', () async {
      final doc = _doc('w', _firstSentence(), url: 'https://x.example/p');
      final docs = [doc];
      expect(identical((await SourcePageEnricher(reader: FakeReader({}, error: StateError('boom'))).enrich(_passage, docs))[0], doc), isTrue);
      expect(identical((await SourcePageEnricher(reader: FakeReader({})).enrich(_passage, docs))[0], doc), isTrue);
      final slow = SourcePageEnricher(
        reader: FakeReader({doc.url!: _passage}, delay: const Duration(seconds: 2)),
        budget: const Duration(milliseconds: 50),
      );
      final sw = Stopwatch()..start();
      final out = await slow.enrich(_passage, docs);
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(identical(out[0], doc), isTrue);
    });
  });

  group('OnlineSourceSearchService integration', () {
    final client = MockClient((_) async => http.Response('', 500));

    OnlineSourceSearchService build(PageReader? reader) => OnlineSourceSearchService(
          retrievers: [_FixedRetriever(_firstSentence())],
          pageReader: reader,
        );

    test('null pageReader keeps snippet documents', () async {
      final r = await build(null).search(_passage);
      expect(r.documents.length, 1);
      expect(r.documents.single.content, _firstSentence());
      expect(r.enrichedPages, 0);
    });

    test('pageReader enriches and reports the count', () async {
      final reader = FakeReader({'https://reefs.example/a': '${_filler(800)} $_passage'});
      final r = await build(reader).search(_passage);
      expect(r.enrichedPages, 1);
      expect(r.documents.single.content, contains('Restoration projects'));
    });

    test('throwing reader does not break search', () async {
      final r = await build(FakeReader({}, error: StateError('x'))).search(_passage);
      expect(r.documents.length, 1);
      expect(r.enrichedPages, 0);
    });

    test('withDefaults budgets total under the coordinator timeout', () {
      final s = OnlineSourceSearchService.withDefaults(client: client);
      expect(s.overallDeadline + s.enrichmentBudget, lessThan(const Duration(seconds: 8)));
    });
  });

  test('aligner stays fast on 4 x 60k-char enriched pages', () {
    final docs = [
      for (var i = 0; i < 4; i++)
        _doc('big$i', '${_filler(30000, 'a$i')} $_passage ${_filler(30000 - _passage.length, 'b$i')}',
            url: 'https://big$i.example/p'),
    ];
    final sw = Stopwatch()..start();
    final repo = SourceRepository(loadDefaultCorpus: false);
    for (final d in docs) {
      repo.addDocument(d);
    }
    final evidence = SourceSimilarityService(repository: repo).analyzeDocument(_passage);
    sw.stop();
    // ignore: avoid_print
    print('aligner 4x60k end-to-end ms=${sw.elapsedMilliseconds}');
    expect(evidence.documentCoveragePercent, greaterThan(70));
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });
}

class _FixedRetriever extends SourceRetriever {
  final String snippet;
  _FixedRetriever(this.snippet) : super(client: MockClient((_) async => http.Response('', 500)), name: 'fixed');

  @override
  String get id => 'fixed';

  @override
  Future<List<OnlineSourceHit>> fetch(SourceQuery query, {int limit = 5}) async => [
        OnlineSourceHit(
          retrieverId: 'fixed',
          title: 'Reefs article',
          content: snippet,
          url: 'https://reefs.example/a',
          category: SourceCategory.web,
        ),
      ];
}
