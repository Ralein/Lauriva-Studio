import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/sources/corpus_loader.dart';
import 'package:lauriva/services/forensic/sources/inverted_shingle_index.dart';

void main() {
  group('InvertedShingleIndex & CorpusLoader Tests', () {
    test('InvertedShingleIndex hashes shingles deterministically', () {
      final h1 = InvertedShingleIndex.hashShingle('the dominant sequence transduction models');
      final h2 = InvertedShingleIndex.hashShingle('the dominant sequence transduction models');
      final h3 = InvertedShingleIndex.hashShingle('a completely different sentence shingle');

      expect(h1, equals(h2));
      expect(h1, isNot(equals(h3)));
    });

    test('InvertedShingleIndex indexes and retrieves candidate documents in O(1)', () {
      final index = InvertedShingleIndex();
      index.indexDocument('doc_a', [
        'deep learning models require proper',
        'recurrent neural networks include encoder',
      ]);
      index.indexDocument('doc_b', [
        'deep learning models require proper',
        'transformer architectures dispense with recurrence',
      ]);

      expect(index.indexedDocumentCount, equals(2));
      expect(index.uniqueShingleCount, equals(3));

      // Query containing shared shingle
      final queryGrams = {'deep learning models require proper'};
      final candidates = index.findCandidates(queryGrams, minShared: 1);

      expect(candidates.length, equals(2));
      expect(candidates.any((c) => c.documentId == 'doc_a'), isTrue);
      expect(candidates.any((c) => c.documentId == 'doc_b'), isTrue);
    });

    test('CorpusLoader loads baseline corpus with documents and inverted index', () async {
      final sourceIndex = await CorpusLoader.load();

      expect(sourceIndex.documentCount, greaterThanOrEqualTo(3));
      expect(sourceIndex.invertedIndex.indexedDocumentCount, greaterThanOrEqualTo(3));
      expect(sourceIndex.documents.any((d) => d.id == 'arxiv_attention'), isTrue);
    });
  });
}
