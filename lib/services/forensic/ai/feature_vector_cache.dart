import 'dart:collection';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// In-memory LRU cache for 38-dimensional stylometric feature vectors.
///
/// Prevents redundant, heavy CPU-bound regex tokenization and statistical feature
/// extraction during repeated rescans, sliding-window subsegment iterations,
/// and Fix & Verify verification loops.
class FeatureVectorCache {
  final int capacity;
  final LinkedHashMap<String, List<double>> _cache = LinkedHashMap<String, List<double>>();

  int _hits = 0;
  int _misses = 0;

  FeatureVectorCache({this.capacity = 16});

  int get hits => _hits;
  int get misses => _misses;
  int get size => _cache.length;

  /// Retrieves cached feature vector for [text] if present, moving it to MRU position.
  List<double>? get(String text) {
    final key = hashKey(text);
    if (_cache.containsKey(key)) {
      _hits++;
      final value = _cache.remove(key)!;
      _cache[key] = value;
      return value;
    }
    _misses++;
    return null;
  }

  /// Inserts [vector] for [text], evicting LRU entry if [capacity] exceeded.
  void put(String text, List<double> vector) {
    if (text.trim().isEmpty || vector.isEmpty) return;
    final key = hashKey(text);

    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= capacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = List<double>.unmodifiable(vector);
  }

  /// Clears cache and metrics.
  void clear() {
    _cache.clear();
    _hits = 0;
    _misses = 0;
  }

  String hashKey(String text) {
    final slice = text.length > 512 ? text.substring(0, 512) : text;
    return sha256.convert(utf8.encode(slice.trim())).toString();
  }
}
