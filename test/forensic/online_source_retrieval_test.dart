import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/circuit_breaker.dart';
import 'package:lauriva/services/forensic/forensic_coordinator_service.dart';
import 'package:lauriva/services/forensic/sources/online/online_source_search_service.dart';
import 'package:lauriva/services/forensic/sources/online/scholarly_retrievers.dart';
import 'package:lauriva/services/forensic/sources/online/source_retriever.dart';
import 'package:lauriva/services/forensic/sources/online/web_search_retrievers.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';

void main() {
  group('Keyless Online Source Retrievers', () {
    test('WikipediaRetriever parses query results into OnlineSourceHit', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('en.wikipedia.org'));
        expect(request.url.path, equals('/w/api.php'));
        // Primary request is generator=search (intro extracts); an empty answer
        // makes the retriever fall back to the list=search snippet endpoint.
        if (request.url.queryParameters['generator'] == 'search') {
          return http.Response(jsonEncode({'batchcomplete': ''}), 200);
        }
        expect(request.url.queryParameters['list'], equals('search'));

        final sampleJson = {
          'query': {
            'search': [
              {
                'title': 'Photosynthesis and Cellular Respiration',
                'snippet': 'Photosynthesis is the process used by plants to convert <span class="searchmatch">light</span> into chemical energy.',
                'pageid': 12345,
              }
            ]
          }
        };
        return http.Response(jsonEncode(sampleJson), 200);
      });

      final retriever = WikipediaRetriever(client: mockClient);
      expect(retriever.id, equals('wikipedia'));
      expect(retriever.isEnabled, isTrue);

      final hits = await retriever.fetch(const SourceQuery(
        text: 'photosynthesis cellular respiration plants light',
        keywords: ['photosynthesis', 'respiration', 'plants', 'light'],
        sentenceIndex: 0,
      ));

      expect(hits.length, equals(1));
      expect(hits.first.retrieverId, equals('wikipedia'));
      expect(hits.first.title, contains('Photosynthesis'));
      expect(hits.first.url, equals('https://en.wikipedia.org/wiki/Photosynthesis_and_Cellular_Respiration'));
      expect(hits.first.content, contains('Photosynthesis is the process'));
      expect(hits.first.category, equals(SourceCategory.web));
    });

    test('DoajRetriever parses Open Access journal articles correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('doaj.org'));
        expect(request.url.path, contains('/api/v2/search/articles'));

        final sampleJson = {
          'results': [
            {
              'bibjson': {
                'title': 'Quantum Computing in Drug Discovery',
                'abstract': 'We explore variational quantum eigensolvers applied to molecular geometry optimization.',
                'year': 2024,
                'author': [
                  {'name': 'Alice Smith'},
                  {'name': 'Bob Jones'}
                ],
                'identifier': [
                  {'type': 'doi', 'id': '10.1234/doaj.qc.2024'}
                ],
                'link': [
                  {'type': 'fulltext', 'url': 'https://journal.org/qc-drug-discovery.pdf'}
                ]
              }
            }
          ]
        };
        return http.Response(jsonEncode(sampleJson), 200);
      });

      final retriever = DoajRetriever(client: mockClient);
      expect(retriever.id, equals('doaj'));
      expect(retriever.isEnabled, isTrue);

      final hits = await retriever.fetch(const SourceQuery(
        text: 'quantum computing variational eigensolvers molecular geometry',
        keywords: ['quantum', 'computing', 'variational'],
        sentenceIndex: 0,
      ));

      expect(hits.length, equals(1));
      expect(hits.first.title, equals('Quantum Computing in Drug Discovery'));
      expect(hits.first.year, equals(2024));
      expect(hits.first.doi, equals('10.1234/doaj.qc.2024'));
      expect(hits.first.authors, contains('Alice Smith'));
      expect(hits.first.url, contains('doi.org/10.1234/doaj.qc.2024'));
    });

    test('NcbiPubMedRetriever searches and summaries biomedical citations', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('eutils.ncbi.nlm.nih.gov'));

        if (request.url.path.contains('esearch.fcgi')) {
          return http.Response(jsonEncode({
            'esearchresult': {
              'count': '1',
              'idlist': ['99887766'],
            }
          }), 200);
        } else if (request.url.path.contains('esummary.fcgi')) {
          return http.Response(jsonEncode({
            'result': {
              '99887766': {
                'title': 'CRISPR-Cas9 Gene Editing Mechanisms in Oncology',
                'pubdate': '2023 Dec 15',
                'authors': [
                  {'name': 'Jennifer Doudna'},
                  {'name': 'Emmanuelle Charpentier'}
                ],
                'articleids': [
                  {'idtype': 'doi', 'value': '10.1038/s41586-023-0000-0'}
                ]
              }
            }
          }), 200);
        }
        return http.Response('Not found', 404);
      });

      final retriever = NcbiPubMedRetriever(client: mockClient);
      expect(retriever.id, equals('ncbi_pubmed'));
      expect(retriever.isEnabled, isTrue);

      final hits = await retriever.fetch(const SourceQuery(
        text: 'crispr cas9 gene editing mechanisms oncology',
        keywords: ['crispr', 'cas9', 'editing'],
        sentenceIndex: 0,
      ));

      expect(hits.length, equals(1));
      expect(hits.first.title, contains('CRISPR-Cas9'));
      expect(hits.first.year, equals(2023));
      expect(hits.first.doi, equals('10.1038/s41586-023-0000-0'));
      expect(hits.first.authors, contains('Jennifer Doudna'));
    });

    test('WikinewsRetriever parses query results into OnlineSourceHit', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('en.wikinews.org'));
        expect(request.url.path, equals('/w/api.php'));
        if (request.url.queryParameters['generator'] == 'search') {
          return http.Response(jsonEncode({
            'query': {
              'pages': {
                '54321': {
                  'pageid': 54321,
                  'title': 'Global Climate Summit Concludes',
                  'extract': 'Delegates from 190 countries finalized an international agreement on emissions targets today in Geneva.',
                }
              }
            }
          }), 200);
        }
        return http.Response(jsonEncode({'batchcomplete': ''}), 200);
      });

      final retriever = WikinewsRetriever(client: mockClient);
      expect(retriever.id, equals('wikinews'));
      expect(retriever.isEnabled, isTrue);

      final hits = await retriever.fetch(const SourceQuery(
        text: 'global climate summit delegates finalized international agreement',
        keywords: ['climate', 'summit', 'delegates'],
        sentenceIndex: 0,
      ));

      expect(hits.length, equals(1));
      expect(hits.first.retrieverId, equals('wikinews'));
      expect(hits.first.title, contains('Global Climate Summit'));
      expect(hits.first.url, equals('https://en.wikinews.org/wiki/Global_Climate_Summit_Concludes'));
      expect(hits.first.content, contains('Delegates from 190 countries'));
      expect(hits.first.category, equals(SourceCategory.web));
    });

    test('OnlineSourceSearchService.withDefaults contains 8 keyless open backends', () {
      final service = OnlineSourceSearchService.withDefaults();
      final ids = service.retrievers.map((r) => r.id).toList();

      expect(ids, contains('openalex'));
      expect(ids, contains('crossref'));
      expect(ids, contains('arxiv'));
      expect(ids, contains('semantic_scholar'));
      expect(ids, contains('wikipedia'));
      expect(ids, contains('wikinews'));
      expect(ids, contains('doaj'));
      expect(ids, contains('ncbi_pubmed'));
    });

    test('OnlineSourceSearchService generates OpenStax siteFilter query for textbook-like expository text', () async {
      const expositoryText =
          'Cell division is the biological process by which a parent cell divides into two or more daughter cells. '
          'In eukaryotes, there are two distinct types of cell division: a vegetative division, wherein each daughter cell is '
          'genetically identical to the parent cell, and a reproductive division, wherein the number of chromosomes in the daughter cells is reduced by half. '
          'Mitosis and meiosis are the primary mechanisms driving these processes across cellular organisms.';

      final mockClient = MockClient((_) async => http.Response(jsonEncode({'results': []}), 200));
      final service = OnlineSourceSearchService(
        retrievers: [WikipediaRetriever(client: mockClient)],
        overallDeadline: const Duration(seconds: 2),
      );

      final result = await service.search(expositoryText);
      expect(result.queries.any((q) => q.siteFilter == 'openstax.org'), isTrue);
    });

    test('OnlineSourceSearchService skips OpenStax query for first-person text', () async {
      const personalText =
          'In my personal view, I believe that cell division is one of the most fascinating topics that I have studied during my semester. '
          'When I looked into the microscope, my professor asked me to observe the chromosomes, and I realized how intricate the whole process appeared to me. '
          'I spent hours documenting what I observed with my own notes.';

      final mockClient = MockClient((_) async => http.Response(jsonEncode({'results': []}), 200));
      final service = OnlineSourceSearchService(
        retrievers: [WikipediaRetriever(client: mockClient)],
        overallDeadline: const Duration(seconds: 2),
      );

      final result = await service.search(personalText);
      expect(result.queries.any((q) => q.siteFilter == 'openstax.org'), isFalse);
    });

    test('OnlineSourceSearchService fast-breaks and trips long cooldown on HTTP 429', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response('Rate limit exceeded', 429);
      });

      final retriever = WikipediaRetriever(
        client: mockClient,
        breaker: CircuitBreaker(name: 'test_wiki_breaker', failureThreshold: 1),
      );
      final service = OnlineSourceSearchService(
        retrievers: [retriever],
        overallDeadline: const Duration(seconds: 2),
      );

      final result1 = await service.search('Photosynthesis is the process used by plants to convert light into chemical energy.');
      expect(result1.retrieverStats['wikipedia']!['failed'], equals(1));
      // Breaker tripped with long cooldown
      expect(retriever.breaker.isOpen, isTrue);
      expect(callCount, equals(1)); // Only called once (fast-break on 429, no further queries in scan)

      // Subsequent search immediately skips the retriever without issuing network calls
      final result2 = await service.search('Another query about cell biology and cellular respiration in eukaryotic cells.');
      expect(result2.retrieverStats['wikipedia']!['skipped'], equals(1));
      expect(callCount, equals(1)); // No additional HTTP requests
    });

    test('ForensicCoordinatorService populates online documents into source evidence', () async {
      const copiedPassage =
          'Photosynthesis is the specialized biochemical process used by photosynthetic organisms to convert electromagnetic radiant energy into stable chemical bonds.';

      final mockClient = MockClient((request) async {
        if (request.url.host == 'en.wikipedia.org') {
          return http.Response(jsonEncode({
            'query': {
              'search': [
                {
                  'title': 'Photosynthesis and Biochemical Energy',
                  'snippet': copiedPassage,
                  'pageid': 111,
                }
              ]
            }
          }), 200);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      });

      final onlineService = OnlineSourceSearchService(
        retrievers: [WikipediaRetriever(client: mockClient)],
        overallDeadline: const Duration(seconds: 2),
      );

      final coordinator = ForensicCoordinatorService(onlineSearchService: onlineService);

      final report = await coordinator.coordinate(
        text: copiedPassage,
        mode: ForensicScanMode.fullForensic,
      );

      expect(report, isNotNull);
      // Online Wikipedia hit is incorporated into the search repository
      expect(SourceRepository.baselineLiterature.documents.any((d) => d.title.contains('Wikipedia')), isTrue);
    });
  });
}
