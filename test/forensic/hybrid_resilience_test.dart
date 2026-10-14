import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/circuit_breaker.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/sources/compact_corpus_index.dart';
import 'package:lauriva/services/forensic/sources/corpus_delivery_service.dart';
import 'package:lauriva/services/forensic/sources/online/keyless_web_retrievers.dart';
import 'package:lauriva/services/forensic/sources/online/online_source_search_service.dart';
import 'package:lauriva/services/forensic/sources/online/scholarly_retrievers.dart';
import 'package:lauriva/services/forensic/sources/online/source_retriever.dart';
import 'package:lauriva/services/forensic/sources/online/web_search_retrievers.dart';

/// A client whose requests never complete (dead Wi-Fi / captive portal).
class _HangingClient extends http.BaseClient {
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return Completer<http.StreamedResponse>().future;
  }
}

/// Every keyless retriever, with throttles zeroed and short timeouts so tests stay fast.
List<SourceRetriever> _allRetrievers(http.Client c, {Duration timeout = const Duration(seconds: 1)}) => [
      DuckDuckGoInstantRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      WikipediaRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      BingWebRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      BraveWebRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      ExaMcpRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      EuropePmcRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      OpenAlexRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      CrossrefRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      DoajRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      NcbiPubMedRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      SemanticScholarRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
      ArxivRetriever(client: c, timeout: timeout, minInterval: Duration.zero),
    ];

const _turingPassage =
    'I propose to consider the question, "Can machines think?" This should begin with definitions of the meaning of the terms "machine" and "think". '
    'The new form of the problem can be described in terms of a game which we call the \'imitation game\'. '
    'It is played with three people, a man (A), a woman (B), and an interrogator (C) who may be of either sex.';

const _copiedPassage =
    'Photosynthesis is the specialized biochemical process used by photosynthetic organisms to convert electromagnetic radiant energy into stable chemical bonds.';

const _originalProse =
    'Harbour pilots in the northern archipelago memorised tidal eddies by singing counted verses, a custom that outlasted every printed chart. '
    'Their apprentices rowed lanterns across the estuary each solstice, learning where silt shoals migrated after autumn storms. '
    'Cartographers who visited later complained that the oral instructions contradicted survey measurements by nearly forty metres.';

const _capturedSentences = <String>[
  'Glaciologists measuring the retreat of alpine tongues discovered that moraine boulders carry cosmogenic beryllium signatures older than previously assumed.',
  'Medieval guild ledgers from Antwerp record fluctuating pepper tariffs alongside meticulous annotations about harbour congestion and seasonal quarantine rules.',
  'Quantum annealing hardware struggles with embedding dense graphs because physical qubit connectivity remains sparse compared with logical problem structure.',
  'Fermented cassava processing in coastal communities reduces cyanogenic glycosides through carefully timed soaking, pressing, and roasting sequences handed down orally.',
  'Urban heat islands intensify nocturnal temperatures whenever impervious asphalt surfaces release stored radiation long after sunset has passed.',
  'Neuroscientists recorded hippocampal place cells while rodents navigated elevated mazes containing deliberately ambiguous landmarks and shifting reward locations.',
  'Seventeenth century Dutch tulip speculation remains a popular cautionary example although historians dispute how severe the actual financial collapse became.',
  'Mycorrhizal networks beneath temperate forests redistribute phosphorus between neighbouring saplings, which complicates simple competitive models of woodland succession.',
  'Contemporary typographers debate whether variable fonts genuinely improve readability or merely complicate rendering pipelines across heterogeneous mobile devices.',
  'Archaeologists excavating Bronze Age smelting sites found slag deposits indicating surprisingly sophisticated control of furnace temperature and ore selection.',
];

String _bigDocument() {
  final b = StringBuffer();
  for (var round = 0; round < 3; round++) {
    for (final s in _capturedSentences) {
      // Vary each repetition so no two sentences are identical.
      b.write(round == 0 ? s : s.replaceFirst(RegExp(r'^\w+'), ['Recent', 'Several', 'Many'][round]));
      b.write(' ');
    }
    if (round == 0) {
      b.write('Please contact jane.doe@university-mail.edu or visit https://example.org/private-portal/session?id=88231 '
          'with reference 4111111111111111 and phone +1 555 123 4567 regarding this manuscript. ');
    }
    b.write('\n\n');
  }
  return b.toString();
}

String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cacheFiles = [
    File(CompactCorpusIndex.cachePath),
    File('${CompactCorpusIndex.cachePath}.id'),
    File('${CompactCorpusIndex.cachePath}.tmp'),
  ];

  tearDown(() {
    CompactCorpusIndex.install(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
  });

  group('1. Airplane mode', () {
    test('service: every retriever failing yields empty documents and per-retriever failure stats, no throw', () async {
      var calls = 0;
      final offline = MockClient((_) async {
        calls++;
        throw calls.isOdd ? http.ClientException('Network is unreachable') : const SocketException('Failed host lookup');
      });
      final service = OnlineSourceSearchService(
        retrievers: _allRetrievers(offline),
        overallDeadline: const Duration(seconds: 3),
      );
      final result = await service.search(_bigDocument());

      expect(result.documents, isEmpty);
      expect(result.hits, isEmpty);
      expect(result.deadlineExceeded, isFalse);
      expect(result.retrieverStats.length, 12);
      for (final entry in result.retrieverStats.entries) {
        expect(entry.value['ok'], 0, reason: entry.key);
        expect(entry.value['failed'], greaterThan(0), reason: entry.key);
      }
    });

    test('coordinator: scan completes and still finds in-memory seed corpus matches', () async {
      final offline = MockClient((_) async => throw http.ClientException('offline'));
      final coordinator = ForensicCoordinatorService(
        onlineSearchService: OnlineSourceSearchService(
          retrievers: _allRetrievers(offline),
          overallDeadline: const Duration(seconds: 3),
        ),
      );
      final report = await coordinator.coordinate(text: _turingPassage, mode: ForensicScanMode.sourceScan);

      expect(report.sourceSimilarity.matches, isNotEmpty);
      expect(report.sourceSimilarity.matches.any((m) => m.sourceTitle.contains('Turing')), isTrue);
      expect(report.sourceSimilarity.overallSimilarityScore, greaterThan(0));
    });
  });

  group('2. Hung network', () {
    test('service returns within overallDeadline with deadlineExceeded and no documents', () async {
      final hung = _HangingClient();
      final service = OnlineSourceSearchService(
        retrievers: _allRetrievers(hung, timeout: const Duration(seconds: 5)),
        overallDeadline: const Duration(milliseconds: 400),
      );
      final sw = Stopwatch()..start();
      final result = await service.search(_bigDocument());
      sw.stop();

      expect(result.deadlineExceeded, isTrue);
      expect(result.documents, isEmpty);
      expect(hung.requests, greaterThan(0), reason: 'requests really were issued and left hanging');
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('coordinator returns a full report promptly when the service deadline fires '
        '(its own fixed backstop is 8s fullForensic / 10s sourceScan, not injectable)', () async {
      final hung = _HangingClient();
      final coordinator = ForensicCoordinatorService(
        onlineSearchService: OnlineSourceSearchService(
          retrievers: _allRetrievers(hung, timeout: const Duration(seconds: 5)),
          overallDeadline: const Duration(milliseconds: 400),
        ),
      );
      final sw = Stopwatch()..start();
      final report = await coordinator.coordinate(text: _turingPassage, mode: ForensicScanMode.fullForensic);
      sw.stop();

      expect(report, isNotNull);
      expect(report.sourceSimilarity.matches.any((m) => m.sourceTitle.contains('Turing')), isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 7)), reason: 'must beat the 8s coordinator backstop');
    });

    test('deadline keeps partial results from fast retrievers while another hangs', () async {
      final fast = MockClient((r) async => http.Response(
            jsonEncode({
              'query': {
                'search': [
                  {'title': 'Photosynthesis and Biochemical Energy', 'snippet': _copiedPassage, 'pageid': 111}
                ]
              }
            }),
            200,
          ));
      final hung = _HangingClient();
      final service = OnlineSourceSearchService(
        retrievers: [
          WikipediaRetriever(client: fast, minInterval: Duration.zero),
          CrossrefRetriever(client: hung, timeout: const Duration(seconds: 5), minInterval: Duration.zero),
        ],
        overallDeadline: const Duration(milliseconds: 500),
      );
      final result = await service.search('$_copiedPassage Chloroplast membranes arrange pigment complexes into densely stacked thylakoid lamellae.');
      expect(result.deadlineExceeded, isTrue);
      expect(result.documents, isNotEmpty);
      expect(result.documents.first.content, contains('photosynthetic organisms'));
    });
  });

  group('3. Partial failure', () {
    http.Client mixedClient(List<String> seen) => MockClient((request) async {
          seen.add(request.url.host);
          switch (request.url.host) {
            case 'en.wikipedia.org':
              return http.Response(
                  jsonEncode({
                    'query': {
                      'search': [
                        {'title': 'Photosynthesis and Biochemical Energy', 'snippet': _copiedPassage, 'pageid': 111}
                      ]
                    }
                  }),
                  200);
            case 'www.bing.com':
              return http.Response('Internal error', 500);
            case 'search.brave.com':
              throw http.ClientException('connection reset');
            default:
              return http.Response('boom', 503);
          }
        });

    test('copied passage is attributed to the online source; failing retrievers show failed counts', () async {
      final seen = <String>[];
      final c = mixedClient(seen);
      final service = OnlineSourceSearchService(
        retrievers: [
          WikipediaRetriever(client: c, minInterval: Duration.zero),
          BingWebRetriever(client: c, minInterval: Duration.zero),
          BraveWebRetriever(client: c, minInterval: Duration.zero),
          CrossrefRetriever(client: c, minInterval: Duration.zero),
        ],
        overallDeadline: const Duration(seconds: 3),
      );
      final coordinator = ForensicCoordinatorService(onlineSearchService: service);
      final report = await coordinator.coordinate(text: _copiedPassage, mode: ForensicScanMode.sourceScan);

      expect(report.sourceSimilarity.matches.any((m) => m.sourceTitle.contains('Photosynthesis and Biochemical Energy')), isTrue,
          reason: 'online Wikipedia hit must be attributed despite 3 failing retrievers');

      final stats = (await service.search('$_copiedPassage Another sentence about thylakoid stacking in chloroplast lamellae.')).retrieverStats;
      expect(stats['wikipedia']!['ok']! + stats['wikipedia']!['cached']!, greaterThan(0));
      for (final id in ['bing', 'brave_web', 'crossref']) {
        expect(stats[id]!['ok'], 0, reason: id);
        expect(stats[id]!['failed']! + stats[id]!['skipped']!, greaterThan(0), reason: id);
      }
    });

    test('breaker opens after repeated failures and later queries are skipped without hitting the network', () async {
      var requests = 0;
      final failing = MockClient((_) async {
        requests++;
        return http.Response('err', 500);
      });
      final retriever = CrossrefRetriever(
        client: failing,
        minInterval: Duration.zero,
        breaker: CircuitBreaker(name: 'hybrid_test_crossref', failureThreshold: 2, cooldownDuration: const Duration(minutes: 5)),
      );
      final service = OnlineSourceSearchService(retrievers: [retriever], overallDeadline: const Duration(seconds: 2));
      final doc = _bigDocument();

      final first = await service.search(doc);
      expect(first.retrieverStats['crossref']!['failed'], 2, reason: 'a retriever is abandoned after 2 failures per scan');
      expect(retriever.breaker.isOpen, isTrue);
      final afterFirst = requests;

      final second = await service.search(doc);
      expect(second.retrieverStats['crossref']!['skipped'], greaterThan(0));
      expect(second.retrieverStats['crossref']!['failed'], 0);
      expect(requests, afterFirst, reason: 'open breaker must short-circuit before any request');
    });
  });

  group('4. Rate-limit / captcha responses', () {
    const captchaHtml = '<html><body><h1>Please verify you are a human</h1><form action="/captcha"></form></body></html>';

    for (final scenario in <String, http.Response Function()>{
      'HTTP 429': () => http.Response('Too Many Requests', 429),
      'HTTP 202 challenge': () => http.Response(captchaHtml, 202),
      '200 captcha HTML': () => http.Response(captchaHtml, 200),
    }.entries) {
      test('Bing and Brave ${scenario.key}: failure outcome, not cached as "no sources", re-queried', () async {
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return scenario.value();
        });
        final bing = BingWebRetriever(client: client, minInterval: Duration.zero);
        final brave = BraveWebRetriever(client: client, minInterval: Duration.zero);

        const q = SourceQuery(
          text: 'photosynthetic organisms convert electromagnetic radiant energy',
          keywords: ['photosynthetic', 'electromagnetic', 'radiant'],
          sentenceIndex: 0,
          exactPhrase: 'photosynthetic organisms convert electromagnetic radiant energy',
        );
        for (final r in [bing, brave]) {
          final o = await r.search(q);
          expect(o.succeeded, isFalse, reason: '${r.id} ${scenario.key}');
          expect(o.skipped, isFalse);
          expect(o.error, isNotNull);
        }

        final service = OnlineSourceSearchService(
          retrievers: [
            BingWebRetriever(client: client, minInterval: Duration.zero, breaker: CircuitBreaker(name: 'h4b', failureThreshold: 50)),
            BraveWebRetriever(client: client, minInterval: Duration.zero, breaker: CircuitBreaker(name: 'h4r', failureThreshold: 50)),
          ],
          overallDeadline: const Duration(seconds: 2),
        );
        final doc = _bigDocument();
        final first = await service.search(doc);
        expect(first.documents, isEmpty);
        expect(service.cache.length, 0, reason: 'failures must never be cached as an empty answer');
        expect(first.retrieverStats['bing']!['failed'], greaterThan(0));
        final afterFirst = requests;

        final second = await service.search(doc);
        expect(requests, greaterThan(afterFirst), reason: 'second search must go back to the network');
        expect(second.retrieverStats['bing']!['cached'], 0);
        expect(second.retrieverStats['brave_web']!['cached'], 0);
      });
    }
  });

  group('5. No offline corpus and online disabled', () {
    test('scan completes with "no meaningful similarity" and without any request', () async {
      for (final f in cacheFiles) {
        if (f.existsSync()) f.deleteSync();
      }
      CompactCorpusIndex.install(null);
      // Make the bundled asset unavailable so ensureReady() cannot extract the corpus.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (_) async => null);

      var requests = 0;
      final spy = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      final coordinator = ForensicCoordinatorService(
        onlineSearchService: OnlineSourceSearchService(retrievers: _allRetrievers(spy)),
      );

      expect(await CompactCorpusIndex.ensureReady(), isNull);
      expect(CompactCorpusIndex.current, isNull);

      final report = await coordinator.coordinate(
        text: _originalProse,
        mode: ForensicScanMode.sourceScan,
        enableOnlineSearch: false,
      );
      expect(report, isNotNull);
      expect(report.sourceSimilarity.matches, isEmpty);
      expect(report.sourceSimilarity.overallSimilarityScore, 0);
      expect(report.sourceSimilarity.defensibleSummary, contains('No meaningful external source similarity'));
      expect(requests, 0, reason: 'online search disabled: nothing may be sent');
    });

    test('CorpusDeliveryService.ensureInBackground is a no-op under FLUTTER_TEST', () async {
      expect(Platform.environment.containsKey('FLUTTER_TEST'), isTrue);
      var requests = 0;
      final spy = MockClient((_) async {
        requests++;
        return http.Response('x', 200);
      });
      CorpusDeliveryService.ensureInBackground(client: spy);
      CorpusDeliveryService.ensureInBackground(client: spy);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests, 0);
      expect(File('${CompactCorpusIndex.cachePath}.tmp').existsSync(), isFalse);
    });
  });

  group('6. Privacy bound', () {
    test('no request carries >40 words of the document, nor emails / URLs / long digit runs', () async {
      final captured = <String>[];
      final client = MockClient((request) async {
        final body = request.body;
        captured.add('${Uri.decodeFull(request.url.toString().replaceAll('+', ' '))} $body');
        return http.Response('{}', 200);
      });
      final doc = _bigDocument();
      final docWords = _normalize(doc).split(' ');
      expect(docWords.length, greaterThan(300));

      final service = OnlineSourceSearchService(
        retrievers: _allRetrievers(client),
        overallDeadline: const Duration(seconds: 3),
      );
      await service.search(doc);
      expect(captured.length, greaterThan(10), reason: 'search must really have issued requests');

      const window = 41;
      for (final raw in captured) {
        final req = _normalize(raw);
        for (var i = 0; i + window <= docWords.length; i++) {
          expect(req.contains(docWords.sublist(i, i + window).join(' ')), isFalse,
              reason: 'request leaks a $window-word contiguous window: $raw');
        }
        final lower = raw.toLowerCase();
        expect(lower, isNot(contains('jane.doe')));
        expect(lower, isNot(contains('university-mail')));
        expect(lower, isNot(contains('example.org')));
        expect(lower, isNot(contains('private-portal')));
        expect(RegExp(r'\d{7,}').hasMatch(raw.replaceAll(RegExp(r'[\s().-]'), '')), isFalse, reason: 'long digit run in: $raw');
        expect(lower, isNot(contains('4111')));
        expect(lower, isNot(contains('555 123')));
      }
    });
  });
}
