import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/services/forensic/forensic_engine.dart';
import 'package:lauriva/services/forensic/sources/fuzzy_similarity_matcher.dart';
import 'package:lauriva/services/forensic/sources/shingle_matching_engine.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';
import 'package:lauriva/services/forensic/sources/source_similarity_service.dart';

void main() {
  group('SourceRepository & Inverted Index Tests', () {
    late SourceRepository repository;

    setUp(() {
      repository = SourceRepository();
    });

    test('Initializes baseline corpus with seminal references', () {
      expect(repository.documentCount, greaterThanOrEqualTo(3));
      expect(repository.getDocument('academic_attention_paper'), isNotNull);
      expect(repository.getDocument('wiki_turing_test'), isNotNull);
    });

    test('Fast candidate retrieval indexes 5-gram shingles', () {
      final queryShingles = {
        'can machines think this should',
        'the imitation game it is',
      };
      final candidates = repository.findCandidates(queryShingles, minShared: 1);
      expect(candidates.isNotEmpty, isTrue);
      expect(candidates.first.documentId, 'wiki_turing_test');
    });
  });

  group('ShingleMatchingEngine & LCS Tests', () {
    late ShingleMatchingEngine engine;
    late SourceCorpusDocument sourceDoc;

    setUp(() {
      engine = ShingleMatchingEngine();
      sourceDoc = SourceCorpusDocument(
        id: 'test_doc',
        title: 'Neural Networks Architecture',
        category: SourceCategory.academic,
        content: 'The dominant sequence transduction models are based on complex recurrent or convolutional neural networks.',
      );
    });

    test('Finds exact contiguous match segment when text is copied verbatim', () {
      const query = 'In this study, the dominant sequence transduction models are based on complex recurrent structures.';
      final detail = engine.matchDocument(
        queryText: query,
        queryTokens: query.split(' '),
        source: sourceDoc,
      );

      expect(detail.longestContiguousRun, greaterThanOrEqualTo(8));
      expect(detail.segments.isNotEmpty, isTrue);
      expect(detail.segments.first.matchType, SourceMatchType.exact);
    });
  });

  group('FuzzySimilarityMatcher & Citation Suppression Tests', () {
    late FuzzySimilarityMatcher matcher;

    setUp(() {
      matcher = FuzzySimilarityMatcher();
    });

    test('Calculates Jaccard and Cosine similarity for paraphrased text', () {
      final a = ['operating', 'costs', 'were', 'reduced', 'by', 'eighteen', 'percent'];
      final b = ['the', 'company', 'reduced', 'operating', 'costs', 'by', 'eighteen', 'percent'];

      final jaccard = matcher.tokenJaccardSimilarity(a, b);
      expect(jaccard, greaterThan(0.60));

      final cosine = matcher.characterNgramCosineSimilarity(a.join(' '), b.join(' '));
      expect(cosine, greaterThan(0.70));
    });

    test('Suppresses plagiarism severity for properly quoted and cited passages', () {
      const citedDoc = '''
As stated in foundational literature:
"All human beings are born free and equal in dignity and rights." (United Nations, 1948)
This forms the cornerstone of international ethics.
''';

      final startOffset = citedDoc.indexOf('All human');
      final endOffset = citedDoc.indexOf('rights.') + 'rights.'.length;

      final analysis = matcher.analyzeCitationContext(
        fullDocumentText: citedDoc,
        matchStartOffset: startOffset,
        matchEndOffset: endOffset,
      );

      expect(analysis.isQuoted, isTrue);
      expect(analysis.status, CitationStatus.quotedAndCited);
      expect(analysis.citationMarker, '(United Nations, 1948)');
    });
  });

  group('SourceSimilarityService & ForensicEngine Integration Tests', () {
    late ForensicEngine engine;

    setUp(() {
      engine = ForensicEngine();
    });

    test('Detects verbatim copied excerpt from known baseline corpus', () {
      const copiedText = '''
Here is the proposed methodology:
We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely.
This approach simplifies training workflows.
''';

      final report = engine.analyze(copiedText);

      expect(report.sourceSimilarity.matches.isNotEmpty, isTrue);
      expect(report.sourceSimilarity.matches.first.sourceTitle, contains('Attention Is All You Need'));
      expect(report.sourceSimilarity.overallSimilarityScore, greaterThan(20.0));
      expect(report.spans.any((s) => s.id.startsWith('source_span_')), isTrue);
    });

    test('Properly cited excerpt does not trigger critical plagiarism penalty', () {
      const citedText = '''
According to seminal research:
"We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely." (Vaswani et al., 2017)
Their experimental results confirm rapid convergence.
''';

      final report = engine.analyze(citedText);

      expect(report.sourceSimilarity.matches.isNotEmpty, isTrue);
      final match = report.sourceSimilarity.matches.first;
      expect(match.citationStatus, CitationStatus.quotedAndCited);
      expect(report.sourceSimilarity.overallSimilarityScore, lessThanOrEqualTo(15.0));
    });

    test('Filters short (< 27 tokens) single-run match for online Wikipedia', () {
      final repo = SourceRepository(loadDefaultCorpus: false);
      repo.addDocument(SourceCorpusDocument(
        id: 'online_wikipedia_abc',
        title: 'Wikipedia: Ribosome',
        url: 'https://en.wikipedia.org/wiki/Ribosome',
        category: SourceCategory.web,
        content: 'A ribosome is a complex macromolecular machine found within all living cells that serves as the site of biological protein synthesis.',
      ));
      final service = SourceSimilarityService(repository: repo);
      const query =
          'A ribosome is a complex macromolecular machine found within all living cells that serves as the site. '
          'Inside the biological cell, thousands of individual units operate simultaneously to synthesize essential chains. '
          'These chains fold into functional shapes that carry out cellular metabolism and enzymatic reactions across diverse physiological pathways.';
      final evidence = service.analyzeDocument(query);
      expect(evidence.matches, isEmpty);
      expect(evidence.overallSimilarityScore, equals(0.0));
    });

    test('Detects online Wikipedia match when run length >= 27 tokens', () {
      final repo = SourceRepository(loadDefaultCorpus: false);
      const longPassage =
          'A ribosome is a complex macromolecular machine found within all living cells that serves as the primary site of biological protein synthesis by linking amino acids together in the precise order specified by messenger RNA molecules during translation in the cellular cytoplasm.';
      repo.addDocument(SourceCorpusDocument(
        id: 'online_wikipedia_def',
        title: 'Wikipedia: Ribosome Long',
        url: 'https://en.wikipedia.org/wiki/Ribosome',
        category: SourceCategory.web,
        content: longPassage,
      ));
      final service = SourceSimilarityService(repository: repo);
      final evidence = service.analyzeDocument(longPassage);
      expect(evidence.matches, isNotEmpty);
      expect(evidence.overallSimilarityScore, greaterThanOrEqualTo(20.0));
    });

    test('Preserves byte-identical offline matching for short runs', () {
      final repo = SourceRepository(loadDefaultCorpus: false);
      const shortPassage = 'A ribosome is a complex macromolecular machine found within all living cells.';
      repo.addDocument(SourceCorpusDocument(
        id: 'offline_cell_biology',
        title: 'Cell Biology Compendium',
        url: 'https://internal.library/cell_bio',
        category: SourceCategory.academic,
        content: shortPassage,
      ));
      final service = SourceSimilarityService(repository: repo);
      final evidence = service.analyzeDocument(shortPassage);
      expect(evidence.matches, isNotEmpty);
      expect(evidence.matches.first.sourceTitle, 'Cell Biology Compendium');
    });
  });
}
