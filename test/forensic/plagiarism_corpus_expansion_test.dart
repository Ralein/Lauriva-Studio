import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/forensic/source_similarity_evidence.dart';
import 'package:lauriva/services/forensic/document/document_segmenter.dart';
import 'package:lauriva/services/forensic/normalization/text_normalizer.dart';
import 'package:lauriva/services/forensic/sources/dense_semantic_matcher.dart';
import 'package:lauriva/services/forensic/sources/fuzzy_similarity_matcher.dart';
import 'package:lauriva/services/forensic/sources/shingle_matching_engine.dart';
import 'package:lauriva/services/forensic/sources/source_repository.dart';

void main() {
  group('Plagiarism Corpus Expansion & Multi-Tier Retrieval', () {
    late SourceRepository repository;
    late ShingleMatchingEngine shingleEngine;
    late DenseSemanticMatcher denseMatcher;
    late FuzzySimilarityMatcher fuzzyMatcher;

    setUp(() {
      repository = SourceRepository();
      shingleEngine = ShingleMatchingEngine();
      denseMatcher = DenseSemanticMatcher();
      fuzzyMatcher = FuzzySimilarityMatcher();
    });

    test('Corpus contains multi-domain baseline documents', () {
      expect(repository.documentCount, greaterThanOrEqualTo(10));
      expect(repository.getDocument('academic_resnet_paper'), isNotNull);
      expect(repository.getDocument('academic_shannon_information'), isNotNull);
      expect(repository.getDocument('literature_gettysburg_address'), isNotNull);
      expect(repository.getDocument('literature_orwell_politics'), isNotNull);
      expect(repository.getDocument('wiki_artificial_intelligence'), isNotNull);
      expect(repository.getDocument('wiki_photosynthesis'), isNotNull);
      expect(repository.getDocument('wiki_quantum_computing'), isNotNull);
      expect(repository.getDocument('essay_technology_society'), isNotNull);
    });

    test('Inverted 5-gram index accurately retrieves candidates for ResNet query', () {
      final queryShingles = {
        'deeper neural networks are more',
        'residual learning framework to ease',
      };
      final candidates = repository.findCandidates(queryShingles, minShared: 1);
      expect(candidates.isNotEmpty, isTrue);
      expect(candidates.any((c) => c.documentId == 'academic_resnet_paper'), isTrue);
    });

    test('ShingleMatchingEngine finds exact match runs on Shannon Information Theory excerpt', () {
      const query =
          'In communication engineering, the fundamental problem of communication is that of reproducing at one point either exactly or approximately a message selected at another point.';
      final shannonDoc = repository.getDocument('academic_shannon_information')!;
      final result = shingleEngine.matchDocument(
        queryText: query,
        queryTokens: query.split(' '),
        source: shannonDoc,
      );

      expect(result.longestContiguousRun, greaterThanOrEqualTo(10));
      expect(result.segments.isNotEmpty, isTrue);
    });

    test('DenseSemanticMatcher projects subword TF-IDF embeddings and detects paraphrasing', () {
      const paraphraseText =
          'We present a residual learning framework to ease the training of networks that are substantially deeper than those used previously.';
      final normalizer = TextNormalizer();
      final normDoc = normalizer.normalize(paraphraseText);
      final segmenter = DocumentSegmenter();
      final segDoc = segmenter.segment(normDoc);

      final matches = denseMatcher.findParaphrases(
        document: segDoc,
        repository: repository,
        threshold: 0.75,
      );

      expect(matches.isNotEmpty, isTrue);
      final best = matches.first;
      expect(best.sourceTitle, contains('He et al.'));
      expect(best.similarityPercent, greaterThanOrEqualTo(85.0));
      expect(best.rawStartOffset, greaterThanOrEqualTo(0));
      expect(best.rawEndOffset, greaterThan(best.rawStartOffset));
    });

    test('DenseSemanticMatcher detects cross-lexical academic paraphrase via synonym clusters', () {
      const original = 'The researchers conducted an experiment to establish whether the new method produced a significant increase in performance.';
      const paraphrase = 'The scientists carried out a study to determine if the novel approach yielded a substantial rise in results.';

      final sim = denseMatcher.similarity(paraphrase, original);
      expect(sim, greaterThanOrEqualTo(0.68));
    });

    test('FuzzySimilarityMatcher suppresses citation for multi-author APA and IEEE formats', () {
      const docWithCitation =
          '"Four score and seven years ago our fathers brought forth on this continent" (Lincoln, 1863).';
      final matchStart = docWithCitation.indexOf('Four score');
      final matchEnd = docWithCitation.indexOf('continent') + 'continent'.length;

      final analysis = fuzzyMatcher.analyzeCitationContext(
        fullDocumentText: docWithCitation,
        matchStartOffset: matchStart,
        matchEndOffset: matchEnd,
      );

      expect(analysis.isQuoted, isTrue);
      expect(analysis.status, CitationStatus.quotedAndCited);
      expect(analysis.citationMarker, '(Lincoln, 1863)');
    });
  });
}
