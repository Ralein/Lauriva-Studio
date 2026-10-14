import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lauriva/services/ai_forensic_service.dart';
import 'package:lauriva/services/forensic/humanizer/algorithmic_humanizer_service.dart';
import 'package:lauriva/services/forensic/humanizer/semantic_preservation_verifier.dart';
import 'package:lauriva/services/forensic/sources/online/source_retriever.dart';
import 'package:lauriva/services/forensic/sources/online/web_search_retrievers.dart';

void main() {
  group('SSS+ Tier 10/10 Functional Backend Upgrades', () {
    test('SemanticPreservationVerifier recognizes all-caps acronyms at sentence starts', () {
      final verifier = SemanticPreservationVerifier();
      const orig = 'NASA developed this algorithm. The GDP grew by 4% in 2023.';
      const rewritten = 'NASA built this method. The GDP increased by 4% in 2023.';

      final report = verifier.verify(originalText: orig, humanizedText: rewritten);

      expect(report.preservedEntities, contains('NASA'));
      expect(report.preservedEntities, contains('GDP'));
      expect(report.missingEntities, isEmpty);
      expect(report.hasNumericalDrift, isFalse);
      expect(report.verdict, equals(SemanticPreservationVerdict.excellent));
    });

    test('AlgorithmicHumanizerService dissolves modern AI platitudes and wrap-up cliches', () {
      const humanizer = AlgorithmicHumanizerService();
      const input = 'This project stands at the forefront of innovation. '
          'In doing so, they pave the way for a brighter future. '
          'Testing is an integral part of the equation.';

      final result = humanizer.postProcess(input);

      expect(result.toLowerCase(), isNot(contains('stands at the forefront of innovation')));
      expect(result.toLowerCase(), isNot(contains('pave the way for a brighter future')));
      expect(result.toLowerCase(), isNot(contains('integral part of the equation')));
      expect(result, contains('leads in innovation'));
      expect(result, contains('helps future progress'));
      expect(result, contains('essential'));
    });

    test('AlgorithmicHumanizerService diversifies consecutive sentence starters', () {
      const humanizer = AlgorithmicHumanizerService();
      const input = 'This model analyzes writing patterns. This approach ensures high fidelity across documents.';

      final result = humanizer.diversifyConsecutiveSentenceStarters(input);

      expect(result, equals('This model analyzes writing patterns. The approach ensures high fidelity across documents.'));
    });

    test('WikipediaRetriever queries exact phrase with fallback', () async {
      final requestedQueries = <String>[];
      final mockClient = MockClient((request) async {
        final queryParam = request.url.queryParameters['gsrsearch'] ?? request.url.queryParameters['srsearch'] ?? '';
        requestedQueries.add(queryParam);

        if (queryParam.startsWith('"')) {
          // Simulate exact match hit on the primary generator=search request
          return http.Response(
            jsonEncode({
              'query': {
                'pages': {
                  '1': {
                    'title': 'Quantum Computing',
                    'extract': 'Quantum computing is a rapidly-emerging technology that harnesses quantum mechanics.',
                  }
                }
              }
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'query': {'search': []}}), 200);
      });

      final retriever = WikipediaRetriever(client: mockClient);
      const query = SourceQuery(
        text: 'quantum computing technology harnesses quantum mechanics',
        keywords: ['quantum', 'computing', 'mechanics'],
        sentenceIndex: 0,
        exactPhrase: 'quantum computing technology',
      );

      final hits = await retriever.fetch(query);

      expect(hits, hasLength(1));
      expect(hits.first.title, contains('Quantum Computing'));
      expect(requestedQueries.first, equals('"quantum computing technology"'));
    });

    test('postProcessWithQualityLoop executes adaptive high-entropy pass on high AI probability', () {
      const humanizer = AlgorithmicHumanizerService();
      final forensic = AiForensicService();
      final verifier = SemanticPreservationVerifier();

      // Heavily synthetic AI paragraph
      const aiInput = 'In today’s rapidly evolving digital landscape, it is important to note that '
          'this pivotal framework serves as a testament to innovation, highlighting the importance of progress. '
          'Furthermore, this framework serves as a testament to engineering excellence.';

      final result = humanizer.postProcessWithQualityLoop(
        aiInput,
        originalText: aiInput,
        forensicService: forensic,
        verifier: verifier,
      );

      expect(result.toLowerCase(), isNot(contains('rapidly evolving digital landscape')));
      expect(result.toLowerCase(), isNot(contains('it is important to note that')));
      expect(result.toLowerCase(), isNot(contains('serves as a testament to')));
      expect(result.toLowerCase(), isNot(contains('highlighting the importance of')));
      expect(result.toLowerCase(), isNot(contains('furthermore')));
    });
  });
}
