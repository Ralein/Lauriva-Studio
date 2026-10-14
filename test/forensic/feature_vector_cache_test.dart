import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/ai/feature_vector_cache.dart';

void main() {
  group('FeatureVectorCache LRU & SHA-256 Tests', () {
    late FeatureVectorCache cache;

    setUp(() {
      cache = FeatureVectorCache(capacity: 3);
    });

    test('Computes deterministic SHA-256 cache keys', () {
      final key1 = cache.hashKey('Hello world this is a test text passage');
      final key2 = cache.hashKey('Hello world this is a test text passage');
      final key3 = cache.hashKey('Hello world this is another text passage');

      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
      expect(key1.length, equals(64)); // SHA-256 hex string length
    });

    test('Stores and retrieves cached feature vectors', () {
      final vector = [1.2, 3.4, 5.6, 7.8];
      const text = 'Text passage';

      expect(cache.get(text), isNull);
      expect(cache.hits, equals(0));
      expect(cache.misses, equals(1));

      cache.put(text, vector);
      final retrieved = cache.get(text);

      expect(retrieved, equals(vector));
      expect(cache.hits, equals(1));
      expect(cache.size, equals(1));
    });

    test('Evicts Least Recently Used (LRU) entry when exceeding capacity', () {
      const p1 = 'passage one';
      const p2 = 'passage two';
      const p3 = 'passage three';
      const p4 = 'passage four';

      cache.put(p1, [1.0]);
      cache.put(p2, [2.0]);
      cache.put(p3, [3.0]);

      expect(cache.size, equals(3));
      expect(cache.get(p1), isNotNull); // Access p1, making p2 the oldest

      // Adding p4 should evict p2
      cache.put(p4, [4.0]);

      expect(cache.size, equals(3));
      expect(cache.get(p2), isNull); // Evicted!
      expect(cache.get(p1), isNotNull); // Still preserved
      expect(cache.get(p3), isNotNull);
      expect(cache.get(p4), isNotNull);
    });

    test('Clears cache and resets counts', () {
      const sample = 'Sample text';
      cache.put(sample, [0.5]);
      expect(cache.size, equals(1));

      cache.clear();
      expect(cache.size, equals(0));
      expect(cache.hits, equals(0));
      expect(cache.misses, equals(0));
    });
  });
}
