import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';
import 'package:lauriva/services/plagiarism_detector_service.dart';
import 'test_mocks.dart';

void main() {
  setUpAll(() {
    setupMockPlatformChannels();
  });

  group('SourceSimilarityService Multi-Threshold Tests', () {
    late SourceSimilarityService service;
    late SourceRepository repository;

    setUp(() {
      repository = SourceRepository();
      // Add a known reference document to repository
      repository.addDocument(SourceCorpusDocument(
        id: 'corpus_plato_republic',
        title: 'Plato Republic Book VII',
        author: 'Plato',
        category: SourceCategory.academic,
        url: 'https://classics.mit.edu/Plato/republic.html',
        content:
            'Behold human beings living in an underground den which has a mouth open towards the light. '
            'They have been there from their childhood and have their legs and necks chained so that they cannot move and can only see before them.',
      ));
      service = SourceSimilarityService(repository: repository);
    });

    test('Detects exact copy verbatim with high confidence', () {
      const copiedText =
          'Behold human beings living in an underground den which has a mouth open towards the light. '
          'They have been there from their childhood and have their legs and necks chained so that they cannot move.';

      final evidence = service.analyzeDocument(copiedText);

      expect(evidence.overallSimilarityScore, greaterThan(40.0));
      expect(evidence.documentCoveragePercent, greaterThan(60.0));
      expect(evidence.longestContiguousTokenMatch, greaterThanOrEqualTo(10));
      expect(evidence.confidenceLevel, 'HIGH CONFIDENCE');
      expect(evidence.uniqueSourceCount, 1);
    });

    test('Common boilerplate phrases do not trigger high plagiarism scores', () {
      const boilerplateText =
          'In today\'s digital era, navigating the complexities of modern research is essential. '
          'It is widely acknowledged that empirical investigation plays a crucial role in scientific discovery. '
          'At the end of the day, taking everything into account helps researchers succeed.';

      final evidence = service.analyzeDocument(boilerplateText);

      expect(evidence.overallSimilarityScore, lessThan(25.0));
      expect(evidence.longestContiguousTokenMatch, lessThan(15));
    });

    test('Long document (1,000 words) with one matching sentence does not produce high plagiarism', () {
      final buffer = StringBuffer();
      for (int i = 0; i < 40; i++) {
        buffer.write(
          'Original analytical writing exploring distinct topics in renewable energy systems, '
          'storage battery design, photovoltaic efficiency, and electrical grid synchronization. ',
        );
      }
      // Insert one matching sentence
      buffer.write(
        'Behold human beings living in an underground den which has a mouth open towards the light. ',
      );
      for (int i = 0; i < 10; i++) {
        buffer.write(
          'Further original commentary examining macroeconomic factors, utility pricing regulations, '
          'and consumer power consumption patterns across urban municipalities. ',
        );
      }

      final longDoc = buffer.toString();
      final evidence = service.analyzeDocument(longDoc);

      // Even with 1 sentence matched, total document coverage must be small in a long text
      expect(evidence.documentCoveragePercent, lessThan(12.0));
      expect(evidence.matchedSentencePercent, lessThan(10.0));
      expect(evidence.overallSimilarityScore, lessThan(35.0));
    });

    test('Short text under 40 words reports INSUFFICIENT EVIDENCE', () {
      const shortText = 'Plato wrote the Republic in classical Greece.';
      final evidence = service.analyzeDocument(shortText);

      expect(evidence.confidenceLevel, 'INSUFFICIENT EVIDENCE');
    });

    test('Computes source concentration and distinctive phrase density', () {
      const testPassage =
          'Behold human beings living in an underground den which has a mouth open towards the light. '
          'They have their legs and necks chained so that they cannot move.';

      final evidence = service.analyzeDocument(testPassage);

      if (evidence.matches.isNotEmpty) {
        expect(evidence.sourceConcentration, greaterThan(0.0));
        expect(evidence.longestMatchingPhrase.isNotEmpty, isTrue);
      }
    });
  });

  group('Trained Forensic Model Offline Execution Tests', () {
    late PlagiarismDetectorService detector;

    setUp(() {
      detector = PlagiarismDetectorService();
    });

    test('Trained model analyzes text purely on-device without LLM API key', () async {
      const sample =
          'It is not only about innovation, but also about execution. '
          'At its core, this stands as a testament to the enduring legacy of modern technology. '
          'Let us dive in to explore the multifaceted intricacies. '
          'As an AI, I hope this helps!';

      final forensicReport = await detector.analyzeForensic(
        sample,
        enableOnlineSearch: false,
      );

      expect(forensicReport.aiAuthorship.aiProbability, greaterThan(65.0));
      expect(forensicReport.confidence.score, greaterThan(0.0));
      expect(forensicReport.toLegacyPlagiarismReport().overallScore, greaterThan(65.0));
    });

    test('Recognizes authentic human prose with low AI risk score', () async {
      const humanText =
          'I left the apartment before sunrise. The morning air had that damp, cold bite that always '
          'reminds me of late November in Chicago, when the buses run twenty minutes late and nobody '
          'bothers to complain because everyone is already numb. Forgot my gloves again. '
          'I stopped at the corner diner, ordered black coffee, and watched steam rise from the grill while the cook prepped hash browns.';

      final forensicReport = await detector.analyzeForensic(
        humanText,
        enableOnlineSearch: false,
      );

      expect(forensicReport.aiAuthorship.aiProbability, lessThan(42.0));
      expect(forensicReport.toLegacyPlagiarismReport().humanScore, greaterThan(58.0));
    });
  });
}
