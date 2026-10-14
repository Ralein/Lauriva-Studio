// Adversarial Robustness and False-Positive Protection Test Suite
// Verifies plan2.md Sections 46-47, 68-69 for Lauriva Forensic Content Intelligence 3.0.

import 'package:lauriva/models/forensic/ai_authorship_evidence.dart';
import 'package:lauriva/models/forensic/confidence_assessment.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Adversarial Robustness & False-Positive Protection Suite', () {
    late ForensicEngine engine;
    late SourceRepository repository;

    setUp(() {
      repository = SourceRepository(loadDefaultCorpus: true);
      engine = ForensicEngine(
        similarityService: SourceSimilarityService(repository: repository),
      );
    });

    group('False Positive Protection (Plan2 Section 47)', () {
      test('Formal academic writing does NOT trigger false-positive AI classification', () {
        const academicPaper =
            'The empirical distribution of word frequencies in natural language corpora has long been observed to follow a power law, as originally formulated by Zipf. In this study, we evaluate whether vocabulary richness estimators such as the moving-average type-token ratio retain stability across heterogenous sample lengths. Our findings demonstrate that window-length calibration is required to mitigate sample-size bias.';

        final report = engine.analyze(academicPaper);

        // Academic prose has high formality, but must NOT be classified as likely AI
        expect(report.aiAuthorship.authorshipClass, isNot(equals(AuthorshipClass.likelyAi)),
            reason: 'Formal academic writing must not be falsely flagged as likely AI');
        expect(report.aiAuthorship.aiProbability, lessThan(65.0));
      });

      test('Technical engineering documentation does NOT trigger false-positive AI classification', () {
        const technicalDoc =
            'We benchmarked the SQLite connection pool under a simulated burst of fifty concurrent write transactions. Latency spiked sharply past the thirty-second threshold due to file lock contention on macOS, whereas Linux handled the queue with minimal disk I/O stall.';

        final report = engine.analyze(technicalDoc);

        expect(report.aiAuthorship.authorshipClass, isNot(equals(AuthorshipClass.likelyAi)),
            reason: 'Technical documentation with specific system metrics must not be falsely flagged as AI');
        expect(report.aiAuthorship.aiProbability, lessThan(60.0));
      });

      test('ESL non-native English writing is protected from false-positive AI classification', () {
        const eslText =
            'In my country we usually take coffee after lunch and stay talking for one hour minimum. Here everybody is in rush, take plastic cup and walk fast to office. At first I found it very strange, but now when calendar is full I understand why people do like this.';

        final report = engine.analyze(eslText);

        expect(report.aiAuthorship.authorshipClass, isNot(equals(AuthorshipClass.likelyAi)),
            reason: 'Non-native English phrasing must not be penalized into AI classification');
        expect(report.aiAuthorship.aiProbability, lessThan(55.0));
      });

      test('Short text produces high uncertainty and length-gating', () {
        const shortNote = 'The system architecture handles fifty requests per second.';

        final report = engine.analyze(shortNote);

        // Uncertainty must be elevated and confidence must not be high
        expect(report.confidence.uncertainty, greaterThanOrEqualTo(0.50),
            reason: 'Short text (<50 words) must report high statistical uncertainty');
        expect(report.confidence.level, isNot(equals(ForensicConfidenceLevel.high)));
      });

      test('Academic citation and quotation is classified as cited, not uncited plagiarism', () {
        const citedText =
            'As argued in seminal literature: "I propose to consider the question, Can machines think?" (Turing, 1950). This remains central to computational cognitive science.';

        final report = engine.analyze(citedText);

        final matches = report.sourceSimilarity.matches;
        expect(matches, isNotEmpty, reason: 'Must match Turing document in baseline repository');
        final turingMatch = matches.firstWhere((m) => m.sourceTitle.toLowerCase().contains('turing'));

        // Citation awareness must classify as cited/quoted
        expect(
          turingMatch.citationStatus,
          anyOf(equals(CitationStatus.quotedAndCited), equals(CitationStatus.quoted), equals(CitationStatus.cited)),
          reason: 'Passage in quotation marks with citation must be recognized as legitimate citation',
        );
      });
    });

    group('Adversarial & Mixed AI Discrimination (Plan2 Sections 46, 5-9)', () {
      test('Detects standard AI scaffolding with transition tells and uniform triad rhythm', () {
        const standardAiText =
            'Let us dive in to explore the multifaceted intricacies of modern productivity. It is not only about managing your time, but also about cultivating a holistic mindset that fosters sustainable growth. Moreover, this approach underscores the importance of balance — a concept that resonates deeply in today\'s fast-paced world. Furthermore, the platform delivers innovation, efficiency, and scalability, bolstering user confidence across every touchpoint. In conclusion, this tool stands as a testament to the evolving landscape of digital transformation.';

        final report = engine.analyze(standardAiText);

        expect(report.aiAuthorship.aiProbability, greaterThanOrEqualTo(65.0));
        expect(report.aiAuthorship.authorshipClass, equals(AuthorshipClass.likelyAi));
        expect(report.aiAuthorship.detectedSignals, isNotEmpty);
      });

      test('Detects verbatim plagiarism against indexed literature without conflating it with AI', () {
        const verbatimPassage =
            'I propose to consider the question, "Can machines think?" This should begin with definitions of the meaning of the terms "machine" and "think". The definitions might be framed so as to reflect so far as possible the normal use of the words.';

        final report = engine.analyze(verbatimPassage);

        expect(report.sourceSimilarity.overallSimilarityScore, greaterThanOrEqualTo(65.0));
        expect(report.sourceSimilarity.matches, isNotEmpty);
        expect(report.sourceSimilarity.matches.first.sourceTitle, contains('Turing'));
        expect(
          report.sourceSimilarity.matches.first.matchType,
          anyOf(equals(SourceMatchType.exact), equals(SourceMatchType.shingleOverlap)),
        );

        // Plagiarism and AI must be independent dimensions
        expect(report.sourceSimilarity.overallSimilarityScore, isNot(equals(report.aiAuthorship.aiProbability)));
      });

      test('Mixed-authorship document correctly identifies style shifts and mixed class', () {
        const mixedDoc =
            // Human Narrative Opening (Casual, high burstiness)
            'I left the apartment before sunrise. The morning air had that damp, cold bite that always reminds me of late November in Chicago. Forgot my gloves again. Stopped at the diner, ordered black coffee, watched steam rise from the grill. '
            // AI Generated Continuation (Triad, stock tells, low variance)
            'Furthermore, the platform delivers innovation, efficiency, and scalability, bolstering user confidence across every touchpoint. Additionally, it plays a pivotal role in streamlining workflows for teams of any size. In conclusion, this tool stands as a testament to the evolving landscape of digital transformation.';

        final report = engine.analyze(mixedDoc);

        expect(report.aiAuthorship.windows.length, greaterThanOrEqualTo(2));
        // Authorship class should identify mixed / edited origin rather than 100% human or pure AI
        expect(
          report.aiAuthorship.authorshipClass,
          anyOf(equals(AuthorshipClass.mixedOrEdited), equals(AuthorshipClass.likelyAi)),
        );
      });
    });
  });
}
