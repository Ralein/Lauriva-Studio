import 'source_repository.dart';

/// High-performance inverted shingle index for O(query_shingles) literature matching.
///
/// Converts string shingles into fast integer hashes to minimize heap allocation
/// and memory footprint when indexing large academic corpora.
class InvertedShingleIndex {
  final Map<int, List<String>> _index = {};
  int _indexedDocumentCount = 0;

  int get indexedDocumentCount => _indexedDocumentCount;
  int get uniqueShingleCount => _index.length;

  /// Fast 32-bit FNV-1a rolling hash for token shingles.
  static int hashShingle(String shingle) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < shingle.length; i++) {
      hash ^= shingle.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Adds a document's shingles into the inverted index.
  void indexDocument(String docId, Iterable<String> shingles) {
    _indexedDocumentCount++;
    for (final s in shingles) {
      final h = hashShingle(s);
      final list = _index.putIfAbsent(h, () => <String>[]);
      if (!list.contains(docId)) {
        list.add(docId);
      }
    }
  }

  /// Retrieves candidate document IDs that share at least [minShared] shingles
  /// with the query set. Runs in O(queryGrams) without linear scans.
  List<SourceMatchCandidate> findCandidates(
    Set<String> queryGrams, {
    int minShared = 2,
    Map<String, String>? docTitles,
    Map<String, String?>? docUrls,
  }) {
    if (queryGrams.isEmpty || _index.isEmpty) return const [];

    final candidateCounts = <String, int>{};

    for (final gram in queryGrams) {
      final h = hashShingle(gram);
      final docIds = _index[h];
      if (docIds != null) {
        for (final id in docIds) {
          candidateCounts[id] = (candidateCounts[id] ?? 0) + 1;
        }
      }
    }

    final candidates = <SourceMatchCandidate>[];
    candidateCounts.forEach((docId, count) {
      if (count >= minShared) {
        candidates.add(
          SourceMatchCandidate(
            documentId: docId,
            title: docTitles?[docId] ?? docId,
            url: docUrls?[docId],
            sharedShingleCount: count,
          ),
        );
      }
    });

    candidates.sort((a, b) => b.sharedShingleCount.compareTo(a.sharedShingleCount));
    return candidates;
  }

  /// Clears the entire index.
  void clear() {
    _index.clear();
    _indexedDocumentCount = 0;
  }
}
