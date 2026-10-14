import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/forensic/sources/online/keyless_web_retrievers.dart';
import 'package:lauriva/services/forensic/sources/online/online_source_search_service.dart';
import 'package:lauriva/services/forensic/sources/online/source_retriever.dart';

const _query = SourceQuery(
  text: 'photosynthesis plants convert light energy chemical energy',
  keywords: ['photosynthesis', 'plants', 'chlorophyll'],
  sentenceIndex: 0,
  exactPhrase: 'convert light energy into chemical energy',
);

const _bingPage = '''
<ol id="b_results">
<li class="b_algo" data-id><style>.x{}</style><div class="b_richcard">card without a heading</div></li>
<li class="b_algo" data-id><div class="b_algoheader"><a href="https://sciencenotes.org/photosynthesis/" h="1"><h2 class="">Photosynthesis &#8211; Definition</h2></a></div>
<div class="b_caption"><p class="b_lineclamp3"><span class="news_dt">Nov 18, 2025</span>&nbsp;&#0183;&#32;Photosynthesis is a process that plants use for converting light energy into chemical energy.</p></div></li>
<li class="b_algo" data-id><h2><a href="https://www.bing.com/ck/a?!&amp;u=a1aHR0cHM6Ly9lbi53aWtpcGVkaWEub3JnL3dpa2kvUGhvdG9zeW50aGVzaXM&amp;ntb=1">Photosynthesis - Wikipedia</a></h2>
<div class="b_caption"><p>Photosynthesis is a system of biological processes by which light energy is converted.</p></div></li>
</ol>''';

const _bravePage = '''
<div class="snippet svelte-x" data-pos="1" data-type="web"><a href="https://www.sciencing.com/plant-energy/" class="l1"><div class="title search-snippet-title svelte-y">How A Plant Converts Light</div></a>
<div class="generic-snippet"><div class="content desktop svelte-z"><span>30 August 2022 -</span> The energy coming into the plant cell is <strong>converted into chemical energy</strong>.</div></div></div>
<div class="snippet svelte-x" data-pos="2" data-type="web"><a href="https://allen.in/qna/1" class="l1"><div class="title svelte-y">Allen answer</div></a>
<div class="content svelte-z">Photosynthesis changes light energy into chemical energy.</div></div>
<div class="snippet svelte-x" data-pos="3" data-type="video"><a href="https://video.example/1"><div class="title">ignored</div></a></div>''';

http.Client _client(String Function(Uri) body, {int status = 200}) =>
    MockClient((req) async => http.Response(body(req.url), status));

void main() {
  group('BingWebRetriever', () {
    test('parses results, skips headingless cards, unwraps redirects, strips dates', () {
      final hits = BingWebRetriever(client: _client((_) => '')).parse(_bingPage);
      expect(hits.length, 2);
      expect(hits[0].url, 'https://sciencenotes.org/photosynthesis/');
      expect(hits[0].title, contains('Definition'));
      expect(hits[0].content, startsWith('Photosynthesis is a process'));
      expect(hits[1].url, 'https://en.wikipedia.org/wiki/Photosynthesis');
    });

    test('quotes the exact phrase and sends a browser UA', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(_bingPage, 200);
      });
      final outcome = await BingWebRetriever(client: client).search(_query);
      expect(outcome.succeeded, isTrue);
      expect(seen.url.host, 'www.bing.com');
      expect(seen.url.queryParameters['q'], '"convert light energy into chemical energy"');
      expect(seen.headers['User-Agent'], contains('Mozilla/5.0'));
    });

    test('challenge page fails (not cached as "no sources"); genuine empty page succeeds', () async {
      final blocked = await BingWebRetriever(client: _client((_) => '<html>captcha</html>')).search(_query);
      expect(blocked.succeeded, isFalse);
      final empty = await BingWebRetriever(client: _client((_) => '<li class="b_no">No results found</li>')).search(_query);
      expect(empty.succeeded, isTrue);
      expect(empty.hits, isEmpty);
    });

    test('unwrapRedirect leaves normal and malformed URLs alone', () {
      expect(BingWebRetriever.unwrapRedirect('https://example.com/a'), 'https://example.com/a');
      expect(BingWebRetriever.unwrapRedirect('https://www.bing.com/ck/a?u=zzz'), isNull);
      expect(BingWebRetriever.unwrapRedirect(null), isNull);
    });
  });

  group('BraveWebRetriever', () {
    test('parses web results only and strips date prefixes', () {
      final hits = BraveWebRetriever(client: _client((_) => '')).parse(_bravePage);
      expect(hits.length, 2);
      expect(hits[0].url, 'https://www.sciencing.com/plant-energy/');
      expect(hits[0].title, 'How A Plant Converts Light');
      expect(hits[0].content, startsWith('The energy coming into the plant cell'));
      expect(hits[1].content, 'Photosynthesis changes light energy into chemical energy.');
    });

    test('respects the result limit', () {
      expect(BraveWebRetriever(client: _client((_) => '')).parse(_bravePage, limit: 1).length, 1);
    });
  });

  group('EuropePmcRetriever', () {
    test('parses abstracts, authors, year, DOI and PMC link', () async {
      final body = jsonEncode({
        'resultList': {
          'result': [
            {
              'title': '<i>CDE6</i> regulates chloroplasts',
              'abstractText': 'Chloroplasts carry out photosynthesis and convert light energy',
              'authorString': 'Yang S, Li B.',
              'pubYear': '2026',
              'doi': '10.3390/plants15020284',
              'pmcid': 'PMC12845262',
            },
            {'title': 'No abstract', 'abstractText': ''},
          ]
        }
      });
      final outcome = await EuropePmcRetriever(client: _client((_) => body)).search(_query);
      expect(outcome.hits.length, 1);
      final h = outcome.hits.single;
      expect(h.title, 'CDE6 regulates chloroplasts');
      expect(h.authors, ['Yang S', 'Li B']);
      expect(h.year, 2026);
      expect(h.url, 'https://europepmc.org/article/PMC/PMC12845262');
    });
  });


  group('ExaMcpRetriever', () {
    String sse(Map<String, dynamic> payload) => 'event: message\ndata: ${jsonEncode(payload)}\n\n';
    final ok = sse({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {
        'content': [
          {
            'type': 'text',
            'text': 'Title: 8.2 Light-Dependent Reactions\nURL: https://openstax.org/books/biology-2e/pages/8-2\nPublished: N/A\nAuthor: N/A\nHighlights:\nLight energy is converted into chemical energy, which photoautotrophs use to build carbohydrate molecules.\n...\nPigments absorb specific wavelengths of visible light.\n\n---\n\n'
                'Title: No highlights page\nURL: https://example.org/x\nPublished: N/A\n\n---\n\n'
                'Title: Second Source\nURL: https://example.org/second\nHighlights:\nPlants convert sunlight into sugar during photosynthesis.',
          }
        ]
      },
    });

    test('parses SSE results, skips entries without highlights, posts a web_search_exa call', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(ok, 200);
      });
      final outcome = await ExaMcpRetriever(client: client).search(_query);
      expect(outcome.succeeded, isTrue);
      expect(outcome.hits.length, 2);
      expect(outcome.hits[0].title, '8.2 Light-Dependent Reactions');
      expect(outcome.hits[0].url, 'https://openstax.org/books/biology-2e/pages/8-2');
      expect(outcome.hits[0].content, contains('Light energy is converted into chemical energy'));
      expect(outcome.hits[0].content, contains('Pigments absorb specific wavelengths'));
      expect(outcome.hits[1].url, 'https://example.org/second');

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(seen.url.host, 'mcp.exa.ai');
      expect(body['params']['name'], 'web_search_exa');
      expect((body['params']['arguments']['query'] as String), startsWith('"convert light energy into chemical energy"'));
      expect(seen.headers['Accept'], contains('text/event-stream'));
    });

    test('plain JSON bodies parse too; errors and rate limits fail instead of caching "no sources"', () async {
      final plain = jsonEncode({
        'result': {
          'content': [
            {'type': 'text', 'text': 'Title: T\nURL: https://e.org/a\nHighlights:\nSome matching passage text here.'}
          ]
        }
      });
      expect((await ExaMcpRetriever(client: _client((_) => plain)).search(_query)).hits.length, 1);
      expect((await ExaMcpRetriever(client: _client((_) => '', status: 429)).search(_query)).succeeded, isFalse);
      expect((await ExaMcpRetriever(client: _client((_) => sse({'error': {'code': -32000}}))).search(_query)).succeeded, isFalse);
      expect((await ExaMcpRetriever(client: _client((_) => 'garbage')).search(_query)).succeeded, isFalse);
    });
  });

  test('default deadline stays under the coordinator timeouts so partial results survive', () {
    final s = OnlineSourceSearchService.withDefaults();
    expect(s.overallDeadline, lessThan(const Duration(seconds: 8)));
    expect(s.overallDeadline + s.enrichmentBudget, lessThan(const Duration(seconds: 8)));
  });

  test('default service includes keyless web search and survives total network failure', () async {
    final ids = OnlineSourceSearchService.withDefaults().retrievers.map((r) => r.id);
    expect(ids, containsAll(['bing', 'brave_web', 'exa', 'stackexchange', 'hackernews', 'europe_pmc', 'wikipedia', 'openalex']));

    final offline = OnlineSourceSearchService.withDefaults(client: MockClient((_) async => throw http.ClientException('offline')));
    final result = await offline.search(
        'Photosynthesis is the specialized biochemical process used by photosynthetic organisms to convert electromagnetic radiant energy into stable chemical bonds. '
        'This reaction sequence occurs within the thylakoid membranes of chloroplasts across many plant species worldwide.');
    expect(result.documents, isEmpty);
  });
}
