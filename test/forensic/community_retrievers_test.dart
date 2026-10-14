import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/forensic/sources/online/community_retrievers.dart';
import 'package:lauriva/services/forensic/sources/online/source_retriever.dart';

const _query = SourceQuery(
  text: 'photosynthesis plants convert light energy chemical energy',
  keywords: ['photosynthesis', 'plants', 'chlorophyll'],
  sentenceIndex: 0,
  exactPhrase: 'convert light energy into chemical energy',
);

const _plainQuery = SourceQuery(
  text: 'how to sort a list in dart quickly',
  keywords: ['sort', 'list', 'dart'],
  sentenceIndex: 1,
);

final _seBody = jsonEncode({
  'items': [
    {
      'item_type': 'answer',
      'question_id': 1234,
      'answer_id': 5678,
      'title': 'How do plants make &quot;food&quot; &amp; energy?',
      'excerpt':
          'Plants <span class="highlight">convert light energy into chemical energy</span> during photosynthesis &#39;in chloroplasts&#39;.',
      'body': '<p>Plants convert light energy into chemical energy during photosynthesis.</p>',
    },
    {
      'item_type': 'question',
      'question_id': 99,
      'title': 'Excerpt only',
      'excerpt': 'Light is <span class="highlight">converted</span> &lt;sic&gt; to sugar',
    },
    {'item_type': 'question', 'question_id': 100, 'title': 'No content'},
  ],
  'has_more': false,
  'quota_max': 300,
  'quota_remaining': 290,
});

final _hnBody = jsonEncode({
  'hits': [
    {
      'objectID': '111',
      'comment_text':
          'Photosynthesis is the process where light energy is converted into chemical energy,<p>stored in glucose &amp; other sugars by plants.',
      'story_title': 'Ask HN: How do plants work?',
    },
    {
      'objectID': '222',
      'title': 'A story title',
      'story_text':
          '<p>This story body is long enough to pass the twelve word minimum filter for hits, easily.</p>',
    },
    {'objectID': '333', 'comment_text': 'Too short to matter.', 'story_title': 'x'},
    {
      'objectID': '444',
      'comment_text': 'Another sufficiently long comment about photosynthesis converting light energy into stored chemical energy today.',
    },
  ],
});

void main() {
  group('StackExchangeRetriever', () {
    test('siteFor and sitesFor map topics and default to stackoverflow', () {
      expect(StackExchangeRetriever.siteFor('photosynthesis in plants'), 'biology');
      expect(StackExchangeRetriever.siteFor('the roman empire fell'), 'history');
      expect(StackExchangeRetriever.siteFor('kant and ethics'), 'philosophy');
      expect(StackExchangeRetriever.siteFor('how to sort a list'), 'stackoverflow');
      expect(StackExchangeRetriever.siteFor('baking bread with yeast and flour'), 'cooking');
      expect(StackExchangeRetriever.siteFor('pruning tomato plants in the garden'), 'gardening');
      expect(StackExchangeRetriever.siteFor('visa requirements for airline flight'), 'travel');
      expect(StackExchangeRetriever.sitesFor('photosynthesis in garden plants'), containsAll(['biology', 'gardening']));
    });

    test('parseResponse strips markup, prefers body, builds URLs, skips empty', () {
      final r = StackExchangeRetriever(client: MockClient((_) async => http.Response('', 500)));
      final hits = r.parseResponse(_seBody, site: 'biology');
      expect(hits.length, 2);
      expect(hits[0].title, 'How do plants make "food" & energy?');
      expect(hits[0].content, 'Plants convert light energy into chemical energy during photosynthesis.');
      expect(hits[0].url, 'https://biology.stackexchange.com/questions/1234');
      expect(hits[1].content, 'Light is converted <sic> to sugar.');
      expect(hits[1].retrieverId, 'stackexchange');
      expect(r.parseResponse(_seBody).first.url, 'https://stackoverflow.com/questions/1234');
    });

    test('empty results parse to no hits', () {
      final r = StackExchangeRetriever(client: MockClient((_) async => http.Response('', 500)));
      expect(r.parseResponse(jsonEncode({'items': [], 'has_more': false})), isEmpty);
    });

    test('error payload and backoff throw', () {
      final r = StackExchangeRetriever(client: MockClient((_) async => http.Response('', 500)));
      expect(
        () => r.parseResponse(jsonEncode({'error_id': 502, 'error_name': 'throttle_violation', 'error_message': 'too many'})),
        throwsA(isA<StateError>()),
      );
      expect(() => r.parseResponse(jsonEncode({'items': [], 'backoff': 10})), throwsA(isA<StackExchangeBackoff>()));
      expect(() => r.parseResponse('[1]'), throwsFormatException);
    });

    test('search sends quoted phrase, candidate sites in parallel and limit', () async {
      final seenUrls = <Uri>[];
      final r = StackExchangeRetriever(
        client: MockClient((req) async {
          seenUrls.add(req.url);
          return http.Response(_seBody, 200);
        }),
        minInterval: Duration.zero,
      );
      final outcome = await r.search(_query, limit: 3);
      expect(outcome.succeeded, isTrue);
      expect(outcome.hits.length, 4); // 2 hits from each of top 2 parallel queried sites
      expect(seenUrls.length, 2);
      final seen = seenUrls.first;
      expect(seen.host, 'api.stackexchange.com');
      expect(seen.path, '/2.3/search/excerpts');
      expect(seen.queryParameters['q'], '"convert light energy into chemical energy"');
      expect(seenUrls.map((u) => u.queryParameters['site']), containsAll(['biology', 'gardening']));
      expect(seen.queryParameters['pagesize'], '3');
      expect(seen.queryParameters['sort'], 'relevance');
      expect(r.maxQueriesPerScan, 2);
    });

    test('plain query uses text and default site; backoff fails the outcome and suppresses retries', () async {
      var calls = 0;
      Uri? seen;
      final r = StackExchangeRetriever(
        client: MockClient((req) async {
          calls++;
          seen = req.url;
          return http.Response(jsonEncode({'items': [], 'backoff': 30}), 200);
        }),
        minInterval: Duration.zero,
      );
      final first = await r.search(_plainQuery);
      expect(seen!.queryParameters['q'], _plainQuery.text);
      expect(seen!.queryParameters['site'], 'stackoverflow');
      expect(first.succeeded, isFalse);
      final second = await r.search(_plainQuery);
      expect(second.succeeded, isFalse);
      expect(calls, 1);
    });

    test('HTTP errors fail the outcome', () async {
      final r = StackExchangeRetriever(client: MockClient((_) async => http.Response('no', 400)), minInterval: Duration.zero);
      final outcome = await r.search(_query);
      expect(outcome.succeeded, isFalse);
      expect(outcome.error, contains('400'));
    });
  });

  group('HackerNewsRetriever', () {
    test('parseResponse maps comments and stories, skips short hits', () {
      final r = HackerNewsRetriever(client: MockClient((_) async => http.Response('', 500)));
      final hits = r.parseResponse(_hnBody);
      expect(hits.length, 3);
      expect(hits[0].title, 'Ask HN: How do plants work?');
      expect(hits[0].content, contains('stored in glucose & other sugars'));
      expect(hits[0].url, 'https://news.ycombinator.com/item?id=111');
      expect(hits[1].title, 'A story title');
      expect(hits[2].title, 'Hacker News comment');
      expect(hits.every((h) => h.retrieverId == 'hackernews'), isTrue);
    });

    test('empty and error payloads', () {
      final r = HackerNewsRetriever(client: MockClient((_) async => http.Response('', 500)));
      expect(r.parseResponse(jsonEncode({'hits': []})), isEmpty);
      expect(() => r.parseResponse(jsonEncode({'message': 'Rate limit exceeded'})), throwsA(isA<StateError>()));
    });

    test('search builds the Algolia request', () async {
      Uri? seen;
      final r = HackerNewsRetriever(
        client: MockClient((req) async {
          seen = req.url;
          return http.Response(_hnBody, 200);
        }),
        minInterval: Duration.zero,
      );
      final outcome = await r.search(_query, limit: 4);
      expect(outcome.succeeded, isTrue);
      expect(seen!.host, 'hn.algolia.com');
      expect(seen!.path, '/api/v1/search');
      expect(seen!.queryParameters['tags'], '(story,comment)');
      expect(seen!.queryParameters['hitsPerPage'], '4');
      expect(seen!.queryParameters['query'], '"convert light energy into chemical energy"');
      expect(r.maxQueriesPerScan, 2);
    });

    test('HTTP 429 fails the outcome', () async {
      final r = HackerNewsRetriever(client: MockClient((_) async => http.Response('', 429)), minInterval: Duration.zero);
      expect((await r.search(_plainQuery)).succeeded, isFalse);
    });
  });
}
